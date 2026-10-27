// Home and firm pages share launch/js/search.js. Choosing a result does not depend on which page asked.
// node --test tests/search_shared.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const searchSrc = fs.readFileSync(new URL('launch/js/search.js', root), 'utf8');
const appSrc = fs.readFileSync(new URL('launch/js/app.js', root), 'utf8');
const companySrc = fs.readFileSync(new URL('launch/js/company.js', root), 'utf8');
const buildSrc = fs.readFileSync(new URL('launch/build.py', root), 'utf8');
const guide = fs.readFileSync(new URL('docs/HOW_IT_WORKS.md', root), 'utf8');

const sandbox = {
  window: { REGRET: { copy: { js: {} } } },
  document: { querySelectorAll() { return []; } },
  console,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(searchSrc, sandbox, { filename: 'search.js' });
const { choose } = sandbox.window.RegretSearch;

const hits = [
  { slug: 'y-combinator', name: 'Y Combinator', short_name: 'YC' },
  { slug: 'mayfield-fund', name: 'Mayfield Fund', short_name: '' },
];

test('an open list picks the same firm on every page', () => {
  assert.equal(choose('y com', hits, 0, true).slug, 'y-combinator');
  assert.equal(choose('y com', hits, 0, true).slug, choose('y com', hits, 0, true).slug);
});

test('a closed list picks only an exact name, short name, or slug', () => {
  assert.equal(choose('y com', hits, 0, false), null);
  assert.equal(choose('YC', hits, -1, false).slug, 'y-combinator');
  assert.equal(choose('y-combinator', hits, -1, false).slug, 'y-combinator');
});

function loadSearch(pageRoot) {
  const box = {
    window: { REGRET: { copy: { js: {} } }, REGRET_ROOT: pageRoot },
    document: { querySelectorAll() { return []; } },
    console,
  };
  box.window.window = box.window;
  box.globalThis = box;
  vm.createContext(box);
  vm.runInContext(searchSrc, box, { filename: 'search.js' });
  return box.window.RegretSearch;
}

test('firmUrl is /vc/<slug>/ on the home page and on a firm page', () => {
  const home = loadSearch('');
  const firm = loadSearch('../../');
  const full = loadSearch('../../../');
  assert.equal(home.firmUrl('point-allerton'), '/vc/point-allerton/');
  assert.equal(firm.firmUrl('point-allerton'), '/vc/point-allerton/');
  assert.equal(full.firmUrl('point-allerton'), '/vc/point-allerton/');
  assert.equal(home.firmUrl('y-combinator'), firm.firmUrl('y-combinator'));
  assert.equal(home.liveUrl('point allerton'), '/pending/?q=point%20allerton');
  assert.equal(firm.liveUrl('point allerton'), home.liveUrl('point allerton'));
});

test('search is one module, included on every page, and not copied into the firm page', () => {
  assert.match(searchSrc, /document\.querySelectorAll\('\[data-search\]'\)/);
  assert.match(searchSrc, /firm_suggest/);
  assert.doesNotMatch(appSrc, /firm_suggest/);
  assert.doesNotMatch(appSrc, /\[data-search\]/);
  assert.doesNotMatch(companySrc, /data-search/);
  assert.match(buildSrc, /if company else ''\) \+ f'<script defer src="\{root\}search\.js\?v=\{V\["search"\]\}"><\/script><script defer src="\{root\}app\.js/);
  assert.match(buildSrc, /'js\/search\.js'/);
  assert.match(guide, /Shared features use one shared module on every page\./);
});
