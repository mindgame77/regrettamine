// Fund asset rows: each current fund's 2021-2026 amount and its as-of date.
// node --test tests/fund_assets.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));

function el() {
  return {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {}, id: '',
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

const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement() { return el(); } },
  console,
  URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(read('launch/js/company.js'), sandbox, { filename: 'company.js' });
const { render } = sandbox.window.RegretCompany;

const EDGAR = 'https://www.sec.gov/Archives/edgar/data/1/index.htm';
const created = [];
sandbox.document.body = el();
sandbox.document.createElement = () => { const e = el(); created.push(e); return e; };

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

const fundsSec = { n: 2, items: [
  { name: 'Sequoia Capital Fund, L.P.', raised_usd: 1000, date: '2020-01-01', url: EDGAR },
  { name: 'Other Fund, L.P.', raised_usd: 5000000000, date: '2024-05-01', url: EDGAR },
] };

test('each 2021-2026 fund asset shows its amount and as-of date, and replaces the same fund', () => {
  created.length = 0;
  const html = paint({
    activity: {
      latest_fund: { name: 'Sequoia Capital Fund, L.P.', raised_usd: 1000000, date: '2026-02-05', url: EDGAR },
      funds_sec: fundsSec,
      fund_assets: { n: 3, items: [
        { name: 'Sequoia Capital Fund, L.P.', raised_display: '$27.2B', date: '2026-11-04', url: EDGAR },
        { name: 'Sequoia Capital Growth Fund, L.P.', raised_display: '$81M', date: '2021-03-30', url: EDGAR },
        { name: 'Old Asset, L.P.', raised_display: '$9B', date: '2020-01-01', url: EDGAR },
      ] },
    },
  });
  assert.match(html, /<b>Sequoia Capital Fund<\/b><span>\$27\.2B<\/span><span>Nov 4, 2026<\/span>/);
  assert.match(html, /<b>Sequoia Capital Growth Fund<\/b><span>\$81M<\/span><span>Mar 30, 2021<\/span>/);
  assert.doesNotMatch(html, /Old Asset/);
  const ov = created.find(e => e.id === 'actfunds');
  assert.ok(ov, 'funds popup made');
  const popup = ov.innerHTML;
  assert.equal((popup.match(/Sequoia Capital Fund</g) || []).length, 1);
  assert.match(popup, /<b>Sequoia Capital Fund<\/b><span>\$27\.2B<\/span><span>Nov 4, 2026<\/span>/);
  assert.match(popup, /<b>Other Fund<\/b><span>\$5B<\/span><span>2024<\/span>/);
  assert.doesNotMatch(popup, /Old Asset/);
});

test('no asset rows leaves the activity tiles unchanged', () => {
  const html = paint({
    activity: { latest_fund: { name: 'Sequoia Capital Fund, L.P.', raised_usd: 22700000000, date: '2026-02-05', url: EDGAR }, funds_sec: { n: 0, items: [] } },
  });
  assert.match(html, /<b>\$22\.7B<\/b>/);
  assert.doesNotMatch(html, /class="adl"/);
});
