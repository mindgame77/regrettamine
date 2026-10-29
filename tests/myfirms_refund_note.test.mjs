// My firms refund note: copy string and the row renderer use my_firms.refunded_at.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
const root = new URL('../', import.meta.url);
const copy = JSON.parse(fs.readFileSync(new URL('launch/copy.json', root), 'utf8'));
const app = fs.readFileSync(new URL('launch/js/app.js', root), 'utf8');
test('copy has the approved wording', () => {
  assert.equal(copy.site.my_firms.refund_note, 'Not finished in 24 hours · 1 credit refunded');
});
test('refunded rows show the note and a Check button, not Open', () => {
  assert.match(app, /const refunded = r\.checked && !!r\.refunded_at;/);
  assert.match(app, /esc\(F\.refund_note\)/);
  assert.match(app, /r\.checked && !refunded \? '<a class="btn o"/);
});
