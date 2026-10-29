// research-ingest v32: news, thesis and socialAccounts records; fixed legal words with old words mapped; AUM basis press removed.
// No network, no database (fake fetch). Run: deno test -A tests/research_ingest_upload_fields.test.ts
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

Deno.test("old-format upload still accepted, old legal words mapped", async () => {
  const r = await submit([rec("r1", "hq", { city: "LA" }),
    rec("r2", "lawsuits", { caption: "A v. B", status: "open", firm_party_role: "defendant" }),
    rec("r3", "lawsuits", { caption: "C v. D", status: "judgment", firm_party_role: "plaintiff" }),
    rec("r4", "regulatoryActions", { regulator: "SEC", status: "adjudicated" }),
    rec("r5", "lawsuits", { caption: "E v. F", status: "unknown" }),
    rec("r6", "aum", { amount_usd: 1e9, basis: "form_adv_raum" })]);
  assertEquals(r.status, 200, JSON.stringify(r.body));
  assertEquals(sent.p_valid, true);
  const v = sent.p_payload.records.map((x: any) => x.value);
  assertEquals([v[1].status, v[1].side, v[1].firm_party_role], ["Active", "Defendant", undefined]);
  assertEquals([v[2].status, v[2].side], ["Closed", "Plaintiff"]);
  assertEquals(v[3].status, "Closed");
  assertEquals("status" in v[4], false);
});

Deno.test("new-format upload with news, thesis and social accounts accepted", async () => {
  const r = await submit([rec("n1", "news", { outlet: "Reuters", headline: "Fund closes", date: "2026-01-02", url: "https://reuters.com/a" }),
    rec("t1", "thesis", { text: "We back seed-stage climate software." }),
    rec("s1", "socialAccounts", { platform: "LinkedIn", url: "https://linkedin.com/company/test", followers: 1200, linked_from_firm_site: true }),
    rec("l1", "lawsuits", { caption: "G v. H", status: "Settled", side: "Defendant", case_type: "securities" })]);
  assertEquals(r.status, 200, JSON.stringify(r.body));
  const v = sent.p_payload.records.map((x: any) => x.value);
  assertEquals(v[1], "We back seed-stage climate software.");
  assertEquals(v[2].platform, "linkedin");
  assertEquals(v[3].case_type, "Securities");
});

for (const [label, recs, want] of [
  ["side other", [rec("x", "lawsuits", { status: "open", firm_party_role: "other" })], 'legal side "other" is not allowed'],
  ["bad status", [rec("x", "lawsuits", { status: "appeal" })], "use Active, Closed, Settled or Dismissed"],
  ["bad topic", [rec("x", "lawsuits", { case_type: "tax" })], "use Fraud, Contract, Employment, Securities, Regulator action or IP"],
  ["aum press", [rec("x", "aum", { amount_usd: 5, basis: "press" })], 'aum basis "press" is no longer allowed'],
  ["social not linked", [rec("x", "socialAccounts", { platform: "x", url: "https://x.com/t" })], "linked from the firm's own website"],
  ["news no headline", [rec("x", "news", { outlet: "Reuters" })], "news needs headline"],
  ["thesis empty", [rec("x", "thesis", 3)], "thesis value must be the thesis text"],
] as const) Deno.test(`rejected with a clear reason: ${label}`, async () => {
  const r = await submit(recs as unknown as unknown[]);
  assertEquals(r.body.ok, false);
  assertEquals(sent.p_valid, false);
  assert(r.body.errors.some((e: string) => e.includes(want)), JSON.stringify(r.body.errors));
});

Deno.test("legal case summary: trimmed at 300, dropped (case kept) without a source link", async () => {
  const r = await submit([rec("c1", "lawsuits", { caption: "A v. B", status: "Active", summary: "x".repeat(350), summary_source_url: "https://www.courtlistener.com/docket/1/a/" }),
    rec("c2", "lawsuits", { caption: "C v. D", status: "Active", summary: "no link", summary_date: "2026-10-29" }),
    rec("c3", "lawsuits", { caption: "E v. F", status: "Closed", summary: "old free-text note" })]);
  assertEquals(r.status, 200, JSON.stringify(r.body));
  const v = sent.p_payload.records.map((x: any) => x.value);
  assertEquals(v[0].summary.length, 300);
  assertEquals(v[0].summary_date, "2026-10-28");
  assertEquals([v[1].summary, v[1].summary_source_url], [undefined, undefined]);
  assertEquals(v[2].summary, "old free-text note");
  assert(JSON.stringify(r.body).includes("no source link"));
});
