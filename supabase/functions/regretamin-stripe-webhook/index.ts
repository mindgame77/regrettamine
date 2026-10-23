// Stripe webhook -> grant_checks. Secrets: STRIPE_LIVE/TEST_SECRET_KEY, REGRETAMIN_STRIPE_WEBHOOK_SECRET[_LIVE|_TEST], SUPABASE_SERVICE_ROLE_KEY.
// Deploy with --no-verify-jwt. Events: checkout.session.completed, invoice.paid,
// customer.subscription.updated (mirrors cancel_at_period_end + period end), customer.subscription.deleted (plan ends).
import Stripe from "npm:stripe@16";
import { createClient } from "npm:@supabase/supabase-js@2";
import { stripeKey, webhookSecrets } from "../_shared/stripe_env.ts";
const clients = { live: new Stripe(stripeKey(true)), test: new Stripe(stripeKey(false)) };
const verifier = clients.test; // signature checks need no key
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
// Checks per month. Code-unlocked plans have kind "custom" with checks in subscription metadata (set by create-checkout).
// Yearly-billed plans are refilled monthly by the DB job refill_yearly_checks(); monthly ones by each paid invoice.
const PLAN: Record<string, number> = { m10: 10, m30: 30, y10: 10, y30: 30 };
const monthLater = (t: number) => { const d = new Date(t * 1000); d.setUTCMonth(d.getUTCMonth() + 1); return d.toISOString(); };
Deno.serve(async (req) => {
  let ev: Stripe.Event | null = null;
  const body = await req.text(), sig = req.headers.get("stripe-signature") ?? "";
  for (const secret of webhookSecrets()) {
    try { ev = await verifier.webhooks.constructEventAsync(body, sig, secret); break; } catch { /* try the next endpoint's secret */ }
  }
  if (!ev) return new Response("bad signature", { status: 400 });
  const stripe = ev.livemode ? clients.live : clients.test; // API calls use the key of the event's own mode
  if (ev.type === "checkout.session.completed") {
    const s = ev.data.object as Stripe.Checkout.Session;
    if (s.mode === "payment" && s.metadata?.kind === "single") {
      await admin.rpc("grant_checks", { p_user: s.metadata.user_id, p_kind: "grant_single", p_amount: 1, p_event: ev.id, p_customer: s.customer as string | null });
    }
  }
  if (ev.type === "invoice.paid") {
    const inv = ev.data.object as Stripe.Invoice;
    const sub = inv.subscription ? await stripe.subscriptions.retrieve(inv.subscription as string) : null;
    const kind = sub?.metadata?.kind, n = kind === "custom" ? Number(sub?.metadata?.checks) : kind && PLAN[kind];
    if (sub && kind && n && n > 0) {
      // monthly_checks = checks per month (shown on Account); only yearly plans get next_refill, so only they are refilled hourly by refill_yearly_checks
      const yearly = sub.items.data[0]?.price.recurring?.interval === "year";
      const { error } = await admin.rpc("grant_checks", { p_user: sub.metadata.user_id, p_kind: "grant_plan", p_amount: n, p_event: ev.id,
        p_plan: kind, p_period_end: new Date(sub.current_period_end * 1000).toISOString(), p_customer: sub.customer as string, p_sub: sub.id,
        p_monthly: n, p_next_refill: yearly ? monthLater(sub.current_period_start) : null, p_plan_name: sub.metadata.name ?? null });
      if (error) return new Response("db error", { status: 500 });
    }
  }
  if (ev.type === "customer.subscription.updated") {
    const sub = ev.data.object as Stripe.Subscription;
    const { error } = await admin.from("check_balances").update({ cancel_at_period_end: sub.cancel_at_period_end,
      period_end: new Date(sub.current_period_end * 1000).toISOString(), updated_at: new Date().toISOString() }).eq("stripe_subscription_id", sub.id);
    if (error) return new Response("db error", { status: 500 });
  }
  if (ev.type === "customer.subscription.deleted") {
    const sub = ev.data.object as Stripe.Subscription;
    const { error } = await admin.from("check_balances").update({ plan: null, stripe_subscription_id: null, cancel_at_period_end: false,
      monthly_checks: null, next_refill: null, plan_name: null, updated_at: new Date().toISOString() }).eq("stripe_subscription_id", sub.id);
    if (error) return new Response("db error", { status: 500 });
  }
  return new Response("ok");
});
