// Team cards show the saved name and title, LinkedIn and X only when stored, and no source pill.
// node --test tests/team_no_source_pills.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const js = read('launch/js/company.js');
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement() { return {}; } },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(js, sandbox, { filename: 'company.js' });
const { teamCard } = sandbox.window.RegretCompany;

const src = [{ url: 'https://a16z.com/team/', label: 'Firm website', date: '2026-11-03' }];

test('team card keeps the saved title and drops the source pill', () => {
  const h = teamCard({ head: 'Marc Andreessen', kind: 'team', role: 'Cofounder and General Partner', src, x_url: 'https://x.com/pmarca' });
  assert.match(h, /Marc Andreessen/);
  assert.match(h, /Cofounder and General Partner/);
  assert.match(h, /https:\/\/x\.com\/pmarca/);
  assert.match(h, />X</);
  assert.doesNotMatch(h, /linkedin/i);
  assert.doesNotMatch(h, /Firm website|a16z\.com\/team|class="sc"|Partner since|Left in|Founder</);
});
test('LinkedIn and X render only when that https url is stored', () => {
  const h = teamCard({
    head: 'Ben Horowitz', role: 'Cofounder and General Partner',
    linkedin_url: 'https://www.linkedin.com/in/behorowitz/', x_url: 'https://x.com/bhorowitz',
  });
  assert.match(h, /LinkedIn/);
  assert.match(h, /linkedin\.com\/in\/behorowitz/);
  assert.match(h, /x\.com\/bhorowitz/);
  const bare = teamCard({ head: 'Garry Tan', role: 'CEO/President', linkedin_url: '', x_url: 'http://x.com/garrytan' });
  assert.equal(bare.includes('tsoc'), false);
  assert.match(bare, /CEO\/President/);
});
test('team section has no show-all popup and no source chips', () => {
  const ps = js.slice(js.indexOf('function personSection'), js.indexOf('function newsBlock'));
  assert.doesNotMatch(ps, /chips\(|actpeople|data-open|Board seat/);
  assert.match(ps, /teamCard/);
  assert.ok((js.match(/chips\(/g) || []).length > 2, 'other sections still render chips');
});
