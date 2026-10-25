// On-demand research emails (docs/ON_DEMAND.md, docs/FIRM_REQUESTS.md). Called by pg_cron (public.ondemand_tick via pg_net) when the outbox has mail.
// Auth: header x-ondemand-key must match the Vault secret 'ondemand_cron_key' (checked in the database; never leaves it).
// Kinds: 'ready' (paid research done), 'ready_request' (a requested firm is now on the site), 'refund' (not done within 24 h,
// credit returned), 'received' (firm request stored). All mail is plain text from support@regretamin.com via Resend.
// Secrets: RESEND_API_KEY. TEST_ONLY_TO is not a send gate: a leftover test address
// used to skip every other recipient without ondemand_mark_notified, so notified_at
// and notify_error stayed empty and every tick retried the skip.
const SITE_URL = "https://regretamin.com/";
const FROM = "Regretamin <support@regretamin.com>";
import { createClient } from "npm:@supabase/supabase-js@2";
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { "Content-Type": "application/json" } });
const FOOT = "\n\nFacts come from public records. This is not legal advice.\nRegretamin, support@regretamin.com";

function mail(kind: string, name: string, link: string): { subject: string; text: string } {
  switch (kind) {
    case "ready":
      return { subject: `Your Regretamin check for ${name} is ready`, text: `Hi,\n\nThe research on ${name} is done. See the results here:\n${link}${FOOT}` };
    case "ready_request":
      return { subject: `${name} is now on Regretamin`, text: `Hi,\n\nYou asked us to add ${name}. It is now on Regretamin and the checks are done:\n${link}${FOOT}` };
    case "refund":
      return { subject: `Your Regretamin check for ${name}: credit refunded`, text: `Hi,\n\nWe could not finish the research on ${name} within 24 hours, so your credit is back in your account.\n${link}${FOOT}` };
    default: // received
      return { subject: `We got your request for ${name}`, text: `Hi,\n\nThanks. We got your request to add ${name} to Regretamin. We will email you when its page is ready.${FOOT}` };
  }
}

Deno.serve(async (req) => {
  const { data: ok } = await admin.rpc("ondemand_cron_ok", { p_key: req.headers.get("x-ondemand-key") ?? "" });
  if (ok !== true) return new Response("forbidden", { status: 403 });
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return json({ error: "RESEND_API_KEY not set" }, 500);
  const { data: box, error } = await admin.rpc("ondemand_outbox", { p_limit: 50 });
  if (error) return json({ error: "outbox failed" }, 500);
  const out: unknown[] = [];
  for (const r of box ?? []) {
    const link = r.slug ? `${SITE_URL}vc/${encodeURIComponent(r.slug)}/` : SITE_URL;
    const { subject, text } = mail(r.kind, r.name, link);
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "Idempotency-Key": `ondemand-${r.kind}-${r.id}` },
      body: JSON.stringify({ from: FROM, reply_to: "support@regretamin.com", to: [r.email], subject, text }),
    });
    await admin.rpc("ondemand_mark_notified", { p_id: r.id, p_error: res.ok ? null : `resend ${res.status}`, p_kind: r.kind });
    out.push({ id: r.id, kind: r.kind, sent: res.ok, status: res.status });
  }
  return json({ processed: out });
});
