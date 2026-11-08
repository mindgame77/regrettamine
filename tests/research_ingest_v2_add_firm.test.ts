// research-ingest-v2: add_firm is a separate action. Submit and verdict stay on their own RPCs.
// No network, no database: supabase-js calls are answered by a fake fetch.
// Run: deno test -A --no-check tests/research_ingest_v2_add_firm.test.ts
Deno.env.set("SUPABASE_URL", "http://mock.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-not-a-key");
type H = (r: Request) => Promise<Response>;
const handlers: H[] = [];
(Deno as any).serve = (h: H) => { handlers.push(h); return {} as any; };
const calls: { name: string; args: any }[] = [];
const reads: { table: string; url: string }[] = [];
let firmRows: any[] = [];
let v2Rows: any[] = [];
let authReply: any = { ok: true, key_id: "11111111-1111-1111-1111-111111111111" };
let addReply: any = { ok: true, bot_id: "bot-a", firm_id: 41, created: true, slug: "example-ventures" };
let submitReply: any = { ok: true, bot_id: "bot-a", accepted: 1, rejected: 0, held: 0, results: [{ index: 0, status: "Accepted" }] };
let verdictReply: any = { ok: true, bot_id: "checker" };
globalThis.fetch = async (input: any, init?: any) => {
  const u = new URL(typeof input === "string" ? input : input.url);
  const body = init?.body ? JSON.parse(String(init.body)) : null;
  const m = u.pathname.match(/\/rest\/v1\/rpc\/(\w+)/);
  const ok = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { "content-type": "application/json" } });
  if (m) {
    calls.push({ name: m[1], args: body });
    if (m[1] === "ingest_auth") return ok(authReply);
    if (m[1] === "v2_research_add_firm") return ok(addReply);
    if (m[1] === "v2_research_submit") return ok(submitReply);
    if (m[1] === "v2_checker_action") return ok(verdictReply);
    return ok(null);
  }
  const table = u.pathname.match(/\/rest\/v1\/([a-z0-9_]+)$/);
  if (table) {
    reads.push({ table: table[1], url: u.pathname + u.search });
    if (table[1] === "v2_firms") return ok(v2Rows);
    if (table[1] === "firms") return ok(firmRows);
  }
  return ok([]);
};
await import(new URL("../supabase/functions/research-ingest-v2/index.ts", import.meta.url).href);
const h = handlers[0];
const req = (body: unknown, key: string | null = "k") =>
  new Request("http://x/research-ingest-v2", { method: "POST", headers: { "content-type": "application/json", ...(key ? { "x-ingest-key": key } : {}) }, body: JSON.stringify(body) });
