-- Backfill: recompute word counts for all users from the sessions table.
-- Run once after deploying the updated sessions route.
--
--   npx wrangler d1 execute talkies --file=migrate-recompute-stats.sql          (local)
--   npx wrangler d1 execute talkies --remote --file=migrate-recompute-stats.sql (production)

UPDATE users SET
  week_words    = (SELECT COALESCE(SUM(s.word_count), 0) FROM sessions s
                   WHERE s.user_id = users.id AND s.recorded_at >= users.week_start),
  total_words   = (SELECT COALESCE(SUM(s.word_count), 0) FROM sessions s
                   WHERE s.user_id = users.id),
  session_count = (SELECT COUNT(*) FROM sessions s WHERE s.user_id = users.id),
  updated_at    = datetime('now');
