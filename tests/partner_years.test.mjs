// E2.1/E2.2/E4.2: partners shown (max 10) with years, officers kept, former hidden, board never shown; count = shown.
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
const src = [{ url: 'https://a16z.com/team/', label: 'Firm website', date: '2026-11-01' }];
const Y = new Date().getUTCFullYear();
const officers = ['A', 'B', 'C'].map(n => ({ head: 'Officer ' + n, kind: 'officer', role: 'Chief Legal Officer', src }));
const partners = Array.from({ length: 12 }, (_, i) => ({ head: 'P' + String(i).padStart(2, '0'), kind: 'partner', role: 'General Partner', joined_year: i === 0 ? Y : null, src }));
const gone = { head: 'Gone Old', kind: 'partner', role: 'Venture Partner', joined_year: Y - 5, left_year: Y - 2, src };
const leftNow = { head: 'Left Now', kind: 'partner', role: 'General Partner', joined_year: Y - 5, left_year: Y, src };
const board = [{ head: 'Board X', kind: 'board', role: 'Board seat: X', src }];
const page = (items) => ({ firm: { name: 'F' }, sections: [{ key: 'people', count: items.length, items }] });

test('E1: founders and a CEO are the team; partners, officers, former and board are not', () => {
  const founders = [{ head: 'Marc Andreessen', kind: 'partner', role: 'Cofounder and General Partner', is_founder: true }];
  const ceo = { head: 'Garry Tan', kind: 'officer', role: 'CEO/President' };
  const p = pageSecs(page([...officers, gone, leftNow, ...partners, ...board, ...founders, ceo])).find(x => x.key === 'people');
  assert.equal(p.count, 2);
  assert.equal(p.title, 'Team');
  assert.equal(p.subtitle, '');
  assert.equal(p.nocount, true);
});
test('partners and officers with no CEO or founder leave no Team section', () => {
  assert.equal(pageSecs(page([...officers, gone, leftNow, ...partners, ...board])).find(x => x.key === 'people'), undefined);
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
  const p = pageSecs(page([{ head: 'Marc Andreessen', kind: 'team', role: 'Cofounder and General Partner', x_url: 'https://x.com/pmarca' }])).find(x => x.key === 'people');
  assert.equal(p.count, 1);
  assert.equal(p.items[0].role, 'Cofounder and General Partner');
});