const eq = (a: unknown, b: unknown, msg: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}\n got ${JSON.stringify(a)}\nwant ${JSON.stringify(b)}`); };

Deno.test("add_firm returns firm_id and does not call submit", async () => {
  calls.length = 0;
  const firm = { name: "Example Ventures", website: "https://example-ventures.com", registry_id: "vc-000123" };
  const r = await h(req({ action: "add_firm", firm }));
  const j = await r.json();
  eq(r.status, 200, "status");
  eq(j.firm_id, 41, "firm_id");
  eq(j.created, true, "created");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_research_add_firm"], "rpcs");
  eq(calls[1].args.p_key_id, authReply.key_id, "key");
  eq(calls[1].args.p_firm, firm, "firm");
});

Deno.test("add_firm again is the same call shape", async () => {
  calls.length = 0;
  addReply = { ok: true, bot_id: "bot-a", firm_id: 41, created: false, slug: "example-ventures" };
  const r = await h(req({ action: "add_firm", firm: { name: "Example Ventures", website: "https://example-ventures.com", registry_id: "vc-000123" } }));
  const j = await r.json();
  eq(r.status, 200, "status");
  eq(j.firm_id, 41, "firm_id");
  eq(j.created, false, "created");
  eq(calls.filter((c) => c.name === "v2_research_submit").length, 0, "no submit");
});

Deno.test("submit still calls v2_research_submit only", async () => {
  calls.length = 0;
  const items = [{ firm_id: 41, box: "F28", table: "v2_news_items", fact: { source_url: "https://example.com/a", source_level: "2", source_date: "2026-11-01", source_type: "news" } }];
  const r = await h(req({ action: "submit", items }));
  const j = await r.json();
  eq(r.status, 200, "status");
  eq(j.accepted, 1, "accepted");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_research_submit"], "rpcs");
  eq(calls[1].args.p_items, items, "items");
});

Deno.test("verdict still calls v2_checker_action", async () => {
  calls.length = 0;
  const r = await h(req({ action: "verdict", id: 9, verdict: "pass" }));
  eq(r.status, 200, "status");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_checker_action"], "rpcs");
  eq(calls[1].args.p_action, "verdict", "action");
});

Deno.test("no key -> 401", async () => {
  calls.length = 0;
  const r = await h(req({ action: "add_firm", firm: { name: "X", website: "https://x.com", registry_id: "vc-1" } }, null));
  eq(r.status, 401, "status");
  eq(calls.length, 0, "no rpc");
});

Deno.test("duplicate domain is refused and a new domain is still accepted", async () => {
  const plugId = "52752433-ef2f-4fbe-b79b-ea881d8755fa";
  calls.length = 0;
  reads.length = 0;
  firmRows = [{ id: plugId, slug: "plugandplay", primary_domain: "plugandplaytechcenter.com" }];
  v2Rows = [{ firm_id: 7, slug: "plug-and-play", website_url: "https://www.plugandplaytechcenter.com", archived: false }];
  const dup = await h(req({ action: "add_firm", firm: { name: "Plug and Play", website: "https://www.PlugAndPlayTechCenter.com/about", registry_id: "vc-999" } }));
  const dupBody = await dup.json();
  eq(dup.status, 409, "dup status");
  eq(dupBody.error, "a firm with this website already exists", "dup error");
  eq(dupBody.slug, "plugandplay", "dup slug");
  eq(dupBody.id, plugId, "dup id");
  eq(calls.map((c) => c.name), ["ingest_auth"], "no create");
  eq(reads.map((r) => r.table).sort(), ["firms", "v2_firms"], "both tables");
  const firmsUrl = reads.find((r) => r.table === "firms")?.url ?? "";
  const v2Url = reads.find((r) => r.table === "v2_firms")?.url ?? "";
  if (!firmsUrl.includes("deleted_at=is.null")) throw new Error(`firms query missed deleted_at\n${firmsUrl}`);
  if (!firmsUrl.includes("plugandplaytechcenter.com") || !v2Url.includes("plugandplaytechcenter.com")) throw new Error(`query missed normalized domain\n${firmsUrl}\n${v2Url}`);
  if (firmsUrl.includes("/about") || firmsUrl.includes("PlugAndPlay") || v2Url.includes("/about")) throw new Error("query kept the path or original case");

  calls.length = 0;
  reads.length = 0;
  firmRows = [];
  v2Rows = [{ firm_id: 7, slug: "plug-and-play", website_url: "https://www.plugandplaytechcenter.com", archived: false }];
  const v2only = await h(req({ action: "add_firm", firm: { name: "Plug and Play", website: "http://plugandplaytechcenter.com/team", registry_id: "vc-999" } }));
  const v2Body = await v2only.json();
  eq(v2only.status, 409, "v2 status");
  eq(v2Body.slug, "plug-and-play", "v2 slug");
  eq(v2Body.id, 7, "v2 id");
  eq(calls.some((c) => c.name === "v2_research_add_firm"), false, "v2 no create");

  calls.length = 0;
  reads.length = 0;
  firmRows = [{ id: plugId, slug: "plugandplay", primary_domain: "plugandplaytechcenter.com" }];
  v2Rows = [{ firm_id: 7, slug: "plug-and-play", website_url: "https://www.plugandplaytechcenter.com", archived: true }];
  addReply = { ok: true, bot_id: "bot-a", firm_id: 42, created: true, slug: "brand-new-firm" };
  const firm = { name: "Brand New Firm", website: "https://www.brand-new-firm.example/about", registry_id: "vc-new" };
  const created = await h(req({ action: "add_firm", firm }));
  const createdBody = await created.json();
  eq(created.status, 200, "new status");
  eq(createdBody.firm_id, 42, "new firm_id");
  eq(createdBody.created, true, "created");
  eq(calls.map((c) => c.name), ["ingest_auth", "v2_research_add_firm"], "new rpcs");
  eq(calls[1].args.p_firm, firm, "firm unchanged");
  firmRows = [];
  v2Rows = [];
});

Deno.test("frozen key -> 403", async () => {
  addReply = { ok: false, bot_id: "bot-a", error: "Key frozen: too many rejections, 2026-11-07 10:00 PT" };
  const r = await h(req({ action: "add_firm", firm: { name: "X", website: "https://example.com", registry_id: "vc-1" } }));
  eq(r.status, 403, "status");
  const j = await r.json();
  eq(j.error.startsWith("Key frozen"), true, "error");
});
