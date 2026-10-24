// Edge rendering for firm pages (Cloudflare Pages Functions). Mirrors launch/build.py firm_desc/firm_head/fill:
// keep the two identical (tests/test_dynamic_pages.py renders both and compares byte for byte).
export const SITE = 'https://regretamin.com/';
export const SUFFIX = ' · Regretamin';
export const BRAND = 'Regretamin';
export const SITEMAP_SIZE = 10000; // firms per sitemap file (1 URL each; /full/ is noindex and not listed)
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
  // Paywalled-content markup: the check table (.gveil, blurred until 1 credit is spent) is not free.
  const ld = { '@context': 'https://schema.org', '@type': 'WebPage', name: F.name + SUFFIX, url, about: org,
    isAccessibleForFree: false, hasPart: { '@type': 'WebPageElement', isAccessibleForFree: false, cssSelector: '.gveil' } };
  const ldj = JSON.stringify(ld).replace(/</g, '\\u003c').replace(/>/g, '\\u003e').replace(/&/g, '\\u0026');
  // /full/ is noindex, follow (Alex, Oct 23) with a self canonical; it is also left out of the sitemaps.
  // 'Not checked yet' pages (firm_meta.indexable false: no research yet) are noindex, follow too, and not in the sitemaps.
  return (full || F.indexable === false ? '<meta name="robots" content="noindex, follow">' : '') + `<meta name="description" content="${d}"><link rel="canonical" href="${url}">` +
    `<meta property="og:type" content="website"><meta property="og:site_name" content="${BRAND}"><meta property="og:title" content="${title}">` +
    `<meta property="og:description" content="${d}"><meta property="og:url" content="${url}"><meta name="twitter:card" content="summary">` +
    `<script type="application/ld+json">${ldj}</script>`;
}

// Official SEC names arrive in ALL CAPS; /full/ shows them in normal (title) case, display only. Keep identical to sec_title() in launch/build.py.
const SEC_KEEP = {'LLC': 'LLC', 'L.L.C.': 'L.L.C.', 'L.L.C': 'L.L.C', 'LP': 'LP', 'L.P.': 'L.P.', 'L.P': 'L.P', 'LLP': 'LLP', 'L.L.P.': 'L.L.P.',
  'INC': 'Inc', 'INC.': 'Inc.', 'LTD': 'Ltd', 'LTD.': 'Ltd.', 'CO': 'Co', 'CO.': 'Co.', 'CORP': 'Corp', 'CORP.': 'Corp.',
  'PLC': 'PLC', 'GP': 'GP', 'SA': 'SA', 'S.A.': 'S.A.', 'AG': 'AG', 'GMBH': 'GmbH', 'SARL': 'SARL', 'S.A.R.L.': 'S.à r.l.',
  'BV': 'BV', 'B.V.': 'B.V.', 'NV': 'NV', 'AB': 'AB', 'AS': 'AS', 'SPA': 'SpA', 'PTE': 'Pte', 'PTY': 'Pty', 'LLLP': 'LLLP',
  'A16Z': 'a16z', 'US': 'US', 'USA': 'USA', 'UK': 'UK', 'VC': 'VC', 'AI': 'AI', 'II': 'II', 'III': 'III', 'IV': 'IV', 'VI': 'VI',
  'VII': 'VII', 'VIII': 'VIII', 'IX': 'IX', 'XI': 'XI', 'XII': 'XII', 'NEA': 'NEA', 'IVP': 'IVP', 'KKR': 'KKR', 'TPG': 'TPG',
  'GGV': 'GGV', 'USV': 'USV', 'TCV': 'TCV', 'IDG': 'IDG', 'NFX': 'NFX', 'DST': 'DST', 'EQT': 'EQT', 'QED': 'QED', 'SOSV': 'SOSV',
  'HV': 'HV', 'GV': 'GV', 'DCM': 'DCM', 'JMI': 'JMI', 'TA': 'TA', 'RRE': 'RRE', 'FPV': 'FPV', 'AVF': 'AVF', 'ESP': 'ESP', 'HIG': 'HIG',
  'H.I.G.': 'H.I.G.', 'UBS': 'UBS', 'LGT': 'LGT', 'GCM': 'GCM', 'HGGC': 'HGGC', 'BVP': 'BVP',
  'SEC': 'SEC', 'FEC': 'FEC', 'PAC': 'PAC', 'CRD': 'CRD', 'LEI': 'LEI', 'FINRA': 'FINRA', 'OFAC': 'OFAC', 'FCA': 'FCA', 'EU': 'EU', 'UN': 'UN', 'SBIC': 'SBIC', 'ERISA': 'ERISA', 'NYC': 'NYC', 'IAPD': 'IAPD', 'ADV': 'ADV', 'RIA': 'RIA', 'AUM': 'AUM', 'LDA': 'LDA', 'FTX': 'FTX', 'RD': 'Rd', 'RD.': 'Rd.', 'ST.': 'St.', 'AVE': 'Ave', 'AVE.': 'Ave.', 'STE': 'Ste', 'STE.': 'Ste.', 'BLVD': 'Blvd', 'BLVD.': 'Blvd.'};
