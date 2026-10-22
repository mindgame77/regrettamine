// Unknown-firm worker. Research is done elsewhere (Regretamin Checker bot via TOXY dev), which publishes the firm row.
// This function only emails people whose requested firm is now published, via Resend.
// Run every minute (pg_cron + pg_net, or an external scheduler). Requires header x-cron-secret = CRON_SECRET.
// Secrets: RESEND_API_KEY, CRON_SECRET, SITE_URL, EMAIL_FROM (verified Resend sender), SEND_EMAILS ("true" to really send).
// Optional: TEST_ONLY_TO = only this address may receive mail (safety while testing).
import { createClient } from "npm:@supabase/supabase-js@2";
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) return new Response("forbidden", { status: 403 });
  const send = Deno.env.get("SEND_EMAILS") === "true" && !!Deno.env.get("RESEND_API_KEY");
  const only = Deno.env.get("TEST_ONLY_TO");
  const site = (Deno.env.get("SITE_URL") ?? "https://regrettamine.com/").replace(/\/?$/, "/");
  const { data: ready, error } = await admin.rpc("ready_check_requests");
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  const out: unknown[] = [];
  for (const r of ready ?? []) {
    const link = `${site}vc/${encodeURIComponent(r.slug)}/`;
    if (!send || (only && r.email.toLowerCase() !== only.toLowerCase())) { out.push({ id: r.id, dry_run: true, link }); continue; }
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}`, "Content-Type": "application/json", "Idempotency-Key": `check-request-${r.id}` },
      body: JSON.stringify({
        from: Deno.env.get("EMAIL_FROM") ?? "Regretamin <checks@regrettamine.com>",
        to: [r.email],
        subject: `Your Regretamin check on ${r.name} is ready`,
        html: `<p>The 10 checks on <b>${esc(r.name)}</b> are ready.</p><p><a href="${link}">See the results</a></p><p style="color:#8C88A3;font-size:12px">You asked us to check this firm on Regretamin. Facts from public records; not legal advice.</p>`,
        text: `The 10 checks on ${r.name} are ready: ${link}`,
      }),
    });
    if (res.ok) {
      await admin.from("check_requests").update({ notified_at: new Date().toISOString(), status: "done" }).eq("id", r.id);
      out.push({ id: r.id, sent: true });
    } else out.push({ id: r.id, sent: false, status: res.status });
  }
  return new Response(JSON.stringify({ send, processed: out }), { headers: { "Content-Type": "application/json" } });
});
