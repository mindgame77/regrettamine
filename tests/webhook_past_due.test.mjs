// node --test tests/webhook_past_due.test.mjs — no Stripe or DB calls; a fake admin client records the RPCs.
import { test } from "node:test";
import assert from "node:assert/strict";
import { handlePastDue } from "../supabase/functions/regretamin-stripe-webhook/past_due.js";

const fake = (error = null) => { const calls = []; return { calls, rpc: async (fn, args) => { calls.push([fn, args]); return { error }; } }; };
const ev = (type, subscription) => ({ type, data: { object: { subscription } } });

test("payment_failed marks the subscription past_due", async () => {
  const a = fake(); assert.equal(await handlePastDue(ev("invoice.payment_failed", "sub_1"), a), null);
  assert.deepEqual(a.calls, [["mark_past_due", { p_sub: "sub_1" }]]);
});
test("invoice.paid clears past_due (expanded subscription object too)", async () => {
  const a = fake(); await handlePastDue(ev("invoice.paid", { id: "sub_2" }), a);
  assert.deepEqual(a.calls, [["clear_past_due", { p_sub: "sub_2" }]]);
});
test("invoices without a subscription and other events are ignored", async () => {
  const a = fake(); await handlePastDue(ev("invoice.payment_failed", null), a); await handlePastDue(ev("customer.subscription.updated", "sub_3"), a);
  assert.equal(a.calls.length, 0);
});
test("a DB error returns 500 so Stripe retries", async () => {
  assert.deepEqual(await handlePastDue(ev("invoice.payment_failed", "sub_4"), fake({ message: "x" })), { status: 500, body: "db error" });
});
