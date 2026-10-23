// Test/live switch for the Payment Link functions. Edge secret STRIPE_MODE=live uses STRIPE_LIVE_SECRET_KEY;
// anything else (default) keeps the sandbox key in app_secrets.stripe_secret_key, so nothing changes until the flip.
export const LIVE_MODE = Deno.env.get("STRIPE_MODE") === "live";
async function appSecret(name: string): Promise<string> {
  const url = Deno.env.get("SUPABASE_URL") || "", key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const r = await fetch(`${url}/rest/v1/app_secrets?key=eq.${name}&select=value`, { headers: { apikey: key, Authorization: `Bearer ${key}` } });
  const rows = r.ok ? await r.json() : [];
  return (Array.isArray(rows) && rows[0] && rows[0].value) || "";
}
// Stripe secret key for a mode (defaults to the active STRIPE_MODE).
export async function stripeKey(live = LIVE_MODE): Promise<string> {
  return live ? (Deno.env.get("STRIPE_LIVE_SECRET_KEY") || "") : await appSecret("stripe_secret_key");
}
// Webhook signing secrets to try: sandbox (app_secrets) and live (STRIPE_LIVE_WEBHOOK_SECRET), whichever are set.
export async function webhookSecrets(): Promise<{ secret: string; live: boolean }[]> {
  const out: { secret: string; live: boolean }[] = [];
  const t = await appSecret("stripe_webhook_secret"); if (t) out.push({ secret: t, live: false });
  const l = Deno.env.get("STRIPE_LIVE_WEBHOOK_SECRET") || ""; if (l) out.push({ secret: l, live: true });
  return out;
}
