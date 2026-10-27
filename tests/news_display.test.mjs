// Display-time News. Press and timeline rows stay as the page received them.
// node --test tests/news_display.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const copy = JSON.parse(fs.readFileSync(new URL('launch/copy.json', root), 'utf8'));
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement() { return { className: '', hidden: true }; } },
  console,
  URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(new URL('launch/js/dates.js', root), 'utf8'), sandbox, { filename: 'dates.js' });
vm.runInContext(fs.readFileSync(new URL('launch/js/company.js', root), 'utf8'), sandbox, { filename: 'company.js' });
const { buildNews, pageSecs } = sandbox.window.RegretCompany;

const press = (url, head, date, extra) => Object.assign({
  head, outlet: 'Outlet', date, url, snippet: 'snip', logo: '', group: '',
  src: [{ label: 'Outlet', date, url }],
}, extra || {});
const timeline = (date, kind, body, url) => ({
  head: date + ' · ' + body, date, kind, body,
  src: [{ label: 'Docket', date, url }],
});

test('a timeline item is not added to News, and two press rows with one link stay one card', () => {
  const url = 'https://www.TechCrunch.com/story?utm=1#x';
  const cards = buildNews(
    [press(url, 'Firm named in a filing', '2026-03-15', { group: 'Regulators & legal' })],
    [timeline('2026-03-15', 'Court', 'Hearing held', url)],
  );
  assert.equal(cards.length, 1);
  assert.equal(cards[0].origin, 'press');
  assert.equal(cards[0].tag, 'Regulator');
  assert.equal(cards[0].head, 'Firm named in a filing');
  assert.equal(cards[0].src.length, 1);
  const again = buildNews(
    [press(url, 'Firm named in a filing', '2026-03-15'), press(url, 'Same story, older line', '2026-03-15')],
    [],
  );
  assert.equal(again.length, 1);
});

test('timeline events are not shown as News cards', () => {
  const docket = 'https://www.courtlistener.com/docket/case/';
  const cards = buildNews([], [
    timeline('2026-10-15', 'Court', 'Discovery order', docket),
    timeline('2025-10-21', 'Court', 'Ninth Circuit', docket + '?x=1'),
    timeline('2026-04-01', 'Filing', 'First filing', 'https://example.com/same'),
    timeline('2026-04-01', 'Filing', 'Same day again', 'https://example.com/same'),
  ]);
  assert.equal(cards.length, 0);
});

test('the same fund close from two outlets is one card, and a different story that day stays separate', () => {
  const day = '2026-05-12';
  const live = 'https://www.reuters.com/doj';
  const cards = buildNews(
    [
      press('https://news.example/2016', 'How the firm started', '2016-06-01'),
      press(live, 'A 2026 article', '2026-01-02'),
      press('https://fund.example/close', 'Fund III final close', day, { outlet: 'Wire', src: [{ label: 'Wire', date: day, url: 'https://fund.example/close' }] }),
    ],
    [
      timeline('1983', 'Reported', 'Founded', 'https://news.example/1983'),
      timeline('2009', 'Reported', 'Founded, wrong link', live),
      timeline(day, 'Reported', 'Fund III final close, other outlet', 'https://other.example/close'),
    ],
  );
  assert.equal(cards.map(c => c.head).sort().join('|'), [
    'A 2026 article',
    'Fund III final close',
  ].join('|'));
  const article = cards.find(c => c.head === 'A 2026 article');
  assert.equal(article.src.length, 1);
  assert.ok(!article.src.some(s => s.label === 'Docket'));
  assert.equal(article.outlets, undefined);
  const close = cards.find(c => c.head === 'Fund III final close');
  assert.equal(close.outlets, undefined);
  assert.equal(close.src.map(s => s.label).join('|'), 'Wire');
});

