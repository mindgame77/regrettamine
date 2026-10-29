// research-ingest: staging intake for an EXTERNAL research bot (dump format 1.2).
// Auth: header x-ingest-key (sha256 checked against bots.ingest_keys, active only). verify_jwt = false.
// Writes through bot RPCs into the bots schema, and claims research_queue (kept in public) through those RPCs.
// The function still connects with SUPABASE_SERVICE_ROLE_KEY. Each bot RPC sets statement_timeout 30s and
// lock_timeout 5s locally (role settings do not apply through PostgREST's SET ROLE). See bots.bot_writer.
// Kill switch: ingest_settings.ingest_paused = 'true' -> 503. Rate limit per key per minute -> 429.
import { createClient } from "npm:@supabase/supabase-js@2";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const MAX_BYTES = 2_000_000;
const TOP_KEYS = ["schema_version", "firm", "coverage", "records", "leads", "search_log"];
const CERTAINTY = ["adjudicated", "reported", "alleged", "self_reported"];
const ENTITY_TYPES = ["firm", "fund", "partner", "company", "lp", "gp_entity"];
const FIELD_PATHS = ["hq", "founded", "aum", "legal_entities", "people", "peopleMoves", "funds", "latestRaise", "limitedPartners",
  "portfolio", "lawsuits", "regulatoryActions", "sanctions", "controversies", "posts", "reviews", "politicalContext",
  "news", "thesis", "socialAccounts"];
// Fixed legal words (docs/PAGE_DATA_GUIDE.md A2.4). Old words are mapped on arrival so old uploads keep working.
const LEGAL_PATHS = ["lawsuits", "regulatoryActions"];
const LEGAL_STATUS: Record<string, string> = { active: "Active", open: "Active", pending: "Active", ongoing: "Active",
  closed: "Closed", judgment: "Closed", adjudicated: "Closed", final: "Closed", settled: "Settled", dismissed: "Dismissed" };
const LEGAL_SIDE: Record<string, string> = { defendant: "Defendant", plaintiff: "Plaintiff" };
const LEGAL_TOPIC: Record<string, string> = { fraud: "Fraud", contract: "Contract", employment: "Employment", securities: "Securities",
  "regulator action": "Regulator action", regulator_action: "Regulator action", ip: "IP" };
