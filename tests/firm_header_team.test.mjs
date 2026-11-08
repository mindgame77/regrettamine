// Industries and stages: grey pills under the header, word for word, hidden when empty.
// Team collapses when the firm has no live CEO or founder.
// Average check sits on the stages pill line when firm.check_size is set, and is omitted when it is not.
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
const checkMig = read('supabase/migrations/20261108200000_v2_firm_page_check_size.sql');

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
  assert.match(html, /Sectors/);
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
  assert.doesNotMatch(pmain.innerHTML, /Sectors|Industries|Stages|Team|Check size|class="tcards"/);
});

test('industries and stages stay word for word with no source on that migration', () => {
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

function headerHtml(firm) {
  const main = mainEl();
  const act = main.set('.actw', el());
  main.set('.pmain', el());
  main.set('.ph .m', el());
  render(main, { open: true, checks: [], firm, sections: [] });
  return act.placed ? act.placed.child.innerHTML : '';
}

test('average check sits on the stages line after the pills', () => {
  const html = headerHtml({
    name: 'Example Firm', slug: 'example-firm',
    industries: ['Example sector'],
    stages: ['Series B', 'Seed'],
    check_size: '$250K',
  });
  const stagesAt = html.indexOf('Stages');
  const ruleAt = html.indexOf('htag-rule');
  const labelAt = html.indexOf('AVG CHECK');
  const amountAt = html.indexOf('>$250K<');
  assert.ok(stagesAt >= 0 && ruleAt > stagesAt && labelAt > ruleAt && amountAt > labelAt);
  assert.match(html, /<span class="hp">Seed<\/span><span class="hp">Series B<\/span><span class="htag-rule"/);
  assert.match(html, /<span class="htag-k">AVG CHECK<\/span><span class="hp">\$250K<\/span>/);
  assert.doesNotMatch(html, /href=|source_url|program_name/i);
  assert.doesNotMatch(html, /[↑↓→←]/);
});

test('a missing or blank check size draws no label and no divider', () => {
  const none = headerHtml({ name: 'Example Firm', industries: [], stages: ['Seed'], check_size: null });
  assert.match(none, /<span class="hp">Seed<\/span>/);
  assert.doesNotMatch(none, /AVG CHECK|htag-rule|htag-k/);
  const blank = headerHtml({ name: 'Example Firm', industries: [], stages: ['Seed'], check_size: '   ' });
  assert.doesNotMatch(blank, /AVG CHECK|htag-rule/);
  const only = headerHtml({ name: 'Example Firm', industries: [], stages: [], check_size: '$250K' });
  assert.match(only, /<span class="htag-k">AVG CHECK<\/span><span class="hp">\$250K<\/span>/);
  assert.doesNotMatch(only, /Stages|htag-rule/);
});

test('check size text is escaped and the page reads one published amount_text', () => {
  const html = headerHtml({ name: 'Example Firm', stages: ['Seed'], check_size: '<b>$250K</b>' });
  assert.match(html, /&lt;b&gt;\$250K&lt;\/b&gt;/);
  assert.doesNotMatch(html, /<b>\$250K<\/b>/);
  const start = checkMig.indexOf("'check_size',(select nullif(btrim(c.amount_text),'') from v2_firm_check_sizes c where");
  const select = checkMig.slice(start, checkMig.indexOf('limit 1)', start) + 'limit 1)'.length);
  assert.match(select, /nullif\(btrim\(c\.amount_text\),''\)/);
  assert.match(select, /c\.is_current and not c\.archived/);
  assert.match(select, /order by c\.read_on desc nulls last, c\.id desc limit 1/);
  assert.doesNotMatch(select, /source_url|min_usd|max_usd|program_name/);
  assert.match(checkMig, /to_regprocedure\('public\.v2_firm_page\(text\)'\) is null/);
  assert.match(checkMig, /v2_firm_check_sizes is missing/);
});
