// Stripe webhook -> grant_checks. Secrets: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, SUPABASE_SERVICE_ROLE_KEY.
// Deploy with --no-verify-jwt. Events: checkout.session.completed, invoice.paid.
import Stripe from "npm:stripe@16";
import { createClient } from "npm:@supabase/supabase-js@2";
const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const PLAN: Record<string, number> = { m10: 10, m30: 30 };
Deno.serve(async (req) => {
  let ev: Stripe.Event;
  try {
    ev = await stripe.webhooks.constructEventAsync(await req.text(), req.headers.get("stripe-signature")!, Deno.env.get("STRIPE_WEBHOOK_SECRET")!);
  } catch { return new Response("bad signature", { status: 400 }); }
  if (ev.type === "checkout.session.completed") {
    const s = ev.data.object as Stripe.Checkout.Session;
    if (s.mode === "payment" && s.metadata?.kind === "single") {
      await admin.rpc("grant_checks", { p_user: s.metadata.user_id, p_kind: "grant_single", p_amount: 1, p_event: ev.id, p_customer: s.customer as string | null });
    }
  }
  if (ev.type === "invoice.paid") {
    const inv = ev.data.object as Stripe.Invoice;
    const sub = inv.subscription ? await stripe.subscriptions.retrieve(inv.subscription as string) : null;
    const kind = sub?.metadata?.kind;
    if (sub && kind && PLAN[kind]) {
      await admin.rpc("grant_checks", { p_user: sub.metadata.user_id, p_kind: "grant_plan", p_amount: PLAN[kind], p_event: ev.id,
        p_plan: kind, p_period_end: new Date(sub.current_period_end * 1000).toISOString(), p_customer: sub.customer as string, p_sub: sub.id });
    }
  }
  return new Response("ok");
});
