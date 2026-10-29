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
const guide = fs.readFileSync(new URL('docs/archive/HOW_IT_WORKS.md', root), 'utf8');

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

// One module instance per page. Home starts empty (ROOT ''). A firm page prefills the
// firm name (ROOT '../../'), the same markup launch/build.py emits. Both run search.js.
function wait(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }

function control(location) {
  const node = {
    className: '', id: '', hidden: false, value: '', children: [], attrs: {}, listeners: {}, links: [],
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k]; },
    appendChild(child) { this.children.push(child); return child; },
    addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); },
  };
  let html = '';
  Object.defineProperty(node, 'innerHTML', {
    get() { return html; },
    set(v) {
      html = String(v);
      node.links = [];
      for (const m of html.matchAll(/<a\b[^>]*href="([^"]*)"/g)) {
        const href = m[1].replace(/&amp;/g, '&');
        node.links.push({ href, click() { location.href = href; } });
      }
    },
  });
  return node;
}

function boot(pageRoot, initial) {
  const location = { href: '' };
  const rpc = [];
  const input = control(location);
  input.value = initial;
  const form = control(location);
  form.q = input;
  form.appendChild(input);
  const sb = {
    rpc(name, args) {
      rpc.push({ name, q: args.q });
      const data = args.q === 'y com' ? [
        { slug: 'y-combinator', name: 'Y Combinator', short_name: 'YC', hq: 'Mountain View' },
        { slug: 'mayfield-fund', name: 'Mayfield Fund', short_name: '', hq: '' },
      ] : [];
      return Promise.resolve({ data });
    },
  };
  const sandbox = {
    window: {
      REGRET: { url: 'https://example.supabase.co', key: 'test-key', copy: { js: { suggest_none: 'No match' } } },
      REGRET_ROOT: pageRoot,
      supabase: { createClient() { return sb; } },
    },
    document: {
      querySelectorAll(sel) { return sel === '[data-search]' ? [form] : []; },
      createElement() { return control(location); },
    },
    location,
    setTimeout,
    clearTimeout,
    console,
  };
  sandbox.window.window = sandbox.window;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(searchSrc, sandbox, { filename: 'search.js' });
  const box = form.children.find((c) => c.className === 'sdd');
  return { form, input, box, location, rpc };
}

function fire(node, type) {
  for (const fn of node.listeners[type] || []) fn({ type, preventDefault() {} });
}

// Relative hrefs from home ('') and from /vc/<slug>/ ('../../') land on the same firm.
function pathFrom(pageRoot, href) {
  const base = pageRoot === '../../' ? 'https://regretamin.com/vc/a16z/' : 'https://regretamin.com/';
  return new URL(href, base).pathname;
}

async function runSearch(pageRoot, initial) {
  const page = boot(pageRoot, initial);
  assert.equal(page.input.value, initial);
  assert.equal(page.box.hidden, true);

  page.input.value = 'y com';
  fire(page.input, 'input');
  await wait(250);

  assert.equal(page.input.value, 'y com');
  assert.deepEqual(page.rpc.map((c) => c.q), ['y com']);
  assert.equal(page.box.hidden, false);
  assert.match(page.box.innerHTML.replace(/<[^>]+>/g, ''), /Y Combinator/);
  const href = page.box.links[0].href;
  assert.equal(pathFrom(pageRoot, href), '/vc/y-combinator/');

  page.box.links[0].click();
  assert.equal(pathFrom(pageRoot, page.location.href), '/vc/y-combinator/');

  page.location.href = '';
  const lookedUp = page.rpc.length;
  await page.form.onsubmit({ preventDefault() {} });
  assert.equal(page.rpc.length, lookedUp);
  assert.equal(pathFrom(pageRoot, page.location.href), '/vc/y-combinator/');
  assert.equal(page.input.value, 'y com');
  return href;
}

test('home page: typing, suggestions, Check, and a suggestion click open Y Combinator', async () => {
  const href = await runSearch('', '');
  assert.equal(href, 'vc/y-combinator/');
});

test('firm page: typing, suggestions, Check, and a suggestion click open Y Combinator', async () => {
  const href = await runSearch('../../', 'Andreessen Horowitz');
  assert.equal(href, '../../vc/y-combinator/');
});
