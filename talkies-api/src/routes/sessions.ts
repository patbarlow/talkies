import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";
import { recomputeUserStats, getUser, WEEK_LIMIT_FREE } from "../db";
import { fireEvent, crossedMilestones, milestoneEventName } from "../events";

const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

app.use("*", requireAuth);

interface SessionEvent {
  id: string;
  recorded_at: string;
  word_count: number;
  duration_seconds: number;
  app_name?: string | null;
  bundle_id?: string | null;
  cleanup_level?: string | null;
  language?: string | null;
}

/**
 * Batch-upsert session analytics events from the client.
 * Accepts up to 500 events per request. Duplicate IDs are silently ignored.
 * Body: { sessions: SessionEvent[] }
 */
app.post("/", async (c) => {
  const user = c.get("user");
  const prevSessionCount = user.session_count;
  const prevWeekWords = user.week_words;

  const body = await c.req
    .json<{ sessions?: unknown[] }>()
    .catch(() => ({} as { sessions?: unknown[] }));

  if (!Array.isArray(body.sessions) || body.sessions.length === 0) {
    return c.json({ ok: true, inserted: 0 });
  }

  const events = (body.sessions.slice(0, 500) as SessionEvent[]).filter(
    (e) =>
      typeof e.id === "string" &&
      e.id.length > 0 &&
      typeof e.recorded_at === "string" &&
      typeof e.word_count === "number" &&
      typeof e.duration_seconds === "number",
  );

  if (events.length === 0) {
    return c.json({ ok: true, inserted: 0 });
  }

  const stmts = events.map((e) =>
    c.env.DB.prepare(
      `INSERT OR IGNORE INTO sessions
         (id, user_id, recorded_at, word_count, duration_seconds, app_name, bundle_id, cleanup_level, language)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      e.id,
      user.id,
      e.recorded_at,
      e.word_count,
      e.duration_seconds,
      e.app_name ?? null,
      e.bundle_id ?? null,
      e.cleanup_level ?? null,
      e.language ?? null,
    ),
  );

  await c.env.DB.batch(stmts);

  // Sessions table is the source of truth — recompute user totals so every
  // device's contributions are reflected without any double-counting.
  await recomputeUserStats(c.env.DB, user);

  // Fire recording milestone and limit events based on updated counts.
  const updated = await getUser(c.env.DB, user.id);
  if (updated) {
    for (const m of crossedMilestones(prevSessionCount, updated.session_count)) {
      fireEvent(c.env, milestoneEventName(m), user.email, {
        session_count: updated.session_count,
        total_words: updated.total_words,
      });
    }
    if (
      user.plan === "free" &&
      prevWeekWords < WEEK_LIMIT_FREE &&
      updated.week_words >= WEEK_LIMIT_FREE
    ) {
      fireEvent(c.env, "limit.reached", user.email, {
        week_words: updated.week_words,
        week_limit: WEEK_LIMIT_FREE,
      });
    }
  }

  return c.json({ ok: true, inserted: events.length });
});

export default app;
