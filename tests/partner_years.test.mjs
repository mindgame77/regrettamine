// Team is only kind 'team'. Older partner, officer, and board rows are not shown.
// node --test tests/partner_years.test.mjs
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
const mig = read('supabase/migrations/20261104235000_v2_firm_page_partner_years.sql');
const undo = read('supabase/rollbacks/20261104235000_v2_firm_page_partner_years_undo.sql');
const js = read('launch/js/company.js');
const team = [
  { head: 'Marc Andreessen', kind: 'team', role: 'Cofounder and General Partner', x_url: 'https://x.com/pmarca' },
  { head: 'Ben Horowitz', kind: 'team', role: 'Cofounder and General Partner' },
];
const notTeam = [
  { head: 'Officer A', kind: 'officer', role: 'CEO/President', is_founder: true },
  { head: 'Partner B', kind: 'partner', role: 'Founder', badge: 'Founder', is_founder: true },
  { head: 'Board X', kind: 'board', role: 'Board seat: X' },
  { head: 'Moved', kind: 'move', role: 'Joined' },
];
const page = (items) => ({ firm: { name: 'F' }, sections: [{ key: 'people', count: items.length, items }] });

test('only kind team rows are the team', () => {
  const p = pageSecs(page([...team, ...notTeam])).find(x => x.key === 'people');
  assert.equal(p.count, 2);
  assert.equal(p.title, 'Team');
  assert.equal(p.subtitle, '');
  assert.equal(p.nocount, true);
  const { render } = sandbox.window.RegretCompany;
  const main = mainEl(), pmain = main.set('.pmain', el());
  render(main, Object.assign(page([...team, ...notTeam]), { open: true, checks: [] }));
  assert.match(pmain.innerHTML, /Marc Andreessen/);
  assert.match(pmain.innerHTML, /Ben Horowitz/);
  assert.doesNotMatch(pmain.innerHTML, /Officer A|Partner B|Board X|Moved/);
});
test('partner, officer, board, and move rows leave no Team section', () => {
  assert.equal(pageSecs(page(notTeam)).find(x => x.key === 'people'), undefined);
});
test('team cards have no partner-since, left-in, founder tag, show-all, green/red or arrows', () => {
  const sec = js.slice(js.indexOf('function isTeamPerson'), js.indexOf('function newsBlock'));
  assert.match(sec, /function teamCard/);
  assert.doesNotMatch(sec, /Partner since|Left in|pfnd|actpeople|pjoin|pleft|data-open|[↑↓→←]/);
});
test('migration: partner rows with years, founders/newest/A-Z order, former filtered, undo exists', () => {
  assert.match(mig, /'kind','partner'/);
  assert.match(mig, /'joined_year',r\.joined_year,'left_year',r\.left_year/);
  assert.match(mig, /when r\.is_founder then 1 when r\.joined_year is not null then 2 \+ \(9999 - r\.joined_year\)/);
  assert.match(mig, /r\.left_year >= extract\(year from now\(\)\)::int - 1/);
  assert.match(mig, /raise exception/);
  assert.match(mig, /to_regprocedure\('public\.v2_firm_page\(text\)'\) is null/);
  assert.match(undo, /select 1, jsonb_build_object\('head',pe\.person_name,'kind','board'/);
});

test('a kind=team row from v2_firm_page is shown as saved', () => {
  const p = pageSecs(page(team.slice(0, 1))).find(x => x.key === 'people');
  assert.equal(p.count, 1);
  assert.equal(p.items[0].role, 'Cofounder and General Partner');
});
