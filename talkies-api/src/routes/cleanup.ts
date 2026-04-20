import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";

const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

app.use("*", requireAuth);

/**
 * Proxy to Claude Haiku for the dictation cleanup pass.
 * Body: { text, appName?, appBundleID? }
 */
app.post("/", async (c) => {
  const body = await c.req
    .json<{ text?: string; appName?: string; appBundleID?: string }>()
    .catch(() => ({}) as Record<string, string | undefined>);

  const input = body.text?.trim();
  if (!input) return c.json({ error: "missing_text" }, 400);

  const system = buildSystemPrompt(body.appName, body.appBundleID);

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": c.env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5",
      max_tokens: 1024,
      system,
      messages: [{ role: "user", content: input }],
    }),
  });

  if (!res.ok) {
    const detail = await res.text();
    return c.json({ error: "upstream_error", detail }, 502);
  }

  const payload = (await res.json()) as {
    content: Array<{ type: string; text?: string }>;
  };
  const text = payload.content
    .filter((block) => block.type === "text")
    .map((block) => block.text ?? "")
    .join("")
    .trim();

  return c.json({ text });
});

function buildSystemPrompt(appName?: string, _bundleID?: string): string {
  const ctx = appName ? ` The user is typing into ${appName}.` : "";
  return (
    `Lightly clean up the dictated text below. Remove filler words (um, uh, like, ` +
    `you know), fix obvious mis-hearings, and apply appropriate punctuation and ` +
    `capitalization.${ctx} Preserve the user's meaning, style, and vocabulary — ` +
    `do not embellish or change the substance. Return only the cleaned text, ` +
    `nothing else.`
  );
}

export default app;
