// AUM tile unit words (2026-10-29): billion/million/thousand/bn/mn show the right unit.
// node --test tests/aum_unit.test.mjs
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
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement() { return node(); } },
  console,
  URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(new URL('launch/js/dates.js', root), 'utf8'), sandbox, { filename: 'dates.js' });
vm.runInContext(fs.readFileSync(new URL('launch/js/company.js', root), 'utf8'), sandbox, { filename: 'company.js' });
const { aumFigure } = sandbox.window.RegretCompany;

test('unit words map to the letter, digits kept as written', () => {
  assert.equal(aumFigure('$18.27 billion'), '$18.27B');
  assert.equal(aumFigure('Regulatory AUM $18.27 Billion (Form ADV)'), '$18.27B');
  assert.equal(aumFigure('$1.2 trillion'), '$1.2T');
  assert.equal(aumFigure('$450 million'), '$450M');
  assert.equal(aumFigure('$900 thousand'), '$900K');
  assert.equal(aumFigure('$3.5bn'), '$3.5B');
  assert.equal(aumFigure('$3.5 bn'), '$3.5B');
  assert.equal(aumFigure('$250mn'), '$250M');
  assert.equal(aumFigure('$250 MM'), '$250M');
});
test('letter units unchanged', () => {
  assert.equal(aumFigure('$46B'), '$46B');
  assert.equal(aumFigure('$46 B'), '$46B');
  assert.equal(aumFigure('$300k'), '$300K');
});
test('no unit: plain dollars still formatted; words that are not units are ignored', () => {
  assert.equal(aumFigure('$18.27 by 2025'), aumFigure('$18.27'));
  assert.equal(aumFigure('$1,500,000 managed'), aumFigure('$1,500,000'));
  assert.equal(aumFigure(''), '');
  assert.equal(aumFigure('no figure'), '');
});
