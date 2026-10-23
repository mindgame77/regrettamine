// Checks a promo code for the pricing popups (no sign-in needed; nothing is redeemed here).
// Body { code }. Returns { ok:false } or { ok:true, code, percent_off|amount_off, duration, months, kinds, hidden }.
// create-checkout re-checks the code and applies the discount itself. Secrets: STRIPE_SECRET_KEY + price IDs (see _shared/stripe_plans.ts).
import Stripe from "npm:stripe@16";
import { lookupCode } from "../_shared/stripe_plans.ts";
import { stripeKey } from "../_shared/stripe_env.ts";
const stripe = new Stripe(stripeKey()); // STRIPE_MODE picks the live or test key
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info" };
const json = (o: unknown) => new Response(JSON.stringify(o), { headers: { ...cors, "Content-Type": "application/json" } });
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const { code } = await req.json().catch(() => ({}));
  const c = await lookupCode(stripe, code).catch(() => null);
  if (!c) return json({ ok: false });
  const cp = c.promo.coupon, h = c.hidden;
  return json({
    ok: true, code: c.promo.code, discount: c.discount, percent_off: cp.percent_off, amount_off: cp.amount_off != null ? cp.amount_off / 100 : null,
    duration: cp.duration, months: cp.duration_in_months, kinds: c.kinds,
    hidden: h && { name: h.name, checks: h.checks, amount: h.price.unit_amount! / 100, interval: h.price.recurring!.interval, discount: c.hiddenDiscount },
  });
});
