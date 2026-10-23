// Stripe webhook for the Payment Link checkout (sandbox + live). verify_jwt is false: Stripe signs the body instead.
// Signing secrets: sandbox in app_secrets.key = 'stripe_webhook_secret', live in edge secret STRIPE_LIVE_WEBHOOK_SECRET.
// The event must be signed by the secret of its own mode (event.livemode). Cancels use that mode's key (see _shared/stripe_mode.ts).
// Events: checkout.session.completed, customer.subscription.created/updated/deleted, invoice.paid, invoice.payment_failed.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { stripeKey, webhookSecrets } from "../_shared/stripe_mode.ts";

const TOLERANCE_SEC = 300;

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function hmacHex(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
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
  return new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const url = Deno.env.get("SUPABASE_URL") || "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!url || !key) return json(500, { error: "function is missing its database credentials" });

  const body = await req.text();
  const header = req.headers.get("stripe-signature") || "";
  const secrets = await webhookSecrets();
  if (!secrets.length) return json(500, { error: "no webhook secret is set" });
  let signedLive: boolean | null = null;
  for (const s of secrets) if (await signatureOk(body, header, s.secret)) { signedLive = s.live; break; }
  if (signedLive === null) return json(400, { error: "invalid signature" });

  let event: { livemode?: boolean };
  try {
    event = JSON.parse(body);
  } catch (_err) {
    return json(400, { error: "invalid json" });
  }
  if (!!event.livemode !== signedLive) return json(400, { error: "event mode does not match its signing secret" });

  const applied = await fetch(`${url}/rest/v1/rpc/apply_stripe_event`, {
    method: "POST",
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
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
    const sk = await stripeKey(signedLive);
    if (sk) {
      for (const id of cancelIds) {
        if (typeof id !== "string" || !id.startsWith("sub_")) continue;
        await fetch(`https://api.stripe.com/v1/subscriptions/${encodeURIComponent(id)}`, {
          method: "POST",
          headers: { Authorization: `Bearer ${sk}`, "Content-Type": "application/x-www-form-urlencoded" },
          body: "cancel_at_period_end=true",
        });
      }
    }
  }
  return json(200, { received: true });
});
