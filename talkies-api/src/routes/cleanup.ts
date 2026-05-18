import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";

const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

app.use("*", requireAuth);

/**
 * Proxy to Claude Haiku for the dictation cleanup pass.
 * Body: { text, appName?, appBundleID?, level?, tone?, spellingVariant? }
 */
app.post("/", async (c) => {
  const body = await c.req
    .json<{ text?: string; appName?: string; appBundleID?: string; level?: string; tone?: string; spellingVariant?: string }>()
    .catch(() => ({}) as Record<string, string | undefined>);

  const input = body.text?.trim();
  if (!input) return c.json({ error: "missing_text" }, 400);

  const level = body.level ?? "clean";
  const system = buildSystemPrompt(body.appName, body.appBundleID, level, body.spellingVariant, body.tone);

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
  const cleaned = payload.content
    .filter((block) => block.type === "text")
    .map((block) => block.text ?? "")
    .join("")
    .trim();

  // Sanity check: if the cleanup output is dramatically longer than the
  // input, Claude likely misread a short or hallucinated transcription as a
  // chat message and replied conversationally ("I'm ready to clean up
  // dictated text for you…"). Fall back to the raw input so the user gets
  // their actual words rather than a chat reply.
  const text = looksHallucinated(input, cleaned) ? input : cleaned;

  return c.json({ text });
});

function wordCount(s: string): number {
  return s.split(/\s+/).filter(Boolean).length;
}

function looksHallucinated(input: string, output: string): boolean {
  const inWords = wordCount(input);
  const outWords = wordCount(output);
  // Cleanup should never balloon the text. 3× the word count + a small
  // floor keeps short legitimate dictations ("yes" → "Yes.") from tripping
  // the guard while catching 30+ word chat replies to ≤10-word inputs.
  return outWords > 10 && outWords > inWords * 3;
}

function toneInstruction(tone?: string): string {
  switch (tone) {
    case "casual":
      return " Use a casual, conversational tone — contractions are fine, keep it natural and direct.";
    case "formal":
      return " Use a formal, professional tone — complete sentences, no contractions.";
    case "technical":
      return " Use precise, technical language — preserve exact technical terms and keep it concise.";
    default:
      return "";
  }
}

function buildSystemPrompt(appName?: string, _bundleID?: string, level = "clean", spellingVariant?: string, tone?: string): string {
  const ctx = appName ? ` The user is typing into ${appName}.` : "";
  const spelling = spellingVariant ? ` Use ${spellingVariant} English spelling throughout.` : "";
  const toneHint = toneInstruction(tone);

  switch (level) {
    case "off":
      return `Return the text exactly as provided. No changes.`;

    case "clean":
      return (
        `Lightly clean up this dictated text. Remove filler words (um, uh, like, you know) ` +
        `and fix obvious mis-hearings. Apply correct punctuation and capitalisation.` +
        `${toneHint}${ctx}${spelling} Preserve the user's natural phrasing — keep casual ` +
        `contractions like "wanna", "gonna", "kinda" if the transcription captured them. ` +
        `Do not restructure or embellish. Return only the cleaned text, nothing else.`
      );

    case "polish":
      return (
        `Clean up and lightly improve this dictated text. Remove filler words, fix mis-hearings, ` +
        `and correct casual contractions ("wanna" → "want to", "gonna" → "going to", ` +
        `"kinda" → "kind of", etc.). Standard contractions like "don't", "can't", "I'll" are fine to keep. ` +
        `Tighten sentences where it helps clarity. Apply correct punctuation and capitalisation.` +
        `${toneHint}${ctx}${spelling} Keep the user's meaning and voice intact — do not add new ideas. ` +
        `Return only the cleaned text, nothing else.`
      );

    default:
      return buildSystemPrompt(appName, _bundleID, "clean", spellingVariant, tone);
  }
}

export default app;
