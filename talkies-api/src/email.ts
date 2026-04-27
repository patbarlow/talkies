import type { Env } from "./env";

/** 6-digit numeric code, zero-padded, generated with Web Crypto. */
export function generateCode(): string {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return String(buf[0]! % 1_000_000).padStart(6, "0");
}

/** SHA-256 hex of the code, so we never persist the plaintext. */
export async function hashCode(code: string): Promise<string> {
  const data = new TextEncoder().encode(code);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

const SIGN_IN_TEMPLATE_ID = "0907b88a-e1c4-44d8-9be9-f4c8087e4772";

export async function sendCodeEmail(
  env: Env,
  to: string,
  code: string,
): Promise<void> {
  const from = env.RESEND_FROM ?? "Speaking Computer <noreply@speaking.computer>";

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to,
      template: {
        id: SIGN_IN_TEMPLATE_ID,
        variables: {
          product: "Yap",
          verification_code: code,
        },
      },
    }),
  });

  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Resend failed (${res.status}): ${detail}`);
  }
}

export function isValidEmail(raw: string): boolean {
  // Pragmatic, not pedantic. Rejects obvious garbage, accepts the rest.
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(raw) && raw.length <= 320;
}
