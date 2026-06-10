// Regression cases for the cleanup chat-mode guard. Run with:
//   npx tsx scripts/test-hallucination-guard.ts
import { looksHallucinated } from "../src/hallucination";

type Case = { name: string; input: string; output: string; styled?: boolean; expect: boolean };

const cases: Case[] = [
  // ---- chat replies that MUST be caught (expect: true) ----
  {
    name: "the reported bug: 'I can't find this' reply to a long prompt",
    input: "can you go into the project and check why the cleanup keeps replying to me instead of dictating what i'm saying",
    output: "I can't find this project. Could you share more details about what you're working on?",
    expect: true,
  },
  {
    name: "refusal reply, shorter than input (old balloon check missed these)",
    input: "have a look at this file and tell me why the login flow is broken it keeps redirecting back to the home page after sign in",
    output: "I don't see any file attached to your message.",
    expect: true,
  },
  {
    name: "echo-heavy clarifying question",
    input: "can you check why the login page is broken in the auth file",
    output: "Could you clarify what you mean by the login page being broken in the auth file?",
    expect: true,
  },
  {
    name: "helpful-assistant reply that balloons",
    input: "what's a good name for a dictation app",
    output: "Here are some great name ideas for a dictation app: VoiceFlow, SpeakEasy, Dictate Pro, TalkType, and EchoScribe. Each conveys speech-to-text functionality clearly.",
    expect: true,
  },
  {
    name: "meta-commentary about the task",
    input: "send the report to finance by friday",
    output: "Here is the cleaned transcription: Send the report to finance by Friday.",
    expect: true,
  },
  {
    name: "pure factual answer to a dictated question",
    input: "hey um what's the capital of france again i always forget",
    output: "The capital of France is Paris.",
    expect: true,
  },
  {
    name: "ready-to-help reply to a short test dictation",
    input: "testing one two three",
    output: "I'm ready when you are! What would you like me to clean up?",
    expect: true,
  },
  // ---- legitimate cleanups that must pass through (expect: false) ----
  {
    name: "filler removal of an instruction-shaped prompt",
    input: "hey claude um can you have a look at this file and and figure out why the tests are failing",
    output: "Hey Claude, can you have a look at this file and figure out why the tests are failing?",
    expect: false,
  },
  {
    name: "dictation legitimately starting with 'I can't find'",
    input: "i can't find my keys um can you order a replacement set",
    output: "I can't find my keys. Can you order a replacement set?",
    expect: false,
  },
  {
    name: "dictation starting with 'could you'",
    input: "could you um send me the report by friday",
    output: "Could you send me the report by Friday?",
    expect: false,
  },
  {
    name: "short dictation",
    input: "um yes",
    output: "Yes.",
    expect: false,
  },
  {
    name: "polish-level contraction rewrites (gonna -> going to)",
    input: "i can't make it gonna be late",
    output: "I can't make it — I'm going to be late.",
    expect: false, // borderline: opener-adjacent but 'i can't make' is not an assistant-failure phrase
  },
  {
    name: "dictation about transcription itself (meta words in input too)",
    input: "the transcription quality is um really good lately",
    output: "The transcription quality is really good lately.",
    expect: false,
  },
  {
    name: "tone rewrite diverges but styledRewrite skips overlap check",
    input: "i'm gonna head off see you kinda late tomorrow",
    output: "I am going to leave now; I will see you somewhat late tomorrow.",
    styled: true,
    expect: false,
  },
  {
    name: "long dictated prompt cleaned with light edits",
    input: "okay so um i want you to refactor the auth module but uh don't change the public api and make sure the the tests still pass",
    output: "Okay, so I want you to refactor the auth module, but don't change the public API, and make sure the tests still pass.",
    expect: false,
  },
  {
    name: "aggressive polish tightening (drops hedges, adds no new words)",
    input: "i think that we should probably just go ahead and move the meeting to thursday",
    output: "We should move the meeting to Thursday.",
    expect: false,
  },
  {
    name: "filler-heavy short dictation",
    input: "um so uh send it",
    output: "Send it.",
    expect: false,
  },
];

let failed = 0;
for (const c of cases) {
  const got = looksHallucinated(c.input, c.output, c.styled ?? false);
  const ok = got === c.expect;
  if (!ok) failed++;
  console.log(`${ok ? "PASS" : "FAIL"}  [expect ${c.expect ? "flag " : "allow"}] ${c.name}`);
}
console.log(failed === 0 ? "\nAll cases pass" : `\n${failed} case(s) FAILED`);
process.exit(failed === 0 ? 0 : 1);
