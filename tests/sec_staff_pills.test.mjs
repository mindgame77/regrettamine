// Staff and Investment staff are not header pills. Private funds still is, except a zero count.
// node --test tests/sec_staff_pills.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const made = [];
function el() {
  return {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
    classList: { toggle() {}, add() {}, remove() {} },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute() {},
    insertAdjacentElement(_pos, node) { return node; },
    remove() {},
  };
}
const sandbox = {
  window: { REGRET: { copy } },
  document: {
    addEventListener() {},
    getElementById() { return null; },
    createElement() { const node = el(); made.push(node); return node; },
  },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(read('launch/js/company.js'), sandbox, { filename: 'company.js' });
const { render } = sandbox.window.RegretCompany;

function mainEl() {
  const kids = {};
  const main = el();
  main.querySelector = (sel) => kids[sel] || null;
  main.set = (sel, child) => { kids[sel] = child; return child; };
  return main;
}
const sec = (label, value) => ({ label, value, src: [{ url: 'https://adviserinfo.sec.gov/firm/summary/160489' }] });

function pills(hero) {
  made.length = 0;
  const main = mainEl();
  const meta = el();
  main.set('.ph .m', meta);
  main.set('.ph h1', el());
  main.set('.m', meta);
  main.set('.actw', el());
  main.set('.toc', el());
  main.set('.spl', el());
  main.set('.pmain', el());
  const lock = el();
  lock.querySelector = () => el();
  main.set('#lockcard', lock);
  render(main, {
    open: true,
    firm: { name: 'Andreessen Horowitz', slug: 'a16z', website: 'https://a16z.com/' },
    hero, checks: [], sections: [],
  });
  const row = made.find(node => node.className === 'secp hpills');
  return row ? row.innerHTML : '';
}

test('header pills keep Private funds and drop Staff and Investment staff', () => {
  const html = pills([
    sec('Staff', '738'),
    sec('Investment staff', '88'),
    sec('Private funds', '12'),
    { label: 'HQ', value: 'Menlo Park, CA', src: [] },
  ]);
  assert.match(html, /Private funds 12/);
  assert.doesNotMatch(html, /Staff 738|Investment staff 88|\bStaff\b/);
  assert.equal(pills([sec('Private funds', '0')]), '');
  assert.equal(pills([sec('Staff', '738'), sec('Investment staff', '88')]), '');
});
