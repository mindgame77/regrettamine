// Plans sold by Regretamin and promotion-code lookup, shared by create-checkout and validate-code.
// Secrets: STRIPE_PRICE_SINGLE, STRIPE_PRICE_M10, STRIPE_PRICE_M30, STRIPE_PRICE_Y10, STRIPE_PRICE_Y30.
// Codes are Stripe promotion codes. Optional promotion-code metadata:
//   unlock_price=price_…  the code also unlocks this hidden price (price metadata hidden=true, checks=<per month>, name=<plan name>)
//   unlock_only=true      the code only unlocks the hidden plan; its coupon discount is not applied
import Stripe from "npm:stripe@16";
export type Kind = "single" | "m10" | "m30" | "y10" | "y30";
export const PRICES: Record<Kind, string> = {
  single: Deno.env.get("STRIPE_PRICE_SINGLE")!, m10: Deno.env.get("STRIPE_PRICE_M10")!, m30: Deno.env.get("STRIPE_PRICE_M30")!,
  y10: Deno.env.get("STRIPE_PRICE_Y10")!, y30: Deno.env.get("STRIPE_PRICE_Y30")!,
};
export type Hidden = { price: Stripe.Price; name: string; checks: number };
export type Code = { promo: Stripe.PromotionCode; discount: boolean; kinds: Kind[]; hidden: Hidden | null; hiddenDiscount: boolean };

const productOf = (p: Stripe.Price) => typeof p.product === "string" ? p.product : p.product.id;
let products: Promise<Record<Kind, string>> | null = null;
const kindProducts = (stripe: Stripe) => products ??= Promise.all(Object.entries(PRICES).map(async ([k, id]) => [k, productOf(await stripe.prices.retrieve(id))]))
  .then(Object.fromEntries);

// Returns null if the code does not exist or cannot be used now (inactive, expired, used up, coupon no longer valid, bad hidden price).
export async function lookupCode(stripe: Stripe, raw: string): Promise<Code | null> {
  const code = String(raw ?? "").trim();
  if (!code || code.length > 64) return null;
  const { data } = await stripe.promotionCodes.list({ code, active: true, limit: 1, expand: ["data.coupon.applies_to"] });
  const promo = data[0];
  if (!promo || promo.code.toUpperCase() !== code.toUpperCase()) return null;
  const now = Date.now() / 1000;
  if (promo.expires_at && promo.expires_at < now) return null;
  if (promo.max_redemptions && promo.times_redeemed >= promo.max_redemptions) return null;
  if (!promo.coupon.valid) return null;
  const only = promo.coupon.applies_to?.products;
  const kp = await kindProducts(stripe);
  const discount = promo.metadata?.unlock_only !== "true";
  const kinds = discount ? (Object.keys(PRICES) as Kind[]).filter((k) => !only || only.includes(kp[k])) : [];
  let hidden: Hidden | null = null, hiddenDiscount = false;
  if (promo.metadata?.unlock_price) {
    const price = await stripe.prices.retrieve(promo.metadata.unlock_price, { expand: ["product"] }).catch(() => null);
    const checks = Number(price?.metadata?.checks);
    if (!price || !price.active || price.metadata?.hidden !== "true" || !price.recurring || !(checks > 0) || !price.unit_amount) return null;
    const prod = price.product as Stripe.Product;
    hidden = { price, checks, name: price.metadata.name || prod.name.replace(/^Regretamin\s+/, "") };
    hiddenDiscount = discount && (!only || only.includes(prod.id));
  }
  if (!kinds.length && !hidden) return null;
  return { promo, discount, kinds, hidden, hiddenDiscount };
}
