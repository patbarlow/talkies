import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";
import { publicUser } from "../db";

const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

app.use("*", requireAuth);

app.get("/", (c) => c.json(publicUser(c.get("user"))));

/**
 * Update the signed-in user's profile.
 * Body: { name?: string }   (trimmed; empty/whitespace clears the field)
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

export default app;
