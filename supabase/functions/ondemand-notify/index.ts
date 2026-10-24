// On-demand research emails (docs/ON_DEMAND.md). Called by pg_cron (public.ondemand_tick via pg_net) when the outbox has mail.
// Auth: header x-ondemand-key must match the Vault secret 'ondemand_cron_key' (checked in the database; never leaves it).
// Sends 'ready' (research done, link to the page) and 'refund' (not done within 24 h, credit returned) emails via Resend.
// Secrets: RESEND_API_KEY, EMAIL_FROM (verified Resend sender). Optional TEST_ONLY_TO: only this address gets mail.
// Email links: the ONE setting below. Flip to "https://regretamin.com/" after the DNS switch, then redeploy this function.
const SITE_URL = "https://regretamin.pages.dev/";
import { createClient } from "npm:@supabase/supabase-js@2";
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  const { data: ok } = await admin.rpc("ondemand_cron_ok", { p_key: req.headers.get("x-ondemand-key") ?? "" });
  if (ok !== true) return new Response("forbidden", { status: 403 });
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return json({ error: "RESEND_API_KEY not set" }, 500);
  const only = Deno.env.get("TEST_ONLY_TO")?.toLowerCase();
  const site = SITE_URL.replace(/\/?$/, "/");
  const from = Deno.env.get("EMAIL_FROM") ?? "Regretamin <checks@regretamin.com>";
  const { data: box, error } = await admin.rpc("ondemand_outbox", { p_limit: 50 });
  if (error) return json({ error: "outbox failed" }, 500);
  const out: unknown[] = [];
  for (const r of box ?? []) {
    if (only && r.email.toLowerCase() !== only) { out.push({ id: r.id, skipped: "TEST_ONLY_TO" }); continue; }
    const link = `${site}vc/${encodeURIComponent(r.slug)}/`;
    const ready = r.kind === "ready";
    const subject = ready ? `Your Regretamin check for ${r.name} is ready` : `Your Regretamin check for ${r.name}: credit refunded`;
    const html = ready
      ? `<p>The research on <b>${esc(r.name)}</b> is done.</p><p><a href="${link}">See the results</a></p>`
      : `<p>We could not finish the research on <b>${esc(r.name)}</b> within 24 hours, so your credit is back in your account.</p><p><a href="${link}">See the page</a></p>`;
    const text = ready ? `The research on ${r.name} is done: ${link}` : `We could not finish the research on ${r.name} within 24 hours, so your credit is back in your account: ${link}`;
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "Idempotency-Key": `ondemand-${r.kind}-${r.id}` },
      body: JSON.stringify({ from, to: [r.email], subject, text,
        html: html + `<p style="color:#8C88A3;font-size:12px">You used a credit to check this firm on Regretamin. Facts from public records; not legal advice.</p>` }),
    });
    if (res.ok) { await admin.rpc("ondemand_mark_notified", { p_id: r.id }); out.push({ id: r.id, kind: r.kind, sent: true }); }
    else { await admin.rpc("ondemand_mark_notified", { p_id: r.id, p_error: `resend ${res.status}` }); out.push({ id: r.id, sent: false, status: res.status }); }
  }
  return json({ processed: out });
});
