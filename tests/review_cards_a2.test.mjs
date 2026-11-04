// G5.2 review cards (design A2): summary in bold quotes, "— Name, Role of Company · year · site", no ↓ on Show all.
// node --test tests/review_cards_a2.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));

function el() {
  return {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
    classList: { toggle() {}, add() {}, remove() {} },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute() {},
  };
}
function mainEl() {
  const kids = {};
  const main = el();
  main.querySelector = (sel) => kids[sel] || null;
  main.querySelectorAll = () => [];
  main.set = (sel, child) => { kids[sel] = child; return child; };
  return main;
}

const created = [];
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById(id) { return created.find(e => e.id === id) || null; }, createElement() { const e = el(); created.push(e); return e; }, body: { appendChild() {} } },
  console,
  URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(read('launch/js/company.js'), sandbox, { filename: 'company.js' });
const { render } = sandbox.window.RegretCompany;

function paint(extra) {
  const main = mainEl();
  const act = el();
  main.set('.m', el());
  main.set('.ph h1', el());
  main.set('.actw', act);
  const toc = el();
  toc.querySelectorAll = () => [];
  main.set('.toc', toc);
  main.set('.csum', el());
  const lock = el();
  const lockB = el(), lockP = el();
  lock.querySelector = (sel) => sel === 'b' ? lockB : sel === 'p' ? lockP : null;
  main.set('#lockcard', lock);
  main.set('.spl', el());
  main.set('.pmain', el());
  main.set('.rgt-n', el());
  const P = Object.assign({
    open: true,
    firm: { name: 'Sequoia Capital', slug: 'sequoia', hq: 'Menlo Park, CA', short_name: 'Sequoia', website: 'https://sequoiacap.com/' },
    hero: [],
    checks: [],
    sections: [],
    activity: {},
  }, extra);
  render(main, P);
  return act.innerHTML;
}

const L = 'https://www.linkedin.com/posts/martykausas_pylons-board';
const reviews = [
  { author: 'Marty Kausas', role: 'CEO', company: 'Pylon', date: '2025', url: L, summary: "Pylon's board is incredible.", body: "Pylon's board is incredible", tone: 'positive' },
  { author: 'malgorithms', role: null, company: 'Keybase', date: '2019', url: 'https://news.ycombinator.com/item?id=19563592', summary: 'a16z was excellent', body: 'x', tone: 'positive' },
  { author: 'Ann', role: 'Founder', company: null, date: '2024', url: 'https://x.com/a/1', summary: 'Great', tone: 'positive' },
  { author: 'Bob', date: '2023', url: 'https://x.com/b/1', summary: 'Fine', tone: 'positive' },
];
const html = paint({ activity: { reviews, latest_review: reviews[0], counts: { reviews: 6, deals: 0 } } });
const block = html.slice(html.indexOf("<div class=\"aps arvs\">"));


test('card shows the summary in bold quotes with no SUMMARY label and no quote line', () => {
  assert.match(block, /<p class="arsm"><b>“Pylon's board is incredible”<\/b><\/p>/);
  assert.doesNotMatch(block, /class="k"/);
  assert.doesNotMatch(block, /class="aq"/);
});
test('reviewer line is "— Name, Role of Company · year · site" with the site as the link', () => {
  assert.match(block, /<p class="arat">— Marty Kausas, CEO of Pylon · 2025 · <a href="[^"]+" target="_blank" rel="noopener">Linkedin\.com|linkedin\.com<\/a><\/p>/i);
  assert.doesNotMatch(block, /Source:/);
});
test('a blank role or company is left out', () => {
  assert.match(block, /— malgorithms, Keybase · 2019 · /);
  assert.match(block, /— Ann, Founder · 2024 · /);
});
test('Show all reviews has no arrow', () => {
  assert.match(block, /data-open="actrevs">Show all 6 reviews<\/button>/);
});
test('the Show all pop-up uses the same A2 cards', () => {
  const m = created.find(e => e.id === 'actrevs');
  assert.ok(m, 'actrevs pop-up exists');
  assert.match(m.innerHTML, /— Marty Kausas, CEO of Pylon · 2025 · /);
  assert.doesNotMatch(m.innerHTML, /class="(k|aq)"/);
});
