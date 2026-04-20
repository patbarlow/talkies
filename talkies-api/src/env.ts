export interface Env {
  DB: D1Database;

  // Vars (wrangler.toml)
  APPLE_BUNDLE_ID: string;

  // Secrets (wrangler secret put ...)
  SESSION_SECRET: string;
  GROQ_API_KEY: string;
  ANTHROPIC_API_KEY: string;
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  STRIPE_PRICE_ID_PRO?: string;
}
