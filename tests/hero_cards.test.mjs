// The firm-page hero card row is not drawn. HQ stays in the meta line. SEC pills stay in secPills.
// node --test tests/hero_cards.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const JS = read('launch/js/company.js');
const BUILD = read('launch/build.py');
const CSS = read('launch/style.css');

function el() {
  return {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
    classList: { toggle() {}, add() {}, remove() {} },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute() {},
  };
}
function mainEl() {
  const kids = {};
  const main = el();
  main.querySelector = (sel) => kids[sel] || null;
  main.set = (sel, child) => { kids[sel] = child; return child; };
  return main;
}

const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement() { return el(); } },
  console,
  URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(JS, sandbox, { filename: 'company.js' });
const { render, summary } = sandbox.window.RegretCompany;

const hero = [
  { label: 'HQ', value: 'Menlo Park, CA', src: [] },
  { label: 'Staff', value: '738 · 88 investment', src: [] },
  { label: 'Regulatory AUM', value: '$90B', src: [{ label: 'SEC', url: 'https://adviserinfo.sec.gov/firm/summary/160489', date: '' }] },
  { label: 'Private funds', value: '119', src: [] },
  { label: 'Founded', value: '2009', src: [] },
];

function page(extra) {
  const main = mainEl();
  const meta = el();
  const heros = el();
  const h1 = el();
  main.set('.m', meta);
  main.set('.ph .m', meta);
  main.set('.ph h1', h1);
  main.set('.heros', heros);
  main.set('.actw', el());
  const toc = el();
  toc.querySelectorAll = () => [];
  main.set('.toc', toc);
  main.set('.csum', el());
  const lock = el();
  const lockB = el(), lockP = el();
  lock.querySelector = (sel) => sel === 'b' ? lockB : sel === 'p' ? lockP : null;
  main.set('#lockcard', lock);
  main.set('.spl', el());
  main.set('.pmain', el());
  main.set('.cside', el());
  main.set('.cban', el());
  main.set('.list', el());
  main.set('.rgt-n', el());
  const P = Object.assign({
    open: true,
    firm: { name: 'Andreessen Horowitz', slug: 'a16z', hq: 'Menlo Park, CA', short_name: 'a16z', website: 'https://a16z.com/', assets: '$90B' },
    hero,
    checks: [],
    sections: [],
  }, extra);
  return { main, meta, heros, P };
}

test('the shell and the painter no longer draw hero cards', () => {
  assert.equal(BUILD.includes('class="hfs heros"'), false);
  assert.match(BUILD, /class="actw"><div class="hfs">/);
  assert.equal(CSS.includes('.hfs.heros'), false);
  assert.equal(JS.includes('function paintHero'), false);
  assert.equal(JS.includes('function heroChips'), false);
  assert.equal(JS.includes('function headerCards'), false);
  assert.equal(JS.includes('function heroBits'), false);
  assert.equal(JS.includes("querySelector('.heros')"), false);
  assert.match(JS, /function metaLine\(/);
  assert.match(JS, /function assetLabel\(/);
  assert.match(JS, /function secPills\(/);
  assert.match(JS, /class="secp"/);
  assert.match(JS, /h\.label !== 'HQ'/);
});

test('an unlocked page keeps the HQ city in the meta line and leaves the hero row empty', () => {
  const { main, meta, heros, P } = page();
  render(main, P);
  assert.equal(heros.innerHTML, '');
  assert.equal(heros.hidden, false);
  assert.match(meta.innerHTML, /Menlo Park, CA/);
  assert.match(meta.innerHTML, /a16z\.com/);
  assert.doesNotMatch(meta.innerHTML, /Regulatory AUM|Private funds|Investment staff|class="hf"/);
  summary(main, P, {});
  assert.equal(heros.innerHTML, '');
  assert.match(meta.innerHTML, /Menlo Park, CA/);
  assert.doesNotMatch(main.innerHTML || '', /class="hf"/);
});

test('a check in progress still swaps the meta line and does not draw cards', () => {
  const checks = Array.from({ length: 10 }, (_, i) => ({ n: i + 1, title: 'T', descr: 'D', state: 'nc' }));
  const { main, meta, heros, P } = page({ hero: [], checks, queue: 'claimed' });
  summary(main, P, { queue: 'claimed' });
  assert.equal(heros.innerHTML, '');
  assert.match(meta.innerHTML, /Sources/);
  assert.match(meta.innerHTML, /being collected/);
  assert.doesNotMatch(meta.innerHTML, /Menlo Park/);
});
