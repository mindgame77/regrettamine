// Deals, this year. Year-only dates show the year. Sectors and Rounds use This year / All time.
// Deals announced is all time, one bar per year. node --test tests/deal_year.test.mjs
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
    attrs: {},
    classList: { toggle() {}, add() {}, remove() {} },
    querySelector(sel) { return (node.kids && node.kids[sel]) || null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute(k, v) { node.attrs[k] = v; },
    getAttribute(k) { return node.attrs[k]; },
    remove() {},
    insertAdjacentElement() {},
  };
  return node;
}
function mainEl() {
  const kids = {};
  const main = el();
  main.querySelector = (sel) => kids[sel] || null;
  main.querySelectorAll = () => main.charts || [];
  main.set = (sel, child) => { kids[sel] = child; return child; };
  return main;
}
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement: () => el(), body: { appendChild() {} } },
  console, URL, Intl, Date,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(js, sandbox, { filename: 'company.js' });
const { render } = sandbox.window.RegretCompany;

function paint(activity) {
  const main = mainEl();
  const act = main.set('.actw', el());
  const pmain = main.set('.pmain', el());
  main.set('.ph .m', el());
  const year = new Date().getFullYear();
  const charts = ['s', 'r', 'd'].map(k => {
    const tile = el();
    tile.attrs['data-chart'] = k;
    const sw = el();
    const box = el();
    tile.kids = { '.segw': sw, '.cc': box };
    tile.sw = sw;
    tile.box = box;
    return tile;
  });
  main.charts = charts;
  render(main, {
    open: true, checks: [],
    firm: { name: 'Example', slug: 'example' },
    activity, sections: [],
  });
  return { act: act.innerHTML, pmain: pmain.innerHTML, charts, year };
}

test('a year-only deal shows the year, and this year is counted in the browser', () => {
  const y = String(new Date().getFullYear());
  const { act } = paint({
    deals_12m: 99,
    latest_deal: { company: 'YearCo', date: y + '-01-01', date_precision: 'year', url: 'https://example.com/y' },
    deals: [
      { company: 'YearCo', date: y + '-01-01', date_precision: 'year', sector: 'Fintech' },
      { company: 'Full', date: y + '-03-02', date_precision: 'full date', sector: 'Health' },
      { company: 'Old', date: '2019-06-01', date_precision: 'full date', sector: 'Security' },
    ],
  });
  assert.match(act, /Deals, this year/);
  assert.match(act, />2</);
  assert.match(act, new RegExp('Last deal: YearCo · ' + y));
  assert.doesNotMatch(act, /Jan 1|last 12 mo|99/);
});

test('Sectors and Rounds have This year \/ All time, and Deals announced is all time with a year bar', () => {
  const y = String(new Date().getFullYear());
  const { charts } = paint({
    deals: [
      { company: 'YearCo', date: y + '-01-01', date_precision: 'year', sector: 'Fintech', round: 'Seed' },
      { company: 'Old', date: '2019-06-01', date_precision: 'full date', sector: 'Security', round: 'Series A' },
    ],
  });
  const [sectors, rounds, announced] = charts;
  assert.match(sectors.sw.innerHTML, /This year/);
  assert.match(sectors.sw.innerHTML, /All time/);
  assert.doesNotMatch(sectors.sw.innerHTML, /12 months/);
  assert.match(rounds.sw.innerHTML, /This year/);
  assert.equal(announced.sw.innerHTML, '');
  assert.match(announced.box.innerHTML, new RegExp("'" + y.slice(2)));
  assert.match(announced.box.innerHTML, /'19/);
  assert.doesNotMatch(announced.box.innerHTML, /Jan|12 months/);
});
