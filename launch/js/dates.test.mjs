import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const ctx = { window: {}, Intl, Date, String, RegExp };
vm.runInNewContext(readFileSync(new URL('./dates.js', import.meta.url), 'utf8'), ctx);
const D = ctx.window.RegretDate;

test('date-only values stay on that calendar day', () => {
  assert.equal(D.format('2024-03-15'), 'Mar 15, 2024');
  assert.equal(D.format('retrieved 2024-03-15'), 'Mar 15, 2024');
  assert.equal(D.format('October 23, 2026'), 'Oct 23, 2026');
  assert.equal(D.format('Q1 2024'), 'Q1 2024');
  assert.equal(D.format('Undated'), 'Undated');
  assert.equal(D.format(''), '');
});

test('a time is Pacific, date and time together', () => {
  // 22:58 UTC on 24 Oct 2024 is 3:58 PM PDT
  assert.equal(D.formatWhen('2024-10-24T22:58:00Z'), 'Oct 24, 2024, 3:58 PM PT');
  assert.equal(D.format('2024-10-24T22:58:00Z'), 'Oct 24, 2024');
  // 06:30 UTC on 15 Mar 2024 is 11:30 PM the previous day in Pacific (PDT)
  assert.equal(D.format('2024-03-15T06:30:00Z'), 'Mar 14, 2024');
  assert.equal(D.formatWhen('2024-03-15'), 'Mar 15, 2024');
});

test('stamps sort newest first and leave undated values unsortable', () => {
  assert.ok(D.stamp('2024-03-15') > D.stamp('2020-01-02'));
  assert.equal(D.stamp('Undated'), null);
  assert.equal(D.stamp('Q1 2024'), null);
  assert.equal(D.stamp(''), null);
});

test('case years use the filed date and never a future or docket guess', () => {
  const docket = 'Think Computer v. Dwolla, 5:13-cv-02054';
  assert.equal(D.caseYear(docket, 'filed 2013-05-06', '2054'), '2013');
  assert.equal(D.caseYear(docket, 'docket 5:13-cv-02054', '2054'), '');
  assert.equal(D.caseYear('Samuels v. Lido DAO', 'stayed pending appeal', '2023'), '2023');
  assert.equal(D.caseYear('In re Example', '5:13-cv-02013', '2013'), '');
  assert.equal(D.caseYear('Future v. Firm', 'filed 2099-01-01', '2099'), '');
  assert.equal(D.caseYear('', '', ''), '');
  assert.equal(D.caseYear('No text', '', null), '');
});
