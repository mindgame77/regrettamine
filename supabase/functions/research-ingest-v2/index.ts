// research-ingest-v2: v2 sender. Bots send batches of facts into the v2 database (v2_research_submissions -> entry check -> v2 page tables / Checker queue).
// Auth: header x-ingest-key (same key as research-ingest; sha256 checked by ingest_auth: active, kill switch, rate limit). verify_jwt = false.
// v1 research-ingest is untouched. Doc: plans/newdb/21_v2_sender.md
// add_firm refuses a website whose domain already belongs to a firm, then creates one v2_firms row (or returns the existing firm_id). It does not publish facts.
import { createClient } from "npm:@supabase/supabase-js@2";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const MAX_BYTES = 2_000_000;
const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "x-ingest-key, content-type, authorization" };
const json = (b: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json", ...extra } });
const sha256 = async (s: string) => [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))]
  .map((b) => b.toString(16).padStart(2, "0")).join("");
const HINT = "POST {\"action\":\"add_firm\",\"firm\":{\"name\",\"website\",\"registry_id\"}} or {\"action\":\"submit\",\"dry_run\":false,\"items\":[{\"firm_id\":2,\"box\":\"F5\",\"table\":\"v2_investor_principles\",\"fact\":{...}}]}; max 10 firms per batch";
// Domain only: lowercase, no scheme, no leading www, no port, no path.
const firmDomain = (website: string) => {
  let s = website.trim().toLowerCase();
  s = s.replace(/^[a-z][a-z0-9+.-]*:\/\//, "");
  s = s.replace(/^www\./, "");
  const cut = s.search(/[/?#]/);
  if (cut >= 0) s = s.slice(0, cut);
  return s.replace(/:\d+$/, "");
};
const domainOr = (column: string, domain: string) =>
  [domain, `www.${domain}`, `*://${domain}`, `*://www.${domain}`, `*://${domain}/*`, `*://www.${domain}/*`, `${domain}/*`, `www.${domain}/*`]
    .map((v) => `${column}.ilike."${v.replace(/"/g, "\"\"")}"`).join(",");
const sameDomain = (stored: unknown, domain: string) => typeof stored === "string" && firmDomain(stored) === domain;
// v2_firms wins when both tables have the domain: bots submit facts to that firm_id.
async function existingFirm(domain: string): Promise<{ error?: true; slug?: string; id?: string | number }> {
  const [v1, v2] = await Promise.all([
    db.from("firms").select("id, slug, primary_domain").is("deleted_at", null).or(domainOr("primary_domain", domain)).limit(50),
    db.from("v2_firms").select("firm_id, slug, website_url, archived").or(domainOr("website_url", domain)).limit(50),
  ]);
  if (v1.error || v2.error) return { error: true };
  const row = (v2.data ?? []).find((r) => r.archived !== true && r.slug && sameDomain(r.website_url, domain));
  if (row) return { slug: String(row.slug), id: row.firm_id };
  const firm = (v1.data ?? []).find((r) => r.slug && sameDomain(r.primary_domain, domain));
  if (firm) return { slug: String(firm.slug), id: firm.id };
  return {};
}
Deno.serve(async (req) => {
  let status = 0; let bot = "";
  const res = await (async () => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    if (req.method !== "POST") return json({ error: "method not allowed", hint: HINT }, 405);
    if (new URL(req.url).searchParams.has("key")) return json({ error: "key must not be in the URL", hint: "send it in header x-ingest-key" }, 400);
    const authz = req.headers.get("authorization") ?? "";
    const key = req.headers.get("x-ingest-key") || (/^bearer\s+/i.test(authz) ? authz.replace(/^bearer\s+/i, "").trim() : "");
    if (!key) return json({ error: "unauthorized", hint: "send the ingest key in header x-ingest-key" }, 401);
    const { data: auth, error: aerr } = await db.rpc("ingest_auth", { p_hash: await sha256(key) });
    if (aerr) return json({ error: "server error" }, 500);
    if (!auth.ok) {
      if (auth.error === "paused") return json({ error: "ingest paused - stop and report" }, 503);
      if (auth.error === "rate_limited") return json({ error: "rate limited - wait 60s" }, 429, { "retry-after": "60" });
      return json({ error: "unauthorized" }, 401);
    }
    const raw = await req.text();
    if (raw.length > MAX_BYTES) return json({ error: `payload too large (max ${MAX_BYTES} bytes)` }, 413);
    let body: any; try { body = JSON.parse(raw); } catch { return json({ error: "body is not valid JSON", hint: HINT }, 400); }
    if (!body || typeof body !== "object" || Array.isArray(body)) return json({ error: "body must be a JSON object", hint: HINT }, 400);
    if (body.dry_run !== undefined && typeof body.dry_run !== "boolean") return json({ error: "dry_run must be true or false" }, 400);
    if (body.action === "add_firm") {
      const website = body.firm && typeof body.firm === "object" && !Array.isArray(body.firm) ? body.firm.website : "";
      const domain = typeof website === "string" ? firmDomain(website) : "";
      if (/^[a-z0-9.-]+$/.test(domain) && domain.includes(".") && domain.length <= 253) {
        const existing = await existingFirm(domain);
        if (existing.error) return json({ error: "server error" }, 500);
        if (existing.slug) return json({ error: "a firm with this website already exists", slug: existing.slug, id: existing.id }, 409);
      }
      const { data, error } = await db.rpc("v2_research_add_firm", { p_key_id: auth.key_id, p_firm: body.firm ?? null });
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) return json({ error: data.error }, String(data.error).startsWith("Key frozen") ? 403 : 400);
      return json(data, 200);
    }
    if (body.action === "list_queue" || body.action === "verdict") {  // Checker key only (checked in SQL)
      const args = body.action === "verdict" ? { id: body.id, verdict: body.verdict, reason: body.reason, sources: body.sources } : { limit: body.limit };
      const { data, error } = await db.rpc("v2_checker_action", { p_key_id: auth.key_id, p_action: body.action, p_args: args, p_dry_run: body.dry_run === true });
      if (error || !data) return json({ error: "server error" }, 500);
      bot = data.bot_id ?? "";
      if (!data.ok) return json({ error: data.error }, String(data.error).startsWith("only the Checker") ? 403 : 400);
      return json(data, 200);
    }
    if (body.action !== "submit") return json({ error: "action must be submit, add_firm, list_queue or verdict", hint: HINT }, 400);
    if (!Array.isArray(body.items) || body.items.length === 0) return json({ error: "items must be a non-empty array", hint: HINT }, 400);
    if (body.dry_run !== undefined && typeof body.dry_run !== "boolean") return json({ error: "dry_run must be true or false" }, 400);
    const { data, error } = await db.rpc("v2_research_submit", { p_key_id: auth.key_id, p_items: body.items, p_dry_run: body.dry_run === true });
    if (error || !data) return json({ error: "server error" }, 500);
    bot = data.bot_id ?? "";
    if (!data.ok) return json({ error: data.error }, String(data.error).startsWith("Key frozen") ? 403 : 400);
    return json(data, data.accepted + data.held > 0 || data.dry_run ? 200 : 422);
  })();
  status = res.status;
  console.log(JSON.stringify({ evt: "ingest_v2_request", method: req.method, bot_id: bot || null, status }));
  return res;
});
