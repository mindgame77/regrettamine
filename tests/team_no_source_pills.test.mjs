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

test('team card uses the company social pill: platform name and compact count', () => {
  const h = teamCard({ head: 'Marc Andreessen', kind: 'team', role: 'Cofounder and General Partner', src, x_url: 'https://x.com/pmarca', x_followers: 6629052 });
  assert.match(h, /Marc Andreessen/);
  assert.match(h, /Cofounder and General Partner/);
  assert.match(h, /class="sc soc" href="https:\/\/x\.com\/pmarca"/);
  assert.match(h, />X <b>6\.63M<\/b>/);
  assert.doesNotMatch(h, /tsoc-a|Firm website|a16z\.com\/team|class="scs"|Partner since|Left in|Founder</);
});
test('LinkedIn then X, and only when the https url and a count are stored', () => {
  const h = teamCard({
    head: 'Ben Horowitz', role: 'Cofounder and General Partner',
    linkedin_url: 'https://www.linkedin.com/in/behorowitz/', linkedin_followers: 255215,
    x_url: 'https://x.com/bhorowitz', x_followers: 768507,
  });
  assert.ok(h.indexOf('>LinkedIn ') < h.indexOf('>X '));
  assert.match(h, /linkedin\.com\/in\/behorowitz/);
  assert.match(h, />LinkedIn <b>255K<\/b>/);
  assert.match(h, /x\.com\/bhorowitz/);
  assert.match(h, />X <b>769K<\/b>/);
  const noCount = teamCard({ head: 'Marc Andreessen', role: 'Cofounder', x_url: 'https://x.com/pmarca' });
  assert.doesNotMatch(noCount, /class="sc soc"|tsoc-a/);
  const bare = teamCard({ head: 'Garry Tan', role: 'CEO/President', linkedin_url: '', x_url: 'http://x.com/garrytan', x_followers: 10 });
  assert.doesNotMatch(bare, /class="sc soc"|tsoc-a/);
  assert.match(bare, /CEO\/President/);
});
test('team section has no show-all popup and no source chips', () => {
  const ps = js.slice(js.indexOf('function personSection'), js.indexOf('function newsBlock'));
  assert.doesNotMatch(ps, /chips\(|actpeople|data-open|Board seat/);
  assert.match(ps, /teamCard/);
  assert.ok((js.match(/chips\(/g) || []).length > 2, 'other sections still render chips');
});
