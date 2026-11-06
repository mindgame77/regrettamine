// HQ country flag after the city, and a Videos section (at most 3, most views first) between Team and News.
// node --test tests/videos_flag.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const css = read('launch/style.css');

function el() {
  const node = {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
    classList: { toggle() {}, add() {}, remove() {} },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute() {},
    remove() {},
    insertAdjacentElement() { return null; },
  };
  return node;
}
function mainEl() {
  const kids = {};
  const main = el();
  main.querySelector = (sel) => kids[sel] || null;
  main.set = (sel, child) => { kids[sel] = child; return child; };
  return main;
}
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement: () => el() },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(read('launch/js/company.js'), sandbox, { filename: 'company.js' });
const { metaLine, pageSecs, render } = sandbox.window.RegretCompany;

const FLAG_US = '\u{1F1FA}\u{1F1F8}';
const FLAG_GB = '\u{1F1EC}\u{1F1E7}';

test('US flag sits after City, ST and the country name is not written', () => {
  const m = metaLine({
    firm: {
      hq: 'Menlo Park, CA', short_name: 'a16z', hq_country: 'US',
      website: 'https://a16z.com', founded_year: 2009,
    },
  });
  assert.match(m, new RegExp('Menlo Park, CA ' + FLAG_US + ' · Founded 2009 · <a href="https://a16z.com"'));
  assert.doesNotMatch(m, /United States|USA/);
  assert.equal(copy.company.header.founded, 'Founded {y}');
});

test('a lowercase code still flags, and an unknown code adds nothing', () => {
  assert.equal(metaLine({ firm: { hq: 'Menlo Park, CA', short_name: 'a16z', hq_country: 'us' } }), 'Menlo Park, CA ' + FLAG_US);
  for (const code of [null, undefined, '', 'USA', 'U', '12']) {
    assert.equal(metaLine({ firm: { hq: 'Menlo Park, CA', short_name: 'a16z', hq_country: code } }), 'Menlo Park, CA');
  }
  assert.equal(metaLine({ firm: { hq: 'London', hq_country: 'GB' } }), 'London ' + FLAG_GB);
  assert.doesNotMatch(metaLine({ firm: { hq: 'London', hq_country: 'GB' } }), /United Kingdom|Britain/);
  assert.equal(metaLine({ firm: { short_name: 'a16z', hq_country: 'US' } }), '');
});

const a16zVideos = [
  { title: 'Marc Andreessen: Trump, Power, Tech, AI, Immigration & Future of America | Lex Fridman Podcast #458', channel: 'Lex Fridman', url: 'https://www.youtube.com/watch?v=OHWnPOKh_S0', date: '2025-01-26', views: 1547628 },
  { title: 'Joe Rogan Experience #2234 - Marc Andreessen', channel: 'PowerfulJRE', url: 'https://www.youtube.com/watch?v=ye8MOfxD5nU', date: '2024-11-26', views: 3030977 },
  { title: 'Marc Andreessen: Future of the Internet, Technology, and AI | Lex Fridman Podcast #386', channel: 'Lex Fridman', url: 'https://www.youtube.com/watch?v=-hxeDjAxvJ8', date: '2023-06-21', views: 1590015 },
];

function page(extra) {
  return {
    open: true, checks: [],
    firm: { name: 'Andreessen Horowitz', short_name: 'a16z', hq: 'Menlo Park, CA', hq_country: 'US', website: 'https://a16z.com', founded_year: 2009 },
    sections: [
      { key: 'people', items: [{ head: 'Marc Andreessen', kind: 'team', role: 'Cofounder and General Partner' }] },
      { key: 'press', items: [{ head: 'A story', outlet: 'Outlet', date: '2024-01-02', url: 'https://example.com/a', src: [{ label: 'Outlet', date: '2024-01-02', url: 'https://example.com/a' }] }] },
      { key: 'lps', items: [{ label: 'CalPERS', value: '$100M' }] },
    ].concat(extra || []),
  };
}

