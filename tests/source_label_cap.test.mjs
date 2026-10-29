// Source chip/link labels: capped at RegretLabel.CAP characters, ending in '..'; full label kept in title/aria-label.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import '../launch/js/dates.js';
const { cap, CAP } = globalThis.RegretLabel;
const js = fs.readFileSync(new URL('../launch/js/company.js', import.meta.url), 'utf8');
test('cap is 28 and short labels are unchanged', () => {
  assert.equal(CAP, 28);
  assert.equal(cap('SEC Form ADV'), 'SEC Form ADV');
  assert.equal(cap('x'.repeat(28)), 'x'.repeat(28));
  assert.equal(cap(null), '');
});
test('long labels end in two dots and stay within the cap', () => {
  const out = cap('IRS Form 990 (GivingTuesday) · other source');
  assert.equal(out, 'IRS Form 990 (GivingTuesda..');
  assert.ok(out.length <= CAP && out.endsWith('..') && !out.endsWith('...'));
  assert.equal(cap('OCERS investment report ab  cdefg'), 'OCERS investment report ab..'); // trailing space trimmed before '..'
});
test('every source link in company.js goes through capL with a full-text title', () => {
  const links = js.split('\n').filter(l => l.includes('↗</a>') || l.includes("' ↗';"));
  for (const l of links) if (!/Source: \{site\}|AC\.filing\) \+ ' ↗/.test(l)) assert.match(l, /capL\(/, l.trim().slice(0, 120));
  assert.match(js, /' title="' \+ esc\(full\) \+ '" aria-label="'/);
});
