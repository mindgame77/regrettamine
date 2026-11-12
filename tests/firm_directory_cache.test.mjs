// Investors directory: read the cache first, then firm_directory, then firms.json.
// node --test tests/firm_directory_cache.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const src = fs.readFileSync(new URL('../launch/js/firms.js', import.meta.url), 'utf8');

function el() {
  return {
    innerHTML: '',
    hidden: true,
    style: {},
    value: '',
    classList: { add() {}, remove() {}, contains() { return false; } },
    attrs: {},
    getAttribute(name) { return this.attrs[name] || ''; },
    setAttribute(name, value) { this.attrs[name] = String(value); },
    addEventListener() {},
    querySelector() { return null; },
    closest() { return null; },
    contains() { return false; },
  };
}

function boot(fetchImpl, regret) {
  const els = {};
  const sandbox = {
    console,
    addEventListener() {},
    innerWidth: 1280,
    document: {
      addEventListener() {},
      querySelector() { return null; },
      getElementById(id) {
        if (!els[id]) els[id] = el();
        return els[id];
      },
    },
    fetch: fetchImpl,
    window: { REGRET: regret, REGRET_ROOT: '/', addEventListener() {}, innerWidth: 1280 },
  };
  sandbox.window.window = sandbox.window;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(src, sandbox, { filename: 'firms.js' });
  return els;
}

function jsonResponse(status, body) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json() { return Promise.resolve(body); },
  };
}

async function flush() {
  for (let i = 0; i < 8; i++) await new Promise((resolve) => setTimeout(resolve, 0));
}

test('a cached payload is the firm list', async () => {
  const calls = [];
  const els = boot((url) => {
    calls.push(String(url));
    return Promise.resolve(jsonResponse(200, {
      payload: [{ slug: 'a16z', name: 'Andreessen Horowitz', added: '2024-01-02' }],
      built_at: '2026-11-12T18:00:00Z',
    }));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  assert.deepEqual(calls, ['https://db.test/rest/v1/rpc/firm_directory_cached']);
  assert.match(els['firms-list'].innerHTML, /Andreessen Horowitz/);
});

test('null cache and a failed cache both fall back to firm_directory', async () => {
  for (const cached of [null, { payload: null, built_at: '2026-11-12T18:00:00Z' }]) {
    const calls = [];
    const els = boot((url) => {
      calls.push(String(url));
      if (String(url).endsWith('/firm_directory_cached')) return Promise.resolve(jsonResponse(200, cached));
      return Promise.resolve(jsonResponse(200, [{ slug: 'yc', name: 'Y Combinator', added: '2024-02-02' }]));
    }, { url: 'https://db.test', key: 'anon-key', copy: {} });
    await flush();
    assert.deepEqual(calls, [
      'https://db.test/rest/v1/rpc/firm_directory_cached',
      'https://db.test/rest/v1/rpc/firm_directory',
    ]);
    assert.match(els['firms-list'].innerHTML, /Y Combinator/);
  }

  const calls = [];
  const els = boot((url) => {
    calls.push(String(url));
    if (String(url).endsWith('/firm_directory_cached')) return Promise.resolve(jsonResponse(500, { message: 'timeout' }));
    return Promise.resolve(jsonResponse(200, [{ slug: 'sequoia', name: 'Sequoia', added: '2024-03-03' }]));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  assert.deepEqual(calls, [
    'https://db.test/rest/v1/rpc/firm_directory_cached',
    'https://db.test/rest/v1/rpc/firm_directory',
  ]);
  assert.match(els['firms-list'].innerHTML, /Sequoia/);
});

test('an empty cached list is shown and does not call firm_directory', async () => {
  const calls = [];
  const els = boot((url) => {
    calls.push(String(url));
    return Promise.resolve(jsonResponse(200, { payload: [], built_at: '2026-11-12T18:00:00Z' }));
  }, { url: 'https://db.test', key: 'anon-key', copy: {} });
  await flush();
  assert.deepEqual(calls, ['https://db.test/rest/v1/rpc/firm_directory_cached']);
  assert.equal(els['firms-none'].hidden, false);
});

test('no Supabase config still reads firms.json', async () => {
  const calls = [];
  boot((url) => {
    calls.push(String(url));
    return Promise.resolve(jsonResponse(200, { firms: [] }));
  }, { copy: {} });
  await flush();
  assert.deepEqual(calls, ['/firms.json']);
});
