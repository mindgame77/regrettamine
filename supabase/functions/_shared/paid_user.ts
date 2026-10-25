// Account for a paid Checkout session. The user is created only after Stripe says the session is paid.
// service role only. No password. Lookup is user_id_for_email (migration); create is GoTrue admin.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export const paidAdmin = () => createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

export function normalizeEmail(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const email = raw.trim().toLowerCase();
  if (email.length < 6 || email.length > 200) return null;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return null;
  return email;
}

export async function userIdForEmail(admin: SupabaseClient, email: string): Promise<string | null> {
  const { data, error } = await admin.rpc("user_id_for_email", { p_email: email });
  if (error) throw error;
  return (data as string | null) || null;
}

// Existing account with this email is linked. A new address gets a confirmed user so the magic link can sign them in.
export async function ensurePaidUser(admin: SupabaseClient, email: string): Promise<string> {
  const existing = await userIdForEmail(admin, email);
  if (existing) return existing;
  const { data, error } = await admin.auth.admin.createUser({ email, email_confirm: true });
  if (data?.user?.id) return data.user.id;
  const again = await userIdForEmail(admin, email);
  if (again) return again;
  throw error ?? new Error("could not create user");
}

type SessionLike = {
  customer_details?: { email?: string | null } | null;
  customer_email?: string | null;
  metadata?: { email?: string } | null;
};

// The address Stripe collected (the payer can edit the prefilled one). Metadata is only a fallback.
export function sessionEmail(s: SessionLike): string | null {
  return normalizeEmail(s.customer_details?.email || s.customer_email || s.metadata?.email || "");
}
