// B6c.1/B6c.8 (Alex, 2026-11-09): the Latest fund tile never shows a source link. The Show all pop-up keeps it.
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
  const m = html.match(/<div class="att afd[^"]*">([\s\S]*?)<\/div>/);
  return m ? m[0] : '';
}

const fund = (url, label) => ({ activity: { latest_fund: { name: 'ZZ Fund', raised_usd: 9000000000, date: '2026-01-01', url, url_label: label } } });

test('the Latest fund tile shows no source link', () => {
  for (const extra of [
    fund(EDGAR, 'SEC'),
    fund('https://reports.adviserinfo.sec.gov/x.pdf'),
    fund('https://www.reuters.com/x', 'Reuters'),
    fund('https://www.davispolk.com/x', null),
    fund('https://evilsec.gov.example/x', '  '),
  ]) {
    const box = tile(paint(extra));
    assert.match(box, /ZZ Fund · \$9B raised · 2026<\/span>/);
    assert.doesNotMatch(box, /<a[\s>]|Filing|Reuters|davispolk|evilsec/);
  }
});
test('a fund with no amount is not drawn', () => {
  const html = paint({ firm: { name: 'ZZ', slug: 'zz-not-lab' }, activity: { latest_fund: { name: 'ZZ Fund', url: 'https://fintechobserver.com/x', url_label: 'Fintech Observer' } } });
  assert.equal(tile(html), '');
  assert.doesNotMatch(html, /Fintech Observer|No SEC filings/);
});
