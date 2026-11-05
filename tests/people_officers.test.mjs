// Team is only kind 'team' (CEO and founders from v2_firm_page). Older officer, partner, and board rows are not shown.
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
const team = { head: 'Marc Andreessen', kind: 'team', role: 'Cofounder and General Partner' };
const notTeam = [
  { head: 'Garry Tan', kind: 'officer', role: 'CEO/President', is_founder: true },
  { head: 'Ben Horowitz', kind: 'partner', role: 'Founder', badge: 'Founder', is_founder: true },
  { head: 'Board X', kind: 'board', role: 'Board seat: X' },
  { head: 'Moved', kind: 'move', role: 'Joined' },
];
const page = (items) => ({ firm: { name: 'F' }, sections: [{ key: 'people', count: items.length, items }] });

test('only a kind team row is shown', () => {
  const s = pageSecs(page([team, ...notTeam])).find(x => x.key === 'people');
  assert.equal(s.count, 1);
  assert.equal(s.items[0].head, 'Marc Andreessen');
  assert.equal(s.title, 'Team');
  assert.equal(s.subtitle, '');
  assert.equal(s.nocount, true);
});
test('officer, partner, board, and move rows leave no Team section', () => {
  assert.equal(pageSecs(page(notTeam)).find(x => x.key === 'people'), undefined);
});
test('copy has no board seats wording for the section', () => {
  const c = copy.sections.list.find(x => x.key === 'people');
  assert.doesNotMatch(c.title + ' ' + c.subtitle, /board/i);
  assert.equal(copy.company.people, undefined);
});
test('team section: heading Team, saved title, no count, subtitle, partner line or show all', () => {
  const { render } = sandbox.window.RegretCompany;
  const main = mainEl(), pmain = main.set('.pmain', el());
  const P = Object.assign(page([team]), { open: true, checks: [] });
  render(main, P);
  const h = pmain.innerHTML;
  assert.match(h, /<h2>Team<\/h2>/);
  assert.match(h, /Marc Andreessen/);
  assert.match(h, /Cofounder and General Partner/);
  assert.match(h, /class="tcards"/);
  assert.doesNotMatch(h, /pc2|Partners and officers|Partner since|Left in|Show all|class="pcards"|class="pfnd"/);
  assert.doesNotMatch(h, /<p class="psub">/);
});
