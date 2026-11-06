// A new deploy must not keep serving the previous firm page.
// The worker may remember a render under the template version. The CDN must not.
// node --test tests/firm_page_cache.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';

const fnUrl = new URL('../launch/functions/vc/[[path]].js', import.meta.url);
const { onRequestGet, clientPage } = await import(fnUrl.href);

function memoryCache() {
  const box = new Map();
  return {
    box,
    async match(req) {
      const hit = box.get(req.url);
      return hit ? hit.clone() : undefined;
    },
    async put(req, res) { box.set(req.url, res); },
  };
}
function world(pages) {
  const cache = memoryCache();
  const assets = {
    async fetch(url) {
      const path = new URL(url).pathname;
      const body = pages[path];
      if (body == null) return new Response('missing', { status: 404 });
      return new Response(body);
    },
  };
  const env = { SUPABASE_URL: 'https://db.test', SUPABASE_ANON_KEY: 'anon', ASSETS: assets };
  const waits = [];
  const ctx = {
    request: new Request('https://regretamin.com/vc/a16z/full/'),
    env,
    waitUntil(p) { waits.push(p); },
  };
  globalThis.caches = { default: cache };
  return {
    cache,
    ctx,
    flush: () => Promise.all(waits.splice(0)),
    set(path, body) { pages[path] = body; },
  };
}
const tpl = (mark) => `<!doctype html><script src="../../../company.js?v=${mark}"></script><p>${mark}</p>`;

test('a 200 page is not CDN-cached, and a new template version is not the previous page', async () => {
  const pages = {
    '/_tpl/version.txt': 'aaaa1111bbbb',
    '/_tpl/full': tpl('newhash1111'),
    '/_tpl/404': '<title>Not found</title>',
  };
  const w = world(pages);
  const fetchImpl = async (url, init) => {
    assert.equal(url, 'https://db.test/rest/v1/rpc/firm_meta');
    assert.equal(JSON.parse(init.body).p_slug, 'a16z');
    return Response.json([{ slug: 'a16z', name: 'Andreessen Horowitz', hq: 'Menlo Park, CA', firm_type: 'VC' }]);
  };
  const realFetch = globalThis.fetch;
  globalThis.fetch = fetchImpl;
  try {
    const first = await onRequestGet(w.ctx);
    await w.flush();
    const html = await first.text();
    assert.equal(first.status, 200);
    assert.match(html, /company\.js\?v=newhash1111/);
    assert.equal(first.headers.get('cache-control'), 'public, max-age=0, must-revalidate');
    assert.equal(first.headers.get('cdn-cache-control'), 'no-store');
    assert.doesNotMatch(first.headers.get('cache-control'), /s-maxage|stale-while-revalidate/);
    const stored = [...w.cache.box.keys()];
    assert.equal(stored.length, 1);
    assert.match(stored[0], /__tplv=aaaa1111bbbb/);
    assert.match(w.cache.box.get(stored[0]).headers.get('cache-control'), /max-age=3600/);

    const again = await onRequestGet(w.ctx);
    assert.match(await again.text(), /newhash1111/);
    assert.equal(again.headers.get('cdn-cache-control'), 'no-store');
    assert.doesNotMatch(again.headers.get('cache-control'), /s-maxage/);

    w.set('/_tpl/version.txt', 'cccc2222dddd');
    w.set('/_tpl/full', tpl('newhash2222'));
    const next = await onRequestGet(w.ctx);
    await w.flush();
    const nextHtml = await next.text();
    assert.match(nextHtml, /company\.js\?v=newhash2222/);
    assert.doesNotMatch(nextHtml, /newhash1111/);
    assert.equal(next.headers.get('cache-control'), 'public, max-age=0, must-revalidate');
    assert.equal(w.cache.box.size, 2);
  } finally {
    globalThis.fetch = realFetch;
  }
});

test('a missing template version is not stored under one key that later deploys would reuse', async () => {
  const pages = { '/_tpl/full': tpl('firstfile') };
  const w = world(pages);
  const realFetch = globalThis.fetch;
  globalThis.fetch = async () => Response.json([{ slug: 'a16z', name: 'Andreessen Horowitz' }]);
  try {
    const first = await onRequestGet(w.ctx);
    await w.flush();
    assert.match(await first.text(), /firstfile/);
    assert.equal(w.cache.box.size, 0);
    w.set('/_tpl/full', tpl('secondfile'));
    const second = await onRequestGet(w.ctx);
    const html = await second.text();
    assert.match(html, /secondfile/);
    assert.doesNotMatch(html, /firstfile/);
    assert.equal(second.headers.get('cdn-cache-control'), 'no-store');
  } finally {
    globalThis.fetch = realFetch;
  }
});

test('clientPage leaves a non-200 response alone', () => {
  const res = new Response('no', { status: 404, headers: { 'cache-control': 'public, max-age=0, s-maxage=300' } });
  assert.equal(clientPage(res), res);
});
