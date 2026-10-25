// Stripe webhook -> grant_checks. Secrets: STRIPE_LIVE/TEST_SECRET_KEY, REGRETAMIN_STRIPE_WEBHOOK_SECRET[_LIVE|_TEST], SUPABASE_SERVICE_ROLE_KEY.
// Deploy with --no-verify-jwt. Events: checkout.session.completed, invoice.paid,
// customer.subscription.updated (mirrors cancel_at_period_end + period end), customer.subscription.deleted (plan ends),
// invoice.payment_failed (past_due; free after 24h unpaid) and invoice.paid (clears past_due), see past_due.js.
import Stripe from "npm:stripe@16";
import { stripeKey, webhookSecrets } from "../_shared/stripe_env.ts";
import { handlePastDue } from "./past_due.js";
import { ensurePaidUser, normalizeEmail, paidAdmin, sessionEmail } from "../_shared/paid_user.ts";
const clients = { live: new Stripe(stripeKey(true)), test: new Stripe(stripeKey(false)) };
const verifier = clients.test; // signature checks need no key
const admin = paidAdmin();
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
  if (ev.type === "checkout.session.completed" || ev.type === "checkout.session.async_payment_succeeded") {
    const s = ev.data.object as Stripe.Checkout.Session;
    const paid = s.payment_status === "paid" || s.payment_status === "no_payment_required";
    if (s.mode === "payment" && s.metadata?.kind === "single") {
      const guest = !s.metadata.user_id;
      // Signed-in grants stay on checkout.session.completed only, keyed by the event id (unchanged).
      // A guest is created from the email Stripe collected, only once the session is paid, keyed by the session id
      // so completed and async_payment_succeeded cannot grant the same purchase twice.
      if ((!guest && ev.type === "checkout.session.completed") || (guest && paid)) {
        let uid = s.metadata.user_id || "";
        if (!uid) {
          const email = sessionEmail(s);
          if (!email) return new Response("no email", { status: 500 });
          uid = await ensurePaidUser(admin, email);
        }
        const { error } = await admin.rpc("grant_checks", { p_user: uid, p_kind: "grant_single", p_amount: 1, p_event: guest ? s.id : ev.id, p_customer: s.customer as string | null });
        if (error) return new Response("db error", { status: 500 });
      }
    }
    if (s.mode === "subscription" && paid && !s.metadata?.user_id) {
      const email = sessionEmail(s);
      const subId = typeof s.subscription === "string" ? s.subscription : null;
      if (email && subId) {
        const uid = await ensurePaidUser(admin, email);
        const sub = await stripe.subscriptions.retrieve(subId);
        await stripe.subscriptions.update(subId, { metadata: { ...sub.metadata, user_id: uid } });
      }
    }
  }
  if (ev.type === "invoice.payment_failed" || ev.type === "invoice.paid") {
    const bad = await handlePastDue(ev, admin);
    if (bad) return new Response(bad.body, { status: bad.status });
  }
  if (ev.type === "invoice.paid") {
    const inv = ev.data.object as Stripe.Invoice;
    const sub = inv.subscription ? await stripe.subscriptions.retrieve(inv.subscription as string) : null;
    const kind = sub?.metadata?.kind, n = kind === "custom" ? Number(sub?.metadata?.checks) : kind && PLAN[kind];
    let uid = sub?.metadata?.user_id || "";
    if (sub && kind && n && n > 0 && !uid) {
      const email = normalizeEmail(inv.customer_email || sub.metadata?.email || "");
      if (!email) return new Response("no email", { status: 500 });
      uid = await ensurePaidUser(admin, email);
      await stripe.subscriptions.update(sub.id, { metadata: { ...sub.metadata, user_id: uid } });
    }
    if (sub && kind && n && n > 0 && uid) {
      // monthly_checks = checks per month (shown on Account); only yearly plans get next_refill, so only they are refilled hourly by refill_yearly_checks
      const yearly = sub.items.data[0]?.price.recurring?.interval === "year";
      const { error } = await admin.rpc("grant_checks", { p_user: uid, p_kind: "grant_plan", p_amount: n, p_event: ev.id,
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
