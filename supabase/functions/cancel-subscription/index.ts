// Cancels (at period end) or resumes the caller's plan: body {resume?: boolean, reason?, other?}.
// Sets Stripe cancel_at_period_end and mirrors it plus the period end into check_balances.
// A cancel with a reason writes one anonymous exit_reasons row. The Stripe secret is app_secrets.key = 'stripe_secret_key'. verify_jwt is true.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { stripeKey as activeKey } from "../_shared/stripe_env.ts";
import { exitReason } from "../_shared/exit_reason.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FAIL = "We couldn't update your plan. Try again or contact malytskyyo@gmail.com";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json", ...cors } });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const url = Deno.env.get("SUPABASE_URL") || "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") || service;
  const authHeader = req.headers.get("Authorization") || "";
  if (!url || !service || !authHeader.toLowerCase().startsWith("bearer ")) return json(401, { message: "Sign in again." });

  const userRes = await fetch(`${url}/auth/v1/user`, { headers: { Authorization: authHeader, apikey: anon } });
  if (!userRes.ok) return json(401, { message: "Sign in again." });
  const user = await userRes.json();
  const uid = user && user.id;
  if (typeof uid !== "string" || !UUID_RE.test(uid)) return json(401, { message: "Sign in again." });

  const body = await req.json().catch(() => ({}));
  const resume = !!(body && body.resume === true);
  const svc = { apikey: service, Authorization: `Bearer ${service}`, "Content-Type": "application/json" };

  const balRes = await fetch(`${url}/rest/v1/check_balances?user_id=eq.${uid}&select=plan,stripe_subscription_id`, { headers: svc });
  if (!balRes.ok) return json(500, { message: FAIL });
  const bal = (await balRes.json())[0];
  const subId = bal && bal.stripe_subscription_id;
  if (typeof subId !== "string" || !subId.startsWith("sub_")) return json(404, { message: "You don't have a plan to cancel." });

  const stripeKey = activeKey(); // STRIPE_MODE picks live or test
  if (!stripeKey) return json(500, { message: FAIL });

  const subRes = await fetch(`https://api.stripe.com/v1/subscriptions/${encodeURIComponent(subId)}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${stripeKey}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: `cancel_at_period_end=${resume ? "false" : "true"}`,
  });
  if (!subRes.ok) return json(409, { message: FAIL });
  const sub = await subRes.json();
  // current_period_end sits on the subscription in older Stripe API versions and on its items in newer ones.
  const endSec = sub.current_period_end ?? sub.items?.data?.[0]?.current_period_end;
  const periodEnd = typeof endSec === "number" ? new Date(endSec * 1000).toISOString() : null;

  const patch: Record<string, unknown> = { cancel_at_period_end: !!sub.cancel_at_period_end, updated_at: new Date().toISOString() };
  if (periodEnd) patch.period_end = periodEnd;
  const saved = await fetch(`${url}/rest/v1/check_balances?user_id=eq.${uid}`, {
    method: "PATCH", headers: { ...svc, Prefer: "return=minimal" }, body: JSON.stringify(patch),
  });
  if (!saved.ok) return json(500, { message: FAIL });

  const why = resume ? null : exitReason(body, "cancel", bal.plan);
  if (why) {
    await fetch(`${url}/rest/v1/exit_reasons`, { method: "POST", headers: { ...svc, Prefer: "return=minimal" }, body: JSON.stringify(why) });
  }
  return json(200, { cancel_at_period_end: !!sub.cancel_at_period_end, period_end: periodEnd });
});
