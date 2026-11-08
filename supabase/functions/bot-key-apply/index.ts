// bot-key-apply: an already registered bot picks up its own research key.
// The URL has no secret. The bot posts bot_id and a proof it keeps. The owner approves once.
// The key is returned once in this response, then the database forgets it. verify_jwt = false
// because the bot has no user login. Authorization is the proof plus public.approve_bot_key_pickup.
// The service role stays in this function's environment. It is never sent to the bot.
// Doc: docs/BOT_KEYS.md
import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const MAX_BYTES = 4_000;
const CODES = new Set(["pending", "delivered", "unauthorized", "pending_locked", "already_delivered"]);
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json" } });
const sha256 = async (s: string) =>
  [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))]
    .map((b) => b.toString(16).padStart(2, "0")).join("");

Deno.serve(async (req) => {
  let status = 0;
  let bot = "";
  let code = "unauthorized";
  const res = await (async () => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    if (req.method !== "POST") return json({ ok: false, error: "method not allowed" }, 405);
    if ([...new URL(req.url).searchParams.keys()].length > 0) return json({ ok: false, error: "unauthorized" }, 400);
    const raw = await req.text();
    if (raw.length > MAX_BYTES) return json({ ok: false, error: "unauthorized" }, 413);
    let body: any;
    try { body = JSON.parse(raw); } catch { return json({ ok: false, error: "unauthorized" }, 400); }
    const botId = body && typeof body.bot_id === "string" ? body.bot_id : "";
    const proof = body && typeof body.proof === "string" ? body.proof : "";
    bot = /^[a-z0-9][a-z0-9-]{2,62}$/.test(botId) ? botId : "";
    if (!bot || proof.length < 32 || proof.length > 200) return json({ ok: false, error: "unauthorized" }, 401);
    const proofHash = await sha256(proof);
    const { data, error } = await db.rpc("bot_key_apply", { p_bot_id: bot, p_proof_hash: proofHash });
    if (error || !data || typeof data !== "object") return json({ ok: false, error: "server error" }, 500);
    const rawCode = data.ok ? String(data.status ?? "") : String(data.error ?? "");
    code = CODES.has(rawCode) ? rawCode : "other";
    if (!data.ok) {
      const http = rawCode === "already_delivered" || rawCode === "pending_locked" ? 409 : 401;
      return json({ ok: false, error: CODES.has(rawCode) ? rawCode : "unauthorized" }, http);
    }
    if (data.status === "delivered") {
      const key = typeof data.key === "string" ? data.key : "";
      if (key.length < 20 || key.length > 200) return json({ ok: false, error: "server error" }, 500);
      return json({ ok: true, status: "delivered", key }, 200);
    }
    if (data.status === "pending") {
      const prefix = typeof data.proof_prefix === "string" && /^[0-9a-f]{8}$/.test(data.proof_prefix)
        ? data.proof_prefix : "";
      return json(prefix ? { ok: true, status: "pending", proof_prefix: prefix } : { ok: true, status: "pending" }, 202);
    }
    return json({ ok: false, error: "server error" }, 500);
  })();
  status = res.status;
  console.log(JSON.stringify({ evt: "bot_key_apply", bot_id: bot || null, status, code }));
  return res;
});
