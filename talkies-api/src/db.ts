export interface User {
  id: string;
  email: string;
  name: string | null;
  plan: "free" | "pro";
  week_words: number;
  total_words: number;
  session_count: number;
  week_start: string;
  stripe_customer_id: string | null;
  stripe_subscription_id: string | null;
  apple_original_transaction_id: string | null;
  avatar_data: string | null;
  created_at: string;
  updated_at: string;
}

export const WEEK_LIMIT_FREE = 2_000;

export interface AppPattern {
  appName: string;
  bundleID: string | null;
  words: number;
  sessions: number;
}

export interface WeekdayPattern {
  weekday: number; // SQLite strftime %w: 0=Sun, 1=Mon … 6=Sat
  words: number;
}

export interface HourPattern {
  hour: number; // 0–23 UTC
  words: number;
}

export interface Patterns {
  topApps: AppPattern[];
  wordsByWeekday: WeekdayPattern[]; // all 7 days
  wordsByHour: HourPattern[];       // non-zero hours only
}

export interface PublicUser {
  id: string;
  email: string;
  name: string | null;
  plan: "free" | "pro";
  weekWords: number;
  totalWords: number;
  weekStart: string;
  weekLimit: number | null;
  hasAvatar: boolean;
  patterns: Patterns | null;
}

export function publicUser(u: User, patterns: Patterns | null = null): PublicUser {
  return {
    id: u.id,
    email: u.email,
    name: u.name,
    plan: u.plan,
    weekWords: u.week_words,
    totalWords: u.total_words,
    weekStart: u.week_start,
    weekLimit: u.plan === "free" ? WEEK_LIMIT_FREE : null,
    hasAvatar: u.avatar_data != null && u.avatar_data.length > 0,
    patterns,
  };
}

export async function getPatterns(db: D1Database, userId: string, tzOffsetMinutes: number): Promise<Patterns> {
  // Clamp offset to a sane range (±14 hours) and build an SQLite modifier string.
  const clamped = Math.max(-840, Math.min(840, tzOffsetMinutes));
  const sign = clamped >= 0 ? "+" : "-";
  const absMin = Math.abs(clamped);
  const hh = String(Math.floor(absMin / 60)).padStart(2, "0");
  const mm = String(absMin % 60).padStart(2, "0");
  const tzModifier = `${sign}${hh}:${mm}`;

  const [appsRes, weekdayRes, hourRes] = await Promise.all([
    db
      .prepare(
        `SELECT app_name, bundle_id, SUM(word_count) AS words, COUNT(*) AS sessions
         FROM sessions
         WHERE user_id = ? AND app_name IS NOT NULL
         GROUP BY app_name, bundle_id
         ORDER BY words DESC
         LIMIT 5`,
      )
      .bind(userId)
      .all<{ app_name: string; bundle_id: string | null; words: number; sessions: number }>(),

    db
      .prepare(
        `SELECT CAST(strftime('%w', datetime(recorded_at, ?)) AS INTEGER) AS weekday,
                SUM(word_count) AS words
         FROM sessions
         WHERE user_id = ?
         GROUP BY weekday`,
      )
      .bind(tzModifier, userId)
      .all<{ weekday: number; words: number }>(),

    db
      .prepare(
        `SELECT CAST(strftime('%H', datetime(recorded_at, ?)) AS INTEGER) AS hour,
                SUM(word_count) AS words
         FROM sessions
         WHERE user_id = ?
         GROUP BY hour
         ORDER BY words DESC`,
      )
      .bind(tzModifier, userId)
      .all<{ hour: number; words: number }>(),
  ]);

  const wdMap = new Map((weekdayRes.results ?? []).map((r) => [r.weekday, r.words]));

  return {
    topApps: (appsRes.results ?? []).map((r) => ({
      appName: r.app_name,
      bundleID: r.bundle_id,
      words: r.words,
      sessions: r.sessions,
    })),
    wordsByWeekday: [0, 1, 2, 3, 4, 5, 6].map((wd) => ({
      weekday: wd,
      words: wdMap.get(wd) ?? 0,
    })),
    wordsByHour: hourRes.results ?? [],
  };
}

export async function upsertUserByEmail(
  db: D1Database,
  email: string,
  name?: string,
): Promise<{ user: User; isNew: boolean }> {
  const existing = await db
    .prepare("SELECT * FROM users WHERE email = ?")
    .bind(email)
    .first<User>();

  if (existing) {
    if (name && !existing.name) {
      await db
        .prepare("UPDATE users SET name = ?, updated_at = ? WHERE id = ?")
        .bind(name, nowISO(), existing.id)
        .run();
      existing.name = name;
    }
    return { user: existing, isNew: false };
  }

  const id = crypto.randomUUID();
  const now = nowISO();
  const weekStart = startOfWeekISO();
  await db
    .prepare(
      `INSERT INTO users (
         id, email, name, plan,
         week_words, total_words, session_count, week_start,
         created_at, updated_at
       ) VALUES (?, ?, ?, 'free', 0, 0, 0, ?, ?, ?)`,
    )
    .bind(id, email, name ?? null, weekStart, now, now)
    .run();

  return {
    user: {
      id,
      email,
      name: name ?? null,
      plan: "free",
      week_words: 0,
      total_words: 0,
      session_count: 0,
      week_start: weekStart,
      stripe_customer_id: null,
      stripe_subscription_id: null,
      apple_original_transaction_id: null,
      avatar_data: null,
      created_at: now,
      updated_at: now,
    },
    isNew: true,
  };
}

