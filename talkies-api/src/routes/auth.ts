import { Hono } from "hono";
import type { Env } from "../env";
import { verifyAppleIdentityToken } from "../apple";
import { upsertUser, publicUser } from "../db";
import { issueSession } from "../session";

const app = new Hono<{ Bindings: Env }>();

/**
 * Exchange a Sign in with Apple identity token for a Talkies session.
 * Body: { identityToken, email?, fullName? }
 * Apple only sends email + fullName on the *first* sign-in per user, so the
 * client should forward them on first auth and omit them afterwards.
 */
app.post("/apple", async (c) => {
  const body = await c.req
    .json<{ identityToken?: string; email?: string; fullName?: string }>()
    .catch(() => ({}) as Record<string, string | undefined>);

  if (!body.identityToken) {
    return c.json({ error: "missing_identity_token" }, 400);
  }

  let claims;
  try {
    claims = await verifyAppleIdentityToken(body.identityToken, c.env.APPLE_BUNDLE_ID);
  } catch (e) {
    return c.json({ error: "invalid_identity_token", detail: String(e) }, 401);
  }

  const user = await upsertUser(c.env.DB, {
    appleSub: claims.sub,
    email: body.email ?? claims.email,
    name: body.fullName,
  });

  const session = await issueSession(user.id, c.env.SESSION_SECRET);
  return c.json({ session, user: publicUser(user) });
});

export default app;
