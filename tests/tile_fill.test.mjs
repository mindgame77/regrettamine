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
  const palette = ['#4B2BD6', '#14D9A5', '#FFB020', '#FF5C8A', '#2EA8FF', '#8A63F5', '#18BBD4', '#FF9566', '#9EDB51', '#788BFF', '#F26C68', '#42CFC3', '#D781EF', '#E6BE45', '#3773DB', '#EC7DA8', '#77C9A1', '#A7A2C2'];
  const js = fs.readFileSync(new URL('launch/js/company.js', root), 'utf8');
  palette.forEach(hex => assert.match(js, new RegExp(hex, 'i')));
  assert.equal(sectorColor('AI agents'), '#4B2BD6');
  assert.equal(sectorColor('Enterprise software'), '#9EDB51');
  assert.equal(sectorColor('Health'), '#D781EF');
  assert.equal(sectorColor('Security'), '#77C9A1');
  assert.equal(sectorColor('Other'), '#A7A2C2');
  assert.equal(sectorColor('other'), '#A7A2C2');
  assert.equal(sectorColor('Health'), sectorColor('health'));
  const future = sectorColor('Quantum widgets');
  assert.equal(future, sectorColor('Quantum widgets'));
  assert.notEqual(future, '#A7A2C2');
  assert.ok(palette.slice(0, 17).includes(future));
  assert.doesNotMatch(js, /PAL\[/);
  assert.doesNotMatch(js, /stroke-dashoffset/);
  assert.match(js, /function ringSlice/);
  assert.match(js, /fill="' \+ sectorColor/);
});

test('LP tile has no commitment count, investors and legal drop row rules', () => {
  const js = fs.readFileSync(new URL('launch/js/company.js', root), 'utf8');
  assert.doesNotMatch(js, /COPY\.commitments/);
  assert.match(js, /oneSource \? src\.slice\(0, 1\)/);
  assert.match(css, /\.bento #investors \.ipr,\.ov \.ipr\{border-top:0/);
  assert.match(css, /\.ipr-a\{background:#E4F2FF\}/);
  assert.match(css, /\.ipr-b\{background:#F1F0F5\}/);
  assert.match(css, /\.lgline\.st-act\{background:#FFE3DE\}/);
  assert.match(css, /\.lgline\.st-dis\{background:#F1F0F5\}/);
  assert.match(css, /\.lgline\.st-set\{background:#E3F8EE\}/);
  assert.match(css, /\.ips \.iplab\{font-weight:700/);
  assert.match(css, /\.prof \.ips\{font:700 15px/);
  assert.match(css, /\.prof \.ipa,\.prof \.arat\{font:400/);
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
  const block = css.slice(at, css.indexOf('@media', at + 8) === -1 ? css.length : css.indexOf('@media', at + 8));
  assert.match(block, /#sectors \.cc,#rounds \.cc\{margin-top:auto;margin-bottom:auto\}/);
  assert.match(block, /#sectors \.ash\{margin-top:0/);
  assert.doesNotMatch(block, /#announced \.cc/);
});
