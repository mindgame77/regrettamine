// research-ingest: entry-check fields on upload + my_results (A4.6). No network, no database: supabase-js calls
// are answered by a fake fetch. Run: deno test -A tests/research_ingest_results.test.ts
// Optional differential run: OLD=<path to the version before the change> NEW=<path> also checks that every old
// response field is unchanged (only entry_check, entry_notes, entry_check_at and submission_id may be added).
Deno.env.set("SUPABASE_URL", "http://mock.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-not-a-key");
type H = (r: Request) => Promise<Response>;
const handlers: H[] = [];
(Deno as any).serve = (h: H) => { handlers.push(h); return {} as any; };
const calls: { name: string; args: any }[] = [];
let submitReply: any = {};
let authReply: any = { ok: true, key_id: "11111111-1111-1111-1111-111111111111" };
let entryReply: any = { entry_check: "Rejected: no source link", entry_notes: ["1 date unreadable, cleared"], entry_check_at: "2026-10-29T06:00:00+00:00" };
let myReply: any = { ok: true, bot_id: "bot-a", days: 30, results: [{ submission_id: 1, registry_id: "vc-1", received_at: "t", entry_check: "Accepted", entry_notes: null, entry_check_at: "t" }] };
globalThis.fetch = async (input: any, init?: any) => {
  const u = new URL(typeof input === "string" ? input : input.url);
  const body = init?.body ? JSON.parse(String(init.body)) : null;
  const m = u.pathname.match(/\/rest\/v1\/rpc\/(\w+)/);
  const ok = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { "content-type": "application/json" } });
  if (m) {
    calls.push({ name: m[1], args: body });
    if (m[1] === "ingest_auth") return ok(authReply);
    if (m[1] === "research_submit") return ok(submitReply);
    if (m[1] === "research_entry_result") return entryReply === "ERR" ? new Response('{"message":"boom"}', { status: 500, headers: { "content-type": "application/json" } }) : ok(entryReply);
    if (m[1] === "research_my_results") return ok(myReply);
    return ok(null);
  }
  return ok([]);
};
const NEW = Deno.env.get("NEW") ?? new URL("../supabase/functions/research-ingest/index.ts", import.meta.url).href;
const OLD = Deno.env.get("OLD");
const toUrl = (p: string) => p.includes("://") ? p : "file://" + p;
await import(toUrl(NEW));
const hNew = handlers[0];
let hOld: H | undefined;
if (OLD) { await import(toUrl(OLD) + "?old"); hOld = handlers[1]; }
const ADDED = ["entry_check", "entry_notes", "entry_check_at"];
const req = (body: unknown, key: string | null = "k", method = "POST", qs = "") =>
  new Request("http://x/research-ingest" + qs, { method, headers: { "content-type": "application/json", ...(key ? { "x-ingest-key": key } : {}) }, body: method === "POST" ? JSON.stringify(body) : undefined });
const dump = { schema_version: "1.2", firm: { registry_id: "vc-1", name: "Test" }, coverage: {}, records: [], leads: [], search_log: [] };
const eq = (a: unknown, b: unknown, msg: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}\n got ${JSON.stringify(a)}\nwant ${JSON.stringify(b)}`); };
const assert = (c: unknown, msg: string) => { if (!c) throw new Error(msg); };
const without = (o: any, keys: string[]) => Object.fromEntries(Object.entries(o).filter(([k]) => !keys.includes(k)));

for (const [label, reply, extra] of [
  ["holding", { ok: true, submission_id: 7, status: "holding", held_for_checker: true }, [] as string[]],
  ["submitted", { ok: true, submission_id: 8, status: "submitted" }, ["submission_id"]],
] as const) {
  Deno.test(`submit (${label}): old fields kept, entry fields added`, async () => {
    submitReply = reply;
    const r = await hNew(req({ action: "submit", bot_id: "bot-a", registry_id: "vc-1", dump }));
    const j = await r.json();
    for (const k of ADDED) assert(k in j, `missing ${k}`);
    eq(j.entry_check, entryReply.entry_check, "entry_check");
    eq(j.entry_notes, entryReply.entry_notes, "entry_notes");
    for (const k of ["ok", "status", "accepted_records", "rejected_records", "errors", "source_tiers", "warnings", "hint"]) assert(k in j, `old field ${k} missing`);
    if (hOld) {
      const ro = await hOld(req({ action: "submit", bot_id: "bot-a", registry_id: "vc-1", dump }));
      const jo = await ro.json();
      eq(r.status, ro.status, "status code changed");
      eq(without(j, [...ADDED, ...extra]), jo, "old fields changed");
      eq(Object.keys(j).slice(0, Object.keys(jo).length), Object.keys(jo), "old field order changed");
    }
  });
}
Deno.test("submit: entry read failing never breaks the upload (nulls)", async () => {
  submitReply = { ok: true, submission_id: 9, status: "holding", held_for_checker: true };
  const saved = entryReply; entryReply = "ERR";
  try {
    const r = await hNew(req({ action: "submit", bot_id: "bot-a", registry_id: "vc-1", dump }));
    const j = await r.json();
    assert(r.status === 200 || r.status === 422, `status ${r.status}`);
    eq([j.entry_check, j.entry_notes, j.entry_check_at], [null, null, null], "nulls");
    eq(j.submission_id, 9, "submission_id");
  } finally { entryReply = saved; }
});
Deno.test("no key -> 401, nothing read", async () => {
  calls.length = 0;
  for (const r of [await hNew(req({ action: "my_results" }, null)), await hNew(req({}, null, "GET", "?action=my_results"))]) {
    eq(r.status, 401, "status");
  }
  eq(calls.length, 0, "no database calls without a key");
});
Deno.test("bad key -> 401", async () => {
  authReply = { ok: false, error: "unauthorized" };
  try { eq((await hNew(req({ action: "my_results" }, "wrong"))).status, 401, "status"); }
  finally { authReply = { ok: true, key_id: "11111111-1111-1111-1111-111111111111" }; }
});
Deno.test("my_results: bot comes from the key, never from bot_id in the request", async () => {
  calls.length = 0;
  const r = await hNew(req({ action: "my_results", bot_id: "someone-else" }));
  eq(r.status, 200, "status");
  const c = calls.find((x) => x.name === "research_my_results")!;
  eq(c.args, { p_key: "11111111-1111-1111-1111-111111111111", p_days: 30, p_limit: 30 }, "rpc args");
  assert(!JSON.stringify(c.args).includes("someone-else"), "body bot_id leaked into the query");
  const j = await r.json();
  eq([j.bot_id, j.days, j.count], ["bot-a", 30, 1], "shape");
  calls.length = 0;
  const g = await hNew(req({}, "k", "GET", "?action=my_results&bot_id=someone-else&days=7&limit=5"));
  eq(g.status, 200, "GET status");
  eq(calls.find((x) => x.name === "research_my_results")!.args, { p_key: "11111111-1111-1111-1111-111111111111", p_days: 7, p_limit: 5 }, "GET args");
});
Deno.test("my_results: limits and unlinked key", async () => {
  eq((await hNew(req({ action: "my_results", days: 31 }))).status, 400, "days 31");
  eq((await hNew(req({ action: "my_results", limit: 0 }))).status, 400, "limit 0");
  myReply = { ok: false, error: "this key is not linked to a bot; ask Alex to link it" };
  try { eq((await hNew(req({ action: "my_results" }))).status, 403, "unlinked"); }
  finally { myReply = { ok: true, bot_id: "bot-a", days: 30, results: [] }; }
});
