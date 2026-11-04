// C4.8: an open firm with no check rows still lists the 10 checks, each Not checked yet.
// node --test tests/checks_empty.test.mjs
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
  main.set = (sel, child) => { kids[sel] = child; return child; };
  return main;
}
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement() { return el(); } },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(read('launch/js/company.js'), sandbox, { filename: 'company.js' });
const { summary } = sandbox.window.RegretCompany;

const NAMES = [
  'Sanctions', 'Terrorism financing lists', 'Export and investment restrictions',
  'Financial regulator actions', 'Money laundering penalties', 'US court records',
  'Court records worldwide', 'Registration check', 'People behind the fund', 'Political ties',
];

function table(checks) {
  const main = mainEl();
  const list = el();
  main.set('.ph h1', el());
  main.set('.ph .m', el());
  main.set('.m', el());
  main.set('.actw', el());
  main.set('.cside', el());
  main.set('.cban', el());
  main.set('.list', list);
  main.set('.rgt-n', el());
  summary(main, {
    open: true,
    firm: { name: 'Andreessen Horowitz', slug: 'a16z', hq: 'Menlo Park, CA' },
    hero: [], checks, sections: [],
  }, {});
  return list.innerHTML;
}

test('no check rows: ten named checks, each Not checked yet, no legend', () => {
  for (const checks of [null, undefined, []]) {
    const html = table(checks);
    assert.equal((html.match(/<tr class="crow/g) || []).length, 10, JSON.stringify(checks));
    NAMES.forEach((name, i) => {
      assert.match(html, new RegExp('id="check-' + (i + 1) + '"[\\s\\S]*<b>' + name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '</b>'));
    });
    assert.equal((html.match(/Not checked yet/g) || []).length, 10);
    assert.doesNotMatch(html, /Red flag|Clear|Review|Worth knowing/);
    assert.doesNotMatch(html, /We found nothing in the sources/);
  }
});

test('a returned result stays, and a missing number is filled as Not checked yet', () => {
  const html = table([{ n: 1, title: 'Sanctions', descr: 'Government lists of people and companies you can\'t do business with.', state: 'clear', count: null }]);
  assert.match(html, /id="check-1"[\s\S]*Clear/);
  assert.match(html, /id="check-10"[\s\S]*Political ties[\s\S]*Not checked yet/);
  assert.equal((html.match(/<tr class="crow/g) || []).length, 10);
});
