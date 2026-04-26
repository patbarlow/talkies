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
  avatar_data: string | null;
  created_at: string;
  updated_at: string;
}

export const WEEK_LIMIT_FREE = 2_000;

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
}

export function publicUser(u: User): PublicUser {
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
  };
}

export async function upsertUserByEmail(
  db: D1Database,
  email: string,
  name?: string,
): Promise<User> {
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
    return existing;
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
    avatar_data: null,
    created_at: now,
    updated_at: now,
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
