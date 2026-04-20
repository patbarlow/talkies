import { Hono } from "hono";
import type { Env } from "../env";
import { requireAuth, type AuthVariables } from "../middleware/auth";
import { setStripeCustomerId, updatePlanByStripeCustomer } from "../db";

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
    const customerRes = await fetch("https://api.stripe.com/v1/customers", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${c.env.STRIPE_SECRET_KEY}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        email: user.email ?? "",
        "metadata[user_id]": user.id,
      }).toString(),
    });
    if (!customerRes.ok) {
      return c.json({ error: "stripe_error", detail: await customerRes.text() }, 502);
    }
    const customer = (await customerRes.json()) as { id: string };
    customerId = customer.id;
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
      await updatePlanByStripeCustomer(c.env.DB, sub.customer, plan, sub.id);
      break;
    }
    case "customer.subscription.deleted": {
      const sub = event.data.object as { customer: string };
      await updatePlanByStripeCustomer(c.env.DB, sub.customer, "free", null);
      break;
    }
  }

  return c.json({ received: true });
});

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
