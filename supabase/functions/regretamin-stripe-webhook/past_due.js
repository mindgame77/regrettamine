// Failed-payment handling, kept as plain JS so tests/webhook_past_due.test.mjs can run it under Node with a fake client.
// invoice.payment_failed -> mark_past_due (plan drops to free after 24h via the hourly downgrade-lapsed-payments job);
// invoice.paid -> clear_past_due. Returns null when handled fine, or an error Response-ish {status, body}.
export async function handlePastDue(ev, admin) {
  if (ev.type !== "invoice.payment_failed" && ev.type !== "invoice.paid") return null;
  const sub = ev.data.object.subscription;
  if (!sub) return null; // one-off invoice: no plan to touch
  const id = typeof sub === "string" ? sub : sub.id;
  const fn = ev.type === "invoice.payment_failed" ? "mark_past_due" : "clear_past_due";
  const { error } = await admin.rpc(fn, { p_sub: id });
  return error ? { status: 500, body: "db error" } : null;
}
