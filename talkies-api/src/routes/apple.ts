import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";
import { publicUser, updatePlanForUser, updatePlanByAppleTransaction } from "../db";

const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

const PRO_PRODUCT_IDS = new Set([
  "app.yap.YapIOS.pro.monthly",
  "app.yap.YapIOS.pro.annual",
]);

// ---------------------------------------------------------------------------
// POST /v1/apple/verify
//
// Called by the iOS app immediately after a successful StoreKit 2 purchase.
// Verifies the transaction with Apple's App Store Server API (not the old
// receipt API) and upgrades the user to Pro if the subscription is active.
// ---------------------------------------------------------------------------
app.post("/verify", requireAuth, async (c) => {
  const user = c.get("user");

  let body: { transactionId?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: "invalid_json" }, 400);
  }

  const { transactionId } = body;
  if (!transactionId) {
    return c.json({ error: "missing_transaction_id" }, 400);
  }

  let jwt: string;
  try {
    jwt = await makeAppStoreJWT(c.env);
  } catch (err) {
    console.error("Failed to build App Store JWT:", err);
    return c.json({ error: "apple_auth_failed" }, 500);
  }

  // Try production first, then sandbox (covers TestFlight and simulator).
  const txn =
    (await fetchTransaction(transactionId, jwt, false)) ??
    (await fetchTransaction(transactionId, jwt, true));

  if (!txn) {
    return c.json({ error: "transaction_not_found" }, 404);
  }

  if (!PRO_PRODUCT_IDS.has(txn.productId ?? "")) {
    return c.json({ error: "unexpected_product_id" }, 400);
  }

  // expiresDate is milliseconds since epoch (or absent for non-expiring products).
  const isActive = !txn.expiresDate || txn.expiresDate > Date.now();
  const plan = isActive ? "pro" : "free";

  const updated = await updatePlanForUser(
    c.env.DB,
    user.id,
    plan,
    txn.originalTransactionId ?? transactionId,
  );

  return c.json(publicUser(updated));
});

// ---------------------------------------------------------------------------
// POST /v1/apple/notifications
//
// App Store Server Notifications v2. Apple calls this for every subscription
// lifecycle event (new purchase, renewal, cancellation, refund, etc.).
//
// Configure the endpoint URL in App Store Connect:
//   Your App → App Information → App Store Server Notifications
//   Production URL: https://talkies-api.pat-barlow.workers.dev/v1/apple/notifications
//   Sandbox URL: same (we handle both in the same handler)
//
// Apple signs the payload as a JWS. For a production hardening pass, add full
// x5c certificate chain verification against Apple's root CA. For now we do a
// structural decode — the endpoint URL is secret, Apple is the only caller.
// ---------------------------------------------------------------------------
app.post("/notifications", async (c) => {
  let body: { signedPayload?: string };
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: "invalid_json" }, 400);
  }

  if (!body.signedPayload) {
    return c.json({ error: "missing_payload" }, 400);
  }

  const notification = decodeJWS<AppleNotificationPayload>(body.signedPayload);
  if (!notification) {
    return c.json({ error: "invalid_payload" }, 400);
  }

  const { notificationType, subtype, data } = notification;

  // Some notification types (e.g. TEST) have no transaction data.
  if (!data?.signedTransactionInfo) {
    return c.json({ ok: true });
  }

  const txn = decodeJWS<AppleTransactionPayload>(data.signedTransactionInfo);
  if (!txn || !PRO_PRODUCT_IDS.has(txn.productId ?? "")) {
    return c.json({ ok: true });
  }

  const originalTransactionId = txn.originalTransactionId;
  if (!originalTransactionId) return c.json({ ok: true });

  const plan = planFromNotification(notificationType, subtype);
  if (plan !== null) {
    await updatePlanByAppleTransaction(c.env.DB, originalTransactionId, plan);
  }

  return c.json({ ok: true });
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Build a signed JWT for authenticating with the App Store Server API.
 * Requires APPLE_KEY_ID, APPLE_ISSUER_ID, and APPLE_PRIVATE_KEY secrets.
 * APPLE_PRIVATE_KEY should be the full .p8 file content (PEM headers included
 * or just the base64 body — both are handled).
 */
