import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";
import { publicUser } from "../db";

const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

app.use("*", requireAuth);

app.get("/", (c) => c.json(publicUser(c.get("user"))));

/**
 * Update the signed-in user's profile.
 * Body: { name?: string }
 * Returns: updated PublicUser.
 */
app.patch("/", async (c) => {
  const user = c.get("user");
  const body = await c.req
    .json<{ name?: string }>()
    .catch(() => ({} as { name?: string }));

  if (typeof body.name === "string") {
    const trimmed = body.name.trim();
    const value = trimmed.length > 0 ? trimmed.slice(0, 120) : null;
    await c.env.DB
      .prepare("UPDATE users SET name = ?, updated_at = ? WHERE id = ?")
      .bind(value, new Date().toISOString(), user.id)
      .run();
    user.name = value;
  }

  return c.json(publicUser(user));
});

/**
 * Upload avatar. Body: { avatar: base64PNGString }
 * Stored in D1 as base64 text (~40 KB max for a 256×256 PNG).
 */
app.put("/avatar", async (c) => {
  const user = c.get("user");
  const body = await c.req
    .json<{ avatar?: string }>()
    .catch(() => ({} as { avatar?: string }));

  const data = body.avatar?.trim();
  if (!data) return c.json({ error: "missing_avatar" }, 400);
  // Sanity-check: base64 only, cap at 200 KB of encoded data (~150 KB PNG)
  if (!/^[A-Za-z0-9+/=]+$/.test(data) || data.length > 200_000) {
    return c.json({ error: "invalid_avatar" }, 400);
  }

  await c.env.DB
    .prepare("UPDATE users SET avatar_data = ?, updated_at = ? WHERE id = ?")
    .bind(data, new Date().toISOString(), user.id)
    .run();

  return c.json({ ok: true });
});

/**
 * Download avatar. Returns { avatar: base64PNGString } or 404.
 */
app.get("/avatar", async (c) => {
  const user = c.get("user");
  const row = await c.env.DB
    .prepare("SELECT avatar_data FROM users WHERE id = ?")
    .bind(user.id)
    .first<{ avatar_data: string | null }>();

  if (!row?.avatar_data) return c.json({ error: "not_found" }, 404);
  return c.json({ avatar: row.avatar_data });
});

export default app;
