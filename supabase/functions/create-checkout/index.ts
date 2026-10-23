// Creates a Stripe Checkout session for the signed-in user. Body { kind, code? }; kind is single|m10|m30|y10|y30, or "code"
// for the hidden plan a valid code unlocks. Discounts come only from a code re-checked here (never from the browser).
// Secrets: STRIPE_SECRET_KEY (sk_test_ only until launch), price IDs (see _shared/stripe_plans.ts), SITE_URL.
import Stripe from "npm:stripe@16";
import { createClient } from "npm:@supabase/supabase-js@2";
import { type Kind, lookupCode, PRICES } from "../_shared/stripe_plans.ts";
const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);
const CHECKS: Record<Kind, number> = { single: 1, m10: 10, m30: 30, y10: 10, y30: 30 };
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info" };
const err = (error: string, status: number) => new Response(JSON.stringify({ error }), { status, headers: cors });
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
  const site = Deno.env.get("SITE_URL")!;
  const s = await stripe.checkout.sessions.create({
    mode: sub ? "subscription" : "payment", line_items: [{ price, quantity: 1 }], customer_email: user.email ?? undefined,
    client_reference_id: user.id, metadata: meta, ...(discount ? { discounts: [{ promotion_code: c!.promo.id }] } : {}),
    ...(sub ? { subscription_data: { metadata: meta } } : {}),
    success_url: site + "?paid=1", cancel_url: site,
  });
  return new Response(JSON.stringify({ url: s.url }), { headers: { ...cors, "Content-Type": "application/json" } });
});
