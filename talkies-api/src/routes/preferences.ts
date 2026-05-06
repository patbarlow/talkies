import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";

const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

app.use("*", requireAuth);

/** Pro-only: edit mode (and personalisation) is a paid feature. */
app.use("*", async (c, next) => {
  const user = c.get("user");
  if (user.plan !== "pro") {
    return c.json({ error: "pro_required", feature: "edit_mode" }, 402);
  }
  await next();
});

/**
 * Parse a free-form spoken description of writing preferences into a list
 * of short imperative phrases the edit-mode system prompt can apply.
 *
 * Body: { text: string }  // raw transcription from /v1/transcribe
 * Returns: { preferences: string[] }
 */
app.post("/extract", async (c) => {
  const body = await c.req.json<{ text?: string }>().catch(() => ({}) as { text?: string });
  const text = body.text?.trim();
  if (!text) return c.json({ error: "missing_text" }, 400);

  const system =
    `Extract the user's writing preferences from a spoken description and ` +
    `return them as a JSON array of short imperative phrases.\n\n` +
    `Each preference should be 3-12 words, written as a directive ` +
    `(e.g. "Use Australian spelling", "Avoid the word 'utilize'", ` +
    `"Prefer bullet points for lists", "Always end emails with 'Cheers'", ` +
    `"Keep things casual and direct").\n\n` +
    `Rules:\n` +
    `- If the user mentions multiple preferences in one breath, return ` +
    `each as a separate item.\n` +
    `- Normalise wording into imperative form, but preserve specifics ` +
    `(exact words/phrases the user mentioned).\n` +
    `- If you can't extract any clear preference, return an empty array.\n` +
    `- Return ONLY the JSON array. No preamble, no markdown fences, no ` +
    `explanation. Example output: ["Use Australian spelling","Avoid the word 'literally'"]`;

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
      messages: [{ role: "user", content: text }],
    }),
  });

  if (!res.ok) {
    const detail = await res.text();
    return c.json({ error: "upstream_error", detail }, 502);
  }

  const payload = (await res.json()) as {
    content: Array<{ type: string; text?: string }>;
  };
  const responseText = payload.content
    .filter((block) => block.type === "text")
    .map((block) => block.text ?? "")
    .join("")
    .trim();

  // Be defensive: Claude *should* return a clean JSON array, but strip any
  // accidental markdown fences before parsing.
  const cleaned = responseText
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  let preferences: string[] = [];
  try {
    const parsed = JSON.parse(cleaned);
    if (Array.isArray(parsed)) {
      preferences = parsed
        .filter((p): p is string => typeof p === "string")
        .map((p) => p.trim())
        .filter((p) => p.length > 0 && p.length <= 200);
    }
  } catch {
    return c.json({ error: "parse_error", raw: responseText }, 502);
  }

  return c.json({ preferences });
});

export default app;
