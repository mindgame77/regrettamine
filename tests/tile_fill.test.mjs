// Whole rows only: a further row is shown when it fits, and never as a partial slice.
// node --test tests/tile_fill.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const copy = JSON.parse(fs.readFileSync(new URL('launch/copy.json', root), 'utf8'));
const css = fs.readFileSync(new URL('launch/style.css', root), 'utf8');
const sandbox = {
  window: { REGRET: { copy } },
  document: {
    addEventListener() {},
    getElementById() { return null; },
    body: { appendChild() {} },
    createElement() { return { className: '', hidden: true, innerHTML: '', appendChild() {} }; },
  },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(new URL('launch/js/dates.js', root), 'utf8'), sandbox, { filename: 'dates.js' });
vm.runInContext(fs.readFileSync(new URL('launch/js/company.js', root), 'utf8'), sandbox, { filename: 'company.js' });
const { extraRowsThatFit } = sandbox.window.RegretCompany;

function boxes(heights, space) {
  const n = extraRowsThatFit(heights, space);
  let y = 0;
  const out = [];
  for (let i = 0; i < n; i++) {
    out.push({ top: y, bottom: y + heights[i], h: heights[i] });
    y += heights[i];
  }
  return out;
}

test('only whole rows that fit are kept, and they do not overlap', () => {
  const placed = boxes([40, 37, 37, 37], 96);
  assert.equal(placed.length, 2);
  assert.ok(placed[placed.length - 1].bottom <= 96);
  for (let i = 1; i < placed.length; i++) assert.ok(placed[i].top >= placed[i - 1].bottom);
  assert.equal(extraRowsThatFit([46], 16), 0);
  assert.equal(extraRowsThatFit([90], 72), 0);
  assert.equal(extraRowsThatFit([68, 90], 72), 1);
  assert.equal(extraRowsThatFit([37, 37, 37], 111), 3);
});

test('legal case titles are not ellipsized', () => {
  const rule = css.slice(css.indexOf('.lgt{'), css.indexOf('}', css.indexOf('.lgt{')) + 1);
  assert.match(rule, /white-space:normal/);
  assert.doesNotMatch(rule, /text-overflow:ellipsis|white-space:nowrap/);
});