const SOCIAL = ["linkedin", "x", "youtube", "instagram", "tiktok", "facebook", "github", "substack", "medium"];
const AUM_BASIS = ["form_adv_raum", "self_reported"];
const low = (x: unknown) => typeof x === "string" ? x.trim().toLowerCase() : "";
// Maps old legal words to the fixed words in place; returns error texts for words that cannot be mapped.
function legalWords(v: any): string[] {
  const e: string[] = [];
  const st = v.status ?? v.legal_status ?? v.lawsuit_status;
  if (st != null) {
    const k = low(st);
    if (k === "unknown" || k === "") { delete v.status; delete v.legal_status; delete v.lawsuit_status; }
    else if (LEGAL_STATUS[k]) { v.status = LEGAL_STATUS[k]; delete v.legal_status; delete v.lawsuit_status; }
    else e.push(`legal status "${st}" not allowed: use Active, Closed, Settled or Dismissed`);
  }
  const sd = v.side ?? v.firm_party_role;
  if (sd != null) {
    const k = low(sd);
    if (LEGAL_SIDE[k]) { v.side = LEGAL_SIDE[k]; delete v.firm_party_role; }
    else if (k === "other") e.push(`legal side "other" is not allowed: the firm must be the Defendant or the Plaintiff; leave this case out if it is neither`);
    else e.push(`legal side "${sd}" not allowed: use Defendant or Plaintiff`);
  }
  const tp = v.case_type ?? v.topic;
  if (tp != null) {
    const k = low(tp);
    if (LEGAL_TOPIC[k]) { v.case_type = LEGAL_TOPIC[k]; delete v.topic; }
    else e.push(`legal topic "${tp}" not allowed: use Fraud, Contract, Employment, Securities, Regulator action or IP`);
  }
  return e;
}
// Shape checks for one record value by field_path; may normalize the value in place.
function valueChecks(r: any): string[] {
  const v = r.value;
  if (r.field_path === "thesis") {
    if (isObj(v) && typeof (v as any).text === "string") r.value = (v as any).text;
    return typeof r.value === "string" && r.value.trim().length >= 5 ? [] : ["thesis value must be the thesis text (a string, or {text})"];
  }
  if (!isObj(v)) return ["value must be an object"];
  const o: any = v;
  if (LEGAL_PATHS.includes(r.field_path)) return legalWords(o);
  if (r.field_path === "aum" && o.basis != null && !AUM_BASIS.includes(o.basis))
    return [o.basis === "press" ? `aum basis "press" is no longer allowed (A7.3): use form_adv_raum or self_reported, or leave AUM out` : `aum basis must be form_adv_raum or self_reported`];
  if (r.field_path === "news") {
    const e: string[] = [];
    if (typeof o.headline !== "string" || !o.headline.trim()) e.push("news needs headline");
    if (typeof o.outlet !== "string" || !o.outlet.trim()) e.push("news needs outlet");
    if (o.date != null && (typeof o.date !== "string" || !DATE.test(o.date))) e.push("news date must be ISO (YYYY-MM-DD)");
    return e;
  }
  if (r.field_path === "socialAccounts") {
    const e: string[] = [];
    if (!SOCIAL.includes(low(o.platform))) e.push(`social platform must be one of ${SOCIAL.join(", ")}`); else o.platform = low(o.platform);
    if (typeof o.url !== "string" || !URL_OK.test(o.url)) e.push("social account needs url");
    if (o.followers != null && typeof o.followers !== "number") e.push("social followers must be a number");
    if (o.linked_from_firm_site !== true) e.push("social account must be linked from the firm's own website (set linked_from_firm_site true)");
    return e;
  }
  return [];
}
const DATE = /^\d{4}(-\d{2}(-\d{2}([T ][0-9:.]+(Z|[+-]\d{2}:?\d{2})?)?)?)?$/;
const URL_OK = /^https?:\/\/[^\s/]+\.[^\s]+$/i;
const BAD_URL = /(google\.[a-z.]+\/search|bing\.com\/search|duckduckgo\.com\/\?|grok\.com|x\.com\/i\/grok|chatgpt\.com|perplexity\.ai\/search)/i;

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "x-ingest-key, content-type, authorization", "Access-Control-Max-Age": "86400" };
const json = (b: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json", ...extra } });
const REQUIRED: Record<string, string[]> = { status: ["action"], gaps: ["action"], claim: ["action", "bot_id"], claim_gap: ["action", "bot_id"],
  submit: ["action", "bot_id", "registry_id", "dump", "(optional) lps", "(optional) lps_over_100"],
  enrich: ["action", "bot_id", "enrichment {slug or registry_id, sections, confirm, fix, add, leads, notes, (optional) searches}"], fail: ["action", "bot_id", "registry_id", "reason"], sources: ["action"], firm_requests: ["action", "(optional) limit"], needs_source: ["action", "(optional) registry_id, slug, limit"],
  add_source: ["action", "bot_id", "submission_id", "record_id", "url", "(optional) quote"], skip: ["action", "bot_id", "registry_id", "reason"],
  my_results: ["action", "(optional) days 1-30", "(optional) limit 1-30"] };
const bad = (error: string, hint: string, action?: string) =>
  json({ error, hint, required_fields: action && REQUIRED[action] ? REQUIRED[action] : REQUIRED }, 400);
const sha256 = async (s: string) => [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))]
  .map((b) => b.toString(16).padStart(2, "0")).join("");
