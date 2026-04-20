# Yap API

Cloudflare Worker + D1 backing Yap. Email magic-link auth, session JWTs, transcription proxy (Groq Whisper), cleanup proxy (Claude Haiku), weekly word limit for free users, Stripe Checkout + webhook for Pro plans.

## One-time setup

```bash
cd talkies-api
npm install

# Log in once per machine
npx wrangler login

# Create the D1 database — copy the printed database_id into wrangler.toml
npm run db:create

# Apply schema locally and to the edge
npm run db:migrate
npm run db:migrate:remote

# Secrets — run once per secret. Paste the value when prompted.
npx wrangler secret put SESSION_SECRET            # openssl rand -hex 32
npx wrangler secret put GROQ_API_KEY
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put RESEND_API_KEY            # from resend.com
npx wrangler secret put STRIPE_SECRET_KEY
npx wrangler secret put STRIPE_WEBHOOK_SECRET
npx wrangler secret put STRIPE_PRICE_ID_PRO       # after creating the Stripe product
```

For local dev, copy `.dev.vars.example` → `.dev.vars` and fill in the same values.

## Email delivery (Resend)

Sign-in codes go out through [Resend](https://resend.com), from `Yap <noreply@speaking.computer>` (baked in as the default in `email.ts`). `speaking.computer` must be verified in your Resend account for this to deliver.

1. Sign up to Resend and verify `speaking.computer` (DKIM/SPF/DMARC records in Cloudflare DNS).
2. Grab an API key from the Resend dashboard → `wrangler secret put RESEND_API_KEY`.
3. If you ever want a different from-address, override with the `RESEND_FROM` env var:
   ```bash
   npx wrangler secret put RESEND_FROM    # e.g. Yap <hello@speaking.computer>
   ```

## Run

```bash
npm run dev          # local at http://127.0.0.1:8787
npm run deploy       # production on *.workers.dev
```

## Endpoints

All responses are JSON unless noted.

### `POST /auth/email/start`
Send a 6-digit sign-in code to the email.
```
Request:  { email: string }
Response: { sent: true }  |  { error, retry_after? }
```
30-second cooldown per email to prevent spam.

### `POST /auth/email/verify`
Verify the code and get a session.
```
Request:  { email: string, code: string, fullName?: string }
Response: { session: string, user: PublicUser }
```
Codes expire after 10 minutes and are invalidated after 5 failed attempts.

### `GET /v1/me` (authed)
Current user + plan + usage.

### `POST /v1/transcribe` (authed)
Multipart: `audio` (File), `prompt` (optional string).  
Returns `{ text, wordCount }`. Returns `402` if the weekly limit is reached.

### `POST /v1/cleanup` (authed)
```
Request:  { text: string, appName?: string, appBundleID?: string }
Response: { text: string }
```

### `POST /v1/stripe/checkout` (authed)
Creates a Stripe Checkout session for the Pro plan. Returns `{ url }`.

### `POST /v1/stripe/webhook`
Stripe → us. Verifies HMAC-SHA256 signature. Updates `users.plan` on subscription lifecycle events.

## Auth header

```
Authorization: Bearer <session-jwt>
```

The session JWT is signed with `SESSION_SECRET` (HS256), issuer `talkies-api`, 365-day expiry. It carries only the user id; all plan / usage state lives in D1 and is looked up on every request.

## Word-limit logic

- Free plan: `WEEK_LIMIT_FREE = 2000` words per ISO week (resets Monday 00:00 UTC).
- Pre-check: `users.week_words >= limit` → `402` before hitting Groq.
- Post-success: increment `week_words` + `total_words`. Best-effort; one-off failures don't block the user.

## Layout

```
src/
  index.ts              — router
  env.ts                — Env bindings type
  email.ts              — code generation + hashing + Resend sending
  session.ts            — HS256 session JWTs (jose)
  db.ts                 — D1 user queries + weekly rotation
  middleware/auth.ts    — Bearer → user, mounted on /v1/*
  routes/
    auth.ts             — POST /auth/email/start + /auth/email/verify
    me.ts               — GET  /v1/me
    transcribe.ts       — POST /v1/transcribe
    cleanup.ts          — POST /v1/cleanup
    stripe.ts           — POST /v1/stripe/checkout + /v1/stripe/webhook
schema.sql              — run via `npm run db:migrate[:remote]`
```