async function makeAppStoreJWT(env: Env): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = base64url(
    JSON.stringify({ alg: "ES256", kid: env.APPLE_KEY_ID, typ: "JWT" }),
  );
  const payload = base64url(
    JSON.stringify({
      iss: env.APPLE_ISSUER_ID,
      iat: now,
      exp: now + 3600,
      aud: "appstoreconnect-v1",
      bid: "app.yap.YapIOS",
    }),
  );

  const signingInput = `${header}.${payload}`;

  // Strip PEM headers/footers and whitespace so the secret can be stored as
  // either a raw base64 string or the full .p8 file content.
  const pemBody = env.APPLE_PRIVATE_KEY.replace(
    /-----(?:BEGIN|END) PRIVATE KEY-----/g,
    "",
  ).replace(/\s/g, "");

  const keyData = Uint8Array.from(atob(pemBody), (ch) => ch.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const sigBytes = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64urlBytes(new Uint8Array(sigBytes))}`;
}

/**
 * Fetch a single transaction from the App Store Server API and decode its JWS.
 * Returns null if the transaction is not found or the request fails.
 */
async function fetchTransaction(
  transactionId: string,
  jwt: string,
  sandbox: boolean,
): Promise<AppleTransactionPayload | null> {
  const host = sandbox
    ? "https://api.storekit-sandbox.itunes.apple.com"
    : "https://api.storekit.itunes.apple.com";

  let res: Response;
  try {
    res = await fetch(`${host}/inApps/v1/transactions/${transactionId}`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
  } catch {
    return null;
  }

  if (!res.ok) return null;

  const { signedTransactionInfo } = (await res.json()) as {
    signedTransactionInfo: string;
  };
  return decodeJWS<AppleTransactionPayload>(signedTransactionInfo);
}

/**
 * Base64url-decode the JWS payload section without verifying the signature.
 * For production hardening, verify the x5c chain against Apple's root CA.
 */
function decodeJWS<T>(jws: string): T | null {
  const parts = jws.split(".");
  if (parts.length !== 3 || !parts[1]) return null;
  try {
    const padded =
      parts[1] +
      "=".repeat((4 - (parts[1].length % 4)) % 4);
    const json = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
    return JSON.parse(json) as T;
  } catch {
    return null;
  }
}

function planFromNotification(
  type: string | undefined,
  subtype: string | undefined,
): "pro" | "free" | null {
  switch (type) {
    case "SUBSCRIBED":
    case "DID_RENEW":
    case "OFFER_REDEEMED":
      return "pro";

    case "EXPIRED":
    case "REVOKED":
      return "free";

    case "DID_CHANGE_RENEWAL_STATUS":
      // CANCEL means auto-renew is off but the subscription is still active.
      // We don't change the plan here — the EXPIRED event will fire when it ends.
      return null;

    case "GRACE_PERIOD_EXPIRED":
      return "free";

    case "REFUND":
    case "REFUND_REVERSED":
      return type === "REFUND" ? "free" : "pro";

    default:
      return null;
  }
}

function base64url(s: string): string {
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function base64urlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

// ---------------------------------------------------------------------------
// Type shapes (subset of Apple's full API — only fields we need)
// ---------------------------------------------------------------------------

interface AppleNotificationPayload {
  notificationType?: string;
  subtype?: string;
  notificationUUID?: string;
  data?: {
    environment?: string;
    bundleId?: string;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}

interface AppleTransactionPayload {
  transactionId?: string;
  originalTransactionId?: string;
  productId?: string;
  type?: string;
  expiresDate?: number; // ms since epoch
  purchaseDate?: number;
  environment?: string;
}

export default app;
