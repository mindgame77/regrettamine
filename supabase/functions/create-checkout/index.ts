// Creates a Stripe Checkout session for the signed-in user. Body { kind, code? }; kind is single|m10|m30|y10|y30, or "code"
// for the hidden plan a valid code unlocks. Discounts come only from a code re-checked here (never from the browser).
// Reuses the user's Stripe customer (check_balances, then the older subscriptions table). A user whose subscription is active or
// trialing cannot start another one: 409 { error: "has_plan", has_plan: true } and the site points them to the billing portal
// (plan changes go through the portal). Single one-time checks stay open to subscribers.
// Secrets: STRIPE_SECRET_KEY (sk_test_ only until launch), price IDs (see _shared/stripe_plans.ts), SITE_URL, SUPABASE_SERVICE_ROLE_KEY.
import Stripe from "npm:stripe@16";
import { createClient } from "npm:@supabase/supabase-js@2";
import { type Kind, lookupCode, PRICES } from "../_shared/stripe_plans.ts";
const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);
const CHECKS: Record<Kind, number> = { single: 1, m10: 10, m30: 30, y10: 10, y30: 30 };
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info" };
const err = (error: string, status: number, extra = {}) => new Response(JSON.stringify({ error, ...extra }), { status, headers: cors });
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const LIVE = ["active", "trialing"];
// The user's Stripe customer ID, if they ever paid: launch balance first, then the older subscriptions table.
async function customerOf(uid: string): Promise<string | null> {
  const { data: b } = await admin.from("check_balances").select("stripe_customer_id").eq("user_id", uid).maybeSingle();
  if (b?.stripe_customer_id) return b.stripe_customer_id;
  const { data: s } = await admin.from("subscriptions").select("stripe_customer_id").eq("profile_id", uid).not("stripe_customer_id", "is", null).maybeSingle();
  return s?.stripe_customer_id ?? null;
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
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return err("sign in", 401);
  const { kind, code } = await req.json();
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
  const meta = { user_id: user.id, kind: plan, checks: String(checks), ...(name ? { name } : {}) };
  const customer = await customerOf(user.id);
  if (sub && await hasPlan(user.id, customer)) return err("has_plan", 409, { has_plan: true });
  const site = Deno.env.get("SITE_URL")!;
  const who = customer ? { customer } : { customer_email: user.email ?? undefined, ...(sub ? {} : { customer_creation: "always" as const }) };
  const s = await stripe.checkout.sessions.create({
    mode: sub ? "subscription" : "payment", line_items: [{ price, quantity: 1 }], ...who,
    client_reference_id: user.id, metadata: meta, ...(discount ? { discounts: [{ promotion_code: c!.promo.id }] } : {}),
    ...(sub ? { subscription_data: { metadata: meta } } : {}),
    success_url: site + "?paid=1", cancel_url: site,
  });
  return new Response(JSON.stringify({ url: s.url }), { headers: { ...cors, "Content-Type": "application/json" } });
});
