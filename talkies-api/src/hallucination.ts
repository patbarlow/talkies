/**
 * Detects when the cleanup model slipped into chat mode and replied to the
 * transcription instead of cleaning it (e.g. dictating a prompt for Claude
 * and getting back "I can't find this file"). Callers fall back to the raw
 * transcription when this returns true, so the cost of a false positive is
 * mild (the user gets their words uncleaned) while a false negative pastes a
 * chat reply into the destination app.
 */

function wordCount(s: string): number {
  return s.split(/\s+/).filter(Boolean).length;
}

/** Lowercased alphanumeric tokens; apostrophes stripped so "can't" === "cant". */
function tokens(s: string): string[] {
  return s
    .toLowerCase()
    .replace(/[’']/g, "")
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}

/**
 * Fraction of the output's tokens that also appear in the input. Cleanup only
 * deletes fillers and fixes punctuation/mis-hearings, so nearly every output
 * word comes from the input. A reply to the content — an answer, refusal, or
 * clarifying question — is built mostly from new vocabulary, even when it
 * echoes the topic words back.
 */
function inputOverlap(input: string, output: string): number {
  const inputSet = new Set(tokens(input));
  const out = tokens(output);
  if (out.length === 0) return 1;
  let hits = 0;
  for (const t of out) if (inputSet.has(t)) hits++;
  return hits / out.length;
}

/**
 * Fraction of the input's distinct tokens that survive into the output.
 * Cleanup drops fillers and duplicates but keeps the content words; an answer
 * to the dictation drops most of them ("what's the capital of france" →
 * "The capital of France is Paris." loses what's/again/forget…).
 */
function inputRecall(input: string, output: string): number {
  const outputSet = new Set(tokens(output));
  const inputSet = new Set(tokens(input));
  if (inputSet.size === 0) return 1;
  let kept = 0;
  for (const t of inputSet) if (outputSet.has(t)) kept++;
  return kept / inputSet.size;
}

/**
 * Conversational-reply openers that mark the model answering rather than
 * cleaning. Only consulted when the output's vocabulary has already diverged
 * from the input (overlap < 0.8), so a dictation that legitimately starts
 * with one of these ("I can't find my keys, can you order…") is not at risk —
 * its cleaned output reuses the input's own words. First-person entries stay
 * narrow (assistant-failure phrasings) because polish-level rewording can
 * push overlap below the gate on real first-person dictations.
 */
const CHAT_OPENERS = [
  "i don't see",
  "i don't have access",
  "i don't have any",
  "i don't have enough",
  "i can't find",
  "i can't see",
  "i can't locate",
  "i can't access",
  "i can't help",
  "i cannot find",
  "i cannot see",
  "i cannot access",
  "i cannot help",
  "i'm not able",
  "i'm unable",
  "i am unable",
  "i'm sorry",
  "i am sorry",
  "i apologize",
  "i apologise",
  "i'm ready",
  "i'd be happy",
  "i'd be glad",
  "i'm happy to",
  "i can help",
  "happy to help",
  "sure,",
  "sure!",
  "of course",
  "certainly",
  "could you clarify",
  "could you provide",
  "could you share",
  "could you tell",
  "can you clarify",
  "can you provide",
  "can you share",
  "here's the",
  "here is the",
  "it looks like you're",
  "it seems like you're",
  "it sounds like you're",
  "what would you like",
  "is there anything",
  "let me know if",
  "to clarify",
];

/**
 * @param styledRewrite true when a tone override (casual/formal/technical) was
 * requested — those legitimately reword the text, so vocabulary divergence
 * stops being a reliable signal and only the opener/balloon checks apply.
 */
export function looksHallucinated(input: string, output: string, styledRewrite = false): boolean {
  const inWords = wordCount(input);
  const outWords = wordCount(output);

  // Cleanup should never balloon the text. 2× the word count + a small floor
  // keeps short legitimate dictations ("yes" → "Yes.") from tripping the
  // guard while catching chat replies that bloat short inputs.
  if (outWords > 8 && outWords > inWords * 2) return true;

  // Meta-commentary about the task ("Here is the cleaned transcription:",
  // "The transcription appears to be…") is never legitimate unless the user
  // actually dictated those words.
  if (/transcription|dictat/i.test(output) && !/transcription|dictat/i.test(input)) return true;

  const overlap = inputOverlap(input, output);

  if (!styledRewrite && outWords >= 5 && overlap < 0.55) return true;

  // Near-verbatim reuse of the input's words is a cleanup, even if it happens
  // to start with a chat-sounding phrase the user dictated themselves. This
  // also clears legitimate tightening: dropping words never lowers overlap.
  if (overlap >= 0.8) return false;

  // Output diverged AND most of the input's words were dropped — the
  // signature of an answer that echoes a few topic words ("The capital of
  // France is Paris."). Legitimate clean/polish edits that reword (lowering
  // overlap) still retain the input's content words, keeping recall high.
  if (!styledRewrite && wordCount(input) >= 5 && inputRecall(input, output) < 0.45) return true;

  const opener = output.trim().toLowerCase().replace(/[’]/g, "'").slice(0, 80);
  return CHAT_OPENERS.some((p) => opener.startsWith(p));
}
