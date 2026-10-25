// After Stripe redirects a guest payer home (?paid=1&session_id=cs_…). Verifies the session is paid, creates or
// links the user from the email Stripe collected, and returns a magic-link token_hash so the browser can sign in.
// The browser then asks Supabase Auth to email a fresh magic link (signInWithOtp). Credits stay on the webhook.
// Does not grant credits and does not set a password. Callable with the anon key (verify_jwt). The session id is the secret.
// Secrets: STRIPE_MODE keys (stripe_env), SUPABASE_SERVICE_ROLE_KEY, SITE_URL.
import Stripe from "npm:stripe@16";
import { createClient } from "npm:@supabase/supabase-js@2";
import { stripeKey } from "../_shared/stripe_env.ts";
import { ensurePaidUser, paidAdmin, sessionEmail } from "../_shared/paid_user.ts";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info" };
const err = (error: string, status: number) => new Response(JSON.stringify({ error }), { status, headers: { ...cors, "Content-Type": "application/json" } });
const admin = paidAdmin();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { session_id } = await req.json().catch(() => ({}));
    if (typeof session_id !== "string" || !/^cs_(test|live)_[A-Za-z0-9]+$/.test(session_id) || session_id.length > 200) return err("bad session", 400);
    const live = session_id.startsWith("cs_live_");
    const stripe = new Stripe(stripeKey(live));
    const s = await stripe.checkout.sessions.retrieve(session_id);
    if (s.payment_status !== "paid" && s.payment_status !== "no_payment_required") return err("unpaid", 402);
    const email = sessionEmail(s);
    if (!email) return err("no email", 400);
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
    const { data: { user } } = await sb.auth.getUser();
    if (user?.email && user.email.toLowerCase() === email) {
      return new Response(JSON.stringify({ already: true, email }), { headers: { ...cors, "Content-Type": "application/json" } });
    }
    await ensurePaidUser(admin, email);
    const link = await admin.auth.admin.generateLink({ type: "magiclink", email, options: { redirectTo: Deno.env.get("SITE_URL") || undefined } });
    const token_hash = link.data?.properties?.hashed_token;
    if (!token_hash) return err("no link", 500);
    return new Response(JSON.stringify({ token_hash, email, type: "magiclink" }), { headers: { ...cors, "Content-Type": "application/json" } });
  } catch (e) {
    console.error(e);
    return err("claim failed", 500);
  }
});
