/* After deploy, the live launch site (launch/ → site-launch/) must work: home + search, firm pages with
   their sections and Check summary, sitemap.xml, and the signed-out account prompt. */
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

  // Summary pages: 10 check rows and a link to the full check
  for (const slug of FIRMS) {
    const r = await page.goto(BASE + 'vc/' + slug + '/', { waitUntil: 'domcontentloaded', timeout: 45000 });
    if (!r || r.status() !== 200) { fail(slug + ' summary: status ' + (r && r.status())); continue; }
    try { await page.waitForFunction(() => document.querySelectorAll('.sumpg .list tr.crow').length === 10, null, { timeout: 30000 }); } catch (_) { fail(slug + ' summary: 10 check rows never rendered'); continue; }
    const s = await page.evaluate(() => ({ tog: document.querySelectorAll('.sumpg tr.crow.tog').length, full: !!document.querySelector('.full a[href="full/"]'), src: document.querySelectorAll('.sumpg tr.cdx a').length }));
    if (!s.full) fail(slug + ' summary: no See the full check link');
    if (s.src) fail(slug + ' summary: dropdowns contain source links');
    ok(slug + ' summary: 10 rows, ' + s.tog + ' with a dropdown');
  }

  // How we check
  { const r = await page.goto(BASE + 'how-we-check/', { waitUntil: 'domcontentloaded', timeout: 45000 });
    if (!r || r.status() !== 200) fail('how-we-check: status ' + (r && r.status()));
    else if (!(await page.locator('nav a.on[href$="how-we-check/"]').count())) fail('how-we-check: nav link not active'); else ok('how-we-check: page and active nav link'); }

  // Full pages: sections, TOC and Check summary
  for (const slug of FIRMS) {
    const r = await page.goto(BASE + 'vc/' + slug + '/full/', { waitUntil: 'domcontentloaded', timeout: 45000 });
    if (!r || r.status() !== 200) { fail(slug + ': status ' + (r && r.status())); continue; }
    try { await page.waitForSelector('.pmain section.ps', { timeout: 30000 }); } catch (_) { fail(slug + ': sections never rendered'); continue; }
    const f = await page.evaluate(() => ({
      h1: (document.querySelector('h1') || {}).textContent || '',
      secs: Array.from(document.querySelectorAll('.pmain section.ps')).map(s => s.id),
      toc: document.querySelectorAll('.toc a[href^="#"]').length,
      checks: document.querySelectorAll('.csum:not([hidden]) .ck').length,
    }));
    if (!f.h1.trim()) fail(slug + ': no firm name');
    if (!f.secs.includes('checks')) fail(slug + ': no checks section');
    if (f.checks !== 10) fail(slug + ': Check summary has ' + f.checks + ' rows, want 10');
    if (f.toc !== f.secs.length) fail(slug + ': TOC has ' + f.toc + ' links for ' + f.secs.length + ' sections');
    if (/Toxy/.test(await page.content())) fail(slug + ': Toxy is still in the page');
    ok(slug + ': ' + f.h1.trim() + ' · sections ' + f.secs.join(',') + ' · ' + f.checks + ' checks');
  }

  // Sitemap
  const sm = await page.request.get(BASE + 'sitemap.xml');
  const xml = sm.ok() ? await sm.text() : '';
  if (!/<urlset/.test(xml)) fail('sitemap.xml missing or invalid (' + sm.status() + ')');
  else { const miss = FIRMS.filter(s => !xml.includes('/vc/' + s + '/')); miss.length ? fail('sitemap.xml lacks ' + miss.join(',')) : ok('sitemap.xml: ' + (xml.match(/<loc>/g) || []).length + ' urls'); }

  // Signed-out account prompt
  await page.goto(BASE + 'account/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  try { await page.waitForSelector('[data-out]:not([hidden]) [data-open="signup"]', { timeout: 20000 }); ok('account: sign-in prompt shown when signed out'); }
  catch (_) { fail('account: no sign-in prompt when signed out'); }
} finally { await browser.close(); }

if (problems.length) { console.error(problems.length + ' problem(s)'); process.exit(1); }
console.log('all live checks passed');
