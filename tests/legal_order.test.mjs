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

const row = (grp, title, year, state, extra) => Object.assign({ grp, title, year, state: state || '', status: '', note: '', src: [] }, extra || {});

function titles(html) {
  const out = {};
  html.split('<h3>').slice(1).forEach(chunk => {
    const name = chunk.slice(0, chunk.indexOf(' ·'));
    const body = chunk.slice(chunk.indexOf('</h3>') + 5).split(/<h3>|<section /)[0];
    out[name] = [...body.matchAll(/<div class="rt">([^<]*)<\/div>/g)].map(m => m[1]);
  });
  return out;
}

test('legal groups put Active first, newest year first, and leave other sections in place', () => {
  const P = {
    open: true,
    firm: { name: 'Example Capital', slug: 'example' },
    checks: [],
    sections: [
      { key: 'legal', count: 8, items: [
        row('case', 'Closed newer', '2024', 'Closed'),
        row('case', 'Active older', '2020', 'Active'),
        row('case', 'Active newer', '2025', 'Active'),
        row('case', 'Same year second', '2025', 'Active'),
        row('case', 'Lead: Lead shown as not confirmed', '2026', 'Active'),
        row('case', 'Non-party filer', '2023', 'Non-party filer'),
        row('case', 'Closed older', '2022', 'Closed'),
        row('case', 'No status', '2021', ''),
        row('regulator', 'Regulator closed newer', '2024', 'Closed'),
        row('regulator', 'Regulator active older', '2019', 'Active'),
        row('context', 'Context closed', '2024', 'Closed'),
        row('context', 'Context active', '2018', 'Active'),
      ]},
      { key: 'founders', count: 2, items: [
        { head: 'Founder later', date: '2020', src: [] },
        { head: 'Founder earlier', date: '2024', src: [] },
      ]},
      { key: 'people', count: 2, items: [
        { kind: 'officer', head: 'First officer', role: 'CEO', badge: '', src: [] },
        { kind: 'officer', head: 'Second officer', role: 'CFO', badge: 'Active', src: [] },
      ]},
    ],
  };
  const main = node();
  const pmain = node();
  main.set('.pmain', pmain);
  render(main, P);
  const html = pmain.innerHTML;
  const groups = titles(html.split('id="founders"')[0]);
  assert.deepEqual(groups.Cases, [
    'Active newer',
    'Same year second',
    'Active older',
    'Lead shown as not confirmed',
    'Closed newer',
    'Non-party filer',
    'Closed older',
    'No status',
  ]);
  assert.deepEqual(groups.Regulators, ['Regulator active older', 'Regulator closed newer']);
  assert.deepEqual(groups.Context, ['Context active', 'Context closed']);
  const founders = html.split('id="founders"')[1].split('id="people"')[0];
  assert.deepEqual([...founders.matchAll(/<div class="rt">([^<]*)<\/div>/g)].map(m => m[1]), ['Founder later', 'Founder earlier']);
  const people = html.split('id="people"')[1];
  assert.deepEqual([...people.matchAll(/<div class="pcard"><b>([^<]*)<\/b>/g)].map(m => m[1]), ['First officer', 'Second officer']);
  assert.match(html, /Lead shown as not confirmed/);
  assert.match(html, />Not confirmed</);
  assert.doesNotMatch(html.split('Lead shown as not confirmed')[1].slice(0, 200), />Active</);
});
