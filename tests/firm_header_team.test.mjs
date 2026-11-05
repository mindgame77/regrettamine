// Industries and stages: grey pills under the header, word for word, hidden when empty.
// Team collapses when the firm has no live CEO or founder. Check size is never drawn.
// node --test tests/firm_header_team.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const js = read('launch/js/company.js');
const mig = read('supabase/migrations/20261105180000_v2_firm_page_industries_stages_team.sql');

function el() {
  const node = {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
    classList: { toggle() {}, add() {}, remove() {} },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute() {},
    remove() {},
    insertAdjacentElement(where, child) { node.placed = { where, child }; return child; },
  };
  return node;
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
  document: { addEventListener() {}, getElementById() { return null; }, createElement: () => el() },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(js, sandbox, { filename: 'company.js' });
const { render, pageSecs } = sandbox.window.RegretCompany;

const a16z = {
  open: true, checks: [],
  firm: {
    name: 'Andreessen Horowitz', slug: 'a16z',
    industries: ['AI', 'bio + healthcare', 'consumer', 'crypto', 'enterprise', 'fintech', 'games', 'infrastructure', 'companies building toward American dynamism'],
    stages: ['Growth', 'Seed', 'Series C and later', 'Series A', 'Series B'],
  },
  sections: [{
    key: 'people', count: 2,
    items: [
      { head: 'Marc Andreessen', kind: 'team', role: 'Cofounder and General Partner', x_url: 'https://x.com/pmarca', linkedin_url: null },
      { head: 'Ben Horowitz', kind: 'team', role: 'Cofounder and General Partner', linkedin_url: 'https://www.linkedin.com/in/behorowitz/', x_url: 'https://x.com/bhorowitz' },
    ],
  }],
};

test('industries and stages render word for word, stages in the fixed order, no source pill', () => {
  const main = mainEl();
  const act = main.set('.actw', el());
  main.set('.pmain', el());
  main.set('.ph .m', el());
  render(main, a16z);
  const html = act.placed.child.innerHTML;
  assert.equal(act.placed.where, 'beforebegin');
  assert.match(html, /Industries/);
  assert.match(html, /Stages/);
  const texts = [...html.matchAll(/<span class="hp">([^<]*)<\/span>/g)].map(m => m[1]);
  assert.deepEqual(texts, [
    'AI', 'bio + healthcare', 'consumer', 'crypto', 'enterprise', 'fintech', 'games', 'infrastructure',
    'companies building toward American dynamism',
    'Seed', 'Series A', 'Series B', 'Series C and later', 'Growth',
  ]);
  assert.doesNotMatch(html, /href=|source|a16z\.com/i);
  assert.doesNotMatch(html, /[↑↓→←]/);
});

test('a firm with no industries, stages or team draws none of those blocks', () => {
  const main = mainEl();
  const act = main.set('.actw', el());
  const pmain = main.set('.pmain', el());
  main.set('.ph .m', el());
  const P = { open: true, checks: [], firm: { name: 'Khosla Ventures', slug: 'khosla-ventures', industries: [], stages: [] }, sections: [{ key: 'people', items: [] }] };
  render(main, P);
  assert.equal(act.placed, undefined);
  assert.equal(pageSecs(P).find(s => s.key === 'people'), undefined);
  assert.doesNotMatch(pmain.innerHTML, /Industries|Stages|Team|Check size|class="tcards"/);
});

test('check size is not a header block', () => {
  assert.doesNotMatch(js.slice(js.indexOf('function tagHtml'), js.indexOf('function paintTags')), /check_size|check size/i);
  assert.doesNotMatch(mig, /from v2_firm_check_sizes/);
  assert.match(mig, /v2_firm_industries/);
  assert.match(mig, /v2_firm_stages/);
  assert.match(mig, /is_founder/);
  assert.match(mig, /chief executive officer/);
  assert.match(mig, /linkedin_url/);
  assert.match(mig, /x_url/);
  assert.doesNotMatch(mig, /industry_text[\s\S]{0,80}source_url/);
  assert.match(mig, /to_regprocedure\('public\.v2_firm_page\(text\)'\) is null/);
  assert.match(mig, /enable row level security/);
});
