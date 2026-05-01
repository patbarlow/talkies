import type { Env } from "./env";

const MILESTONES = [1, 10, 50, 100, 500, 1000] as const;

export function crossedMilestones(before: number, after: number): number[] {
  return MILESTONES.filter((m) => before < m && after >= m);
}

export function milestoneEventName(n: number): string {
  return n === 1 ? "recording.first" : `recording.${n}`;
}

// Fire-and-forget: never awaited so events never block or fail API responses.
export function fireEvent(
  env: Env,
  event: string,
  email: string,
  payload?: Record<string, string | number | boolean>,
): void {
  void fetch("https://api.resend.com/events/send", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ event, email, ...(payload ? { payload } : {}) }),
  }).catch((e) => console.error(`Resend event "${event}" failed:`, e));
}
