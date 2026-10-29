// B6c.1/B6c.8/A1.8: the fund tile link names its real source: Filing for sec.gov, else the stored outlet name, else the host.
// node --test tests/funds_line.test.mjs
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

const EDGAR = 'https://www.sec.gov/Archives/edgar/data/1906948/000206235726000016/0002062357-26-000016-index.htm';
const ADV = 'https://reports.adviserinfo.sec.gov/reports/ADV/157373/PDF/157373.pdf';

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

function tile(html) {
  const m = html.match(/<div class="att afd">([\s\S]*?)<\/div>/);
  return m ? m[0] : '';
}

const link = (html) => (tile(html).match(/<a [^>]*>([^<]*)<\/a>/) || [])[1];
const fund = (url, label) => ({ activity: { latest_fund: { name: 'ZZ Fund', raised_usd: 9000000000, date: '2026-01-01', url, url_label: label } } });

test('sec.gov is a Filing even with a label', () => {
  assert.equal(link(paint(fund(EDGAR, 'SEC'))), 'Filing ↗');
  assert.equal(link(paint(fund('https://reports.adviserinfo.sec.gov/x.pdf'))), 'Filing ↗');
});
test('a news link names the outlet', () => {
  assert.equal(link(paint(fund('https://www.reuters.com/x', 'Reuters'))), 'Reuters ↗');
});
test('no stored name falls back to the host, never to Filing', () => {
  assert.equal(link(paint(fund('https://www.davispolk.com/x', null))), 'davispolk.com ↗');
  assert.equal(link(paint(fund('https://evilsec.gov.example/x', '  '))), 'evilsec.gov.example ↗');
});
test('a name-only fund tile (non-lab firm) uses the same label', () => {
  const html = paint({ firm: { name: 'ZZ', slug: 'zz-not-lab' }, activity: { latest_fund: { name: 'ZZ Fund', url: 'https://fintechobserver.com/x', url_label: 'Fintech Observer' } } });
  assert.equal(link(html), 'Fintech Observer ↗');
});
