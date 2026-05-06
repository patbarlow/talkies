import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";

const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

app.use("*", requireAuth);

interface HistoryEntry {
  instruction: string;
  output: string;
}

/**
 * Edit mode is a Pro feature. Block free users at the edge so it can't be
 * bypassed by setting the hotkey via UserDefaults manipulation.
 */
app.use("*", async (c, next) => {
  const user = c.get("user");
  if (user.plan !== "pro") {
    return c.json({ error: "pro_required", feature: "edit_mode" }, 402);
  }
  await next();
});

/**
 * Apply a voice instruction to selected text. Each refinement passes the
 * original selection plus the prior instruction/output history so iterations
 * refine the goal rather than compounding edits.
 *
 * Body: { selection, instruction, appName?, history? }
 */
app.post("/", async (c) => {
  const body = await c.req
    .json<{
      selection?: string;
      instruction?: string;
      appName?: string;
      spellingVariant?: string;
      preferences?: string[];
      history?: HistoryEntry[];
    }>()
    .catch(() => ({}) as {
      selection?: string;
      instruction?: string;
      appName?: string;
      spellingVariant?: string;
      preferences?: string[];
      history?: HistoryEntry[];
    });

  const selection = typeof body.selection === "string" ? body.selection : "";
  const instruction = typeof body.instruction === "string" ? body.instruction.trim() : "";
  if (!selection) return c.json({ error: "missing_selection" }, 400);
  if (!instruction) return c.json({ error: "missing_instruction" }, 400);

  const history = Array.isArray(body.history) ? body.history.slice(-5) : [];
  const appName = typeof body.appName === "string" ? body.appName : undefined;
  const spellingVariant = typeof body.spellingVariant === "string" ? body.spellingVariant : undefined;
  const preferences = Array.isArray(body.preferences)
    ? body.preferences.filter((p): p is string => typeof p === "string" && p.trim().length > 0)
    : [];
  const system = buildSystemPrompt(appName, spellingVariant, preferences);
  const userMessage = buildUserMessage(selection, instruction, history);

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": c.env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5",
      max_tokens: 2048,
      system,
      messages: [{ role: "user", content: userMessage }],
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

function buildSystemPrompt(
  appName?: string,
  spellingVariant?: string,
  preferences?: string[],
): string {
  const ctx = appName ? ` The user is editing text in ${appName}.` : "";
  const spelling = spellingVariant
    ? `\n\nWhen the text is in English, use ${spellingVariant} spelling throughout (favourite vs favorite, organise vs organize, etc.).`
    : "";
  const prefs =
    preferences && preferences.length > 0
      ? `\n\nThe user has set these personal writing preferences. Honour them in your output unless the explicit instruction overrides:\n` +
        preferences.map((p) => `- ${p}`).join("\n")
      : "";
  return (
    `You rewrite a passage of text according to a spoken instruction.${ctx}${spelling}${prefs}\n` +
    `\n` +
    `The user dictated the instruction quickly, so it is often terse. When ` +
    `it is, expand it internally into the richer goal it implies before ` +
    `applying. Example interpretations:\n` +
    `- "polish" / "clean it up" / "make it better" → Fix grammar, tighten ` +
    `sentences, remove filler, make it sound clean and confident. Preserve ` +
    `meaning and voice.\n` +
    `- "shorter" / "concise" / "fewer words" → Express the same meaning in ` +
    `fewer words. Keep it clear, confident, and natural. Remove filler but ` +
    `maintain flow.\n` +
    `- "bullet points" / "make it a list" → Summarize the content into ` +
    `clear, parallel bullet points. Preserve all key information.\n` +
    `- "email" / "make this an email" → Rephrase in email format with an ` +
    `appropriate greeting and sign-off, professional but warm tone.\n` +
    `- "casual" / "informal" → Conversational tone, contractions are fine, ` +
    `sound like a person talking.\n` +
    `- "formal" / "professional" → Complete sentences, no contractions, ` +
    `polished tone suitable for business.\n` +
    `- "fix" / "fix typos" / "fix grammar" → Correct grammar, spelling, and ` +
    `punctuation only. Do not change wording.\n` +
    `- "summarize" / "tldr" → Condense to the key points only. Be ruthless ` +
    `about what is essential.\n` +
    `- "expand" / "more detail" → Develop the ideas with context and ` +
    `clarification. Do not invent new facts.\n` +
    `- "translate to X" → Translate to the named language, preserving ` +
    `meaning and tone.\n` +
    `- "improve transitions" / "make it flow" → Strengthen connections ` +
    `between sentences and paragraphs so each builds on the previous one.\n` +
    `\n` +
    `When the instruction is *specific and literal* — like "capitalize ` +
    `every word", "delete the second paragraph", "change every 'we' to 'I'", ` +
    `or "add a question mark at the end" — follow it precisely without ` +
    `expansion or reinterpretation.\n` +
    `\n` +
    `Rules:\n` +
    `- Apply the user's intent faithfully. Do not invent facts or add ` +
    `information they did not ask for.\n` +
    `- Preserve the user's voice and meaning unless the instruction ` +
    `explicitly asks to change them.\n` +
    `- If genuinely ambiguous, pick the most natural interpretation rather ` +
    `than asking for clarification.\n` +
    `- Return ONLY the rewritten text. No preamble, no explanation, no ` +
    `markdown fences, no quotes around the result.`
  );
}

function buildUserMessage(
  selection: string,
  instruction: string,
  history: HistoryEntry[],
): string {
  const parts: string[] = [];
  parts.push("<original_text>");
  parts.push(selection);
  parts.push("</original_text>");

  if (history.length > 0) {
    parts.push("");
    parts.push(
      "Earlier you produced these revisions of the original text. The user has now given a new instruction; apply it to the original (using the prior revisions only as context for what they've been refining toward).",
    );
    history.forEach((h, i) => {
      parts.push("");
      parts.push(`<revision_${i + 1}>`);
      parts.push(`<instruction>${h.instruction}</instruction>`);
      parts.push(`<output>${h.output}</output>`);
      parts.push(`</revision_${i + 1}>`);
    });
  }

  parts.push("");
  parts.push("<instruction>");
  parts.push(instruction);
  parts.push("</instruction>");

  return parts.join("\n");
}

export default app;
