// Creates a Stripe Checkout session. Body { kind, code?, email? }; kind is single|m10|m30|y10|y30, or "code"
// for the hidden plan a valid code unlocks. Discounts come only from a code re-checked here (never from the browser).
// Signed-in: reuses the user's Stripe customer (check_balances, then the older subscriptions table) and metadata.user_id.
// Signed-out: email is required and sent as customer_email (prefilled, not a user id). The account is created after payment
// by the webhook, not here. A user whose subscription is active or trialing cannot start another one: 409 { error: "has_plan" }.
// Single one-time checks stay open to subscribers.
// Secrets: STRIPE_MODE + STRIPE_<LIVE|TEST>_SECRET_KEY, price IDs (see _shared/stripe_plans.ts), SITE_URL, SUPABASE_SERVICE_ROLE_KEY.
import Stripe from "npm:stripe@16";
import { createClient } from "npm:@supabase/supabase-js@2";
import { type Kind, lookupCode, PRICES } from "../_shared/stripe_plans.ts";
import { stripeKey } from "../_shared/stripe_env.ts";
import { normalizeEmail, paidAdmin, userIdForEmail } from "../_shared/paid_user.ts";
const stripe = new Stripe(stripeKey()); // STRIPE_MODE picks the live or test key
const CHECKS: Record<Kind, number> = { single: 1, m10: 10, m30: 30, y10: 10, y30: 30 };
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info" };
const err = (error: string, status: number, extra = {}) => new Response(JSON.stringify({ error, ...extra }), { status, headers: { ...cors, "Content-Type": "application/json" } });
const admin = paidAdmin();
const LIVE = ["active", "trialing"];
// The user's Stripe customer ID, if they ever paid: launch balance first, then the older subscriptions table.
async function customerOf(uid: string): Promise<string | null> {
  const { data: b } = await admin.from("check_balances").select("stripe_customer_id").eq("user_id", uid).maybeSingle();
  if (b?.stripe_customer_id) return b.stripe_customer_id;
  const { data: s } = await admin.from("subscriptions").select("stripe_customer_id").eq("profile_id", uid).not("stripe_customer_id", "is", null).maybeSingle();
  return s?.stripe_customer_id ?? null;
}
// A stored customer from the other Stripe mode (e.g. a test customer after STRIPE_MODE=live) does not exist for this key:
// treat it as no customer so checkout falls back to customer_email instead of crashing.
async function usable(customer: string | null): Promise<string | null> {
  if (!customer) return null;
  try {
    const c = await stripe.customers.retrieve(customer);
    return (c as { deleted?: boolean }).deleted ? null : customer;
  } catch (e) {
    if ((e as { code?: string }).code === "resource_missing") return null;
    throw e;
  }
}
// True if Stripe has an active/trialing subscription for this customer, or the DB still shows a running plan.
async function hasPlan(uid: string, customer: string | null): Promise<boolean> {
  if (customer) {
    const { data } = await stripe.subscriptions.list({ customer, status: "all", limit: 20 });
    if (data.some((s) => LIVE.includes(s.status))) return true;
  }
  const { data: b } = await admin.from("check_balances").select("plan, period_end").eq("user_id", uid).maybeSingle();
  if (b?.plan && (!b.period_end || Date.parse(b.period_end) > Date.now())) return true;
  const { data: s } = await admin.from("subscriptions").select("status, current_period_end").eq("profile_id", uid).maybeSingle();
  return !!s && LIVE.includes(s.status) && Date.parse(s.current_period_end) > Date.now();
}
// Cancel / back from Stripe returns to the page the user came from (same site, path only), else /account/.
function cancelUrl(site: string, p: unknown): string {
  const base = site.replace(/\/?$/, "/");
  if (typeof p !== "string" || !/^\/[^/\\]/.test(p) || p.length > 300 || /[\s<>"]/.test(p)) return base + "account/";
  try { const u = new URL(p, base); return u.origin === new URL(base).origin ? u.toString() : base + "account/"; } catch { return base + "account/"; }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try { return await handle(req); } catch (e) {
    console.error(e);
    return err("checkout failed", 500); // keep CORS headers so the site can show the error
  }
});
async function handle(req: Request): Promise<Response> {
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: { user } } = await sb.auth.getUser();
  const body = await req.json().catch(() => ({}));
  const { kind, code, return_path } = body;
  const guest = user ? null : normalizeEmail(body.email);
  if (!user && !guest) return err(body.email ? "bad email" : "sign in", body.email ? 400 : 401);
  const c = code ? await lookupCode(stripe, code).catch(() => null) : null;
  if (code && !c) return err("bad code", 400);
  let price: string, checks: number, name = "", discount: boolean;
  if (kind === "code") {
    if (!c?.hidden) return err("bad kind", 400);
    price = c.hidden.price.id; checks = c.hidden.checks; name = c.hidden.name; discount = c.hiddenDiscount;
  } else if (kind in PRICES) {
    price = PRICES[kind as Kind]; checks = CHECKS[kind as Kind]; discount = !!c?.kinds.includes(kind);
  } else return err("bad kind", 400);
  const plan = kind === "code" ? "custom" : kind, sub = kind !== "single";
  const site = Deno.env.get("SITE_URL")!;
  // Signed-in purchases keep metadata.user_id. A guest email is prefilled only; the webhook creates the account after payment.
  let meta: Record<string, string>, who: { customer: string } | { customer_email?: string; customer_creation?: "always" }, ref: string | undefined, success: string;
  if (user) {
    const customer = await usable(await customerOf(user.id));
    if (sub && await hasPlan(user.id, customer)) return err("has_plan", 409, { has_plan: true });
    meta = { user_id: user.id, kind: plan, checks: String(checks), ...(name ? { name } : {}) };
    who = customer ? { customer } : { customer_email: user.email ?? undefined, ...(sub ? {} : { customer_creation: "always" as const }) };
    ref = user.id; success = site + "?paid=1";
  } else {
    if (sub) {
      const existing = await userIdForEmail(admin, guest!);
      if (existing && await hasPlan(existing, await usable(await customerOf(existing)))) return err("has_plan", 409, { has_plan: true });
    }
    meta = { email: guest!, kind: plan, checks: String(checks), ...(name ? { name } : {}) };
    who = { customer_email: guest!, ...(sub ? {} : { customer_creation: "always" as const }) };
    ref = undefined; success = site + "?paid=1&session_id={CHECKOUT_SESSION_ID}";
  }
  const s = await stripe.checkout.sessions.create({
    mode: sub ? "subscription" : "payment", line_items: [{ price, quantity: 1 }], ...who,
    ...(ref ? { client_reference_id: ref } : {}), metadata: meta, ...(discount ? { discounts: [{ promotion_code: c!.promo.id }] } : {}),
    ...(sub ? { subscription_data: { metadata: meta } } : {}),
    success_url: success, cancel_url: cancelUrl(site, return_path),
    ...(discount ? {} : { allow_promotion_codes: true }), // Stripe rejects allow_promotion_codes together with discounts
  });
  return new Response(JSON.stringify({ url: s.url }), { headers: { ...cors, "Content-Type": "application/json" } });
}