const SEC_SMALL = new Set(['A', 'AN', 'AND', 'AT', 'DE', 'DER', 'DES', 'DU', 'ET', 'FOR', 'IN', 'LA', 'LE', 'OF', 'ON', 'THE', 'VAN', 'VON']);
const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
function secPart(w) {
  if (!/[A-Z]/.test(w)) return w;
  if (has(SEC_KEEP, w)) return SEC_KEEP[w];
  const core = w.replace(/[^A-Z]/g, '');
  if (/^[IVX]{2,5}$/.test(core)) return w;
  if (core.length <= 4 && !/[AEIOUY]/.test(core)) return w;
  const lo = w.toLowerCase(), i = lo.search(/[a-z]/);
  return lo.slice(0, i) + lo[i].toUpperCase() + lo.slice(i + 1);
}
export function secTitle(s) {
  s = s || '';
  if (!s || /[a-z]/.test(s)) return s;
  return s.split(' ').map((w, i) => {
    const bare = w.replace(/^[,;()]+|[,;()]+$/g, '');
    if (i && SEC_SMALL.has(bare)) return w.toLowerCase();
    const k = has(SEC_KEEP, bare) ? bare : bare.replace(/[.,]+$/, '');
    if (has(SEC_KEEP, k)) return w.replace(k, SEC_KEEP[k]);
    return w.replace(/[^\s\-/'’&]+/g, secPart);
  }).join(' ');
}

// /full/ shows the official SEC name; everything else the display name
export const fillFirm = (tpl, F, full = false) =>
  tpl.split('{{HEAD}}').join(firmHead(F, full)).split('{{NAME}}').join(esc(full ? secTitle(F.legal_name || F.name) : F.name)).split('{{SLUG}}').join(esc(F.slug));

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
  if (!F) {
    // merged duplicate pages: old slug 301s to the surviving page (firm_slug_redirects, docs/DEDUPE.md)
    let to = null;
    try { to = await rpc(env, fetchImpl, 'firm_redirect', { p_slug: p.slug }); } catch (e) { to = null; }
    if (typeof to === 'string' && /^[a-z0-9-]+$/.test(to) && to !== p.slug) {
      return new Response(null, { status: 301, headers: { location: new URL(`/vc/${to}/${p.full ? "full/" : ""}${url.search}`, url.origin).toString(), 'cache-control': cacheHdr(3600) } });
    }
    return notFound();
  }
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
      return [{ loc: `${SITE}vc/${r.slug}/`, lastmod: lm }]; // /full/ is noindex: not listed
    });
  }
  const body = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    urls.map((u) => `<url><loc>${xmlEsc(u.loc)}</loc>${u.lastmod ? `<lastmod>${u.lastmod}</lastmod>` : ''}</url>\n`).join('') + '</urlset>\n';
  return new Response(body, { headers: { 'content-type': XML, 'cache-control': cacheHdr(3600) } });
}
