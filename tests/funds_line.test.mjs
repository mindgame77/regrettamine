// A9.6 fund tile line: "N funds on SEC record · Show all", popup list after a credit, gate when locked, hidden at 0.
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

const created = [];
sandbox.document.body = el();
sandbox.document.createElement = () => { const e = el(); created.push(e); return e; };
const fundsSec = { n: 2, items: [
  { name: 'Sequoia Capital Fund, L.P.', raised_usd: 22700000000, date: '2026-02-05', url: EDGAR },
  { name: 'Sequoia Capital Fund Feeder, L.P.', raised_usd: 7000000000, date: '2026-02-05', url: 'https://www.sec.gov/Archives/edgar/data/1906966/feeder' },
] };
const latest = { name: 'Sequoia Capital Fund, L.P.', raised_usd: 22700000000, date: '2026-02-05', url: EDGAR };

test('the line sits inside the fund tile and Show all opens the existing popup with each fund', () => {
  created.length = 0;
  const html = paint({ activity: { latest_fund: latest, funds_sec: fundsSec } });
  assert.match(tile(html), /<span class="afl">2 funds on SEC record · <button type="button" class="ash" data-open="actfunds" aria-haspopup="dialog">Show all ↓<\/button><\/span><\/div>$/);
  const ov = created.find(e => e.id === 'actfunds');
  assert.ok(ov, 'popup made');
  assert.match(ov.innerHTML, /role="dialog" aria-modal="true" aria-label="2 funds on SEC record · Sequoia Capital"/);
  assert.match(ov.innerHTML, /<b>Sequoia Capital Fund<\/b><span>\$22\.7B<\/span><span>Feb 5, 2026<\/span><a href="https:\/\/www\.sec\.gov\/Archives\/edgar\/data\/1906948\/[^"]+" target="_blank" rel="noopener">Filing ↗<\/a>/);
  assert.match(ov.innerHTML, /Sequoia Capital Fund Feeder<\/b><span>\$7B<\/span>/);
});

test('one fund reads singular; locked pages get the sign-in gate and no popup', () => {
  created.length = 0;
  const html = paint({ open: false, activity: { latest_fund: latest, funds_sec: { n: 1, items: null } } });
  assert.match(tile(html), /1 fund on SEC record · <button type="button" class="ash" data-gate>Show all ↓<\/button>/);
  assert.ok(!created.find(e => e.id === 'actfunds'));
});

test('no line with zero SEC funds', () => {
  assert.doesNotMatch(paint({ activity: { latest_fund: latest, funds_sec: { n: 0, items: [] } } }), /afl|on SEC record/);
  assert.doesNotMatch(paint({ activity: { funds_sec: { n: 0, items: [] } } }), /afl|on SEC record/);
});

test('no tile at all (accel): the line sits on its own at the top of the activity area', () => {
  created.length = 0;
  const html = paint({ activity: { funds_sec: fundsSec } });
  assert.match(html, /^<section class="actv"[^>]*><div class="ats" style="grid-template-columns:1fr"><span class="afl">2 funds on SEC record · <button type="button" class="ash" data-open="actfunds" aria-haspopup="dialog">Show all ↓<\/button><\/span><\/div>/);
  assert.doesNotMatch(html, /att afd/);
  assert.ok(created.find(e => e.id === 'actfunds'), 'same Show all popup');
  const locked = paint({ open: false, activity: { funds_sec: { n: 6, items: null } } });
  assert.match(locked, /<div class="ats" style="grid-template-columns:1fr"><span class="afl">6 funds on SEC record · <button type="button" class="ash" data-gate>Show all ↓<\/button>/);
});

test('a lone line is not added when other tiles exist but no fund tile', () => {
  const html = paint({ activity: { deals_12m: 3, funds_sec: fundsSec } });
  assert.doesNotMatch(html, /afl|on SEC record/);
});

test('copy strings live in copy.json', () => {
  const A = copy.company.activity;
  assert.deepEqual(A.funds_sec, ['{n} fund on SEC record', '{n} funds on SEC record']);
  assert.equal(A.show_all, 'Show all');
});
