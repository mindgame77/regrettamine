// Edge rendering for firm pages (Cloudflare Pages Functions). Mirrors launch/build.py firm_desc/firm_head/fill:
// keep the two identical (tests/test_dynamic_pages.py renders both and compares byte for byte).
export const SITE = 'https://regretamin.com/';
export const SUFFIX = ' · Regretamin';
export const BRAND = 'Regretamin';
export const SITEMAP_SIZE = 10000; // firms per sitemap file (2 URLs each => 20,000 URLs, under the 50,000 limit)
const SLUG_RE = /^[a-z0-9][a-z0-9-]{0,99}$/;

// Same as Python html.escape(s, quote=True)
export const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#x27;');

export function firmDesc(F) {
  const bits = [F.firm_type, F.hq].filter(Boolean).map(esc).join(', ');
  return `Background check on ${esc(F.name)}` + (bits ? ` (${bits})` : '') + ': SEC filings, legal matters, team changes and 10 checks before you take the meeting or the money.';
}

// Python json.dumps(ensure_ascii=False, separators=(',', ':')) == JSON.stringify for these plain string objects
export function firmHead(F, full = false) {
  const url = `${SITE}vc/${F.slug}/` + (full ? 'full/' : '');
  const title = esc(F.name + SUFFIX);
  const d = firmDesc(F);
  const org = { '@type': 'Organization', name: F.name };
  if (F.legal_name) org.legalName = F.legal_name;
  if (F.primary_domain) org.url = 'https://' + F.primary_domain;
  if (F.hq) org.address = F.hq;
  if (F.founded_year) org.foundingDate = String(F.founded_year);
  const ld = { '@context': 'https://schema.org', '@type': 'WebPage', name: F.name + SUFFIX, url, about: org };
  const ldj = JSON.stringify(ld).replace(/</g, '\\u003c').replace(/>/g, '\\u003e').replace(/&/g, '\\u0026');
  return `<meta name="description" content="${d}"><link rel="canonical" href="${url}">` +
    `<meta property="og:type" content="website"><meta property="og:site_name" content="${BRAND}"><meta property="og:title" content="${title}">` +
    `<meta property="og:description" content="${d}"><meta property="og:url" content="${url}"><meta name="twitter:card" content="summary">` +
    `<script type="application/ld+json">${ldj}</script>`;
}

export const fillFirm = (tpl, F, full = false) =>
  tpl.split('{{HEAD}}').join(firmHead(F, full)).split('{{NAME}}').join(esc(F.name)).split('{{SLUG}}').join(esc(F.slug));

// /vc/<slug>/ or /vc/<slug>/full/ -> {slug, full} | {redirect} | null
export function parseFirmPath(pathname) {
  const m = pathname.match(/^\/vc\/([^/]+)(\/full)?(\/?)$/);
  if (!m) return null;
  const slug = decodeURIComponent(m[1]);
  if (!SLUG_RE.test(slug.toLowerCase())) return null;
  const want = `/vc/${slug.toLowerCase()}/` + (m[2] ? 'full/' : '');
  if (want !== pathname) return { redirect: want };
  return { slug, full: !!m[2] };
}

async function rpc(env, fetchImpl, fn, args) {
  const r = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${env.SUPABASE_ANON_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify(args),
  });
  if (!r.ok) throw new Error(`rpc ${fn} ${r.status}`);
  return r.json();
}

const HTML = 'text/html; charset=utf-8';
const cacheHdr = (s) => `public, max-age=0, s-maxage=${s}, stale-while-revalidate=86400`;

export async function renderFirm({ request, env, assets, fetchImpl = fetch }) {
  const url = new URL(request.url);
  const p = parseFirmPath(url.pathname);
  const asset = async (path) => (await assets.fetch(new URL(path, url.origin))).text();
  const notFound = async () => new Response(await asset('/_tpl/404'), { status: 404, headers: { 'content-type': HTML, 'cache-control': cacheHdr(300) } });
  if (!p) return notFound();
  if (p.redirect) return Response.redirect(new URL(p.redirect + url.search, url.origin).toString(), 301);
  let rows;
  try { rows = await rpc(env, fetchImpl, 'firm_meta', { p_slug: p.slug }); }
  catch (e) { return new Response('Temporary error, please retry.', { status: 503, headers: { 'cache-control': 'no-store', 'retry-after': '30' } }); }
  const F = Array.isArray(rows) ? rows[0] : null;
  if (!F) return notFound();
  const tpl = await asset(p.full ? '/_tpl/full' : '/_tpl/summary');
  const headers = { 'content-type': HTML, 'cache-control': cacheHdr(3600) };
  if (env.NOINDEX === '1') headers['x-robots-tag'] = 'noindex';
  return new Response(fillFirm(tpl, F, p.full), { status: 200, headers });
}

const STATIC = ['', 'how-we-check/', 'privacy/', 'terms/'];
const XML = 'application/xml; charset=utf-8';
const xmlEsc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export async function sitemapIndex({ env, fetchImpl = fetch }) {
  const rows = await rpc(env, fetchImpl, 'firm_sitemap', { p_page: 1, p_size: 1 });
  const total = rows.length ? Number(rows[0].total) : 0;
  const n = Math.max(1, Math.ceil(total / SITEMAP_SIZE));
  const locs = ['sitemaps/static.xml', ...Array.from({ length: n }, (_, i) => `sitemaps/firms-${i + 1}.xml`)];
  const body = '<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    locs.map((l) => `<sitemap><loc>${SITE}${l}</loc></sitemap>\n`).join('') + '</sitemapindex>\n';
  return new Response(body, { headers: { 'content-type': XML, 'cache-control': cacheHdr(3600) } });
}

export async function sitemapPart({ name, env, fetchImpl = fetch }) {
  let urls;
  if (name === 'static.xml') urls = STATIC.map((p) => ({ loc: SITE + p }));
  else {
    const m = /^firms-([1-9][0-9]{0,4})\.xml$/.exec(name);
    if (!m) return new Response('Not found', { status: 404 });
    const rows = await rpc(env, fetchImpl, 'firm_sitemap', { p_page: Number(m[1]), p_size: SITEMAP_SIZE });
    if (!rows.length) return new Response('Not found', { status: 404 });
    urls = rows.flatMap((r) => {
      const lm = r.updated_at ? String(r.updated_at).slice(0, 10) : null;
      return ['', 'full/'].map((x) => ({ loc: `${SITE}vc/${r.slug}/${x}`, lastmod: lm }));
    });
  }
  const body = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    urls.map((u) => `<url><loc>${xmlEsc(u.loc)}</loc>${u.lastmod ? `<lastmod>${u.lastmod}</lastmod>` : ''}</url>\n`).join('') + '</urlset>\n';
  return new Response(body, { headers: { 'content-type': XML, 'cache-control': cacheHdr(3600) } });
}
