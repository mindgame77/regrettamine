import { renderFirm } from '../../edge/firm.mjs';
// Every /vc/<slug>/ and /vc/<slug>/full/: one template, meta from the firm_meta RPC, cached at the edge.
export async function onRequestGet(ctx) {
  const cache = caches.default;
  const hit = await cache.match(ctx.request);
  if (hit) return hit;
  const res = await renderFirm({ request: ctx.request, env: ctx.env, assets: ctx.env.ASSETS });
  if (res.status === 200 || res.status === 404) ctx.waitUntil(cache.put(ctx.request, res.clone()));
  return res;
}
