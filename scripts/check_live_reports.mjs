/* After deploy, the live launch site (launch/ → site-launch/) must work: home + search, firm pages,
   sitemap.xml, and the signed-out account prompt.
   firm_page.open is the live reading of app_settings.lock_enabled. open true means the switch is
   off and the page must be unlocked. open false means the switch is on and today's lock must be back. */
import { chromium } from 'playwright';

const BASE = (process.env.REGRET_BASE || 'https://regretamin.com/').replace(/\/?$/, '/');
const FIRMS = (process.env.REGRET_FIRMS || 'a16z,y-combinator,sequoia,lightspeed,generalcatalyst,plugandplay,accel,greenoaks,khosla-ventures,mio-partners').split(',');
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

  // firm_page.open follows app_settings.lock_enabled. Assert the matching view.
  const REAL = ['state', 'count', 'searched_at', 'items', 'itemized'];
  async function checkFirm(slug, url, view) {
    let body = null;
    const on = async (res) => { if (/\/rpc\/firm_page/.test(res.url())) { try { body = await res.json(); } catch (_) {} } };
    page.on('response', on);
    try {
      const r = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
      if (!r || r.status() !== 200) return fail(slug + ' ' + view + ': status ' + (r && r.status()));
      try {
        await page.waitForFunction(() => {
          const main = document.querySelector('main');
          if (!main || main.classList.contains('ld')) return false;
          return main.classList.contains('unlocked') || document.querySelectorAll('.gate .gveil tr.crow').length === 10;
        }, null, { timeout: 30000 });
      } catch (_) { return fail(slug + ' ' + view + ': page never finished rendering'); }
      await page.waitForTimeout(500);
      if (!body) return fail(slug + ' ' + view + ': firm_page response not seen');
      const g = await page.evaluate(() => {
        const root = document.querySelector('#panel-checks:not([hidden])') || document.querySelector('#panel-full:not([hidden])') || document;
        const main = document.querySelector('main');
        const lock = document.getElementById('lockcard');
        const veil = root.querySelector('.gate .gveil');
        const card = root.querySelector('.gate .gcard');
        return {
          unlocked: !!(main && main.classList.contains('unlocked')),
          rows: root.querySelectorAll('.gate .gveil tr.crow').length,
          blur: veil ? getComputedStyle(veil).filter : '',
          card: !!card && card.offsetHeight > 0,
          btn: !!(card && card.querySelector('[data-gate]')),
          real: root.querySelectorAll('.gveil .pill:not(.gp), .gveil .cti, .gveil .cdx').length,
          lockHidden: !!(lock && lock.hidden) && lock.offsetHeight === 0,
          full: !!document.querySelector('.rgt-tabs [data-tab="full"], .rgt-tabs a[href$="full/"]'),
        };
      });
      if (!g.full) return fail(slug + ' ' + view + ': no tab switch');
      if (body.open) {
        const errs = [];
        if (!g.unlocked || !g.lockHidden) errs.push('lock panel still showing');
        if (/blur\(10px\)/.test(g.blur) || g.rows) errs.push('page is blurred');
        if (body.details == null) errs.push('details missing');
        if (!(body.checks || []).length || (body.checks || []).some(c => c.state == null)) errs.push('checks missing their results');
        if (view === 'full' && !(body.sections || []).length) errs.push('no sections');
        return errs.length ? fail(slug + ' ' + view + ': lock is off but ' + errs.join('; ')) : ok(slug + ' ' + view + ': lock off, unlocked, no blur, no lock panel');
      }
      const errs = [];
      if (g.unlocked) errs.push('a fresh visitor got an open page');
      if (g.rows !== 10) errs.push('locked placeholder (10 rows) never rendered');
      if (!/blur\(10px\)/.test(g.blur)) errs.push('placeholder not blurred (' + g.blur + ')');
      if (!g.card || !g.btn) errs.push('no "Check with 1 credit" card');
      if (g.real) errs.push('placeholder contains result elements');
      const leak = (body.checks || []).flatMap(c => REAL.filter(k => c[k] != null).map(k => c.n + '.' + k));
      if (leak.length || (body.sections || []).length || body.outline != null || body.details != null) errs.push('locked response leaks ' + (leak.slice(0, 5).join(',') || 'sections/outline/details'));
      return errs.length ? fail(slug + ' ' + view + ': lock is on but ' + errs.join('; ')) : ok(slug + ' ' + view + ': lock on, blurred placeholder + card, response has check names only');
    } finally { page.off('response', on); }
  }
  for (const slug of FIRMS) await checkFirm(slug, BASE + 'vc/' + slug + '/', 'summary');

  // How we check
  { const r = await page.goto(BASE + 'how-we-check/', { waitUntil: 'domcontentloaded', timeout: 45000 });
    if (!r || r.status() !== 200) fail('how-we-check: status ' + (r && r.status()));
    else if (!(await page.locator('nav a.on[href$="how-we-check/"]').count())) fail('how-we-check: nav link not active'); else ok('how-we-check: page and active nav link'); }

  // Full pages follow the same switch. The firm name stays public either way.
  for (const slug of FIRMS) {
    await checkFirm(slug, BASE + 'vc/' + slug + '/full/', 'full');
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
  else {
    const miss = FIRMS.filter(s => !xml.includes('/vc/' + s + '/'));
    const knownCap = miss.filter(s => s === 'forbion');
    const rest = miss.filter(s => s !== 'forbion');
    if (knownCap.length) console.log('warn sitemap.xml lacks forbion (known 1,000-firm sitemap cap, postponed)');
    if (rest.length) fail('sitemap.xml lacks ' + rest.join(','));
    else ok('sitemap.xml (' + kind + '): ' + (xml.match(/<loc>/g) || []).length + ' urls');
  }
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
