-- Migration: add Apple IAP column
-- Run with:
--   npx wrangler d1 execute talkies --file=migrate-apple.sql          (local)
--   npx wrangler d1 execute talkies --remote --file=migrate-apple.sql (production)

ALTER TABLE users ADD COLUMN apple_original_transaction_id TEXT;
CREATE INDEX IF NOT EXISTS idx_users_apple_txn ON users(apple_original_transaction_id);
