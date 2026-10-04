// Stripe webhook. verify_jwt is false: Stripe signs the body instead.
// The signing secret lives in app_secrets.key = 'stripe_webhook_secret'.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const TOLERANCE_SEC = 300;

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function hmacHex(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const raw = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return [...new Uint8Array(raw)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function signatureOk(body: string, header: string, secret: string): Promise<boolean> {
  let timestamp = "";
  const signatures: string[] = [];
  for (const part of header.split(",")) {
    const [k, v] = part.split("=", 2);
    if (k === "t") timestamp = v || "";
    if (k === "v1" && v) signatures.push(v);
  }
  if (!timestamp || !/^[0-9]+$/.test(timestamp) || signatures.length === 0) return false;
  const age = Math.abs(Math.floor(Date.now() / 1000) - Number(timestamp));
  if (age > TOLERANCE_SEC) return false;
  const expected = await hmacHex(secret, `${timestamp}.${body}`);
  return signatures.some((sig) => timingSafeEqual(sig, expected));
}

function json(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const url = Deno.env.get("SUPABASE_URL") || "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!url || !key) return json(500, { error: "function is missing its database credentials" });

  const body = await req.text();
  const header = req.headers.get("stripe-signature") || "";
  const secretRes = await fetch(
    `${url}/rest/v1/app_secrets?key=eq.stripe_webhook_secret&select=value`,
    { headers: { apikey: key, Authorization: `Bearer ${key}` } },
  );
  if (!secretRes.ok) return json(500, { error: "could not read the webhook secret" });
  const rows = await secretRes.json();
  const secret = Array.isArray(rows) && rows[0] && rows[0].value;
  if (!secret) return json(500, { error: "stripe_webhook_secret is not set" });
  if (!await signatureOk(body, header, secret)) return json(400, { error: "invalid signature" });

  let event: unknown;
  try {
    event = JSON.parse(body);
  } catch (_err) {
    return json(400, { error: "invalid json" });
  }

  const applied = await fetch(`${url}/rest/v1/rpc/apply_stripe_event`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_event: event }),
  });
  if (!applied.ok) {
    const detail = await applied.text();
    return json(500, { error: "event was not applied", detail: detail.slice(0, 300) });
  }

  let result: { cancel_at_period_end?: unknown } = {};
  try {
    result = await applied.json();
  } catch (_err) {
    result = {};
  }
  const cancelIds = Array.isArray(result.cancel_at_period_end) ? result.cancel_at_period_end : [];
  if (cancelIds.length) {
    const keyRes = await fetch(
      `${url}/rest/v1/app_secrets?key=eq.stripe_secret_key&select=value`,
      { headers: { apikey: key, Authorization: `Bearer ${key}` } },
    );
    const keyRows = keyRes.ok ? await keyRes.json() : [];
    const stripeKey = Array.isArray(keyRows) && keyRows[0] && keyRows[0].value;
    if (stripeKey) {
      for (const id of cancelIds) {
        if (typeof id !== "string" || !id.startsWith("sub_")) continue;
        await fetch(`https://api.stripe.com/v1/subscriptions/${encodeURIComponent(id)}`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${stripeKey}`,
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: "cancel_at_period_end=true",
        });
      }
    }
  }
  return json(200, { received: true });
});
