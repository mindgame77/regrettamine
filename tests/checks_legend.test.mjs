// C4.4: one grey legend, once, under the Checks table; live pill words; no Red flag line; no icon.
// node --test tests/checks_legend.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const el = () => ({ hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
  classList: { toggle() {}, add() {}, remove() {} }, querySelector() { return null; }, querySelectorAll() { return []; },
  appendChild() {}, setAttribute() {} });
const sandbox = { window: { REGRET: { copy } }, document: { addEventListener() {}, getElementById() { return null; }, createElement: el }, console, URL };
sandbox.window.window = sandbox.window; sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox);
vm.runInContext(read('launch/js/company.js'), sandbox);

function table(checks) {
  const kids = {}, main = el(), list = el();
  main.querySelector = (s) => kids[s] || null;
  for (const s of ['.ph h1', '.ph .m', '.m', '.actw', '.cside', '.cban', '.rgt-n']) kids[s] = el();
  kids['.list'] = list;
  sandbox.window.RegretCompany.summary(main, { open: true, firm: { name: 'A', slug: 'a16z' }, hero: [], checks, sections: [] }, {});
  return list.innerHTML;
}

test('legend: once, after the table, four lines with live pill words', () => {
  const html = table([{ n: 1, title: 'Sanctions', descr: 'x', state: 'clear' }, { n: 2, title: 'T', descr: 'y', state: 'review', count: '1 record' }]);
  const P = copy.site.pills;
  assert.equal((html.match(/We found nothing in the sources we checked on this date\. It's not a guarantee\./g) || []).length, 1);
  const leg = html.slice(html.indexOf('</table>'));
  assert.match(leg, /^<\/table><p class="note">/);
  for (const k of ['clear', 'review', 'wk', 'nc']) assert.ok(leg.includes('<b>' + P[k][1] + ':</b>'), k);
  assert.match(leg, /Run this check to see the result\./);
  assert.doesNotMatch(leg, /Red flag|ⓘ|→/);
  assert.equal((leg.match(/<br>/g) || []).length, 3);
});
