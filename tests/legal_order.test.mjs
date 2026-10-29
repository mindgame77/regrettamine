// Legal & regulatory display order. Active first, then every other status. Newest year first inside each.
// node --test tests/legal_order.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const copy = JSON.parse(fs.readFileSync(new URL('launch/copy.json', root), 'utf8'));

function node() {
  const kids = {};
  return {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
    classList: { toggle() {} },
    querySelector(sel) { return kids[sel] || null; },
    querySelectorAll() { return []; },
    set(sel, child) { kids[sel] = child; return child; },
  };
}
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement() { return node(); } },
  console,
  URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(new URL('launch/js/dates.js', root), 'utf8'), sandbox, { filename: 'dates.js' });
vm.runInContext(fs.readFileSync(new URL('launch/js/company.js', root), 'utf8'), sandbox, { filename: 'company.js' });
const { render } = sandbox.window.RegretCompany;

const src = [{ label: 'CourtListener', url: 'https://www.courtlistener.com/docket/1/x/' }];
const row = (title, year, state, extra) => Object.assign({ grp: 'case', title, year, state: state || '', status: '', note: '', role: '', src }, extra || {});

function page(items) {
  const P = { open: true, firm: { name: 'Example Capital', slug: 'example' }, checks: [],
    sections: [{ key: 'legal', count: items.length, items }, { key: 'founders', count: 1, items: [{ head: 'Founder', date: '2024', src }] }] };
  const main = node(), pmain = node();
  main.set('.pmain', pmain);
  render(main, P);
  return pmain.innerHTML;
}
const legal = (html) => (html.split('id="legal"')[1] || '').split('<section ')[0];
const rows = (html) => [...legal(html).matchAll(/<div class="rw lg( lg-act)?"><div class="rt">([^<]*)<\/div>/g)].map(m => ({ t: m[2], act: !!m[1] }));

test('section is hidden when there are no cases', () => {
  const html = page([row('Lead (allegation, not verified): something', '2025', 'Unverified'), { grp: 'context', title: 'Context only', src }]);
  assert.doesNotMatch(html, /id="legal"/);
  assert.doesNotMatch(page([]), /id="legal"/);
});

test('active cases first, then the rest newest first; old status words mapped', () => {
  const html = page([
    row('Closed newer', '2024', 'Closed'),
    row('Active older', '2020', 'Active'),
    row('Settled one', '2022', 'Closed', { status: 'closed - class settlement approved 2022-09-30' }),
    row('Active newer', '2025', '', { status: 'open - stayed' }),
    row('Dismissed one', '2023', 'Closed', { status: 'dismissed' }),
  ]);
  assert.deepEqual(rows(html).map(r => r.t), ['Active newer', 'Active older', 'Closed newer', 'Dismissed one', 'Settled one']);
  assert.match(legal(html), />Settled</);
  assert.match(legal(html), />Dismissed</);
});

test('only Active rows are highlighted red', () => {
  const html = page([row('A v. Example Capital', '2025', 'Active', { role: 'Defendant' }), row('Example Capital v. B', '2021', 'Closed', { role: 'Plaintiff' })]);
  assert.deepEqual(rows(html), [{ t: 'A v. Example Capital', act: true }, { t: 'Example Capital v. B', act: false }]);
  assert.match(legal(html), /vs\. A /);
  assert.match(legal(html), /vs\. B /);
  assert.match(legal(html), />Defendant</);
  assert.match(legal(html), />Plaintiff</);
});

test('caps at 10 rows and offers Show all', () => {
  const items = Array.from({ length: 13 }, (_, i) => row('Case ' + i, String(2000 + i), i < 2 ? 'Active' : 'Closed'));
  const html = page(items);
  assert.equal(rows(html).length, 10);
  assert.deepEqual(rows(html).slice(0, 2).map(r => r.t), ['Case 1', 'Case 0']);
  assert.match(legal(html), /class="ash" data-open="actlegal">Show all 13 legal items ↓/);
  assert.match(html, /Legal &amp; regulatory <em class="pc2">13<\/em>/);
  assert.doesNotMatch(legal(page(items.slice(0, 10))), /actlegal/);
});

test('settlement terms show only for Settled cases that state them', () => {
  const note = 'Class settlement of $1.2M approved by the court.';
  const html = page([
    row('Settled with terms', '2022', 'Closed', { status: 'settled', note }),
    row('Settled without terms', '2021', 'Closed', { status: 'settled', note: 'Settled.' }),
    row('Closed with money note', '2020', 'Closed', { note }),
  ]);
  const L = legal(html);
  assert.equal((L.match(/lg-set/g) || []).length, 1);
  assert.match(L.split('Settled without terms')[0], /\$1\.2M/);
});

test('a case without a court or regulator link is not shown', () => {
  assert.doesNotMatch(page([row('No link', '2024', 'Active', { src: [] })]), /id="legal"/);
});
