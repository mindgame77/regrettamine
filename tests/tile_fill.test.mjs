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

test('industry color comes from the name, and the donut is a filled ring', () => {
  const { sectorColor } = sandbox.window.RegretCompany;
  assert.equal(sectorColor('Health'), '#f425af');
  assert.equal(sectorColor('Enterprise software'), '#287fbd');
  assert.equal(sectorColor('Health'), sectorColor('Health'));
  assert.equal(sectorColor('Not a real sector'), 'var(--mute)');
  const js = fs.readFileSync(new URL('launch/js/company.js', root), 'utf8');
  assert.doesNotMatch(js, /PAL\[/);
  assert.doesNotMatch(js, /stroke-dashoffset/);
  assert.match(js, /function ringSlice/);
  assert.match(js, /fill="' \+ sectorColor/);
});

test('LP tile has no commitment count, investors and legal drop row rules', () => {
  const js = fs.readFileSync(new URL('launch/js/company.js', root), 'utf8');
  assert.doesNotMatch(js, /COPY\.commitments/);
  assert.match(js, /oneSource \? src\.slice\(0, 1\)/);
  assert.match(css, /\.bento #investors \.ipr\{border-top:0\}/);
  assert.match(css, /\.bento #lps \.lpl \.rt\{[^}]*text-overflow:ellipsis/);
  const legal = css.slice(css.indexOf('.lglines .lgline{'), css.indexOf('}', css.indexOf('.lglines .lgline{')) + 1);
  assert.match(legal, /border-bottom:0/);
  assert.doesNotMatch(legal, /border-bottom:1px/);
});

test('desktop pairs share the Deals announced / Videos height, recent deals does not', () => {
  const at = css.indexOf('@media (min-width:801px)');
  assert.ok(at > 0);
  const rule = css.slice(at, css.indexOf('}', css.indexOf('.bento .mod:not(.span2)', at)) + 1);
  assert.match(rule, /height:323px/);
  assert.match(rule, /:not\(\.span2\)/);
  const js = fs.readFileSync(new URL('launch/js/company.js', root), 'utf8');
  assert.match(js, /bentoCard\('lps', esc\(by\.lps\.title\),/);
  assert.doesNotMatch(js, /by\.lps\.count/);
});
