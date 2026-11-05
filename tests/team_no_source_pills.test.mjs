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
const css = read('launch/style.css');
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
const { teamCard, socialPills } = sandbox.window.RegretCompany;

const src = [{ url: 'https://a16z.com/team/', label: 'Firm website', date: '2026-11-03' }];

test('a team pill is the same markup as a company pill: icon and count only', () => {
  const x = { platform: 'x', url: 'https://x.com/bhorowitz', followers: 768507 };
  const li = { platform: 'linkedin', url: 'https://www.linkedin.com/in/behorowitz/', followers: 255215 };
  const company = socialPills({ firm: { social: [li, x] } });
  const h = teamCard({
    head: 'Ben Horowitz', kind: 'team', role: 'Cofounder and General Partner', src,
    linkedin_url: li.url, linkedin_followers: li.followers, x_url: x.url, x_followers: x.followers,
  });
  assert.match(h, /Ben Horowitz/);
  assert.match(h, /Cofounder and General Partner/);
  assert.ok(h.includes('<div class="secp socp">' + company + '</div>'));
  assert.match(h, /aria-label="LinkedIn: 255K" title="LinkedIn"/);
  assert.match(h, /aria-label="X: 769K" title="X"/);
  assert.doesNotMatch(h, />LinkedIn |>X |tsoc|Firm website|a16z\.com\/team|class="scs"/);
  const marcX = { platform: 'x', url: 'https://x.com/pmarca', followers: 6629052 };
  const marc = teamCard({ head: 'Marc Andreessen', role: 'Cofounder', x_url: marcX.url, x_followers: marcX.followers });
  assert.equal(marc.includes(socialPills({ firm: { social: [marcX] } })), true);
  assert.match(marc, /<\/svg><b>6\.63M<\/b>/);
});
test('LinkedIn then X, and only when the https url and a count are stored', () => {
  const h = teamCard({
    head: 'Ben Horowitz', role: 'Cofounder and General Partner',
    linkedin_url: 'https://www.linkedin.com/in/behorowitz/', linkedin_followers: 255215,
    x_url: 'https://x.com/bhorowitz', x_followers: 768507,
  });
  assert.ok(h.indexOf('linkedin.com/in/behorowitz') < h.indexOf('x.com/bhorowitz'));
  assert.match(h, /<\/svg><b>255K<\/b>/);
  assert.match(h, /<\/svg><b>769K<\/b>/);
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
  assert.doesNotMatch(css, /\.tsoc|\.tcard b\{/);
  assert.match(css, /\.tcard > b\{/);
  assert.match(css, /\.socp\{max-height:none\}/);
});
