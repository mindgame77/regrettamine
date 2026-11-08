// v4 (Alex 2026-11-03): LPs are a simple list, one line per LP, not cards.
// node --test tests/lp_list.test.mjs
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
const sandbox = { window: { REGRET: { copy } }, document: { addEventListener() {}, getElementById() { return null; }, createElement() { return node(); } }, console, URL };
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(new URL('launch/js/dates.js', root), 'utf8'), sandbox, { filename: 'dates.js' });
vm.runInContext(fs.readFileSync(new URL('launch/js/company.js', root), 'utf8'), sandbox, { filename: 'company.js' });
const { render } = sandbox.window.RegretCompany;

test('LP rows in the payload are not drawn', () => {
  const src = [{ label: 'CalPERS', url: 'https://www.calpers.ca.gov/report.pdf' }];
  const items = [
    { label: 'CalPERS', value: '$50M', src },
    { label: 'CalPERS', value: '$20M', src },
    { label: 'Yale Endowment', value: '', src: [{ label: 'Yale', url: 'https://investments.yale.edu/x' }] },
  ];
  const P = { open: true, firm: { name: 'Example Capital', slug: 'example' }, checks: [], sections: [{ key: 'lps', count: 3, items }] };
  const main = node(), pmain = node(); main.set('.pmain', pmain); render(main, P);
  const html = pmain.innerHTML;
  assert.doesNotMatch(html, /class="rw lpl"|id="lps"|Limited partners|CalPERS/);
});

test('an LP payload does not open the LP popup', () => {
  const made = [];
  sandbox.document.body = { appendChild(el) { made.push(el); } };
  sandbox.document.getElementById = () => null;
  sandbox.document.createElement = () => node();
  const extras = ['One', 'Two', 'Three', 'Four', 'Five'].map(name => ({
    label: name, value: '$1M', src: [{ label: 'LP report', url: 'https://example.com/' + name }],
  }));
  const items = [
    { label: 'CalPERS', value: '$50M', src: [{ label: 'LP report', url: 'https://example.com/a', date: '2026-03-31' }] },
    { label: 'CalPERS', value: '$20M', src: [{ label: 'Regulator', url: 'https://example.com/b', date: '2019-12-01' }, { label: 'LP report', url: 'https://example.com/c', date: '2016-10-01' }] },
  ].concat(extras);
  const P = { open: true, firm: { name: 'Example Capital', slug: 'example' }, checks: [], sections: [{ key: 'lps', count: 6, items }] };
  const main = node(), pmain = node(); main.set('.pmain', pmain); render(main, P);
  assert.doesNotMatch(pmain.innerHTML, /id="lps"|actlps|CalPERS/);
  assert.equal(made.length, 0);
});
