// Finished firm searches are logged once, after a pause or Enter, and a failed log never breaks search.
// node --test tests/search_log.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const searchSrc = fs.readFileSync(new URL('launch/js/search.js', root), 'utf8');
const firmsSrc = fs.readFileSync(new URL('launch/js/firms.js', root), 'utf8');

function clock() {
  let now = 0;
  let id = 1;
  const queue = [];
  return {
    setTimeout(fn, ms) {
      const t = { id: id++, fn, at: now + (ms || 0), ran: false, cleared: false };
      queue.push(t);
      return t.id;
    },
    clearTimeout(tid) {
      const t = queue.find(item => item.id === tid);
      if (t) t.cleared = true;
    },
    tick(ms) {
      now += ms;
      for (let guard = 0; guard < 30; guard++) {
        const due = queue.filter(t => !t.cleared && !t.ran && t.at <= now).sort((a, b) => a.at - b.at || a.id - b.id);
        if (!due.length) return;
        due[0].ran = true;
        due[0].fn();
      }
    },
  };
}

async function settle() {
  for (let i = 0; i < 6; i++) await new Promise(r => setImmediate(r));
}

function loadSearch(opts) {
  const time = clock();
  const fetches = [];
  const store = {};
  const listeners = {};
  const inp = {
    value: opts.value || '',
    listeners,
    setAttribute() {},
    addEventListener(type, fn) { (listeners[type] = listeners[type] || []).push(fn); },
  };
  const form = { q: inp, appendChild() {}, onsubmit: null };
  const hrefs = [];
  const box = {
    window: {
      REGRET: { url: 'https://example.supabase.co/', key: 'publishable-key', copy: { js: {} } },
      supabase: {
        createClient() {
          return {
            rpc(_name, args) {
              const q = String(args.q || '').toLowerCase();
              const data = (q === 'se' || q === 'sequoia')
                ? [{ slug: 'sequoia', name: 'Sequoia Capital', short_name: 'Sequoia', hq: 'Menlo Park' }]
                : [];
              return Promise.resolve({ data });
            },
          };
        },
      },
      crypto: { randomUUID: () => '11111111-2222-4333-8444-555555555555' },
    },
    document: {
      querySelectorAll(sel) { return sel === '[data-search]' ? [form] : []; },
      createElement() { return { id: '', hidden: true, className: '', innerHTML: '', setAttribute() {} }; },
    },
    location: {
      pathname: opts.pathname || '/',
      set href(v) { hrefs.push(v); },
      get href() { return hrefs[hrefs.length - 1] || ''; },
    },
    localStorage: {
      getItem(k) { return Object.prototype.hasOwnProperty.call(store, k) ? store[k] : null; },
      setItem(k, v) { store[k] = String(v); },
    },
    fetch(url, init) {
      if (opts.fetchThrows) return Promise.reject(new Error('down'));
      fetches.push({ url, ...init });
      return Promise.resolve({ ok: true });
    },
    setTimeout: time.setTimeout,
    clearTimeout: time.clearTimeout,
    console,
  };
  box.window.window = box.window;
  box.window.localStorage = box.localStorage;
  box.window.fetch = box.fetch;
  box.globalThis = box;
  vm.createContext(box);
  vm.runInContext(searchSrc, box, { filename: 'search.js' });
  function type(value) {
    inp.value = value;
    (listeners.input || []).forEach(fn => fn());
  }
  return { type, tick: time.tick, fetches, hrefs, store, form, log: box.window.RegretSearch.log };
}

test('a home search is not logged on each key, only once the typing stops', async () => {
  const page = loadSearch({ pathname: '/' });
  page.type('se');
  page.tick(1000);
  await settle();
  assert.equal(page.fetches.length, 0);
  page.type('sequoia');
  page.tick(1499);
  await settle();
  assert.equal(page.fetches.length, 0);
  page.tick(1);
  await settle();
  assert.equal(page.fetches.length, 1);
  const req = page.fetches[0];
  assert.equal(req.url, 'https://example.supabase.co/rest/v1/rpc/log_search');
  assert.equal(req.method, 'POST');
  assert.equal(req.keepalive, true);
  assert.equal(req.credentials, 'omit');
  assert.equal(req.headers.apikey, 'publishable-key');
  assert.equal(req.headers.Authorization, 'Bearer publishable-key');
  const body = JSON.parse(req.body);
  assert.equal(body.p_term, 'sequoia');
  assert.equal(body.p_page, 'home');
  assert.equal(body.p_result_count, 1);
  assert.equal(body.p_top_firm_id, 'sequoia');
  assert.equal(body.p_anon_key, '11111111-2222-4333-8444-555555555555');
  assert.equal(page.store['regretamin.anon'], body.p_anon_key);
  page.type('Sequoia');
  page.tick(2000);
  await settle();
  assert.equal(page.fetches.length, 1);
});

test('Enter logs immediately and still opens the firm', async () => {
  const page = loadSearch({ pathname: '/vc/a16z/' });
  page.type('sequoia');
  page.tick(120);
  await settle();
  assert.equal(page.fetches.length, 0);
  await page.form.onsubmit({ preventDefault() {} });
  assert.equal(page.fetches.length, 1);
  const body = JSON.parse(page.fetches[0].body);
  assert.equal(body.p_page, 'firm');
  assert.equal(body.p_result_count, 1);
  assert.equal(body.p_top_firm_id, 'sequoia');
  assert.equal(page.hrefs[0], '/vc/sequoia/');
});

