import { Hono } from "hono";
import type { Env } from "./env";

import authRoutes from "./routes/auth";
import meRoutes from "./routes/me";
import transcribeRoutes from "./routes/transcribe";
import cleanupRoutes from "./routes/cleanup";
import stripeRoutes from "./routes/stripe";
import sessionsRoutes from "./routes/sessions";

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.json({ ok: true, service: "talkies-api" }));
app.get("/healthz", (c) => c.text("ok"));

app.route("/auth", authRoutes);
app.route("/v1/me", meRoutes);
app.route("/v1/transcribe", transcribeRoutes);
app.route("/v1/cleanup", cleanupRoutes);
app.route("/v1/stripe", stripeRoutes);
app.route("/v1/sessions", sessionsRoutes);

app.onError((err, c) => {
  console.error("Unhandled error:", err);
  return c.json({ error: "internal_error", detail: err.message }, 500);
});

export default app;
