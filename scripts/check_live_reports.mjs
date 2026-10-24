/* After deploy, the live launch site (launch/ → site-launch/) must work: home + search, firm pages locked
   (blur A) for a fresh visitor, sitemap.xml, and the signed-out account prompt. */
import { chromium } from 'playwright';

const BASE = (process.env.REGRET_BASE || 'https://regretamin.com/').replace(/\/?$/, '/');
const FIRMS = (process.env.REGRET_FIRMS || 'a16z,accel').split(',');
const problems = [];
const fail = (m) => { problems.push(m); console.log('FAIL ' + m); };
const ok = (m) => console.log('ok   ' + m);

async function retry(fn, tries = 4) { // Pages can take a minute to serve the new build
  for (let i = 1; ; i++) { try { return await fn(); } catch (e) { if (i >= tries) throw e; await new Promise(r => setTimeout(r, 15000)); } }
}

const browser = await chromium.launch();
const page = await browser.newPage();
try {
  // Home
  await retry(async () => {
    const r = await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 45000 });
    if (!r || r.status() !== 200) throw new Error('home status ' + (r && r.status()));
  });
  if (await page.locator('form[data-search] input').count()) ok('home: search box'); else fail('home: no search box');
  try { await page.waitForFunction(() => /\d/.test((document.querySelector('#left') || {}).textContent || ''), null, { timeout: 20000 }); ok('home: check counter "' + (await page.textContent('#left')).trim() + '"'); }
  catch (_) { fail('home: check counter never loaded'); }

  // A fresh visitor sees every firm locked (blur A): a blurred placeholder of the 10-check table, a "Check with 1 credit" card,
  // and a firm_page() response that carries the check names only (no states, counts, dates, items, sections or outline).
  const REAL = ['state', 'count', 'searched_at', 'items', 'itemized'];
  async function lockedPage(slug, url, view) {
    let body = null;
    const on = async (res) => { if (/\/rpc\/firm_page/.test(res.url())) { try { body = await res.json(); } catch (_) {} } };
    page.on('response', on);
    try {
      const r = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
      if (!r || r.status() !== 200) return fail(slug + ' ' + view + ': status ' + (r && r.status()));
      try { await page.waitForFunction(() => document.querySelectorAll('.gate .gveil tr.crow').length === 10, null, { timeout: 30000 }); }
      catch (_) { return fail(slug + ' ' + view + ': locked placeholder (10 rows) never rendered'); }
      const g = await page.evaluate(() => { const v = document.querySelector('.gate .gveil'), c = document.querySelector('.gate .gcard');
        return { blur: getComputedStyle(v).filter, card: !!c && c.offsetHeight > 0, btn: !!(c && c.querySelector('[data-gate]')), real: document.querySelectorAll('.gveil .pill:not(.gp), .gveil .cti, .gveil .cdx').length,
          full: !!document.querySelector('.rgt-tabs a[href$="full/"]') }; });
      if (!/blur\(10px\)/.test(g.blur)) fail(slug + ' ' + view + ': placeholder not blurred (' + g.blur + ')');
      if (!g.card || !g.btn) fail(slug + ' ' + view + ': no "Check with 1 credit" card');
      if (g.real) fail(slug + ' ' + view + ': placeholder contains result elements');
      if (!g.full) fail(slug + ' ' + view + ': no tab switch');
      await page.waitForTimeout(500);
      if (!body) fail(slug + ' ' + view + ': firm_page response not seen');
      else {
        const leak = (body.checks || []).flatMap(c => REAL.filter(k => c[k] != null).map(k => c.n + '.' + k));
        if (body.open) fail(slug + ' ' + view + ': a fresh visitor got an open page');
        if (leak.length || (body.sections || []).length || body.outline != null || body.details != null) fail(slug + ' ' + view + ': locked response leaks ' + (leak.slice(0, 5).join(',') || 'sections/outline/details'));
        else ok(slug + ' ' + view + ': locked, blurred placeholder + card, response has check names only');
      }
    } finally { page.off('response', on); }
  }
  for (const slug of FIRMS) await lockedPage(slug, BASE + 'vc/' + slug + '/', 'summary');

  // How we check
  { const r = await page.goto(BASE + 'how-we-check/', { waitUntil: 'domcontentloaded', timeout: 45000 });
    if (!r || r.status() !== 200) fail('how-we-check: status ' + (r && r.status()));
    else if (!(await page.locator('nav a.on[href$="how-we-check/"]').count())) fail('how-we-check: nav link not active'); else ok('how-we-check: page and active nav link'); }

  // Full pages: same locked state, firm name and SEC hero facts stay public
  for (const slug of FIRMS) {
    await lockedPage(slug, BASE + 'vc/' + slug + '/full/', 'full');
    if (/Toxy/.test(await page.content())) fail(slug + ': Toxy is still in the page');
    const h1 = ((await page.textContent('h1').catch(() => '')) || '').trim(); if (!h1) fail(slug + ': no firm name');
  }

  // Sitemap
  // regretamin.com (GitHub Pages) serves one <urlset>; Cloudflare serves a <sitemapindex>
  // whose child locs use the canonical host, so fetch each child from BASE.
  const sm = await page.request.get(BASE + 'sitemap.xml');
  let xml = sm.ok() ? await sm.text() : '';
  let kind = 'urlset';
  if (/<sitemapindex/.test(xml)) {
    kind = 'index';
    const kids = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map(m => new URL(m[1]).pathname.replace(/^\//, ''));
    let all = '';
    for (const k of kids) {
      const r = await page.request.get(BASE + k); const t = r.ok() ? await r.text() : '';
      if (!/<urlset/.test(t)) fail('sitemap child ' + k + ' missing or invalid (' + r.status() + ')'); else all += t;
    }
    xml = kids.length ? all : '';
  }
  if (!/<urlset/.test(xml)) fail('sitemap.xml missing or invalid (' + sm.status() + ')');
  else { const miss = FIRMS.filter(s => !xml.includes('/vc/' + s + '/')); miss.length ? fail('sitemap.xml lacks ' + miss.join(',')) : ok('sitemap.xml (' + kind + '): ' + (xml.match(/<loc>/g) || []).length + ' urls'); }
  if (/\/full\/<\/loc>/.test(xml)) fail('sitemap lists /full/ pages (they are noindex)'); else ok('sitemap: no /full/ pages');

  // SEO head: summary indexable + self canonical; /full/ noindex, follow + self canonical; paywall JSON-LD on both
  for (const slug of FIRMS) for (const full of [false, true]) {
    const path = 'vc/' + slug + '/' + (full ? 'full/' : ''), r = await page.request.get(BASE + path), h = r.ok() ? await r.text() : '';
    const robots = (h.match(/<meta name="robots" content="([^"]*)"/) || [])[1] || '';
    const canon = (h.match(/<link rel="canonical" href="([^"]*)"/) || [])[1] || '';
    const ld = [...h.matchAll(/<script type="application\/ld\+json">([^<]*)<\/script>/g)].map(m => { try { return JSON.parse(m[1]); } catch (_) { return {}; } }).find(o => o['@type'] === 'WebPage') || {};
    const errs = [];
    if (full ? robots !== 'noindex, follow' : /noindex/.test(robots)) errs.push('robots=' + (robots || 'none'));
    if (canon !== 'https://regretamin.com/' + path) errs.push('canonical=' + canon);
    if (ld.isAccessibleForFree !== false || !ld.hasPart || ld.hasPart.isAccessibleForFree !== false || ld.hasPart.cssSelector !== '.gveil') errs.push('JSON-LD paywall markup missing');
    errs.length ? fail(path + ': ' + errs.join('; ')) : ok(path + ': ' + (full ? 'noindex, follow' : 'indexable') + ', self canonical, paywall JSON-LD');
  }

  // Signed-out account prompt
  await page.goto(BASE + 'account/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  try { await page.waitForSelector('[data-out]:not([hidden]) [data-open="signup"]', { timeout: 20000 }); ok('account: sign-in prompt shown when signed out'); }
  catch (_) { fail('account: no sign-in prompt when signed out'); }
} finally { await browser.close(); }

if (problems.length) { console.error(problems.length + ' problem(s)'); process.exit(1); }
console.log('all live checks passed');
