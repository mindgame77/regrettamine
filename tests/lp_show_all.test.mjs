// LPs (Alex 2026-11-04 4:54 PM PT): first 5 on the page, Show all {n} LPs pop-up above 5, same rows, same order.
// node --test tests/lp_show_all.test.mjs
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

const lps = (n) => Array.from({ length: n }, (_, i) => ({ label: 'Endowment ' + String.fromCharCode(65 + i), value: '$' + (i + 1) + 'M', src: [{ label: 'Report', url: 'https://example.org/' + i + '.pdf' }] }));
function draw(n) {
  for (const k of Object.keys(made)) delete made[k];
  const items = lps(n);
  const P = { open: true, firm: { name: 'Example Capital', slug: 'example' }, checks: [], sections: [{ key: 'lps', count: n, items }] };
  const main = node(), pmain = node(); main.set('.pmain', pmain); render(main, P);
  return pmain.innerHTML;
}
const names = (h) => (h.match(/<span class="rt">Endowment [A-Z]/g) || []).map(x => x.slice(-1)).join('');

test('more than 5 LPs: first 5 in order, Show all button, full list in the shared pop-up', () => {
  const html = draw(7);
  assert.equal(names(html), 'ABCDE');
  assert.match(html, /<button type="button" class="ash" data-open="actlps">Show all<\/button>/);
  assert.doesNotMatch(html, /<p class="psub">|Named LP commitments/);
  assert.doesNotMatch(html, /[→›↗]/);
  const ov = made.actlps;
  assert.ok(ov, 'pop-up made');
  assert.match(ov.innerHTML, /class="md w amd"/);
  assert.equal(names(ov.innerHTML), 'ABCDEFG');
  assert.equal((ov.innerHTML.match(/<div class="rw lpl">/g) || []).length, 7);
  assert.deepEqual(copy.company.lps.all, ['Show all {n} LP', 'Show all {n} LPs']);
});

test('5 or fewer LPs: no button, no pop-up', () => {
  const html = draw(5);
  assert.equal(names(html), 'ABCDE');
  assert.doesNotMatch(html, /actlps|Show all/);
  assert.equal(made.actlps, undefined);
});
