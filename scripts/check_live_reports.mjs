/* After deploy, the live launch site (launch/ → site-launch/) must work: home + search, firm pages
   unlocked while app_settings.lock_enabled is false, sitemap.xml, and the signed-out account prompt. */
import { chromium } from 'playwright';

const BASE = (process.env.REGRET_BASE || 'https://regretamin.com/').replace(/\/?$/, '/');
const FIRMS = (process.env.REGRET_FIRMS || 'a16z,accel,forbion').split(',');
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

  // Lock is off until launch. A fresh visitor gets the full firm_page payload: open, check states, sections,
  // no blur and no lock card. Turning app_settings.lock_enabled back to true restores the locked page.
  async function openPage(slug, url, view) {
    let body = null;
    const on = async (res) => { if (/\/rpc\/firm_page/.test(res.url())) { try { body = await res.json(); } catch (_) {} } };
    page.on('response', on);
    try {
      const r = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
      if (!r || r.status() !== 200) return fail(slug + ' ' + view + ': status ' + (r && r.status()));
      try { await page.waitForFunction(() => { const main = document.querySelector('main'); const lock = document.getElementById('lockcard'); return !!(main && main.classList.contains('unlocked') && !main.classList.contains('ld') && lock && lock.hidden && !document.querySelector('.gveil, .gate')); }, null, { timeout: 30000 }); }
      catch (_) { return fail(slug + ' ' + view + ': unlocked page never rendered'); }
      const g = await page.evaluate(() => { const lock = document.getElementById('lockcard'); const veil = document.querySelector('.gveil');
        return { unlocked: document.querySelector('main').classList.contains('unlocked'), lockHidden: !!(lock && lock.hidden) && lock.offsetHeight === 0, blur: veil ? getComputedStyle(veil).filter : '',
          full: !!document.querySelector('.rgt-tabs [data-tab="full"], .rgt-tabs a[href$="full/"]') }; });
      if (!g.unlocked || !g.lockHidden) fail(slug + ' ' + view + ': lock panel still showing');
      if (/blur\(10px\)/.test(g.blur)) fail(slug + ' ' + view + ': content is blurred');
      if (!g.full) fail(slug + ' ' + view + ': no tab switch');
      await page.waitForTimeout(500);
      if (!body) fail(slug + ' ' + view + ': firm_page response not seen');
      else if (!body.open || body.details == null) fail(slug + ' ' + view + ': firm_page stayed closed');
      else if (!(body.checks || []).length || (body.checks || []).some(c => c.state == null)) fail(slug + ' ' + view + ': checks are missing their results');
      else if (view === 'full' && !(body.sections || []).length) fail(slug + ' ' + view + ': no sections');
      else ok(slug + ' ' + view + ': unlocked, no blur, no lock panel, firm_page open');
    } finally { page.off('response', on); }
  }
  for (const slug of FIRMS) await openPage(slug, BASE + 'vc/' + slug + '/', 'summary');

  // How we check
  { const r = await page.goto(BASE + 'how-we-check/', { waitUntil: 'domcontentloaded', timeout: 45000 });
    if (!r || r.status() !== 200) fail('how-we-check: status ' + (r && r.status()));
    else if (!(await page.locator('nav a.on[href$="how-we-check/"]').count())) fail('how-we-check: nav link not active'); else ok('how-we-check: page and active nav link'); }

  // Full pages: same unlocked state, firm name stays public
  for (const slug of FIRMS) {
    await openPage(slug, BASE + 'vc/' + slug + '/full/', 'full');
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
