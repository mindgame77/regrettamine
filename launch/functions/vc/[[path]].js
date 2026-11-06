import { renderFirm } from '../../edge/firm.mjs';
// Every /vc/<slug>/ and /vc/<slug>/full/: one template, meta from the firm_meta RPC.
// The worker remembers a rendered page under the build's template version. The copy and
// the company.js hash live in that HTML. The response the CDN sees must not be stored:
// s-maxage kept the previous deploy's page (old company.js?v= and no new section) after
// the new files were already published. A missing version is not cached, so it cannot
// pin every later deploy to one shared key.
export function clientPage(res) {
  if (!res || res.status !== 200) return res;
  const headers = new Headers(res.headers);
  headers.set('cache-control', 'public, max-age=0, must-revalidate');
  headers.set('cdn-cache-control', 'no-store');
  return new Response(res.body, { status: res.status, headers });
}
export async function onRequestGet(ctx) {
  const cache = caches.default;
  const vr = await ctx.env.ASSETS.fetch(new URL('/_tpl/version.txt', ctx.request.url));
  const v = vr.ok ? (await vr.text()).trim() : '';
  const render = () => renderFirm({ request: ctx.request, env: ctx.env, assets: ctx.env.ASSETS });
  if (!v) return clientPage(await render());
  const u = new URL(ctx.request.url);
  u.searchParams.set('__tplv', v);
  const key = new Request(u.toString(), { method: 'GET' });
  const hit = await cache.match(key);
  if (hit) return clientPage(hit);
  const res = await render();
  if (res.status === 200 || res.status === 404) {
    const stored = res.clone();
    const headers = new Headers(stored.headers);
    headers.set('cache-control', 'public, max-age=3600');
    ctx.waitUntil(cache.put(key, new Response(stored.body, { status: stored.status, headers })));
  }
  return clientPage(res);
}
