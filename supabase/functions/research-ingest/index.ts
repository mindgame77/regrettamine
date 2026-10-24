// research-ingest: staging intake for an EXTERNAL research bot (dump format 1.2).
// Auth: header x-ingest-key (sha256 checked against public.ingest_keys, active only). verify_jwt = false.
// Writes ONLY to research_queue / research_submissions / research_gaps / firm_lps (staging). Never touches live/public tables.
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

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "x-ingest-key, content-type, authorization", "Access-Control-Max-Age": "86400" };
const json = (b: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(b), { status, headers: { ...CORS, "content-type": "application/json", ...extra } });
// every 400 says what was wrong, how to fix it, and which fields the action needs
const REQUIRED: Record<string, string[]> = { status: ["action"], gaps: ["action"], claim: ["action", "bot_id"], claim_gap: ["action", "bot_id"],
  submit: ["action", "bot_id", "registry_id", "dump", "(optional) lps", "(optional) lps_over_100"], fail: ["action", "bot_id", "registry_id", "reason"], skip: ["action", "bot_id", "registry_id", "reason"] };
const bad = (error: string, hint: string, action?: string) =>
  json({ error, hint, required_fields: action && REQUIRED[action] ? REQUIRED[action] : REQUIRED }, 400);
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

// optional submit.lps: [{lp_name, lp_type, status, source_url, ...}] -> public.firm_lps (only if the dump is accepted)
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

// feedback channel: active public.bot_feedback rows ('*' or a bot_id prefix) are added as a `feedback` field to every
// authenticated JSON reply (success and error). Existing fields are never changed. Read failures never break the reply.
const FEEDBACK_DOC = "https://docs.google.com/document/d/1GFdHpQzV8olMb9dhek5zK_xs_7Env0Pu-1uf6TDdfH4/edit";
async function feedbackFor(bot: string) {
  const { data, error } = await db.from("bot_feedback").select("bot_id, message, created_at").eq("active", true)
    .order("created_at", { ascending: false }).limit(200);
  const messages = error ? [] : (data ?? []).filter((f: any) => f.bot_id === "*" || (bot && bot.startsWith(f.bot_id)))
    .slice(0, 20).map((f: any) => ({ message: f.message, created_at: f.created_at }));
  return { rule: "read and follow these messages and the feedback doc", doc_url: FEEDBACK_DOC, messages };
}
async function withFeedback(res: Response, bot: string): Promise<Response> {
  if (!(res.headers.get("content-type") ?? "").includes("application/json")) return res;
  try {
    const body = await res.clone().json();
    if (!isObj(body) || "feedback" in body) return res;
    const headers = new Headers(res.headers);
    return new Response(JSON.stringify({ ...body, feedback: await feedbackFor(bot) }), { status: res.status, headers });
  } catch { return res; }
}

Deno.serve(async (req) => {
  // one log line per request: action, bot_id, status (never the key)
  const meta = { action: "", bot: "", authed: false };
  let res = await handle(req, meta);
  if (meta.authed) res = await withFeedback(res, meta.bot);
  console.log(JSON.stringify({ evt: "ingest_request", method: req.method, action: meta.action || null, bot_id: meta.bot || null, status: res.status }));
  return res;
});