const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === "object" && !Array.isArray(v);
const GOV = /(\.gov|\.gov\.[a-z]{2}|\.gouv\.[a-z]{2}|\.mil|\.europa\.eu|\.gc\.ca|\.admin\.ch)$/;
function tierOf(url: string, allow: string[]): "trusted" | "other" {
  const h = (url.toLowerCase().match(/^https?:\/\/(?:www\.)?([^/:?#\s]+)/) ?? [])[1] ?? "";
  if (allow.some((d) => h === d || h.endsWith("." + d))) return "trusted";
  if ((GOV.test(h) && !/embass/.test(h)) || /(^|\.)courts?\./.test(h) || /\.courts?\.[a-z.]+$/.test(h)) return "trusted";
  return "other";
}
let allowCache: { at: number; list: string[] } = { at: 0, list: [] };
async function allowlist(): Promise<string[]> {
  if (Date.now() - allowCache.at < 300_000 && allowCache.list.length) return allowCache.list;
  const { data } = await db.from("trusted_source_domains").select("domain");
  if (data?.length) allowCache = { at: Date.now(), list: data.map((r: any) => r.domain) };
  return allowCache.list;
}
function validate(d: unknown, registryId: string, allow: string[] = []) {
  const errors: string[] = [], w: string[] = []; let good = 0, bad = 0;
  const tiers = { trusted: 0, other: 0, needs_source: 0 };
  if (!isObj(d)) return { errors: ["dump must be a JSON object"], good, bad, warnings: w, tiers };
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
    e.push(...valueChecks(r));
    if (!CERTAINTY.includes(r.certainty)) e.push("certainty invalid");
    if (!Array.isArray(r.query_ids)) e.push("query_ids must be an array");
    else for (const q of r.query_ids) if (!qids.has(q)) { e.push(`query_id ${q} not in search_log`); break; }
    let usable = 0, trusted = false;
    (Array.isArray(r.sources) ? r.sources : []).forEach((s: any, j: number) => {
      if (!isObj(s)) { w.push(`${p}: sources[${j}] not an object (ignored)`); return; }
      if (typeof s.url !== "string" || !URL_OK.test(s.url)) { w.push(`${p}: sources[${j}].url missing/invalid (ignored)`); return; }
      if (BAD_URL.test(s.url)) { w.push(`${p}: sources[${j}].url is a search/chat page (ignored); cite the page itself`); return; }
      usable++; if (tierOf(s.url, allow) === "trusted") trusted = true;
      if (typeof s.quote !== "string" || s.quote.trim().length < 5) w.push(`${p}: sources[${j}].quote missing`);
      else if (s.quote.length > 300) w.push(`${p}: sources[${j}].quote > 300 chars`);
      if (typeof s.retrieved_at !== "string" || !DATE.test(s.retrieved_at)) w.push(`${p}: sources[${j}].retrieved_at missing/not ISO`);
      if (s.tier != null && !["T1", "T2", "T3"].includes(s.tier)) w.push(`${p}: sources[${j}].tier should be T1|T2|T3`);
      if (s.body_read != null && typeof s.body_read !== "boolean" || s.firm_controlled != null && typeof s.firm_controlled !== "boolean") w.push(`${p}: sources[${j}].body_read/firm_controlled should be boolean`);
    });
    if (!e.length) tiers[usable === 0 ? "needs_source" : trusted ? "trusted" : "other"]++;
    if (e.length) { bad++; errors.push(`${p}: ${e.join("; ")}`); } else good++;
  });
  return { errors, good, bad, warnings: w, tiers };
}
const LP_TYPES = ["pension", "endowment", "foundation", "sovereign", "family_office", "fund_of_funds", "insurance", "corporate", "other"];
const LP_STATUS = ["confirmed", "lead"];
const SANCTIONS = ["clear", "possible_match", "match", "not_screened"];
const LP_FIELDS = ["lp_name", "lp_type", "country", "commitment_amount", "currency", "fund_name", "commitment_year", "status",
  "source_url", "source_title", "checked_at", "sanctions_result", "notes"];
const MAX_LPS = 100;
function validateLps(lps: unknown): string[] {
  if (!Array.isArray(lps)) return ["lps must be an array of objects"];
  if (lps.length > MAX_LPS) return [`lps has ${lps.length} entries (max ${MAX_LPS}); list the first 100 and send "lps_over_100": true`];
  const e: string[] = [];
  lps.forEach((l: any, i: number) => {
    const p = `lps[${i}]`;
    if (!isObj(l)) { e.push(`${p}: not an object`); return; }
    for (const k of Object.keys(l)) if (!LP_FIELDS.includes(k)) e.push(`${p}.${k}: unknown field`);
    const str = (k: string, max: number) => l[k] == null || (typeof l[k] === "string" && l[k].length <= max) || e.push(`${p}.${k} must be a string <= ${max} chars`);
    if (typeof l.lp_name !== "string" || l.lp_name.trim().length < 2 || l.lp_name.length > 300) e.push(`${p}.lp_name required (2-300 chars)`);
    if (l.lp_type != null && !LP_TYPES.includes(l.lp_type)) e.push(`${p}.lp_type must be one of ${LP_TYPES.join("|")}`);
    if (!LP_STATUS.includes(l.status)) e.push(`${p}.status required: confirmed|lead`);
    if (typeof l.source_url !== "string" || !URL_OK.test(l.source_url)) e.push(`${p}.source_url required (http(s) URL of the page)`);
    else if (BAD_URL.test(l.source_url)) e.push(`${p}.source_url is a search/chat page, not a source page`);
    if (l.sanctions_result != null && !SANCTIONS.includes(l.sanctions_result)) e.push(`${p}.sanctions_result must be one of ${SANCTIONS.join("|")}`);
    if (l.commitment_amount != null && (typeof l.commitment_amount !== "number" || !isFinite(l.commitment_amount) || l.commitment_amount < 0))
      e.push(`${p}.commitment_amount must be a number >= 0 (full units, e.g. 25000000)`);
    if (l.currency != null && (typeof l.currency !== "string" || !/^[A-Za-z]{3}$/.test(l.currency))) e.push(`${p}.currency must be a 3-letter ISO code`);
    if (l.commitment_year != null && (!Number.isInteger(l.commitment_year) || l.commitment_year < 1950 || l.commitment_year > 2100)) e.push(`${p}.commitment_year must be an integer year`);
    if (l.checked_at != null && (typeof l.checked_at !== "string" || !DATE.test(l.checked_at) || isNaN(Date.parse(l.checked_at)))) e.push(`${p}.checked_at must be an ISO date`);
    str("country", 100); str("fund_name", 300); str("source_title", 500); str("notes", 2000);
  });
  return e;
}
const FEEDBACK_DOC = "https://docs.google.com/document/d/1GFdHpQzV8olMb9dhek5zK_xs_7Env0Pu-1uf6TDdfH4/edit";
async function feedbackFor(bot: string) {
  const { data, error } = await db.from("bot_feedback").select("bot_id, message, created_at").eq("active", true)
    .order("created_at", { ascending: false }).limit(200);
  const messages = error ? [] : (data ?? []).filter((f: any) => f.bot_id === "*" || (bot && bot.startsWith(f.bot_id)))
    .slice(0, 20).map((f: any) => ({ message: f.message, created_at: f.created_at }));
  return { rule: "read and follow these messages and the feedback doc", doc_url: FEEDBACK_DOC, messages };
}
const FEEDBACK_BOT = "portal-night-bot";
async function withFeedback(res: Response, bot: string): Promise<Response> {
  if (!bot || !bot.startsWith(FEEDBACK_BOT)) return res;
  if (!(res.headers.get("content-type") ?? "").includes("application/json")) return res;
  try {
    const body = await res.clone().json();
    if (!isObj(body) || "feedback" in body) return res;
    const headers = new Headers(res.headers);
    return new Response(JSON.stringify({ ...body, feedback: await feedbackFor(bot) }), { status: res.status, headers });
  } catch { return res; }
}
// Entry check (A4.6): the bot that sent an upload may read its result. Additive fields; a read failure gives nulls.
const NO_ENTRY = { entry_check: null, entry_notes: null, entry_check_at: null };
async function entryOf(id: unknown): Promise<Record<string, unknown>> {
  if (!Number.isInteger(id)) return { ...NO_ENTRY };
  try {
    const { data, error } = await db.rpc("research_entry_result", { p_sub: id });
    if (error || !isObj(data)) return { ...NO_ENTRY };
    return { entry_check: data.entry_check ?? null, entry_notes: data.entry_notes ?? null, entry_check_at: data.entry_check_at ?? null };
  } catch { return { ...NO_ENTRY }; }
}
Deno.serve(async (req) => {
  const meta = { action: "", bot: "", authed: false };
  let res = await handle(req, meta);
  if (meta.authed) res = await withFeedback(res, meta.bot);
  console.log(JSON.stringify({ evt: "ingest_request", method: req.method, action: meta.action || null, bot_id: meta.bot || null, status: res.status }));
  return res;
});
async function handle(req: Request, meta: { action: string; bot: string; authed: boolean }): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST" && req.method !== "GET") return json({ error: "method not allowed", hint: "use POST with header x-ingest-key and a JSON body" }, 405);
  const authz = req.headers.get("authorization") ?? "";
  const key = req.headers.get("x-ingest-key") || (/^bearer\s+/i.test(authz) ? authz.replace(/^bearer\s+/i, "").trim() : "");
  if (!key) return json({ error: "unauthorized", hint: "send the ingest key in header x-ingest-key (or Authorization: Bearer <key>); never in the URL" }, 401);
  const { data: auth, error: aerr } = await db.rpc("ingest_auth", { p_hash: await sha256(key) });
  if (aerr) return json({ error: "server error" }, 500);
  if (!auth.ok) {
    if (auth.error === "paused") return json({ error: "ingest paused - stop and report" }, 503);
    if (auth.error === "rate_limited") return json({ error: "rate limited - wait 60s" }, 429, { "retry-after": "60" });
    return json({ error: "unauthorized" }, 401);
  }
  meta.authed = true;
  const keyId: string | null = typeof auth.key_id === "string" ? auth.key_id : null;
  let body: any;
  if (req.method === "GET") {
    const u = new URL(req.url);
    if (u.searchParams.has("key") || u.searchParams.has("x-ingest-key")) return bad("key must not be in the URL", "send the key in header x-ingest-key");
    body = Object.fromEntries(u.searchParams);
    meta.action = String(body.action ?? ""); meta.bot = String(body.bot_id ?? "").slice(0, 100);
    if (body.action !== "status" && body.action !== "gaps" && body.action !== "my_results") return bad("GET supports only action=status, action=gaps or action=my_results", "use ?action=status, ?action=gaps or ?action=my_results");
  } else {
    const raw = await req.text();
    if (raw.length > MAX_BYTES) return json({ error: `payload too large (${raw.length} bytes, max ${MAX_BYTES})` }, 413);
    try { body = JSON.parse(raw); } catch { return bad("body is not valid JSON", "send a JSON object"); }
    if (!isObj(body)) return bad("body must be a JSON object", "send a JSON object");
    meta.action = typeof body.action === "string" ? body.action.slice(0, 40) : "";
  }
  const bot = typeof body.bot_id === "string" ? body.bot_id.slice(0, 100) : "";
  meta.bot = bot;
  switch (body.action) {
    case "status": {
      const { data, error } = await db.rpc("research_status");
      return error ? json({ error: "server error" }, 500) : json({ counts: data });
    }
    case "claim": {
      if (!bot) return bad("bot_id required", "add bot_id", "claim");
      const n = Number(body.count ?? 1);
      if (!Number.isInteger(n) || n < 1 || n > 300) return bad("count must be 1-300", "send an integer 1-300", "claim");
      const { data, error } = await db.rpc("research_claim", { p_bot: bot, p_count: n });
      if (error) return json({ error: "server error" }, 500);
      const firms = (data ?? []).map((f: any) => ({ registry_id: f.registry_id, firm_id: f.registry_id, name: f.name, website: f.website, country: f.country, state: f.state, hq_city: f.hq_city, sec_crd: f.sec_crd, lei: f.lei, attempts: f.attempts }));
      if (firms.length && bot === "toxy-researcher-3") {
        const { data: info } = await db.rpc("ondemand_job_info", { p_ids: firms.map((f: any) => f.registry_id) });
        for (const f of firms as any[]) if (info?.[f.registry_id]) Object.assign(f, info[f.registry_id]);
      }
      return json({ firms, none_left: firms.length === 0 });
    }
    case "submit": {
      if (!bot || typeof body.registry_id !== "string") return bad("bot_id and registry_id required", "send registry_id, bot_id, and the dump", "submit");
      const hasLps = body.lps !== undefined && body.lps !== null;
      if (body.lps_over_100 !== undefined && typeof body.lps_over_100 !== "boolean") return bad("lps_over_100 must be boolean", "send true or omit it", "submit");
      if (hasLps) {
        const le = validateLps(body.lps);
        if (le.length) return json({ error: "invalid lps", errors: le.slice(0, 200), hint: "fix the lps entries or omit lps", required_fields: REQUIRED.submit }, 400);
      }
      const v = validate(body.dump, body.registry_id, await allowlist());
      const valid = v.errors.length === 0;
      const { data, error } = await db.rpc("research_submit", { p_id: body.registry_id, p_bot: bot, p_payload: body.dump ?? null, p_count: v.good + v.bad, p_valid: valid, p_errors: valid ? null : v.errors.slice(0, 200) });
      if (error) {
        const msg = String(error.message || error.details || "");
        if (msg.includes("rate_limited:")) return json({ error: "rate_limited: max 20 uploads per minute per bot, retry shortly" }, 429, { "retry-after": "60" });
        return json({ error: "server error" }, 500);
      }
      if (data.error) return json({ error: data.error }, 409);
      if (data.status === "holding") return json({ ok: valid, status: "holding", held_for_checker: true, submission_id: data.submission_id, accepted_records: valid ? v.good : 0, rejected_records: v.bad, errors: v.errors.slice(0, 200), source_tiers: v.tiers, warnings: v.warnings.slice(0, 200), hint: valid ? "stored in holding for the Checker; not written to a page table" : "not accepted (kept in holding for audit); fix ALL errors and resubmit the whole dump", ...(await entryOf(data.submission_id)) }, valid ? 200 : 422);
      let lpRes: any = undefined;
      if (valid && (hasLps || body.lps_over_100 === true)) {
        const r = await db.rpc("research_store_lps", { p_id: body.registry_id, p_submission: data.submission_id, p_lps: hasLps ? body.lps : [], p_over_100: body.lps_over_100 === true });
        lpRes = r.error ? { ok: false, error: "lps not stored (server error); dump was stored" } : r.data;
      }
      return json({ ok: valid, ...(lpRes !== undefined ? { lps: lpRes } : {}), status: data.status, attempts: data.attempts ?? null, accepted_records: valid ? v.good : 0, rejected_records: v.bad, errors: v.errors.slice(0, 200), source_tiers: v.tiers, warnings: v.warnings.slice(0, 200), hint: valid ? (v.tiers.needs_source ? `stored; ${v.tiers.needs_source} record(s) have no usable source: kept as needs_source (hidden until a source is added). Claim the next firm` : "stored; claim the next firm") : "not accepted (kept for audit only); fix ALL errors and resubmit the whole dump once (same registry_id, same bot_id)", submission_id: data.submission_id ?? null, ...(await entryOf(data.submission_id)) }, valid ? 200 : 422);
    }
    case "enrich": {
      if (!bot) return bad("bot_id required", "add bot_id", "enrich");
      const en = body.enrichment;
      if (!isObj(en)) return bad("enrichment must be a JSON object", "send the enrichment object", "enrich");
      if (typeof en.slug !== "string" && typeof en.registry_id !== "string") return bad("enrichment.slug or enrichment.registry_id required", "send the slug or registry_id", "enrich");
      for (const k of ["fix", "add", "leads", "confirm", "searches"]) if (k in en && !Array.isArray(en[k])) return bad(`enrichment.${k} must be an array`, "send an array or omit it", "enrich");
      if ("sections" in en && !isObj(en.sections)) return bad("enrichment.sections must be an object of arrays", "send sections as an object", "enrich");
      const { data, error } = await db.rpc("research_enrich", { p_bot: bot, p_payload: en });
      if (error) return json({ error: "server error" }, 500);
      if (data.error) return json({ error: data.error }, 409);
      return json({ ok: data.valid, ...data, hint: data.valid ? (data.on_page ? "stored and on the firm page (at least one item published or merged); rejected items (if any) list the reason, fix their source and resubmit the whole file" : "stored in the holding area; nothing from this file was published or merged onto a firm page. on_page is true only for bot_id toxy-enricher after an item lands on the page") : "nothing accepted: every item needs a source URL of the page itself (any site; search/chat result pages are not sources)" }, data.valid ? 200 : 422);
    }
    case "sources": {
      const { data, error } = await db.from("trusted_source_domains").select("domain, label, kind, path_like").order("domain");
      return error ? json({ error: "server error" }, 500) : json({ trusted: data, other: "any other http(s) page is accepted and shown as an other source", never: "search or chat result pages (google/bing/duckduckgo search, grok, chatgpt, perplexity search)" });
    }
    case "needs_source": {
      const n = Number(body.limit ?? 100);
      let q = db.from("facts_needing_source").select("submission_id, registry_id, slug, firm_name, record_id, field_path, checklist_item, value, received_at").order("received_at", { ascending: false }).limit(Number.isInteger(n) && n > 0 && n <= 500 ? n : 100);
      if (typeof body.registry_id === "string") q = q.eq("registry_id", body.registry_id);
      if (typeof body.slug === "string") q = q.eq("slug", body.slug);
      const { data, error } = await q;
      return error ? json({ error: "server error" }, 500) : json({ facts: data, count: (data ?? []).length });
    }
    case "firm_requests": {
      const { data, error } = await db.rpc("firm_requests_list", { p_limit: Number.isInteger(body.limit) ? body.limit : 100 });
      return error ? json({ error: "server error" }, 500) : json({ requests: data, count: (data ?? []).length, hint: "add the firm to research_queue with the same name (or website) and it links automatically" });
    }
    case "add_source": {
      if (!bot || !Number.isInteger(body.submission_id) || typeof body.record_id !== "string" || typeof body.url !== "string") return bad("bot_id, submission_id, record_id and url required", "take them from action needs_source", "add_source");
      const { data, error } = await db.rpc("fact_add_source", { p_sub: body.submission_id, p_record: body.record_id, p_url: body.url, p_quote: typeof body.quote === "string" ? body.quote : null, p_by: bot });
      if (error) return json({ error: "server error" }, 500);
      return json(data, data.status === "ok" ? 200 : 400);
    }
    case "fail": {
      if (!bot || typeof body.registry_id !== "string") return bad("bot_id and registry_id required", "send the registry_id and a reason", "fail");
      const { data, error } = await db.rpc("research_fail", { p_id: body.registry_id, p_bot: bot, p_reason: String(body.reason ?? "").slice(0, 2000) });
      if (error) return json({ error: "server error" }, 500);
      return data.error ? json({ error: data.error }, 409) : json(data);
    }
    case "skip": {
      if (!bot || typeof body.registry_id !== "string") return bad("bot_id and registry_id required", "send the registry_id and a reason", "skip");
      const reason = String(body.reason ?? "").slice(0, 1990);
      const { data, error } = await db.rpc("research_skip", { p_id: body.registry_id, p_bot: bot, p_reason: reason.toLowerCase().startsWith("skip:") ? reason : `skip: ${reason}` });
      if (error) return json({ error: "server error" }, 500);
      return data.error ? json({ error: data.error }, 409) : json(data);
    }
    case "gaps": {
      const rid = typeof body.registry_id === "string" ? body.registry_id : null;
      const n = Number(body.limit ?? 100);
      const { data, error } = await db.rpc("research_gaps_list", { p_registry: rid, p_limit: Number.isInteger(n) ? n : 100 });
      return error ? json({ error: "server error" }, 500) : json({ gaps: data, count: (data ?? []).length });
    }
    case "claim_gap": {
      if (!bot) return bad("bot_id required", "add bot_id", "claim_gap");
      const rid = typeof body.registry_id === "string" ? body.registry_id : null;
      const { data, error } = await db.rpc("research_claim_gaps", { p_bot: bot, p_registry: rid });
      if (error) return json({ error: "server error" }, 500);
      return data.error ? json({ error: data.error }, 409) : json(data);
    }
    case "my_results": {
      // Identity comes only from the ingest key (bots.ingest_keys.bot_id); body.bot_id is ignored here.
      if (!keyId) return json({ error: "server error" }, 500);
      const d = Number(body.days ?? 30), n = Number(body.limit ?? 30);
      if (!Number.isInteger(d) || d < 1 || d > 30) return bad("days must be 1-30", "omit days (defaults to 30) or send an integer 1-30", "my_results");
      if (!Number.isInteger(n) || n < 1 || n > 30) return bad("limit must be 1-30", "omit limit (defaults to 30) or send an integer 1-30", "my_results");
      const { data, error } = await db.rpc("research_my_results", { p_key: keyId, p_days: d, p_limit: n });
      if (error || !isObj(data)) return json({ error: "server error" }, 500);
      if (data.ok !== true) return json({ error: data.error ?? "this key is not linked to a bot" }, 403);
      const results = Array.isArray(data.results) ? data.results : [];
      return json({ bot_id: data.bot_id, days: data.days, count: results.length, results,
        hint: "your own uploads only. entry_check is Accepted or Rejected: <reasons>; entry_notes are fix-ups that did not reject. Results are cleared after 30 days" });
    }
    default: return bad("action must be claim | submit | enrich | fail | skip | status | gaps | claim_gap | sources | needs_source | add_source | firm_requests | my_results", "set action to one of the listed values");
  }
}
