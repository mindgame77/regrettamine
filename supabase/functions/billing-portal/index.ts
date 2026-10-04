// Opens a Stripe Customer Portal session for the signed-in user.
// verify_jwt is true. The client falls back to the portal login URL if this fails.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PORTAL_CONFIG = "bpc_1UMuvYHcbGkfjKgmIKZWNWhe";
const RETURN_URL = "https://mindgame77.github.io/regrettamine/settings/?tab=billing";

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

function rank(row: Record<string, unknown>): number {
  const end = typeof row.current_period_end === "string" ? Date.parse(row.current_period_end) : 0;
  const live = row.status === "active" && end > Date.now();
  if (live && row.flagged !== true) return 0;
  if (live) return 1;
  if (row.payment_failed_at) return 2;
  return 3;
}

async function rememberCard(url: string, service: string, stripeKey: string, customer: string) {
  try {
    const custRes = await fetch(`https://api.stripe.com/v1/customers/${customer}`, {
      headers: { Authorization: `Bearer ${stripeKey}` },
    });
    if (!custRes.ok) return;
    const cust = await custRes.json();
    let brand = "";
    let last4 = "";
    const preset = cust && cust.invoice_settings && cust.invoice_settings.default_payment_method;
    const pmId = typeof preset === "string" ? preset : (preset && preset.id);
    if (pmId) {
      const pmRes = await fetch(`https://api.stripe.com/v1/payment_methods/${pmId}`, {
        headers: { Authorization: `Bearer ${stripeKey}` },
      });
      if (pmRes.ok) {
        const pm = await pmRes.json();
        brand = pm && pm.card && pm.card.brand || "";
        last4 = pm && pm.card && pm.card.last4 || "";
      }
    }
    if (!/^[0-9]{4}$/.test(last4)) {
      const list = await fetch(`https://api.stripe.com/v1/customers/${customer}/payment_methods?type=card&limit=1`, {
        headers: { Authorization: `Bearer ${stripeKey}` },
      });
      if (list.ok) {
        const payload = await list.json();
        const card = payload && payload.data && payload.data[0] && payload.data[0].card;
        brand = card && card.brand || "";
        last4 = card && card.last4 || "";
      }
    }
    if (!/^[0-9]{4}$/.test(last4)) return;
    await fetch(`${url}/rest/v1/subscriptions?stripe_customer_id=eq.${customer}`, {
      method: "PATCH",
      headers: {
        apikey: service,
        Authorization: `Bearer ${service}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify({ card_brand: brand || null, card_last4: last4 }),
    });
  } catch (_e) { /* the stored webhook card remains */ }
}

function pickCustomer(rows: unknown): string {
  const list = (Array.isArray(rows) ? rows : []).filter((row) => {
    const id = row && row.stripe_customer_id;
    return typeof id === "string" && id.startsWith("cus_");
  });
  list.sort((a, b) => {
    const diff = rank(a) - rank(b);
    if (diff) return diff;
    const ae = typeof a.current_period_end === "string" ? Date.parse(a.current_period_end) : 0;
    const be = typeof b.current_period_end === "string" ? Date.parse(b.current_period_end) : 0;
    return be - ae;
  });
  return list.length ? String(list[0].stripe_customer_id) : "";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const url = Deno.env.get("SUPABASE_URL") || "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") || service;
  const authHeader = req.headers.get("Authorization") || "";
  if (!url || !service || !authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { message: "Sign in to manage your card." });
  }

  const userRes = await fetch(`${url}/auth/v1/user`, {
    headers: { Authorization: authHeader, apikey: anon },
  });
  if (!userRes.ok) return json(401, { message: "Sign in to manage your card." });
  const user = await userRes.json();
  const uid = user && user.id;
  if (typeof uid !== "string" || !UUID_RE.test(uid)) {
    return json(401, { message: "Sign in to manage your card." });
  }

  const subRes = await fetch(
    `${url}/rest/v1/subscriptions?profile_id=eq.${uid}&stripe_customer_id=not.is.null&select=stripe_customer_id,status,flagged,current_period_end,payment_failed_at`,
    { headers: { apikey: service, Authorization: `Bearer ${service}` } },
  );
  if (!subRes.ok) return json(502, { message: "Could not open the billing portal." });
  const customer = pickCustomer(await subRes.json());
  if (!customer) return json(404, { message: "No card on file." });

  const secretRes = await fetch(
    `${url}/rest/v1/app_secrets?key=eq.stripe_secret_key&select=value`,
    { headers: { apikey: service, Authorization: `Bearer ${service}` } },
  );
  if (!secretRes.ok) return json(502, { message: "Could not open the billing portal." });
  const secretRows = await secretRes.json();
  const stripeKey = Array.isArray(secretRows) && secretRows[0] && secretRows[0].value;
  if (!stripeKey) return json(502, { message: "Could not open the billing portal." });

  let cardOnly = false;
  try {
    const incoming = await req.json();
    cardOnly = !!(incoming && incoming.cardOnly);
  } catch (_e) { /* a portal open sends no body */ }

  await rememberCard(url, service, stripeKey, customer);

  if (cardOnly) return json(200, { ok: true });

  const body = new URLSearchParams({
    customer,
    configuration: PORTAL_CONFIG,
    return_url: RETURN_URL,
  });
  const session = await fetch("https://api.stripe.com/v1/billing_portal/sessions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${stripeKey}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });
  if (!session.ok) return json(502, { message: "Could not open the billing portal." });
  const payload = await session.json();
  const portal = payload && payload.url;
  if (typeof portal !== "string" || !portal.startsWith("https://billing.stripe.com/")) {
    return json(502, { message: "Could not open the billing portal." });
  }
  return json(200, { url: portal });
});
