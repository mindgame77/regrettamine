// research-ingest-v2: action results is read-only and keyed from x-ingest-key.
// No network, no database: supabase-js calls are answered by a fake fetch.
// Run: deno test -A --no-check tests/research_ingest_v2_results.test.ts
Deno.env.set("SUPABASE_URL", "http://mock.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-not-a-key");
type H = (r: Request) => Promise<Response>;
const handlers: H[] = [];
(Deno as any).serve = (h: H) => { handlers.push(h); return {} as any; };
const calls: { name: string; args: any }[] = [];
let authReply: any = { ok: true, key_id: "11111111-1111-1111-1111-111111111111" };
let resultsReply: any = {
  ok: true, bot_id: "bot-a", days: 30,
  counts: { live: 2, held: 0, rejected: 1 },
  items: [{ submission_id: 9, status: "rejected", reason: "Cited company page lists the stage as Series C or Later, not Series D.", label: "FloQast", firm: "Example Ventures", slug: "example-ventures" }],
  firms: [{ firm_id: 7, name: "Example Ventures", slug: "example-ventures", not_sent: ["Funds were not sent, look for it."] }],
};
let submitReply: any = { ok: true, bot_id: "bot-a", accepted: 1, rejected: 0, held: 0, results: [{ index: 0, status: "Accepted" }] };
globalThis.fetch = async (input: any, init?: any) => {
  const u = new URL(typeof input === "string" ? input : input.url);
  const body = init?.body ? JSON.parse(String(init.body)) : null;
  const m = u.pathname.match(/\/rest\/v1\/rpc\/(\w+)/);
  const ok = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { "content-type": "application/json" } });
  if (m) {
    calls.push({ name: m[1], args: body });
    if (m[1] === "ingest_auth") return ok(authReply);
    if (m[1] === "v2_research_my_results") return ok(resultsReply);
    if (m[1] === "v2_research_submit") return ok(submitReply);
    return ok(null);
  }
  return ok([]);
};
await import(new URL("../supabase/functions/research-ingest-v2/index.ts", import.meta.url).href);
const h = handlers[0];
const req = (body: unknown, key: string | null = "k") =>
  new Request("http://x/research-ingest-v2", { method: "POST", headers: { "content-type": "application/json", ...(key ? { "x-ingest-key": key } : {}) }, body: JSON.stringify(body) });
const eq = (a: unknown, b: unknown, msg: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}\n got ${JSON.stringify(a)}\nwant ${JSON.stringify(b)}`); };

Deno.test("results: bot comes from the key, never from bot_id in the request", async () => {
  calls.length = 0;
  const r = await h(req({ action: "results", bot_id: "someone-else", days: 14, limit: 50, firm_id: 7 }));
  eq(r.status, 200, "status");
  const c = calls.find((x) => x.name === "v2_research_my_results")!;
  eq(c.args, { p_key: "11111111-1111-1111-1111-111111111111", p_days: 14, p_limit: 50, p_firm_id: 7 }, "rpc args");
  if (JSON.stringify(c.args).includes("someone-else")) throw new Error("body bot_id leaked into the query");
  const j = await r.json();
  eq([j.ok, j.bot_id, j.days, j.counts.rejected, j.items.length, j.firms[0].not_sent[0]], [true, "bot-a", 30, 1, 1, "Funds were not sent, look for it."], "shape");
  eq(j.items[0].reason, "Cited company page lists the stage as Series C or Later, not Series D.", "reason");
});

Deno.test("results: defaults, limits, unlinked key, no key", async () => {
  calls.length = 0;
  eq((await h(req({ action: "results" }))).status, 200, "defaults");
  eq(calls.find((x) => x.name === "v2_research_my_results")!.args, {
    p_key: "11111111-1111-1111-1111-111111111111", p_days: 30, p_limit: 100, p_firm_id: null,
  }, "default args");
  eq((await h(req({ action: "results", days: 31 }))).status, 400, "days 31");
  eq((await h(req({ action: "results", limit: 0 }))).status, 400, "limit 0");
  eq((await h(req({ action: "results", firm_id: "7" }))).status, 400, "firm_id string");
  resultsReply = { ok: false, error: "this key is not linked to a bot; ask Alex to link it" };
  try { eq((await h(req({ action: "results" }))).status, 403, "unlinked"); }
  finally {
    resultsReply = { ok: true, bot_id: "bot-a", days: 30, counts: { live: 0, held: 0, rejected: 0 }, items: [], firms: [] };
  }
  calls.length = 0;
  eq((await h(req({ action: "results" }, null))).status, 401, "no key");
  eq(calls.length, 0, "no database calls without a key");
});

Deno.test("submit is unchanged when results is present", async () => {
  calls.length = 0;
  const items = [{ firm_id: 7, box: "F5", table: "v2_investor_principles", fact: { source_url: "https://example.com/a" } }];
  const r = await h(req({ action: "submit", items }));
  eq(r.status, 200, "status");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_research_submit"], "rpcs");
  eq(calls.filter((c) => c.name === "v2_research_my_results").length, 0, "no results rpc");
});