test('an undated item is shown, and three outlets stay three cards', () => {
  const cards = buildNews([
    press('https://techcrunch.com/doj', 'DOJ opens a board probe', '2026-02-01'),
    press('https://www.reuters.com/doj', 'Board seats draw a DOJ look', '2026-02-02'),
    press('https://thenextweb.com/doj', 'DOJ board review widens', '2026-02-03'),
    press('https://example.com/nodate', 'No date on this one', ''),
  ], []);
  assert.equal(cards.length, 4);
  assert.equal(cards[cards.length - 1].head, 'No date on this one');
});

test('pageSecs draws News from press only and does not draw press or timeline', () => {
  const P = {
    sections: [
      { key: 'overview', items: [{ label: 'Founded', value: '2009' }], count: 1 },
      { key: 'press', items: [press('https://example.com/a', 'A story', '2024-01-02')], count: 1 },
      { key: 'timeline', items: [timeline('2024-01-02', 'Court', 'Hearing', 'https://example.com/a')], count: 1 },
      { key: 'lps', items: [{ label: 'University of Michigan', value: '$100M' }, { label: 'University of Michigan', value: '$30M' }], count: 2 },
    ],
  };
  const secs = pageSecs(P);
  assert.equal(secs.map(s => s.key).join('|'), 'overview|news|lps');
  assert.equal(secs[1].count, 1);
  assert.equal(secs[1].items[0].origin, 'press');
  assert.equal(secs[1].items[0].tag, '');
  assert.equal(secs[1].items[0].head, 'A story');
  assert.equal(secs[2].count, 1);
});

const A16Z = { name: 'Andreessen Horowitz', short_name: 'a16z', sec_name: 'AH Capital Management, L.L.C.' };
const outlet = (url, head, date, label) => press(url, head, date, {
  outlet: label, src: [{ label, date, url }],
});

