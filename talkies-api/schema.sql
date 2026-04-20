-- Yap API schema. Apply via `npm run db:migrate[:remote]`.
--
-- NOTE: This rewrites the schema since the auth model changed from Apple sub
-- to email magic link. If you've already run the Apple-based schema, the DROP
-- statements below will discard those tables (no user data should exist yet).

DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS email_codes;

CREATE TABLE users (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    name TEXT,
    plan TEXT NOT NULL DEFAULT 'free',
    week_words INTEGER NOT NULL DEFAULT 0,
    total_words INTEGER NOT NULL DEFAULT 0,
    session_count INTEGER NOT NULL DEFAULT 0,
    week_start TEXT NOT NULL,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_stripe_customer ON users(stripe_customer_id);

CREATE TABLE email_codes (
    email TEXT PRIMARY KEY,
    code_hash TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    expires_at TEXT NOT NULL,
    last_sent_at TEXT NOT NULL
);
