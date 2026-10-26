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

test('a timeline item folds into the press card with the same link and keeps the Court tag', () => {
  const url = 'https://www.TechCrunch.com/story?utm=1#x';
  const cards = buildNews(
    [press(url, 'Firm named in a filing', '2026-03-15', { group: 'Regulators & legal' })],
    [timeline('2026-03-15', 'Court', 'Hearing held', url)],
  );
  assert.equal(cards.length, 1);
  assert.equal(cards[0].origin, 'press');
  assert.equal(cards[0].tag, 'Court');
  assert.equal(cards[0].head, 'Firm named in a filing');
  const again = buildNews(
    [press(url, 'Firm named in a filing', '2026-03-15'), press(url, 'Same story, older line', '2026-03-15')],
    [],
  );
  assert.equal(again.length, 1);
});

test('two timeline events that share a link and differ by date stay two cards', () => {
  const docket = 'https://www.courtlistener.com/docket/case/';
  const cards = buildNews([], [
    timeline('2026-10-15', 'Court', 'Discovery order', docket),
    timeline('2025-10-21', 'Court', 'Ninth Circuit', docket + '?x=1'),
    timeline('2026-04-01', 'Filing', 'First filing', 'https://example.com/same'),
    timeline('2026-04-01', 'Filing', 'Same day again', 'https://example.com/same'),
  ]);
  const courts = cards.filter(c => c.tag === 'Court');
  const filings = cards.filter(c => c.tag === 'Filing');
  assert.equal(courts.length, 2);
  assert.equal(courts.map(c => c.head).sort().join('|'), 'Discovery order|Ninth Circuit');
  assert.equal(filings.length, 1);
});

test('the same date with a different link stays two cards, and dates before 2023 are left off', () => {
  const day = '2026-05-12';
  const live = 'https://www.reuters.com/doj';
  const cards = buildNews(
    [
      press('https://news.example/2016', 'How the firm started', '2016-06-01'),
      press(live, 'A 2026 article', '2026-01-02'),
      press('https://fund.example/close', 'Fund III final close', day),
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
    'Fund III final close, other outlet',
  ].join('|'));
  const article = cards.find(c => c.head === 'A 2026 article');
  assert.equal(article.src.length, 1);
  assert.ok(!article.src.some(s => s.label === 'Docket'));
  const reported = cards.find(c => c.head === 'Fund III final close, other outlet');
  assert.equal(reported.tag, '');
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

test('pageSecs draws News from press and timeline and does not draw those sections', () => {
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
  assert.equal(secs[1].items[0].tag, 'Court');
  assert.equal(secs[2].count, 1);
});
