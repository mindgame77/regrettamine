// node --test launch/edge/firm.test.mjs   (needs python3 launch/build.py first)
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { renderFirm, sitemapIndex, sitemapPart, parseFirmPath, fillFirm } from './firm.mjs';

const OUT = new URL('../../site-launch/', import.meta.url);
const DATA = new URL('../../data/launch/', import.meta.url);
const read = (p) => readFileSync(new URL(p, OUT), 'utf8');
const assets = { fetch: async (u) => new Response(read(`.${new URL(u).pathname}.html`)) };
const env = { SUPABASE_URL: 'https://db.test', SUPABASE_ANON_KEY: 'anon' };
const FIRMS = { sequoia: { slug: 'sequoia', name: 'Sequoia Capital', hq: 'Menlo Park, CA', firm_type: 'VC', updated_at: '2026-10-20T00:00:00Z' },
  evil: { slug: 'evil', name: 'A&B <script>"x"</script> \'Co\'', hq: null, firm_type: null } };
const db = (calls = []) => async (url, init) => {
  const fn = url.split('/rpc/')[1]; const a = JSON.parse(init.body); calls.push(fn);
  assert.equal(init.headers.apikey, 'anon');
  if (fn === 'firm_meta') return Response.json(FIRMS[a.p_slug] ? [FIRMS[a.p_slug]] : []);
  if (fn === 'firm_sitemap') {
    const all = Array.from({ length: 12345 }, (_, i) => ({ slug: `f${i}`, updated_at: '2026-10-01T00:00:00Z', total: 12345 }));
    return Response.json(all.slice((a.p_page - 1) * a.p_size, a.p_page * a.p_size));
  }
  return new Response('x', { status: 404 });
};
const get = (path, fetchImpl = db()) => renderFirm({ request: new Request('https://regretamin.com' + path), env, assets, fetchImpl });

test('static pages from build.py == edge rendering of the same firm (all 30)', () => {
  const tpl = { s: read('_tpl/summary.html'), f: read('_tpl/full.html') };
  for (const f of readdirSync(DATA).filter((x) => x.endsWith('.json'))) {
    const F = JSON.parse(readFileSync(new URL(f, DATA), 'utf8')).firm;
    assert.equal(fillFirm(tpl.s, F), read(`vc/${F.slug}/index.html`), F.slug);
    assert.equal(fillFirm(tpl.f, F, true), read(`vc/${F.slug}/full/index.html`), F.slug);
  }
});

test('published firm not in launch set gets a 200 page with SEO tags', async () => {
  for (const [path, canon] of [['/vc/sequoia/', 'https://regretamin.com/vc/sequoia/'], ['/vc/sequoia/full/', 'https://regretamin.com/vc/sequoia/full/']]) {
    const r = await get(path); const h = await r.text();
    assert.equal(r.status, 200);
    assert.match(r.headers.get('cache-control'), /s-maxage=3600/);
    assert.ok(h.includes('<title>Sequoia Capital · Regretamin</title>'));
    assert.ok(h.includes(`<link rel="canonical" href="${canon}">`));
    assert.ok(h.includes('og:description') && h.includes('application/ld+json') && h.includes('<h1>Sequoia Capital'));
    assert.ok(h.includes('data-firm="sequoia"') && !h.includes('{{'));
  }
});

test('unknown, bad and template slugs are real 404s', async () => {
  for (const p of ['/vc/not-a-firm/', '/vc/not-a-firm/full/', '/vc/a%20b/', '/vc/../x/', '/vc/x/y/z/']) {
    const r = await get(p); assert.equal(r.status, 404, p); assert.match(await r.text(), /noindex/);
  }
});

test('normalises: missing slash / uppercase -> 301', async () => {
  for (const [p, to] of [['/vc/sequoia', '/vc/sequoia/'], ['/vc/Sequoia/full', '/vc/sequoia/full/']]) {
    const r = await get(p); assert.equal(r.status, 301); assert.equal(new URL(r.headers.get('location')).pathname, to);
  }
  assert.equal(parseFirmPath('/vc/'), null);
});

test('names are escaped in HTML and JSON-LD', async () => {
  const h = await (await get('/vc/evil/')).text();
  assert.ok(!h.includes('<script>"x"'));
  assert.ok(h.includes('A&amp;B &lt;script&gt;'));
  assert.ok(h.includes('\\u003cscript\\u003e'));
});

test('DB down -> 503, not cached as a 404', async () => {
  const r = await get('/vc/sequoia/', async () => new Response('down', { status: 500 }));
  assert.equal(r.status, 503); assert.equal(r.headers.get('cache-control'), 'no-store');
});

test('split sitemaps', async () => {
  const idx = await (await sitemapIndex({ env, fetchImpl: db() })).text();
  assert.equal((idx.match(/<sitemap>/g) || []).length, 3); // static + 2 firm files for 12,345 firms
  assert.ok(idx.includes('https://regretamin.com/sitemaps/firms-2.xml'));
  const p1 = await (await sitemapPart({ name: 'firms-1.xml', env, fetchImpl: db() })).text();
  assert.equal((p1.match(/<url>/g) || []).length, 20000);
  const p2 = await (await sitemapPart({ name: 'firms-2.xml', env, fetchImpl: db() })).text();
  assert.equal((p2.match(/<url>/g) || []).length, 4690);
  assert.ok(p2.includes('<lastmod>2026-10-01</lastmod>'));
  assert.equal((await sitemapPart({ name: 'firms-3.xml', env, fetchImpl: db() })).status, 404);
  assert.equal((await sitemapPart({ name: 'x.xml', env, fetchImpl: db() })).status, 404);
  assert.match(await (await sitemapPart({ name: 'static.xml', env, fetchImpl: db() })).text(), /how-we-check/);
});