export async function getUser(db: D1Database, id: string): Promise<User | null> {
  return await db.prepare("SELECT * FROM users WHERE id = ?").bind(id).first<User>();
}

export async function rotateWeekIfNeeded(db: D1Database, user: User): Promise<User> {
  const currentWeek = startOfWeekISO();
  if (currentWeek > user.week_start) {
    await db
      .prepare("UPDATE users SET week_words = 0, week_start = ?, updated_at = ? WHERE id = ?")
      .bind(currentWeek, nowISO(), user.id)
      .run();
    user.week_words = 0;
    user.week_start = currentWeek;
  }
  return user;
}

export async function recordUsage(
  db: D1Database,
  userId: string,
  words: number,
): Promise<void> {
  await db
    .prepare(
      `UPDATE users SET
         week_words    = week_words + ?,
         total_words   = total_words + ?,
         session_count = session_count + 1,
         updated_at    = ?
       WHERE id = ?`,
    )
    .bind(words, words, nowISO(), userId)
    .run();
}

// Recompute week_words, total_words, and session_count directly from the
// sessions table so the user row is always consistent with the session log
// regardless of which device or code path inserted the sessions.
export async function recomputeUserStats(db: D1Database, user: User): Promise<void> {
  const rotated = await rotateWeekIfNeeded(db, user);
  await db
    .prepare(
      `UPDATE users SET
         week_words    = (SELECT COALESCE(SUM(s.word_count),0) FROM sessions s
                          WHERE s.user_id = users.id AND s.recorded_at >= ?),
         total_words   = (SELECT COALESCE(SUM(s.word_count),0) FROM sessions s
                          WHERE s.user_id = users.id),
         session_count = (SELECT COUNT(*) FROM sessions s WHERE s.user_id = users.id),
         updated_at    = ?
       WHERE id = ?`,
    )
    .bind(rotated.week_start, nowISO(), user.id)
    .run();
}

export async function updatePlanByStripeCustomer(
  db: D1Database,
  customerId: string,
  plan: "free" | "pro",
  subscriptionId: string | null,
): Promise<void> {
  await db
    .prepare(
      `UPDATE users SET plan = ?, stripe_subscription_id = ?, updated_at = ?
       WHERE stripe_customer_id = ?`,
    )
    .bind(plan, subscriptionId, nowISO(), customerId)
    .run();
}

export async function setStripeCustomerId(
  db: D1Database,
  userId: string,
  customerId: string,
): Promise<void> {
  await db
    .prepare("UPDATE users SET stripe_customer_id = ?, updated_at = ? WHERE id = ?")
    .bind(customerId, nowISO(), userId)
    .run();
}

/**
 * Set a user's plan and record the Apple original transaction ID.
 * Used after a successful in-app purchase on iOS.
 */
export async function updatePlanForUser(
  db: D1Database,
  userId: string,
  plan: "free" | "pro",
  appleOriginalTransactionId: string,
): Promise<User> {
  await db
    .prepare(
      `UPDATE users
         SET plan = ?, apple_original_transaction_id = ?, updated_at = ?
       WHERE id = ?`,
    )
    .bind(plan, appleOriginalTransactionId, nowISO(), userId)
    .run();
  const updated = await db
    .prepare("SELECT * FROM users WHERE id = ?")
    .bind(userId)
    .first<User>();
  if (!updated) throw new Error("user not found after update");
  return updated;
}

/**
 * Look up a user by their Apple original transaction ID and update their plan.
 * Used by the App Store Server Notifications webhook for renewals/cancellations.
 */
export async function updatePlanByAppleTransaction(
  db: D1Database,
  originalTransactionId: string,
  plan: "free" | "pro",
): Promise<void> {
  await db
    .prepare(
      `UPDATE users SET plan = ?, updated_at = ?
       WHERE apple_original_transaction_id = ?`,
    )
    .bind(plan, nowISO(), originalTransactionId)
    .run();
}

function nowISO(): string {
  return new Date().toISOString();
}

function startOfWeekISO(): string {
  const now = new Date();
  const day = now.getUTCDay();
  const daysFromMonday = (day + 6) % 7;
  const monday = new Date(now);
  monday.setUTCDate(now.getUTCDate() - daysFromMonday);
  monday.setUTCHours(0, 0, 0, 0);
  return monday.toISOString();
}