test('videos render before Team and News, three tiles, most views first, no source pill', () => {
  const low = { title: 'A smaller interview', channel: 'Other', url: 'https://www.youtube.com/watch?v=abcdefghijk', date: '2022-01-01', views: 10 };
  const press = { title: 'Not a video', channel: 'Wire', url: 'https://example.com/story', date: '2024-01-01', views: 99999999 };
  const blank = { title: '   ', channel: 'X', url: 'https://www.youtube.com/watch?v=zzzzzzzzzzz', views: 50 };
  const P = page([{ key: 'videos', items: a16zVideos.concat([low, press, blank, { title: 'No views', channel: 'C', url: 'https://youtu.be/yyyyyyyyyyy', date: '2024-05-01', views: null }]) }]);
  const secs = pageSecs(P);
  const keys = secs.map(s => s.key);
  assert.ok(keys.indexOf('people') < keys.indexOf('videos') && keys.indexOf('videos') < keys.indexOf('news'));
  assert.ok(keys.indexOf('news') < keys.indexOf('lps'));
  const v = secs.find(s => s.key === 'videos');
  assert.equal(v.title, 'Videos');
  assert.equal(v.subtitle, '');
  assert.equal(v.nocount, true);
  assert.equal(v.count, 3);
  assert.deepEqual(v.items.map(x => x.views), [3030977, 1590015, 1547628]);
  const main = mainEl();
  main.set('.actw', el());
  main.set('.pmain', el());
  const meta = main.set('.m', el());
  main.set('.ph .m', meta);
  render(main, P);
  assert.match(meta.innerHTML, new RegExp('Menlo Park, CA ' + FLAG_US));
  const html = main.querySelector('.pmain').innerHTML;
  const videosAt = html.indexOf('id="videos"');
  const block = html.slice(videosAt, html.indexOf('</article>', videosAt));
  assert.match(block, /<h3>Videos<\/h3>/);
  assert.doesNotMatch(block, /<h3>Videos <em/);
  assert.doesNotMatch(block, /class="scs"|Source/);
  assert.doesNotMatch(block, /[↓↑→↗←]/);
  assert.equal((block.match(/class="vtile"/g) || []).length, 3);
  assert.match(block, /href="https:\/\/www\.youtube\.com\/watch\?v=ye8MOfxD5nU" target="_blank" rel="noopener"/);
  assert.match(block, /src="https:\/\/i\.ytimg\.com\/vi\/ye8MOfxD5nU\/hqdefault\.jpg"/);
  assert.match(block, /src="https:\/\/i\.ytimg\.com\/vi\/-hxeDjAxvJ8\/hqdefault\.jpg"/);
  assert.match(block, /Joe Rogan Experience #2234 - Marc Andreessen/);
  assert.match(block, /PowerfulJRE · Nov 26, 2024 · 3,030,977 views/);
  assert.match(block, /Lex Fridman · Jun 21, 2023 · 1,590,015 views/);
  assert.match(block, /Lex Fridman · Jan 26, 2025 · 1,547,628 views/);
  assert.doesNotMatch(block, /A smaller interview|Not a video|No views|abcdefghijk/);
  const teamAt = html.indexOf('id="team"');
  const newsAt = html.indexOf('id="news"');
  assert.ok(videosAt >= 0 && videosAt < teamAt && teamAt < newsAt);
});

test('a firm with no videos renders no Videos section', () => {
  const P = page();
  assert.equal(pageSecs(P).find(s => s.key === 'videos'), undefined);
  const main = mainEl();
  main.set('.actw', el());
  const pmain = main.set('.pmain', el());
  main.set('.m', el());
  render(main, P);
  assert.doesNotMatch(pmain.innerHTML, /id="videos"|class="vgrid"|Videos/);
  assert.match(pmain.innerHTML, /id="team"/);
  assert.match(pmain.innerHTML, /id="news"/);
});

test('video tiles use a 3-column grid that stacks on a phone', () => {
  assert.match(css, /\.vgrid\{display:grid;grid-template-columns:repeat\(3,minmax\(0,1fr\)\)/);
  assert.match(css, /@media \(max-width:640px\)\{\.vgrid\{grid-template-columns:minmax\(0,1fr\)/);
  assert.match(css, /-webkit-line-clamp:3/);
  assert.equal(copy.company.videos.views, '{n} views');
});
