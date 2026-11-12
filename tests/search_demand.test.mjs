// Search demand on the investors page and the nav box.
// node --test tests/search_demand.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (path) => fs.readFileSync(new URL(path, root), 'utf8');

test('the two migrations split additive work from behavior', () => {
  const add = read('supabase/migrations/20261112180000_v2_search_demand_tables.sql');
  const job = read('supabase/migrations/20261112190000_v2_search_demand_job.sql');
  assert.match(add, /create table if not exists public\.v2_search_log/);
  assert.match(add, /create table if not exists public\.v2_firm_watch/);
  assert.match(add, /add column if not exists demand_hidden boolean not null default false/);
  assert.match(add, /v2_log_search/);
  assert.match(add, /v2_watch_firm/);
  assert.match(add, /grant execute on function public\.v2_log_search\(text, text, integer, text, uuid\) to anon, authenticated/);
  assert.doesNotMatch(add, /cron\.schedule/);
  assert.doesNotMatch(add, /v2_research_claim/);
  assert.match(job, /ORDER BY CASE q\.priority WHEN 'top' THEN 0 ELSE 1 END, q\.firm_id/);
  assert.match(job, /FOR UPDATE OF q SKIP LOCKED/);
  assert.match(job, /interval '6 hours'/);
  assert.match(job, /cron\.schedule\('v2-search-demand', '0 \*\/6 \* \* \*'/);
  assert.match(job, /v2_search_go_live/);
  assert.match(job, /'search_live'/);
  assert.match(job, /not coalesce\(f\.demand_hidden, false\)/);
  assert.doesNotMatch(job, /pg_trgm|similarity\(/);
});

test('the notify worker sends the searched-firm email with the existing Resend path', () => {
  const src = read('supabase/functions/ondemand-notify/index.ts');
  assert.match(src, /case "search_live"/);
  assert.match(src, /api\.resend\.com\/emails/);
  assert.match(src, /Its page is ready/);
});

function element(id) {
  const el = {
    id,
    hidden: false,
    textContent: '',
    value: '',
    innerHTML: '',
    className: '',
    style: {},
    disabled: false,
    attributes: {},
    listeners: {},
    children: [],
    classList: {
      add() {},
      remove() {},
      toggle(name, on) { el.className = on ? name : ''; },
      contains() { return false; },
    },
    addEventListener(type, fn) { (el.listeners[type] ||= []).push(fn); },
    setAttribute(name, value) { el.attributes[name] = String(value); },
    getAttribute(name) { return Object.prototype.hasOwnProperty.call(el.attributes, name) ? el.attributes[name] : null; },
    appendChild(child) { el.children.push(child); return child; },
    querySelector(sel) { return sel === 'button' ? el.button || null : null; },
    querySelectorAll() { return []; },
    closest() { return null; },
    contains() { return false; },
    focus() {},
    getBoundingClientRect() { return { top: 0, right: 0, bottom: 0, left: 0, width: 0, height: 0 }; },
  };
  return el;
}

test('an unknown investors search asks for an email after a pause and logs once', async () => {
  const ids = ['firms-list', 'firms-q', 'firms-none', 'firms-sidebar', 'facet-groups', 'facet-panel', 'firms-chips', 'filters-backdrop', 'filters-open', 'filters-open-badge', 'panel-close', 'panel-clear', 'panel-apply', 'facet-search', 'pinned-options', 'remaining-label', 'full-options', 'draft-count', 'panel-title', 'panel-total', 'firms-miss', 'firms-miss-form', 'firms-miss-msg'];
  const els = Object.fromEntries(ids.map((id) => [id, element(id)]));
  els['firms-none'].textContent = 'No investors match those filters.';
  els['firms-none'].hidden = true;
  els['firms-miss'].hidden = true;
  els['firms-miss'].setAttribute('data-out', 'We don\'t have this firm yet. Leave your email and we\'ll let you know when we add it.');
  els['firms-miss'].setAttribute('data-in', 'We\'ll notify you when we find this firm.');
  els['firms-q'].setAttribute('placeholder', 'Search');
  const email = element('email');
  email.value = 'founder@startup.com';
  els['firms-miss-form'].email = email;
  els['firms-miss-form'].button = element('go');
  const page = element('page');
  page.classList.contains = (name) => name === 'firms-pg';
  const calls = [];
  const sandbox = {
    console,
    location: { pathname: '/investors/' },
    localStorage: { store: {}, getItem(k) { return this.store[k] || null; }, setItem(k, v) { this.store[k] = String(v); } },
    crypto: { randomUUID: () => '11111111-1111-4111-8111-111111111111' },
    fetch(url, opts) {
      calls.push({ url: String(url), body: opts && opts.body, keepalive: !!(opts && opts.keepalive) });
      const payload = String(url).includes('firm_directory')
        ? [{ slug: 'acme', name: 'Acme Ventures', website: 'https://acme.example', industries: [], stages: [], added: '2026-01-01' }]
        : { status: 'ok', already: false };
      return Promise.resolve({ ok: true, json: async () => payload });
    },
    document: {
      getElementById: (id) => els[id] || null,
      querySelector: (sel) => sel === '.firms-pg' ? page : null,
      querySelectorAll: () => [],
      addEventListener() {},
    },
    window: {},
    setTimeout,
    clearTimeout,
    innerWidth: 1280,
    innerHeight: 800,
    addEventListener() {},
  };
  sandbox.window.REGRET = {
    url: 'https://example.supabase.co',
    key: 'anon-key',
    copy: { js: { notify_ok: 'Got it. We\'ll email you when it\'s ready.', error: 'Something went wrong, try again.', req_bad_email: 'Please enter a valid email.', req_rate: 'Too many requests. Please try again later.', req_dup: 'You already asked for this firm. We\'ll email you when it\'s ready.' }, site: {} },
  };
  sandbox.window.RegretSearch = {};
  sandbox.window.addEventListener = () => {};
  sandbox.window.innerWidth = 1280;
  sandbox.window.window = sandbox.window;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(read('launch/js/search.js'), sandbox, { filename: 'search.js' });
  vm.runInContext(read('launch/js/firms.js'), sandbox, { filename: 'firms.js' });
  await new Promise((resolve) => setImmediate(resolve));
  await new Promise((resolve) => setImmediate(resolve));

  const input = els['firms-q'];
  input.value = 'a';
  input.listeners.input.forEach((fn) => fn());
  assert.equal(els['firms-miss'].hidden, true);

  input.value = 'Northwind';
  input.listeners.input.forEach((fn) => fn());
  assert.equal(els['firms-none'].hidden, false);
  assert.equal(els['firms-none'].textContent, 'No investors match those filters.');
  assert.equal(calls.some((c) => c.url.includes('v2_log_search')), false);

  await new Promise((resolve) => setTimeout(resolve, 1600));
  const logs = calls.filter((c) => c.url.includes('v2_log_search'));
  assert.equal(logs.length, 1);
  assert.equal(logs[0].keepalive, true);
  const body = JSON.parse(logs[0].body);
  assert.equal(body.p_term, 'Northwind');
  assert.equal(body.p_result_count, 0);
  assert.equal(body.p_page, '/investors/');
  assert.equal(els['firms-none'].textContent, 'We don\'t have this firm yet. Leave your email and we\'ll let you know when we add it.');
  assert.equal(els['firms-miss'].hidden, false);
  assert.equal(els['firms-miss-form'].hidden, false);

  input.value = 'Acme';
  input.listeners.input.forEach((fn) => fn());
  await new Promise((resolve) => setTimeout(resolve, 1600));
  assert.equal(els['firms-none'].hidden, true);
  assert.equal(calls.filter((c) => c.url.includes('v2_log_search')).length, 2);

  input.value = 'Northwind';
  input.listeners.input.forEach((fn) => fn());
  await new Promise((resolve) => setTimeout(resolve, 1600));
  assert.equal(calls.filter((c) => c.url.includes('v2_log_search')).length, 2);

  const form = els['firms-miss-form'];
  form.listeners.submit.forEach((fn) => fn({ preventDefault() {} }));
  await new Promise((resolve) => setImmediate(resolve));
  await new Promise((resolve) => setImmediate(resolve));
  const watch = calls.find((c) => c.url.includes('v2_watch_firm'));
  assert.ok(watch);
  assert.equal(JSON.parse(watch.body).p_email, 'founder@startup.com');
  assert.equal(els['firms-miss-msg'].textContent, 'Got it. We\'ll email you when it\'s ready.');
});
