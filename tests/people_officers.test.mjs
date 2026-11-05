// People section: SEC Form ADV officers shown, board seats never shown or counted; nobody shown = no section.
// node --test tests/people_officers.test.mjs
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
const { pageSecs } = sandbox.window.RegretCompany;
const src = [{ url: 'https://reports.adviserinfo.sec.gov/x.pdf', label: 'SEC filing', date: '2026-03-30' }];
const officers = [
  { head: 'A One', kind: 'officer', role: 'Chief Legal Officer', src },
  { head: 'B Two', kind: 'officer', role: 'Chief Operating Officer', src },
  { head: 'C Three', kind: 'officer', role: 'Chief Compliance Officer', src },
];
const board = Array.from({ length: 14 }, (_, i) => ({ head: 'Board ' + i, kind: 'board', role: 'Board seats: X', src }));
const page = (items) => ({ firm: { name: 'F' }, sections: [{ key: 'people', count: items.length, items }] });

test('officers are counted and board seats are not', () => {
  const s = pageSecs(page([...officers, ...board])).find(x => x.key === 'people');
  assert.equal(s.count, 3);
  assert.equal(s.title, 'Team');
  assert.equal(s.subtitle, '');
  assert.doesNotMatch(s.title + ' ' + s.subtitle, /board/i);
});
test('only board seats = no people section', () => {
  assert.equal(pageSecs(page(board)).find(x => x.key === 'people'), undefined);
});
test('copy has no board seats wording for the section', () => {
  const c = copy.sections.list.find(x => x.key === 'people');
  assert.doesNotMatch(c.title + ' ' + c.subtitle, /board/i);
});
test('team section: heading Team with count, no subtitle, no group heading', () => {
  const { render } = sandbox.window.RegretCompany;
  const main = mainEl(), pmain = main.set('.pmain', el());
  const P = Object.assign(page(officers), { open: true, checks: [] });
  render(main, P);
  const h = pmain.innerHTML;
  assert.match(h, /<h2>Team <em class="pc2">3<\/em><\/h2>/);
  assert.doesNotMatch(h, /Partners and officers/);
  assert.doesNotMatch(h, /<h3>[^<]*· 3<\/h3>/);
  assert.match(h, /class="pcards"/);
});
