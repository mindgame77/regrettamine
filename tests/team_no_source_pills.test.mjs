// G7.8: Team cards (page and Show all pop-up) show no source pill; other sections keep theirs.
// node --test tests/team_no_source_pills.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const js = read('launch/js/company.js');
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement() { return {}; } },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(js, sandbox, { filename: 'company.js' });
const { partnerCard } = sandbox.window.RegretCompany;

const src = [{ url: 'https://a16z.com/team/', label: 'Firm website', date: '2026-11-03' }];
const sec = [{ url: 'https://reports.adviserinfo.sec.gov/x.pdf', label: 'SEC filing', date: '2026-03-30' }];

test('partner card has no source pill, name and role kept', () => {
  const h = partnerCard({ head: 'Jane Doe', kind: 'partner', role: 'General Partner', src });
  assert.match(h, /Jane Doe/); assert.match(h, /General Partner/);
  assert.doesNotMatch(h, /Firm website|a16z\.com|2026/);
});
test('officer card has no source pill', () => {
  const h = partnerCard({ head: 'A One', kind: 'officer', role: 'Chief Legal Officer', src: sec });
  assert.doesNotMatch(h, /SEC filing|adviserinfo|Mar 30/);
});
test('page and Show all pop-up both use partnerCard; pills kept elsewhere', () => {
  const ps = js.slice(js.indexOf('function personSection'), js.indexOf('function newsBlock'));
  assert.equal((ps.match(/map\(partnerCard\)/g) || []).length, 2);
  assert.doesNotMatch(ps, /chips\(/);
  assert.ok((js.match(/chips\(/g) || []).length > 2, 'other sections still render chips');
});
