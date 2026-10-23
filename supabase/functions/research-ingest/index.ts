// research-ingest: staging intake for an EXTERNAL research bot (dump format 1.2).
// Auth: header x-ingest-key (sha256 checked against public.ingest_keys, active only). verify_jwt = false.
// Writes ONLY to research_queue / research_submissions / research_gaps (staging). Never touches live/public tables.
// Kill switch: ingest_settings.ingest_paused = 'true' -> 503. Rate limit per key per minute -> 429.
import { createClient } from "npm:@supabase/supabase-js@2";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const MAX_BYTES = 2_000_000;
const TOP_KEYS = ["schema_version", "firm", "coverage", "records", "leads", "search_log"];
const CERTAINTY = ["adjudicated", "reported", "alleged", "self_reported"];
const ENTITY_TYPES = ["firm", "fund", "partner", "company", "lp", "gp_entity"];
const FIELD_PATHS = ["hq", "founded", "aum", "legal_entities", "people", "peopleMoves", "funds", "latestRaise", "limitedPartners",
  "portfolio", "lawsuits", "regulatoryActions", "sanctions", "controversies", "posts", "reviews", "politicalContext"];
const DATE = /^\d{4}(-\d{2}(-\d{2}([T ][0-9:.]+(Z|[+-]\d{2}:?\d{2})?)?)?)?$/;
const URL_OK = /^https?:\/\/[^\s/]+\.[^\s]+$/i;
const BAD_URL = /(google\.[a-z.]+\/search|bing\.com\/search|duckduckgo\.com\/\?|grok\.com|x\.com\/i\/grok|chatgpt\.com|perplexity\.ai\/search)/i;

const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { "content-type": "application/json" } });
const sha256 = async (s: string) => [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))]
  .map((b) => b.toString(16).padStart(2, "0")).join("");
const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);

