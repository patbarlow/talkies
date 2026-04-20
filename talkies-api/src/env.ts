export interface Env {
  DB: D1Database;

  // Secrets (wrangler secret put ...)
  SESSION_SECRET: string;
  GROQ_API_KEY: string;
  ANTHROPIC_API_KEY: string;
  RESEND_API_KEY: string;

  // Optional: custom from-address once your domain is verified with Resend.
  // Defaults to Resend's onboarding address which only sends to addresses
  // you've verified on your Resend account.
  RESEND_FROM?: string;

  // Stripe (optional until you wire up paid plans)
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  STRIPE_PRICE_ID_PRO?: string;
}
