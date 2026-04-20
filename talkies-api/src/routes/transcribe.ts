import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";
import { recordUsage, WEEK_LIMIT_FREE } from "../db";

const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

app.use("*", requireAuth);

/**
 * Proxy to Groq Whisper. Enforces the weekly word limit for free users.
 * Body: multipart/form-data with `audio` (File) and optional `prompt` (string).
 */
app.post("/", async (c) => {
  const user = c.get("user");

  if (user.plan === "free" && user.week_words >= WEEK_LIMIT_FREE) {
    return c.json(
      {
        error: "weekly_limit_reached",
        plan: user.plan,
        limit: WEEK_LIMIT_FREE,
        used: user.week_words,
      },
      402,
    );
  }

  const form = await c.req.formData();
  const audioRaw = form.get("audio") as unknown;
  if (!audioRaw || typeof audioRaw === "string") {
    return c.json({ error: "missing_audio" }, 400);
  }
  const audio = audioRaw as Blob & { name?: string };
  const prompt = form.get("prompt");

  const groqForm = new FormData();
  groqForm.append("file", audio, audio.name ?? "audio.wav");
  groqForm.append("model", "whisper-large-v3-turbo");
  groqForm.append("response_format", "json");
  if (typeof prompt === "string" && prompt.length > 0) {
    groqForm.append("prompt", prompt);
  }

  const groqRes = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${c.env.GROQ_API_KEY}` },
    body: groqForm,
  });

  if (!groqRes.ok) {
    const detail = await groqRes.text();
    return c.json({ error: "upstream_error", detail }, 502);
  }

  const result = (await groqRes.json()) as { text?: string };
  const text = (result.text ?? "").trim();
  const wordCount = text.split(/\s+/).filter(Boolean).length;

  // Best-effort increment. If this fails the user got a free one — log and move on.
  try {
    await recordUsage(c.env.DB, user.id, wordCount);
  } catch (e) {
    console.error("recordUsage failed:", e);
  }

  return c.json({ text, wordCount });
});

export default app;
