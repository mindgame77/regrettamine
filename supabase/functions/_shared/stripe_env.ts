// One switch for Stripe test/live: edge secret STRIPE_MODE = "live" | "test" (default test).
// Keys: STRIPE_LIVE_SECRET_KEY / STRIPE_TEST_SECRET_KEY. Prices: STRIPE_<MODE>_PRICE_SINGLE|M10|M30|Y10|Y30.
// Portal: STRIPE_<MODE>_PORTAL_CONFIG. Going back to test = set STRIPE_MODE=test (no deploy needed).
export const LIVE = (Deno.env.get("STRIPE_MODE") || "test") === "live";
const M = LIVE ? "LIVE" : "TEST";
export const stripeKey = (live = LIVE): string => Deno.env.get(live ? "STRIPE_LIVE_SECRET_KEY" : "STRIPE_TEST_SECRET_KEY") || "";
export const price = (kind: string): string => Deno.env.get(`STRIPE_${M}_PRICE_${kind.toUpperCase()}`) || "";
export const portalConfig = (): string => Deno.env.get(`STRIPE_${M}_PORTAL_CONFIG`) || "";
// Signing secrets of the regretamin-stripe-webhook endpoints, any mode (the event's livemode picks the API key).
export const webhookSecrets = (): string[] =>
  ["REGRETAMIN_STRIPE_WEBHOOK_SECRET_LIVE", "REGRETAMIN_STRIPE_WEBHOOK_SECRET_TEST", "REGRETAMIN_STRIPE_WEBHOOK_SECRET"]
    .map((n) => Deno.env.get(n) || "").filter(Boolean);
