import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";
import { setStripeCustomerId, updatePlanByStripeCustomer } from "../db";
import { fireEvent } from "../events";

const app = new Hono<{ Bindings: Env; Variables: AuthVariables }>();

/**
 * Authed: create a Stripe Checkout session for the Pro plan and return its URL.
 * The client opens the URL in a browser; Stripe redirects back to a deep link.
 */
app.post("/checkout", requireAuth, async (c) => {
  const user = c.get("user");
  if (!c.env.STRIPE_PRICE_ID_PRO) {
    return c.json({ error: "price_not_configured" }, 500);
  }

  let customerId = user.stripe_customer_id;
  if (!customerId) {
    const result = await getOrCreateStripeCustomer(c.env.STRIPE_SECRET_KEY, user.email, user.id);
    if ("error" in result) {
      return c.json({ error: "stripe_error", detail: result.error }, 502);
    }
    customerId = result.customerId;
    await setStripeCustomerId(c.env.DB, user.id, customerId);
  }

  const checkoutRes = await fetch("https://api.stripe.com/v1/checkout/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${c.env.STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      customer: customerId,
      mode: "subscription",
      "line_items[0][price]": c.env.STRIPE_PRICE_ID_PRO,
      "line_items[0][quantity]": "1",
      success_url: "talkies://checkout/success",
      cancel_url: "talkies://checkout/cancel",
    }).toString(),
  });

  if (!checkoutRes.ok) {
    return c.json({ error: "stripe_error", detail: await checkoutRes.text() }, 502);
  }

  const session = (await checkoutRes.json()) as { url: string };
  fireEvent(c.env, "checkout.started", user.email, {
    total_words: user.total_words,
    session_count: user.session_count,
  });
  return c.json({ url: session.url });
});

/**
 * Stripe → us. Verify the webhook signature (HMAC-SHA256 over `{t}.{body}`),
 * then update the user's plan based on subscription lifecycle events.
 */
app.post("/webhook", async (c) => {
  const rawBody = await c.req.text();
  const signature = c.req.header("Stripe-Signature");
  if (!signature) return c.json({ error: "missing_signature" }, 400);

  const verified = await verifyStripeSignature(
    rawBody,
    signature,
    c.env.STRIPE_WEBHOOK_SECRET,
  );
  if (!verified) return c.json({ error: "invalid_signature" }, 400);

  const event = JSON.parse(rawBody) as {
    type: string;
    data: { object: Record<string, unknown> };
  };

  switch (event.type) {
    case "customer.subscription.created":
    case "customer.subscription.updated": {
      const sub = event.data.object as {
        id: string;
        customer: string;
        status: string;
      };
      const plan = sub.status === "active" || sub.status === "trialing" ? "pro" : "free";
      await ensureStripeCustomerLinked(c.env.DB, c.env.STRIPE_SECRET_KEY, sub.customer);
      const preUpdate = await c.env.DB
        .prepare("SELECT email, plan FROM users WHERE stripe_customer_id = ?")
        .bind(sub.customer)
        .first<{ email: string; plan: string }>();
      await updatePlanByStripeCustomer(c.env.DB, sub.customer, plan, sub.id);
      if (plan === "pro" && preUpdate && preUpdate.plan !== "pro") {
        fireEvent(c.env, "subscription.started", preUpdate.email);
      }
      break;
    }
    case "customer.subscription.deleted": {
      const sub = event.data.object as { customer: string };
      await ensureStripeCustomerLinked(c.env.DB, c.env.STRIPE_SECRET_KEY, sub.customer);
      const preUpdate = await c.env.DB
        .prepare("SELECT email FROM users WHERE stripe_customer_id = ?")
        .bind(sub.customer)
        .first<{ email: string }>();
      await updatePlanByStripeCustomer(c.env.DB, sub.customer, "free", null);
      if (preUpdate) fireEvent(c.env, "subscription.cancelled", preUpdate.email);
      break;
    }
  }

  return c.json({ received: true });
});

/**
 * If no user row has stripe_customer_id = customerId, fetch the customer's
 * email from Stripe and set it on the matching user row. This handles the
 * race where the webhook fires before setStripeCustomerId completes.
 */
async function ensureStripeCustomerLinked(
  db: D1Database,
  secretKey: string,
  customerId: string,
): Promise<void> {
  const existing = await db
    .prepare("SELECT id FROM users WHERE stripe_customer_id = ?")
    .bind(customerId)
    .first<{ id: string }>();
  if (existing) return;

  const res = await fetch(`https://api.stripe.com/v1/customers/${customerId}`, {
    headers: { Authorization: `Bearer ${secretKey}` },
  });
  if (!res.ok) return;
  const customer = (await res.json()) as { email?: string };
  if (!customer.email) return;

  await db
    .prepare("UPDATE users SET stripe_customer_id = ?, updated_at = ? WHERE email = ? AND stripe_customer_id IS NULL")
    .bind(customerId, new Date().toISOString(), customer.email)
    .run();
}

/**
 * Returns an existing Stripe customer for the given email (across all products
 * on the account) or creates a new one. This keeps a single customer record
 * per email so the Stripe portal shows all subscriptions in one place.
 */
async function getOrCreateStripeCustomer(
  secretKey: string,
  email: string,
  userId: string,
): Promise<{ customerId: string } | { error: string }> {
  const headers = {
    Authorization: `Bearer ${secretKey}`,
    "Content-Type": "application/x-www-form-urlencoded",
  };

  // Search for an existing customer with this email.
  const searchRes = await fetch(
    `https://api.stripe.com/v1/customers/search?query=${encodeURIComponent(`email:"${email}"`)}`,
    { headers },
  );
  if (searchRes.ok) {
    const result = (await searchRes.json()) as { data: { id: string }[] };
    if (result.data.length > 0 && result.data[0]) {
      return { customerId: result.data[0].id };
    }
  }

  // No existing customer — create one.
  const createRes = await fetch("https://api.stripe.com/v1/customers", {
    method: "POST",
    headers,
    body: new URLSearchParams({
      email,
      "metadata[user_id]": userId,
    }).toString(),
  });
  if (!createRes.ok) {
    return { error: await createRes.text() };
  }
  const customer = (await createRes.json()) as { id: string };
  return { customerId: customer.id };
}

/**
 * Stripe signs the webhook body with HMAC-SHA256 using the endpoint secret.
 * Header format: `t=<timestamp>,v1=<signature>,v1=<signature>,...`
 * We accept the request iff any of the v1 signatures match.
 */
async function verifyStripeSignature(
  body: string,
  header: string,
  secret: string,
): Promise<boolean> {
  const parts = Object.fromEntries(
    header.split(",").map((kv) => {
      const [k, ...rest] = kv.split("=");
      return [k, rest.join("=")];
    }),
  ) as Record<string, string | undefined>;
  const timestamp = parts["t"];
  const expected = header
    .split(",")
    .filter((kv) => kv.startsWith("v1="))
    .map((kv) => kv.slice(3));
  if (!timestamp || expected.length === 0) return false;

  const payload = `${timestamp}.${body}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  const computed = Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  // Constant-time-ish compare.
  return expected.some((cand) => cand.length === computed.length && cand === computed);
}

export default app;
