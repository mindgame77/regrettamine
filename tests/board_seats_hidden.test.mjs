// Board seats line hidden from firm pages (display only, data kept). node --test tests/board_seats_hidden.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
const js = fs.readFileSync(new URL('../launch/js/company.js', import.meta.url), 'utf8');
test('people section does not render the Board seats block', () => {
  const sec = js.slice(js.indexOf('function personSection'), js.indexOf('function newsBlock'));
  assert.doesNotMatch(sec, /return[^\n]*Board seats/);
});