test('a search with no firm is logged as zero results and goes to pending', async () => {
  const page = loadSearch({ pathname: '/' });
  page.type('nomatch');
  await page.form.onsubmit({ preventDefault() {} });
  const body = JSON.parse(page.fetches[0].body);
  assert.equal(body.p_result_count, 0);
  assert.equal(body.p_top_firm_id, null);
  assert.equal(page.hrefs[0], '/pending/?q=nomatch');
});

test('one letter is not logged, and a failed request does not throw', async () => {
  const quiet = loadSearch({ pathname: '/' });
  quiet.type('a');
  quiet.tick(2000);
  await settle();
  assert.equal(quiet.fetches.length, 0);

  const broken = loadSearch({ pathname: '/', fetchThrows: true });
  broken.type('sequoia');
  broken.tick(2000);
  await settle();
  assert.equal(broken.fetches.length, 0);
});

test('the same term on two pages is two logs, and loading the box logs nothing', async () => {
  const page = loadSearch({ pathname: '/', value: 'Andreessen Horowitz' });
  page.tick(5000);
  await settle();
  assert.equal(page.fetches.length, 0);
  page.log('acme', 'home', 0, null);
  page.log('acme', 'home', 0, null);
  page.log('Acme', 'firm', 2, 'acme');
  assert.equal(page.fetches.length, 2);
  assert.equal(JSON.parse(page.fetches[0].body).p_result_count, 0);
  assert.equal(JSON.parse(page.fetches[1].body).p_page, 'firm');
});

function loadFirms() {
  const time = clock();
  const logs = [];
  const els = {};
  function makeEl(id) {
    const node = {
      id,
      hidden: true,
      value: '',
      placeholder: 'Search investors',
      textContent: '',
      innerHTML: '',
      className: '',
      style: {},
      classList: { add() {}, remove() {}, contains() { return false; }, toggle() {} },
      _h: {},
      setAttribute() {},
      getAttribute(name) { return name === 'placeholder' ? 'Search investors' : ''; },
      addEventListener(type, fn) { (node._h[type] = node._h[type] || []).push(fn); },
      closest() { return null; },
      contains() { return false; },
      focus() {},
      getBoundingClientRect() { return { top: 0, right: 0, bottom: 0, left: 0, width: 0, height: 0 }; },
    };
    return node;
  }
  function el(id) {
    if (!els[id]) els[id] = makeEl(id);
    return els[id];
  }
  const firms = [
    { slug: 'sequoia', name: 'Sequoia Capital', short_name: 'Sequoia', website: 'https://sequoiacap.com', country: 'US', added: '2026-01-02', industries: [], stages: [], startups: ['Stripe'], startup_sites: [] },
    { slug: 'a16z', name: 'Andreessen Horowitz', short_name: 'a16z', website: 'https://a16z.com', country: 'US', added: '2026-01-01', industries: ['Crypto'], stages: ['Seed'], startups: [], startup_sites: [] },
  ];
  const sandbox = {
    window: {
      REGRET: { copy: { site: { pages: { investors: {} } } } },
      RegretSearch: { log(term, page, count, top) { logs.push({ term, page, count, top }); } },
      addEventListener() {},
      innerWidth: 1280,
      innerHeight: 800,
    },
    document: {
      getElementById: el,
      querySelector() { return null; },
      addEventListener() {},
    },
    addEventListener() {},
    fetch() {
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ firms }) });
    },
    setTimeout: time.setTimeout,
    clearTimeout: time.clearTimeout,
    console,
  };
  sandbox.window.window = sandbox.window;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(firmsSrc, sandbox, { filename: 'firms.js' });
  return { logs, els, tick: time.tick, q: () => el('firms-q'), list: () => el('firms-list') };
}

test('the investors field filters the list and logs the term only after a pause', async () => {
  const page = loadFirms();
  await settle();
  assert.equal(page.logs.length, 0);
  const q = page.q();
  q.value = 'sequoia';
  q._h.input.forEach(fn => fn());
  assert.match(page.list().innerHTML, /sequoia/);
  assert.doesNotMatch(page.list().innerHTML, /a16z/);
  assert.equal(page.logs.length, 0);
  page.tick(1499);
  assert.equal(page.logs.length, 0);
  page.tick(1);
  assert.deepEqual(page.logs, [{ term: 'sequoia', page: 'investors', count: 1, top: 'sequoia' }]);
  q.value = 'SEQUOIA';
  q._h.input.forEach(fn => fn());
  page.tick(1500);
  assert.equal(page.logs.length, 1);
});

test('investors Enter and a comma commit log immediately, including a miss', async () => {
  const page = loadFirms();
  await settle();
  const q = page.q();
  q.value = 'no such fund';
  q._h.keydown.forEach(fn => fn({ key: 'Enter', preventDefault() {} }));
  assert.deepEqual(page.logs, [{ term: 'no such fund', page: 'investors', count: 0, top: null }]);
  assert.equal(q.value, '');

  q.value = 'a16z,stripe';
  q._h.input.forEach(fn => fn());
  assert.equal(page.logs.length, 2);
  assert.equal(page.logs[1].term, 'a16z');
  assert.equal(page.logs[1].count, 1);
  assert.equal(page.logs[1].top, 'a16z');
  page.tick(1500);
  assert.equal(page.logs.length, 3);
  assert.equal(page.logs[2].term, 'stripe');
  assert.equal(page.logs[2].count, 1);
  assert.equal(page.logs[2].top, 'sequoia');
});