async function handle(req: Request, meta: { action: string; bot: string; authed: boolean }): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST" && req.method !== "GET") return json({ error: "method not allowed",
    hint: "use POST with header x-ingest-key and a JSON body {action, bot_id, ...}; read-only GET ?action=status|gaps also works (key in header, never in the URL)" }, 405);
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
  let body: any;
  if (req.method === "GET") {
    // read-only GET: ?action=status | gaps (&registry_id=&limit=&bot_id=). Never accepts the key in the query string.
    const u = new URL(req.url);
    if (u.searchParams.has("key") || u.searchParams.has("x-ingest-key")) return bad("key must not be in the URL",
      "remove the key from the query string and send it in header x-ingest-key (or Authorization: Bearer <key>)");
    body = Object.fromEntries(u.searchParams);
    meta.action = String(body.action ?? ""); meta.bot = String(body.bot_id ?? "").slice(0, 100);
    if (body.action !== "status" && body.action !== "gaps") return bad("GET supports only action=status or action=gaps",
      "use ?action=status or ?action=gaps; claim, submit, fail, skip and claim_gap need POST with a JSON body");
  } else {
    const raw = await req.text();
    if (raw.length > MAX_BYTES) return json({ error: `payload too large (${raw.length} bytes, max ${MAX_BYTES})` }, 413);
    try { body = JSON.parse(raw); } catch { return bad("body is not valid JSON",
      'send a JSON object with header content-type: application/json, e.g. {"action":"status","bot_id":"my-bot"}'); }
    if (!isObj(body)) return bad("body must be a JSON object", 'e.g. {"action":"status","bot_id":"my-bot"}');
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
      if (!bot) return bad("bot_id required", "add a stable \"bot_id\" string (the same on every call)", "claim");
      const n = Number(body.count ?? 1);
      if (!Number.isInteger(n) || n < 1 || n > 5) return bad("count must be 1-5", "omit count (defaults to 1) or send an integer 1-5", "claim");
      const { data, error } = await db.rpc("research_claim", { p_bot: bot, p_count: n });
      if (error) return json({ error: "server error" }, 500);
      const firms = (data ?? []).map((f: any) => ({ registry_id: f.registry_id, firm_id: f.registry_id, name: f.name, website: f.website,
        country: f.country, state: f.state, hq_city: f.hq_city, sec_crd: f.sec_crd, lei: f.lei, attempts: f.attempts }));
      return json({ firms, none_left: firms.length === 0 });
    }
    case "submit": {
      if (!bot || typeof body.registry_id !== "string") return bad("bot_id and registry_id required", "send the registry_id you claimed, your bot_id, and the full dump object", "submit");
      const hasLps = body.lps !== undefined && body.lps !== null;
      if (body.lps_over_100 !== undefined && typeof body.lps_over_100 !== "boolean") return bad("lps_over_100 must be boolean",
        "send \"lps_over_100\": true only when the firm has more than 100 LPs (then list at most 100), or omit it", "submit");
      if (hasLps) {
        const le = validateLps(body.lps);
        if (le.length) return json({ error: "invalid lps", errors: le.slice(0, 200), hint: "nothing was stored; fix the lps entries " +
          `(fields: ${LP_FIELDS.join(", ")}; required: lp_name, status confirmed|lead, source_url) or omit lps, then resubmit`,
          required_fields: REQUIRED.submit }, 400);
      }
      const v = validate(body.dump, body.registry_id);
      const valid = v.errors.length === 0;
      const { data, error } = await db.rpc("research_submit", { p_id: body.registry_id, p_bot: bot,
        p_payload: body.dump ?? null, p_count: v.good + v.bad, p_valid: valid, p_errors: valid ? null : v.errors.slice(0, 200) });
      if (error) return json({ error: "server error" }, 500);
      if (data.error) return json({ error: data.error }, 409);
      let lpRes: any = undefined;
      if (valid && (hasLps || body.lps_over_100 === true)) {
        const r = await db.rpc("research_store_lps", { p_id: body.registry_id, p_submission: data.submission_id,
          p_lps: hasLps ? body.lps : [], p_over_100: body.lps_over_100 === true });
        lpRes = r.error ? { ok: false, error: "lps not stored (server error); dump was stored" } : r.data;
      }
      return json({ ok: valid, ...(lpRes !== undefined ? { lps: lpRes } : {}), status: data.status, attempts: data.attempts ?? null, accepted_records: valid ? v.good : 0,
        rejected_records: v.bad, errors: v.errors.slice(0, 200),
        hint: valid ? "stored; claim the next firm" : "not accepted (kept for audit only); fix ALL errors and resubmit the whole dump once (same registry_id, same bot_id)" }, valid ? 200 : 422);
    }
    case "fail": {
      if (!bot || typeof body.registry_id !== "string") return bad("bot_id and registry_id required", "send the registry_id you claimed, the same bot_id, and a short reason", "fail");
      const { data, error } = await db.rpc("research_fail", { p_id: body.registry_id, p_bot: bot, p_reason: String(body.reason ?? "").slice(0, 2000) });
      if (error) return json({ error: "server error" }, 500);
      return data.error ? json({ error: data.error }, 409) : json(data);
    }
    case "skip": {
      // out of scope / duplicate: marks the firm 'skipped' at once, no retries
      if (!bot || typeof body.registry_id !== "string") return bad("bot_id and registry_id required", "send the registry_id you claimed, the same bot_id, and a reason starting with skip:", "skip");
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
      if (!bot) return bad("bot_id required", "add a stable \"bot_id\" string (the same on every call)", "claim_gap");
      const rid = typeof body.registry_id === "string" ? body.registry_id : null;
      const { data, error } = await db.rpc("research_claim_gaps", { p_bot: bot, p_registry: rid });
      if (error) return json({ error: "server error" }, 500);
      return data.error ? json({ error: data.error }, 409) : json(data);
    }
    default: return bad("action must be claim | submit | fail | skip | status | gaps | claim_gap",
      'set "action" to one of the listed values; start with {"action":"status","bot_id":"your-bot"}');
  }
}
