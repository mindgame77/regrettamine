/* After deploy, every live fund page must match the landing list once the report has loaded. */
import { chromium } from 'playwright';

const BASE = (process.env.REGRET_BASE || 'https://mindgame77.github.io/regrettamine/').replace(/\/?$/, '/');
const SLUGS = [
  'a16z', 'battery', 'bessemer', 'accel', 'baincapitalventures', 'generalcatalyst',
  'khosla', 'lux', 'sequoia', 'lightspeed', 'insightpartners',
];

function redundantShort(name, short) {
  const initials = name.split(/\s+/).filter(Boolean).map(part => part[0]).join('');
  return !short
    || short.toLowerCase() === name.toLowerCase()
    || (short.length > 1 && name.toLowerCase().includes(short.toLowerCase()))
    || short.toLowerCase() === initials.toLowerCase();
}

async function readFund(page, slug) {
  const problems = [];
  await page.goto(BASE + 'vc/' + slug + '/', { waitUntil: 'domcontentloaded', timeout: 45000 });
  try {
    await page.waitForFunction(() => {
      const wait = document.querySelector('.report-wait');
      const rank = document.querySelector('.rankb');
      return rank && (!wait || !wait.textContent.trim());
    }, { timeout: 30000 });
  } catch (err) {
    problems.push(slug + ': report did not finish loading');
    return { slug, problems };
  }
  if (await page.locator('.gatecard, .report-veil').count()) {
    problems.push(slug + ': report was gated');
    return { slug, problems };
  }
  const facts = await page.evaluate(() => {
    const h1 = document.querySelector('#report h1') || document.querySelector('h1');
    const clone = h1.cloneNode(true);
    const span = clone.querySelector('span');
    const short = span ? span.textContent.trim() : '';
    clone.querySelectorAll('button, span').forEach(node => node.remove());
    const name = clone.textContent.trim();
    const score = (document.querySelector('.num b') || {}).textContent || '';
    const rank = (document.querySelector('.rankb') || {}).innerText || '';
    const html = document.documentElement.innerHTML;
    const overviewStart = html.indexOf('data-panel="overview"');
    const scoreStart = html.indexOf('data-panel="score"');
    const overview = overviewStart >= 0 && scoreStart > overviewStart
      ? html.slice(0, scoreStart)
      : '';
    const zeros = Array.from(document.querySelectorAll('[data-tab]')).filter(button => {
      const mark = button.querySelector('i');
      return mark && mark.textContent.trim() === '0';
    }).map(button => {
      const panel = document.querySelector('[data-panel="' + button.dataset.tab + '"]');
      return { tab: button.dataset.tab, text: panel ? panel.innerText : '' };
    });
    const scorePanel = document.querySelector('[data-panel="score"]');
    return {
      name,
      short,
      score: score.trim(),
      rank: rank.replace(/\s+/g, ' ').trim(),
      html,
      doj: (overview.match(/DOJ/g) || []).length,
      zeros,
      capped: scorePanel ? (scorePanel.innerText.match(/capped at \+3/g) || []).length : 0,
    };
  });
  if (/Toxy/.test(facts.html)) problems.push(slug + ': Toxy is still in the page');
  if (/v2 fund of|Top 1 fund/.test(facts.html)) problems.push(slug + ': old rank wording');
  if (facts.short && redundantShort(facts.name, facts.short)) {
    problems.push(slug + ': doubled name ' + facts.name + ' / ' + facts.short);
  }
  facts.zeros.forEach(row => {
    if (!row.text.includes('No data yet')) problems.push(slug + ': ' + row.tab + ' is empty without No data yet');
    if (row.text.includes('0 matters')) problems.push(slug + ': ' + row.tab + ' still says 0 matters');
  });
  if (facts.capped > 1) problems.push(slug + ': founded sentence is repeated');
  if (slug === 'a16z' && facts.doj !== 1) problems.push('a16z overview mentions DOJ ' + facts.doj + ' times');
  return {
    slug,
    name: facts.name,
    score: Number(facts.score),
    rank: facts.rank,
    problems,
  };
}

async function checkSettings(page) {
  const problems = [];
  const html = await page.evaluate(async (base) => {
    const pageRes = await fetch(base + 'settings/', { cache: 'no-store' });
    const jsRes = await fetch(base + 'js/settings.js', { cache: 'no-store' });
    return { page: await pageRes.text(), js: await jsRes.text(), ok: pageRes.ok && jsRes.ok };
  }, BASE);
  if (!html.ok) problems.push('settings files did not load');
  if (!html.page.includes('id="planCancel" hidden')) problems.push('delete note is not hidden by default');
  if (!html.js.includes('scrollTo(0, 0)') || !html.js.includes('scrollIntoView')) {
    problems.push('settings scroll fix is not live');
  }
  if (!html.js.includes('planCancel')) problems.push('delete note is not tied to the plan');
  return problems;
}

const browser = await chromium.launch({
  headless: true,
  executablePath: process.env.CHROME_PATH || undefined,
});
const problems = [];
const loaded = [];
try {
  for (let attempt = 1; attempt <= 8; attempt++) {
    const context = await browser.newContext();
    const page = await context.newPage();
    const sample = await readFund(page, 'a16z');
    const settings = await checkSettings(page);
    await context.close();
    const stale = sample.problems.some(item => /Toxy|old rank|did not finish/.test(item)) || settings.length;
    if (!stale || attempt === 8) {
      problems.push(...sample.problems, ...settings);
      if (!sample.problems.length) loaded.push(sample);
      break;
    }
    await new Promise(resolve => setTimeout(resolve, 15000));
  }
  for (const slug of SLUGS.filter(slug => slug !== 'a16z')) {
    let row;
    for (let attempt = 1; attempt <= 4; attempt++) {
      const context = await browser.newContext();
      const page = await context.newPage();
      row = await readFund(page, slug);
      await context.close();
      const stalled = row.problems.some(item => /did not finish/.test(item));
      if (!stalled || attempt === 4) break;
      await new Promise(resolve => setTimeout(resolve, 5000));
    }
    problems.push(...row.problems);
    if (!row.problems.length) loaded.push(row);
  }
  const home = await browser.newContext();
  const homePage = await home.newPage();
  await homePage.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 45000 });
  await homePage.waitForSelector('.tbl .nm b', { timeout: 20000 });
  const homeNames = await homePage.locator('.tbl .nm b').allTextContents();
  await home.close();
  if (loaded.length === SLUGS.length) {
    const expected = loaded.slice().sort((a, b) => b.score - a.score || a.name.localeCompare(b.name));
    expected.forEach((fund, index) => {
      const want = '#' + (index + 1) + ' of ' + SLUGS.length + ' funds';
      if (fund.rank !== want) problems.push(fund.slug + ': rank ' + fund.rank + ' != ' + want);
    });
    const top = expected.slice(0, 3).map(fund => fund.name);
    if (homeNames.slice(0, 3).join('|') !== top.join('|')) {
      problems.push('landing order ' + homeNames.slice(0, 3).join(', ') + ' != ' + top.join(', '));
    }
  }
} finally {
  await browser.close();
}

if (problems.length) {
  console.error(problems.join('\n'));
  process.exit(1);
}
console.log('hydrated reports match the landing list');
