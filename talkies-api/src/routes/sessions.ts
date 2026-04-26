import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";

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

  return c.json({ ok: true, inserted: events.length });
});

export default app;
