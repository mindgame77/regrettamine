// Cancels the caller's Stripe subscriptions, then deletes the account.
// The Stripe secret is app_secrets.key = 'stripe_secret_key'. verify_jwt is true.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const PLAN_MSG = "We couldn't cancel your plan, contact malytskyyo@gmail.com";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...cors },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const url = Deno.env.get("SUPABASE_URL") || "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") || service;
  const authHeader = req.headers.get("Authorization") || "";
  if (!url || !service || !authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { message: "Sign in again, then delete the account." });
  }

  const userRes = await fetch(`${url}/auth/v1/user`, {
    headers: { Authorization: authHeader, apikey: anon },
  });
  if (!userRes.ok) return json(401, { message: "Sign in again, then delete the account." });
  const user = await userRes.json();
  const uid = user && user.id;
  if (typeof uid !== "string" || !UUID_RE.test(uid)) {
    return json(401, { message: "Sign in again, then delete the account." });
  }

  const subRes = await fetch(
    `${url}/rest/v1/subscriptions?profile_id=eq.${uid}&select=stripe_subscription_id,status`,
    { headers: { apikey: service, Authorization: `Bearer ${service}` } },
  );
  if (!subRes.ok) return json(500, { message: "Could not delete this account." });
  const subs = await subRes.json();
  const live = (Array.isArray(subs) ? subs : []).filter((row) => {
    const id = row && row.stripe_subscription_id;
    const status = row && row.status;
    return typeof id === "string" && id.startsWith("sub_") && status !== "canceled" && status !== "incomplete_expired";
  });

  if (live.length) {
    const secretRes = await fetch(
      `${url}/rest/v1/app_secrets?key=eq.stripe_secret_key&select=value`,
      { headers: { apikey: service, Authorization: `Bearer ${service}` } },
    );
    if (!secretRes.ok) return json(409, { message: PLAN_MSG });
    const secretRows = await secretRes.json();
    const stripeKey = Array.isArray(secretRows) && secretRows[0] && secretRows[0].value;
    if (!stripeKey) return json(409, { message: PLAN_MSG });

    for (const row of live) {
      const canceled = await fetch(
        `https://api.stripe.com/v1/subscriptions/${encodeURIComponent(row.stripe_subscription_id)}`,
        { method: "DELETE", headers: { Authorization: `Bearer ${stripeKey}` } },
      );
      if (canceled.status === 404) continue;
      if (!canceled.ok) return json(409, { message: PLAN_MSG });
    }

    const ids = live.map((row) => row.stripe_subscription_id).join(",");
    const marked = await fetch(
      `${url}/rest/v1/subscriptions?stripe_subscription_id=in.(${ids})`,
      {
        method: "PATCH",
        headers: {
          apikey: service,
          Authorization: `Bearer ${service}`,
          "Content-Type": "application/json",
          Prefer: "return=minimal",
        },
        body: JSON.stringify({ status: "canceled" }),
      },
    );
    if (!marked.ok) return json(409, { message: PLAN_MSG });
  }

  const deleted = await fetch(`${url}/rest/v1/rpc/delete_my_account`, {
    method: "POST",
    headers: {
      apikey: anon,
      Authorization: authHeader,
      "Content-Type": "application/json",
    },
    body: "{}",
  });
  if (!deleted.ok) {
    const detail = await deleted.text();
    if (detail.includes("couldn't cancel your plan")) return json(409, { message: PLAN_MSG });
    return json(500, { message: "Could not delete this account." });
  }
  return json(200, { deleted: true });
});
