// A live firm with no published rows still paints: name, site link, ten Not checked yet rows.
// The payload is the shape v2_firm_page returns for Accel before any facts are published.
// node --test tests/empty_firm_page.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));

function el() {
  const node = {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
    classList: { toggle() {}, add() {}, remove() {} },
    kids: {},
    querySelector(sel) { return this.kids[sel] || null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute() {},
    remove() {},
    insertAdjacentElement() { return null; },
  };
  return node;
}
function mainEl() {
  const main = el();
  main.dataset = { tab: 'checks', firm: 'accel' };
  main.set = (sel, child) => { main.kids[sel] = child; return child; };
  return main;
}
const sandbox = {
  window: { REGRET: { copy }, matchMedia() { return { matches: false }; }, addEventListener() {} },
  document: { addEventListener() {}, getElementById() { return null; }, createElement() { return el(); }, querySelector() { return null; } },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(read('launch/js/company.js'), sandbox, { filename: 'company.js' });
const { paint } = sandbox.window.RegretCompany;

const EMPTY = {
  status: 'ok', open: true, unchecked: false, done: null, source: 'v2',
  firm: {
    slug: 'accel', name: 'Accel', sec_name: 'Accel', short_name: null, hq: null, hq_country: null,
    website: 'https://www.accel.com', assets: null, social: [], founded_year: null,
    industries: [], deal_sectors: [], stages: [], contact_email: null, contact_phone: null,
    apply_link: null, money: {},
  },
  hero: [], sections: [], checks: [], queue: null, started_at: null, details: [], outline: null, ondemand: null,
  activity: {
    lazy: false, active: true, deals: [], reviews: [], latest_deal: null, latest_review: null, latest_fund: null,
    counts: { deals: 0, reviews: 0 }, deals_12m: 0,
    sector_12m: { n: 0, top: [], other: 0 },
    funds_announced: { n: 0, latest: null, items: [] },
    funds_sec: { n: 0, items: [] },
    funds_closed_12m: 0,
  },
};

test('a firm with no published data paints its name and ten unchecked rows', () => {
  const main = mainEl();
  const h1 = el();
  const list = el();
  const lock = el();
  lock.kids.b = el();
  lock.kids.p = el();
  main.set('.ph h1', h1);
  main.set('h1', h1);
  main.set('.m', el());
  main.set('.ph .m', el());
  main.set('.actw', el());
  main.set('.cban', el());
  main.set('.cside', el());
  main.set('.list', list);
  main.set('.toc', el());
  main.set('.csum', el());
  main.set('.spl', el());
  main.set('.pmain', el());
  main.set('.rgt-n', el());
  main.set('#lockcard', lock);
  main.set('#puse', el());
  const view = paint(main, EMPTY, null);
  const table = list.innerHTML.slice(0, list.innerHTML.indexOf('</table>'));
  assert.equal(h1.textContent, 'Accel');
  assert.match(main.kids['.ph .m'].innerHTML, /accel\.com/);
  assert.equal((table.match(/<tr class="crow/g) || []).length, 10);
  assert.equal((table.match(/Not checked yet/g) || []).length, 10);
  assert.equal(view.checking, false);
  assert.equal(main.kids['.pmain'].innerHTML, '');
});