test('a16z groups the three DOJ outlets into one card and leaves other stories alone', () => {
  const tc = 'https://techcrunch.com/2026/08/18/dojs-probe-into-andreessen-horowitz-over-board-seats-baffles-vcs/';
  const reu = 'https://www.reuters.com/legal/legalindustry/andreessen-horowitz-focus-doj-probe-over-board-directors-bloomberg-news-reports-2026-08-17/';
  const tnw = 'https://thenextweb.com/news/andreessen-horowitz-doj-probe-databricks-fivetran-board-seats';
  const cards = buildNews([
    outlet(tc, "DOJ probes a16z partners' board seats at Databricks and Fivetran", 'Aug 18, 2026', 'TechCrunch'),
    outlet(reu, 'Andreessen Horowitz focus of DOJ probe over board directors, Bloomberg News reports', '2026-08-17', 'Reuters'),
    outlet(tnw, 'DOJ probe into a16z over Databricks and Fivetran board seats', '2026', 'The Next Web'),
    outlet('https://www.axios.com/pregnancy', 'Run The World co-founder alleges pregnancy discrimination, names a16z', 'Sep 11, 2023', 'Axios'),
    outlet('https://www.bloomberg.com/pac', 'a16z-backed AI super PAC passes $50M', 'Apr 15, 2026', 'Bloomberg'),
    outlet('https://www.propublica.org/cfpb', 'CFPB probes into a16z-backed fintechs disrupted under political pressure', '2025', 'ProPublica'),
    outlet('https://www.cnbc.com/accuse', "Ex-partner John O'Farrell accuses a16z of political infiltration", 'Jun 11, 2026', 'CNBC'),
    outlet('https://example.com/stripe', 'DOJ probes Stripe over payment fees', '2026-08-16', 'StripeWire'),
  ], [
    timeline('2026-08-18', 'Regulator', "DOJ probe into partners' board seats at Databricks and Fivetran reported. Open, no charges.", tc),
    timeline('2026-08-17', 'Reported', 'Reuters reports DOJ probe focused on a16z board directors', reu),
    timeline('2009', 'Reported', 'Founded by Marc Andreessen and Ben Horowitz', reu),
  ], A16Z);
  const doj = cards.filter(c => /Databricks and Fivetran/.test(c.head) || /Bloomberg News reports/.test(c.head));
  assert.equal(doj.length, 1);
  assert.equal(doj[0].head, "DOJ probes a16z partners' board seats at Databricks and Fivetran");
  assert.equal(doj[0].outlets, 3);
  assert.equal(doj[0].tag, '');
  assert.equal(doj[0].src.map(s => s.label).sort().join('|'), 'Reuters|TechCrunch|The Next Web');
  assert.equal(cards.filter(c => c.head === 'DOJ probes Stripe over payment fees').length, 1);
  assert.ok(cards.some(c => c.head.startsWith('Run The World')));
  assert.ok(cards.some(c => /super PAC/.test(c.head)));
  assert.ok(cards.some(c => c.head.startsWith('CFPB')));
  assert.ok(cards.some(c => /O'Farrell/.test(c.head)));
  assert.equal(cards.filter(c => /Founded by Marc/.test(c.head)).length, 0);
});

test('obviously different stories are not grouped', () => {
  const split = buildNews([
    outlet('https://example.com/cfpb', 'CFPB probes fintech lenders over fees', '2026-08-18', 'A'),
    outlet('https://example.com/doj', 'DOJ probes Databricks and Fivetran', '2026-08-18', 'B'),
    outlet('https://example.com/f7', 'Fund VII final close', '2026-05-12', 'C'),
    outlet('https://example.com/f8', 'Fund VIII final close', '2026-05-12', 'D'),
    outlet('https://example.com/sb', 'Series B raise closes', '2026-03-01', 'E'),
    outlet('https://example.com/sc', 'Series C raise closes', '2026-03-02', 'F'),
    outlet('https://example.com/d1', 'DOJ probes Databricks', '2026-08-01', 'G'),
    outlet('https://example.com/d2', 'DOJ probes Databricks', '2026-08-09', 'H'),
    outlet('https://example.com/disc', 'Firm disclosed a letter about Fund III', '2026-05-12', 'I'),
    outlet('https://example.com/close', 'Fund III final close', '2026-05-12', 'J'),
  ], [], A16Z);
  assert.equal(split.length, 10);
  const week = buildNews([
    outlet('https://near.example/a', 'DOJ probes Databricks', '2026-08-01', 'Near'),
    outlet('https://week.example/a', 'DOJ probes Databricks', '2026-08-08', 'Week'),
  ], [], A16Z);
  assert.equal(week.length, 1);
  assert.equal(week[0].outlets, 2);
  const bridge = buildNews([
    outlet('https://example.com/jan', 'DOJ probes Databricks and Fivetran', '2026-01-10', 'Jan'),
    outlet('https://example.com/aug', 'DOJ probes Databricks and Fivetran', '2026-08-18', 'Aug'),
    outlet('https://example.com/year', 'DOJ probe into Databricks and Fivetran', '2026', 'Year'),
  ], [], A16Z);
  assert.equal(bridge.filter(c => c.src.some(s => s.label === 'Jan') && c.src.some(s => s.label === 'Aug')).length, 0);
  assert.ok(bridge.filter(c => c.src.some(s => s.label === 'Year')).length <= 1);
  const months = buildNews([
    outlet('https://example.com/m1', 'DOJ probes Databricks', '2026-08', 'MonthA'),
    outlet('https://example.com/m2', 'DOJ probe of Databricks', '2026-08', 'MonthB'),
  ], [], A16Z);
  assert.equal(months.length, 2);
  const undated = buildNews([
    outlet('https://example.com/u', 'DOJ probes Databricks', '', 'Undated'),
    outlet('https://example.com/dated', 'DOJ probes Databricks', '2026-08-18', 'Dated'),
  ], [], A16Z);
  assert.equal(undated.length, 2);
});
