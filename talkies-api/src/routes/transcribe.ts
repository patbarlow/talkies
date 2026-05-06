import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";
import { WEEK_LIMIT_FREE } from "../db";

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
  const rawText = (result.text ?? "").trim();
  const text = isWhisperHallucination(rawText) ? "" : rawText;
  const wordCount = text.split(/\s+/).filter(Boolean).length;

  // Word counts are maintained by the /sessions sync endpoint (recomputeUserStats)
  // so we don't update them here. The client syncs the session immediately after
  // transcription, keeping the server totals accurate without double-counting.

  const limitReached =
    user.plan === "free" && user.week_words + wordCount >= WEEK_LIMIT_FREE;

  return c.json({ text, wordCount, limitReached });
});

/**
 * Whisper consistently emits these strings on silent or near-silent audio
 * (training-set artifacts from auto-captioned YouTube). They must be filtered
 * here so downstream cleanup (Claude) doesn't misread them as user input and
 * respond conversationally.
 *
 * Match is exact, case-insensitive, after trimming and stripping outer
 * punctuation/whitespace. We deliberately don't fuzzy-match — a real
 * dictation of the word "thanks" should still go through.
 */
const WHISPER_HALLUCINATIONS: ReadonlySet<string> = new Set([
  "",
  "[blank_audio]",
  "[ blank_audio ]",
  "[music]",
  "[applause]",
  "[silence]",
  "(music)",
  "(applause)",
  "(silence)",
  "thank you",
  "thanks",
  "thank you for watching",
  "thank you for watching!",
  "thanks for watching",
  "thanks for watching!",
  "thank you so much for watching",
  "you",
  "bye",
  "goodbye",
  "the end",
  "...",
  "♪",
  "♫",
  "♪♪",
  "♪ ♪",
]);

function isWhisperHallucination(text: string): boolean {
  const normalized = text
    .toLowerCase()
    .replace(/[.,!?]+$/g, "")
    .trim();
  return WHISPER_HALLUCINATIONS.has(normalized);
}

export default app;
