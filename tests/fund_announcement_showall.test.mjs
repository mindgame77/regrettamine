// Announcements open the existing Show all control and actfunds popup.
// The button count is the current item list. latest.n stays on the Latest fund card only.
// node --test tests/fund_announcement_showall.test.mjs
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
const NEWS = 'https://example.com/fund-news';
const created = [];
sandbox.document.body = el();
sandbox.document.createElement = () => { const e = el(); created.push(e); return e; };

function paint(extra) {
  created.length = 0;
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
    firm: { name: 'Founders Fund', slug: 'founders-fund', hq: 'San Francisco, CA', short_name: 'Founders Fund', website: 'https://foundersfund.com/' },
    hero: [],
    checks: [],
    sections: [],
    activity: {},
  }, extra);
  render(main, P);
  return act.innerHTML;
}

function popup() {
  return created.find(e => e.id === 'actfunds');
}

const sec = {
  n: 2,
  items: [
    { name: 'Filed Fund I, L.P.', raised_usd: 1000000000, date: '2024-02-01', url: EDGAR },
    { name: 'Filed Fund II, L.P.', raised_usd: 2000000000, date: '2022-06-01', url: EDGAR },
  ],
};

function announced(n, latestN = 1) {
  const items = [];
  for (let i = 0; i < n; i++) {
    items.push({
      name: 'Announced Fund ' + (i + 1),
      raised_usd: (i + 1) * 100000000,
      raised_display: '$' + (i + 1) + '00M',
      date: i === 0 ? '2026-03-23' : '2020-0' + ((i % 8) + 1) + '-15',
      url: NEWS + '/' + (i + 1),
    });
  }
  return {
    n,
    latest: { n: latestN, total_display: '$4B', date: '2026-03-23', url: NEWS + '/1' },
    items,
  };
}

test('announcements alone open Show all with the item count, not latest.n', () => {
  const html = paint({
    activity: {
      funds_sec: { n: 0, items: [] },
      funds_announced: announced(5, 1),
    },
  });
  assert.match(html, /<b>\$4B<\/b>/);
  assert.match(html, /1 fund announced/);
  assert.match(html, /2026/);
  assert.match(html, /data-fundtile class="att afd/);
  assert.doesNotMatch(html, /<a[\s>]/);
  assert.match(html, /Show all \(5 funds\)/);
  assert.doesNotMatch(html, /Show all \(1 fund\)/);
  assert.doesNotMatch(html, /class="adl"/);
  assert.doesNotMatch(html, /Announced Fund 2|\$200M|\$500M/);
  assert.doesNotMatch(html, /Firm &amp; funds|Firm & funds/);
  const ov = popup();
  assert.ok(ov, 'existing actfunds popup');
  assert.match(ov.innerHTML, /aria-label="5 announced · Founders Fund"/);
  for (let i = 1; i <= 5; i++) assert.equal((ov.innerHTML.match(new RegExp('Announced Fund ' + i + '<', 'g')) || []).length, 1);
  assert.match(ov.innerHTML, /<b>Announced Fund 1<\/b><span>\$100M<\/span><span>2026<\/span><a href="https:\/\/example.com\/fund-news\/1" target="_blank" rel="noopener">Source<\/a>/);
});

test('one current announcement still uses the same Show all popup', () => {
  const html = paint({ activity: { funds_sec: { n: 0, items: [] }, funds_announced: announced(1, 1) } });
  assert.match(html, /Show all \(1 fund\)/);
  assert.match(html, /<b>\$4B<\/b>/);
  assert.doesNotMatch(html, /class="adl"/);
  const ov = popup();
  assert.equal((ov.innerHTML.match(/Announced Fund 1</g) || []).length, 1);
});

test('SEC-only funds keep the SEC count and do not invent an announcement title', () => {
  const html = paint({ activity: { latest_fund: { name: 'Filed Fund I, L.P.', raised_usd: 1000000000, date: '2024-02-01', url: EDGAR }, funds_sec: sec } });
  assert.match(html, /Show all \(2 funds\)/);
  assert.match(html, /<b>\$1B<\/b>/);
  assert.doesNotMatch(html, /<a[\s>]|Filing/);
  assert.doesNotMatch(html, /announced/);
  assert.doesNotMatch(html, /class="adl"/);
  const ov = popup();
  assert.match(ov.innerHTML, /aria-label="2 funds on SEC record · Founders Fund"/);
  assert.match(ov.innerHTML, /<b>Filed Fund I<\/b><span>\$1B<\/span><span>2024<\/span><a href="https:\/\/www\.sec\.gov\/[^"]+" target="_blank" rel="noopener">Filing<\/a>/);
  assert.match(ov.innerHTML, /Filed Fund II/);
  assert.doesNotMatch(ov.innerHTML, /Announced Fund/);
});

test('mixed SEC and announcements keep the SEC button count and list each announcement once', () => {
  const html = paint({
    activity: {
      funds_sec: sec,
      funds_announced: announced(2, 1),
    },
  });
  assert.match(html, /<b>\$4B<\/b>/);
  assert.match(html, /Show all \(2 funds\)/);
  assert.doesNotMatch(html, /Show all \(3 funds\)|Show all \(4 funds\)/);
  assert.doesNotMatch(html, /class="adl"/);
  assert.doesNotMatch(html, /Announced Fund 2/);
  const ov = popup();
  assert.match(ov.innerHTML, /aria-label="2 funds on SEC record · 2 announced · Founders Fund"/);
  assert.equal((ov.innerHTML.match(/Announced Fund 1</g) || []).length, 1);
  assert.equal((ov.innerHTML.match(/Announced Fund 2</g) || []).length, 1);
  assert.match(ov.innerHTML, /Filed Fund I/);
  assert.match(ov.innerHTML, /Filed Fund II/);
});

test('no SEC funds and no announcements leaves Show all off', () => {
  const html = paint({ activity: { latest_fund: { name: 'Filed Fund I, L.P.', raised_usd: 1000000000, date: '2024-02-01', url: EDGAR }, funds_sec: { n: 0, items: [] } } });
  assert.match(html, /<b>\$1B<\/b>/);
  assert.doesNotMatch(html, /afl|Show all|class="adl"|data-fundtile/);
  assert.equal(popup(), undefined);
});

test('a locked announcement list uses the existing gate and does not build the popup', () => {
  const html = paint({ open: false, activity: { funds_sec: { n: 0, items: [] }, funds_announced: announced(8, 1) } });
  assert.match(html, /<button type="button" class="ash" data-gate>Show all \(8 funds\)<\/button>/);
  assert.doesNotMatch(html, /data-open="actfunds"|class="adl"/);
  assert.equal(popup(), undefined);
});
