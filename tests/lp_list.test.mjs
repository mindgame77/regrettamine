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

test('one line per LP name, commitments counted, source pill on the same line', () => {
  const src = [{ label: 'CalPERS', url: 'https://www.calpers.ca.gov/report.pdf' }];
  const items = [
    { label: 'CalPERS', value: '$50M', src },
    { label: 'CalPERS', value: '$20M', src },
    { label: 'Yale Endowment', value: '', src: [{ label: 'Yale', url: 'https://investments.yale.edu/x' }] },
  ];
  const P = { open: true, firm: { name: 'Example Capital', slug: 'example' }, checks: [], sections: [{ key: 'lps', count: 3, items }] };
  const main = node(), pmain = node(); main.set('.pmain', pmain); render(main, P);
  const html = pmain.innerHTML;
  const rows = html.match(/<div class="rw lpl">/g) || [];
  assert.equal(rows.length, 2);
  assert.doesNotMatch(html, /class="rn"/);
  assert.match(html, /<div class="rw lpl"><div class="rm"><span class="rt">CalPERS · [^<]*\$50M · \$20M<\/span> <div class="scs"><a class="sc" href="https:\/\/www\.calpers\.ca\.gov\/report\.pdf"/);
});
