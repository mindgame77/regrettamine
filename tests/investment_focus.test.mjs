// Investment focus (F.11): website labels are the stored words, with no source link. Empty industries use recorded-deal sectors.
// node --test tests/investment_focus.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const js = read('launch/js/company.js');

function el() {
  const node = {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
    classList: { toggle() {}, add() {}, remove() {} },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute() {},
    remove() {},
    insertAdjacentElement(where, child) { node.placed = { where, child }; return child; },
  };
  return node;
}
function mainEl() {
  const kids = {};
  const main = el();
  main.querySelector = (sel) => kids[sel] || null;
  main.set = (sel, child) => { kids[sel] = child; return child; };
  return main;
}
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement: () => el() },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(js, sandbox, { filename: 'company.js' });
const { render } = sandbox.window.RegretCompany;

function tags(firm) {
  const main = mainEl();
  const act = main.set('.actw', el());
  main.set('.pmain', el());
  main.set('.ph .m', el());
  render(main, { open: true, checks: [], firm, sections: [] });
  return act.placed ? act.placed.child.innerHTML : '';
}
const pills = (html) => [...html.matchAll(/<span class="hp">([^<]*)<\/span>/g)].map(m => m[1]);

test('website focus shows the stored labels and no source link', () => {
  const html = tags({
    name: 'Andreessen Horowitz', slug: 'a16z',
    industries: [
      { industry_text: 'AI', source_url: 'https://a16z.com/about/' },
      { industry_text: 'Fintech', source_url: 'https://a16z.com/about/' },
    ],
    stages: [],
    deal_sectors: [{ sector: 'Security', n: 9 }],
  });
  assert.match(html, /Sectors/);
  assert.doesNotMatch(html, /Top sectors from recorded deals/);
  assert.deepEqual(pills(html), ['AI', 'Fintech']);
  assert.doesNotMatch(html, /href=|htag-src|a16z\.com/);
  assert.doesNotMatch(html, /[↑↓→←▶◀▸▹›»]/);
});

test('plain industry strings stay labels with no link', () => {
  const html = tags({ industries: ['AI', 'Crypto'], stages: ['Seed'] });
  assert.deepEqual(pills(html), ['AI', 'Crypto', 'Seed']);
  assert.doesNotMatch(html, /href=|htag-src/);
});

test('an empty industry list shows recorded-deal sector names under Sectors, with no counts', () => {
  const html = tags({
    industries: [],
    stages: ['Growth'],
    deal_sectors: [
      { sector: 'Fintech', n: 10 },
      { sector: 'AI agents', n: 12 },
      { sector: 'Security', n: 13 },
    ],
  });
  assert.match(html, /Sectors/);
  assert.doesNotMatch(html, /Top sectors from recorded deals/);
  assert.deepEqual(pills(html), ['Security', 'AI agents', 'Fintech', 'Growth']);
  assert.doesNotMatch(html, /href=|htag-src|Other|·/);
});

test('equal deal counts break alphabetically and a blank sector is dropped', () => {
  const html = tags({
    industries: [],
    deal_sectors: [
      { sector: 'Security', n: 4 },
      { sector: 'Bio', n: 4 },
      { sector: '', n: 9 },
      { sector: 'Health', n: 0 },
    ],
  });
  assert.deepEqual(pills(html), ['Bio', 'Security']);
});

test('no website focus and no recorded sectors hides the field', () => {
  const html = tags({ name: 'Empty', industries: [], stages: [], deal_sectors: [] });
  assert.equal(html, '');
});
