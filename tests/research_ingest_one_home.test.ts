// Fix 3: one home per field. AUM / RAUM / fund assets only in the "aum" record; other paths or labels rejected.
// No network, no database (fake fetch). Run: deno test -A tests/research_ingest_one_home.test.ts
import { assertEquals, assert } from "jsr:@std/assert@1";
Deno.env.set("SUPABASE_URL", "http://mock.local");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-not-a-key");
type H = (r: Request) => Promise<Response>;
let handler: H | undefined;
(Deno as any).serve = (h: H) => { handler = h; return {} as any; };
let sent: any = null;
globalThis.fetch = async (input: any, init?: any) => {
  const u = new URL(typeof input === "string" ? input : input.url);
  const body = init?.body ? JSON.parse(String(init.body)) : null;
  const m = u.pathname.match(/\/rest\/v1\/rpc\/(\w+)/);
  const ok = (b: unknown) => new Response(JSON.stringify(b), { status: 200, headers: { "content-type": "application/json" } });
  if (m?.[1] === "ingest_auth") return ok({ ok: true, key_id: "11111111-1111-1111-1111-111111111111" });
  if (m?.[1] === "research_submit") { sent = body; return ok({ ok: true, status: "submitted", submission_id: 9 }); }
  if (m?.[1] === "research_entry_result") return ok({ entry_check: "Accepted", entry_notes: null, entry_check_at: "t" });
  return ok(m ? null : []);
};
await import(Deno.env.get("NEW") ?? new URL("../supabase/functions/research-ingest/index.ts", import.meta.url).href);
const src = { url: "https://www.sec.gov/x.htm", quote: "a quote here", retrieved_at: "2026-10-28", tier: "T1" };
const rec = (id: string, field_path: string, value: unknown) =>
  ({ record_id: id, field_path, entity: { id: "f", type: "firm", name: "Test" }, value, certainty: "reported", query_ids: ["q1"], sources: [src] });
const dump = (records: unknown[]) => ({ schema_version: "dump-1.2", firm: { firm_id: "vc-1", name: "Test", website: "https://test.vc", generated_at: "2026-10-28" },
  coverage: [{ item: "hq", status: "found" }], records, leads: [], search_log: [{ query_id: "q1", query: "x" }] });
const submit = async (records: unknown[]) => {
  sent = null;
  const r = await handler!(new Request("http://x/research-ingest", { method: "POST", headers: { "content-type": "application/json", "x-ingest-key": "k" },
    body: JSON.stringify({ action: "submit", bot_id: "bot-a", registry_id: "vc-1", dump: dump(records) }) }));
  return { status: r.status, body: await r.json() };
};

Deno.test("fix 3: AUM in the aum record is accepted", async () => {
  const r = await submit([rec("a1", "aum", { amount_usd: 160242886816, basis: "form_adv_raum" }),
    rec("a2", "funds", { name: "Fund I", size_usd: 14000000000, gross_assets_usd: 7800000000 })]);
  assertEquals(r.status, 200, JSON.stringify(r.body));
});

Deno.test("fix 3: AUM or fund assets under other paths or labels rejected with a clear reason", async () => {
  for (const r0 of [rec("b1", "funds", { name: "Fund I", aum_usd: 5000000000 }),
    rec("b2", "latestRaise", { amount_usd: 5000000000, label: "Regulatory AUM" }),
    rec("b3", "people", { name: "Fund assets", role: "x" }),
    rec("b4", "funds", { name: "F", fund_assets_usd: 7000000000 }),
    rec("b5", "funds", { name: "F", label: "Gross assets" })]) {
    const r = await submit([r0]);
    assertEquals(r.status, 422, JSON.stringify(r0));
    assert(JSON.stringify(r.body).includes("one home"), JSON.stringify(r.body));
  }
});

Deno.test("fix 3: ordinary labels are not caught", async () => {
  const r = await submit([rec("c1", "people", { name: "Ana Assetson", role: "Partner" }),
    rec("c2", "funds", { name: "Asset Fund II", size_usd: 100000000 })]);
  assertEquals(r.status, 200, JSON.stringify(r.body));
});
