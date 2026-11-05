// D2.8 / D4.8 / D4.8.1 (Alex 2026-11-04 9:21 PM PT): lab firm deals, one line per startup.
// node --test tests/deals_grouped.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const copy = JSON.parse(fs.readFileSync(new URL('launch/copy.json', root), 'utf8'));
function node() {
  const kids = {};
  return {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
    classList: { toggle() {} },
    querySelector(sel) { return kids[sel] || null; },
    querySelectorAll() { return []; },
    insertAdjacentElement() {}, setAttribute() {},
    set(sel, child) { kids[sel] = child; return child; },
  };
}
const made = {};
const body = { appendChild(n) { made[n.id] = n; } };
const sandbox = { window: { REGRET: { copy } }, document: { body, addEventListener() {}, getElementById(id) { return made[id] || null; }, createElement() { return node(); } }, console, URL };
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(new URL('launch/js/dates.js', root), 'utf8'), sandbox, { filename: 'dates.js' });
vm.runInContext(fs.readFileSync(new URL('launch/js/company.js', root), 'utf8'), sandbox, { filename: 'company.js' });
const { render } = sandbox.window.RegretCompany;

const deals = [
  { company: 'Nova Health', domain: 'nova.health', round: 'Series A', date: '2026-03-01', lead: false, url: 'https://news.example.com/nova-a', sector: 'Healthcare' },
  { company: 'Orbit Labs', domain: 'orbit.dev', round: 'Series B', date: '2025-06-01', lead: false, url: 'https://a16z.com/orbit' },
  { company: 'Nova Health', domain: 'nova.health', round: 'Seed', date: '2024-02-01', lead: true, url: 'https://a16z.com/nova-seed', sector: 'Healthcare' },
  { company: 'Acme AI', domain: 'acme.ai', round: 'Series A', date: '2025-09-01', lead: true, amount: 12000000, currency: 'USD', url: 'https://a16z.com/acme' },
];
function draw() {
  for (const k of Object.keys(made)) delete made[k];
  const P = { open: true, firm: { name: 'a16z', slug: 'a16z' }, checks: [], sections: [],
    activity: { lazy: false, deals, latest_deal: deals[0], counts: { deals: 4, reviews: 0 }, deals_12m: 1, active: true } };
  const main = node(), actw = node(); main.set('.actw', actw); main.set('.pmain', node()); render(main, P);
  return actw.innerHTML;
}
const lines = (h) => (h.match(/<span class="rt">.*?<\/span>/g) || []).map(x => x.replace(/<[^>]+>/g, ''));

test('page shows the newest startup with its rounds grouped, oldest first, lead mark per round', () => {
  const h = draw();
  assert.deepEqual(lines(h), ['Nova Health · Seed (lead) 2024 · Series A 2026']);
  assert.match(h, /Show all 4 deals/);
  assert.match(h, /class="sc" href="https:\/\/a16z.com\/nova-seed"/);
  assert.match(h, /class="sc" href="https:\/\/news.example.com\/nova-a"/);
  assert.doesNotMatch(h, /[→›↗]/);
});

test('Show all pop-up: one line per startup, newest first, single rounds keep the D3.8 / D4.8 line', () => {
  draw();
  const ov = made.actdeals;
  assert.ok(ov, 'pop-up made');
  assert.match(ov.innerHTML, /class="md w amd"/);
  assert.deepEqual(lines(ov.innerHTML), [
    'Nova Health · Seed (lead) 2024 · Series A 2026',
    'Acme AI · Series A (lead) · $12M · 2025',
    'Orbit Labs · Series B · 2025',
  ]);
  assert.equal((ov.innerHTML.match(/class="sc"/g) || []).length, 4);
  assert.equal(copy.company.activity.deal_line.lead, '(lead)');
});