function validate(d: unknown, registryId: string) {
  const errors: string[] = []; let good = 0, bad = 0;
  if (!isObj(d)) return { errors: ["dump must be a JSON object"], good, bad };
  for (const k of TOP_KEYS) if (!(k in d)) errors.push(`missing top-level key: ${k}`);
  if (d.schema_version !== "dump-1.2") errors.push(`schema_version must be "dump-1.2"`);
  if (!isObj(d.firm)) errors.push("firm must be an object");
  else {
    for (const k of ["firm_id", "name", "website", "generated_at"]) if (!(k in d.firm)) errors.push(`firm.${k} missing`);
    if (d.firm.firm_id !== registryId) errors.push(`firm.firm_id must equal registry_id "${registryId}"`);
  }
  for (const k of ["coverage", "records", "leads", "search_log"]) if (k in d && !Array.isArray(d[k])) errors.push(`${k} must be an array`);
  if (Array.isArray(d.coverage) && d.coverage.length === 0) errors.push("coverage is empty (one entry per checklist item required)");
  const ids = new Set<string>();
  const qids = new Set((Array.isArray(d.search_log) ? d.search_log : []).map((q: any) => q?.query_id));
  (Array.isArray(d.records) ? d.records : []).forEach((r: any, i: number) => {
    const e: string[] = []; const p = `records[${i}]${r?.record_id ? ` (${r.record_id})` : ""}`;
    if (!isObj(r)) { errors.push(`${p}: not an object`); bad++; return; }
    if (typeof r.record_id !== "string" || !r.record_id) e.push("record_id missing");
    else if (ids.has(r.record_id)) e.push("duplicate record_id"); else ids.add(r.record_id);
    if (!FIELD_PATHS.includes(r.field_path)) e.push(`field_path "${r.field_path}" not allowed`);
    if (!isObj(r.entity) || !ENTITY_TYPES.includes((r.entity as any).type) || !(r.entity as any).name) e.push("entity {id,type,name} invalid");
    if (!isObj(r.value)) e.push("value must be an object");
    if (!CERTAINTY.includes(r.certainty)) e.push("certainty invalid");
    if (!Array.isArray(r.query_ids)) e.push("query_ids must be an array");
    else for (const q of r.query_ids) if (!qids.has(q)) { e.push(`query_id ${q} not in search_log`); break; }
    if (!Array.isArray(r.sources) || r.sources.length === 0) e.push("no sources (every record needs >=1 source)");
    else r.sources.forEach((s: any, j: number) => {
      if (!isObj(s)) { e.push(`sources[${j}] not an object`); return; }
      if (typeof s.url !== "string" || !URL_OK.test(s.url)) e.push(`sources[${j}].url missing/invalid`);
      else if (BAD_URL.test(s.url)) e.push(`sources[${j}].url is a search/chat page, not a source page`);
      if (typeof s.quote !== "string" || s.quote.trim().length < 5) e.push(`sources[${j}].quote missing`);
      else if (s.quote.length > 300) e.push(`sources[${j}].quote > 300 chars`);
      if (typeof s.retrieved_at !== "string" || !DATE.test(s.retrieved_at)) e.push(`sources[${j}].retrieved_at missing/not ISO`);
      if (!["T1", "T2", "T3"].includes(s.tier)) e.push(`sources[${j}].tier invalid`);
      if (typeof s.body_read !== "boolean" || typeof s.firm_controlled !== "boolean") e.push(`sources[${j}].body_read/firm_controlled must be boolean`);
    });
    if (e.length) { bad++; errors.push(`${p}: ${e.join("; ")}`); } else good++;
  });
  return { errors, good, bad };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const key = req.headers.get("x-ingest-key");
  if (!key) return json({ error: "unauthorized" }, 401);
  const { data: auth, error: aerr } = await db.rpc("ingest_auth", { p_hash: await sha256(key) });
  if (aerr) return json({ error: "server error" }, 500);
  if (!auth.ok) {
    if (auth.error === "paused") return json({ error: "ingest paused - stop and report" }, 503);
    if (auth.error === "rate_limited") return new Response(JSON.stringify({ error: "rate limited - wait 60s" }), { status: 429, headers: { "content-type": "application/json", "retry-after": "60" } });
    return json({ error: "unauthorized" }, 401);
  }
  const raw = await req.text();
  if (raw.length > MAX_BYTES) return json({ error: `payload too large (${raw.length} bytes, max ${MAX_BYTES})` }, 413);
  let body: any; try { body = JSON.parse(raw); } catch { return json({ error: "body is not valid JSON" }, 400); }
  const bot = typeof body.bot_id === "string" ? body.bot_id.slice(0, 100) : "";
  switch (body.action) {
    case "status": {
      const { data, error } = await db.rpc("research_status");
      return error ? json({ error: "server error" }, 500) : json({ counts: data });
    }
    case "claim": {
      if (!bot) return json({ error: "bot_id required" }, 400);
      const n = Number(body.count ?? 1);
      if (!Number.isInteger(n) || n < 1 || n > 5) return json({ error: "count must be 1-5" }, 400);
      const { data, error } = await db.rpc("research_claim", { p_bot: bot, p_count: n });
      if (error) return json({ error: "server error" }, 500);
      const firms = (data ?? []).map((f: any) => ({ registry_id: f.registry_id, firm_id: f.registry_id, name: f.name, website: f.website,
        country: f.country, state: f.state, hq_city: f.hq_city, sec_crd: f.sec_crd, lei: f.lei, attempts: f.attempts }));
      return json({ firms, none_left: firms.length === 0 });
    }
    case "submit": {
      if (!bot || typeof body.registry_id !== "string") return json({ error: "bot_id and registry_id required" }, 400);
      const v = validate(body.dump, body.registry_id);
      const valid = v.errors.length === 0;
      const { data, error } = await db.rpc("research_submit", { p_id: body.registry_id, p_bot: bot,
        p_payload: body.dump ?? null, p_count: v.good + v.bad, p_valid: valid, p_errors: valid ? null : v.errors.slice(0, 200) });
      if (error) return json({ error: "server error" }, 500);
      if (data.error) return json({ error: data.error }, 409);
      return json({ ok: valid, status: data.status, attempts: data.attempts ?? null, accepted_records: valid ? v.good : 0,
        rejected_records: v.bad, errors: v.errors.slice(0, 200),
        hint: valid ? "stored; claim the next firm" : "not accepted (kept for audit only); fix ALL errors and resubmit the whole dump once (same registry_id, same bot_id)" }, valid ? 200 : 422);
    }
    case "fail": {
      if (!bot || typeof body.registry_id !== "string") return json({ error: "bot_id and registry_id required" }, 400);
      const { data, error } = await db.rpc("research_fail", { p_id: body.registry_id, p_bot: bot, p_reason: String(body.reason ?? "").slice(0, 2000) });
      if (error) return json({ error: "server error" }, 500);
      return data.error ? json({ error: data.error }, 409) : json(data);
    }
    case "skip": {
      // out of scope / duplicate: marks the firm 'skipped' at once, no retries
      if (!bot || typeof body.registry_id !== "string") return json({ error: "bot_id and registry_id required" }, 400);
      const reason = String(body.reason ?? "").slice(0, 1990);
      const { data, error } = await db.rpc("research_skip", { p_id: body.registry_id, p_bot: bot, p_reason: reason.toLowerCase().startsWith("skip:") ? reason : `skip: ${reason}` });
      if (error) return json({ error: "server error" }, 500);
      return data.error ? json({ error: data.error }, 409) : json(data);
    }
    case "gaps": {
      // list open gaps (optionally registry_id) so a gap-fill bot researches ONLY those items
      const rid = typeof body.registry_id === "string" ? body.registry_id : null;
      const n = Number(body.limit ?? 100);
      const { data, error } = await db.rpc("research_gaps_list", { p_registry: rid, p_limit: Number.isInteger(n) ? n : 100 });
      return error ? json({ error: "server error" }, 500) : json({ gaps: data, count: (data ?? []).length });
    }
    case "claim_gap": {
      // claims ALL open gaps of one firm (optional registry_id) and puts the firm in 'claimed' for one merged resubmit
      if (!bot) return json({ error: "bot_id required" }, 400);
      const rid = typeof body.registry_id === "string" ? body.registry_id : null;
      const { data, error } = await db.rpc("research_claim_gaps", { p_bot: bot, p_registry: rid });
      if (error) return json({ error: "server error" }, 500);
      return data.error ? json({ error: data.error }, 409) : json(data);
    }
    default: return json({ error: "action must be claim | submit | fail | skip | status | gaps | claim_gap" }, 400);
  }
});
