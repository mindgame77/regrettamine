import { renderFirm } from '../../edge/firm.mjs';
// Every /vc/<slug>/ and /vc/<slug>/full/: one template, meta from the firm_meta RPC, cached at the edge.
export async function onRequestGet(ctx) {
  const cache = caches.default;
  // Key includes the build's template version so a new deploy never serves pages rendered by the old one.
  const vr = await ctx.env.ASSETS.fetch(new URL('/_tpl/version.txt', ctx.request.url));
  const v = vr.ok ? (await vr.text()).trim() : '0';
  const u = new URL(ctx.request.url); u.searchParams.set('__tplv', v);
  const key = new Request(u.toString(), { method: 'GET' });
  const hit = await cache.match(key);
  if (hit) return hit;
  const res = await renderFirm({ request: ctx.request, env: ctx.env, assets: ctx.env.ASSETS });
  if (res.status === 200 || res.status === 404) ctx.waitUntil(cache.put(key, res.clone()));
  return res;
}
