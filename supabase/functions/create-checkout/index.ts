// Creates a Stripe Checkout session for the signed-in user. Secrets: STRIPE_SECRET_KEY (sk_test_ only until launch),
// STRIPE_PRICE_SINGLE, STRIPE_PRICE_M10, STRIPE_PRICE_M30, SITE_URL.
import Stripe from "npm:stripe@16";
import { createClient } from "npm:@supabase/supabase-js@2";
const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);
const PRICES: Record<string, { price: string; mode: "payment" | "subscription" }> = {
  single: { price: Deno.env.get("STRIPE_PRICE_SINGLE")!, mode: "payment" },
  m10: { price: Deno.env.get("STRIPE_PRICE_M10")!, mode: "subscription" },
  m30: { price: Deno.env.get("STRIPE_PRICE_M30")!, mode: "subscription" },
};
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info" };
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return new Response(JSON.stringify({ error: "sign in" }), { status: 401, headers: cors });
  const { kind } = await req.json();
  const p = PRICES[kind];
  if (!p) return new Response(JSON.stringify({ error: "bad kind" }), { status: 400, headers: cors });
  const site = Deno.env.get("SITE_URL")!;
  const s = await stripe.checkout.sessions.create({
    mode: p.mode, line_items: [{ price: p.price, quantity: 1 }], customer_email: user.email ?? undefined,
    client_reference_id: user.id, metadata: { user_id: user.id, kind },
    ...(p.mode === "subscription" ? { subscription_data: { metadata: { user_id: user.id, kind } } } : {}),
    success_url: site + "?paid=1", cancel_url: site,
  });
  return new Response(JSON.stringify({ url: s.url }), { headers: { ...cors, "Content-Type": "application/json" } });
});
