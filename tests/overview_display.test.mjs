// Overview rows are rewritten when the page draws. Stored facts stay as they are.
// node --test tests/overview_display.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const copy = JSON.parse(fs.readFileSync(new URL('launch/copy.json', root), 'utf8'));

function node() {
  const kids = {};
  return {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
    classList: { toggle() {} },
    querySelector(sel) { return kids[sel] || null; },
    querySelectorAll() { return []; },
    set(sel, child) { kids[sel] = child; return child; },
  };
}
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement() { return node(); } },
  console,
  URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(new URL('launch/js/dates.js', root), 'utf8'), sandbox, { filename: 'dates.js' });
vm.runInContext(fs.readFileSync(new URL('launch/js/company.js', root), 'utf8'), sandbox, { filename: 'company.js' });
const { render, pageSecs } = sandbox.window.RegretCompany;

const link = (url, label) => ({ label: label || '', url, date: '' });
const ADV = 'https://reports.adviserinfo.sec.gov/reports/ADV/160489/PDF/160489.pdf';
const SUM = 'https://adviserinfo.sec.gov/firm/summary/160489';
const REU = 'https://www.reuters.com/legal/legalindustry/andreessen-horowitz-focus-doj-probe-over-board-directors-bloomberg-news-reports-2026-08-17/';
const YC_ADV = 'https://reports.adviserinfo.sec.gov/reports/ADV/171730/PDF/171730.pdf';
const YC_SUM = 'https://adviserinfo.sec.gov/firm/summary/171730';
const YC_SITE = 'https://www.ycombinator.com/about';

function draw(sections) {
  const P = { open: true, firm: { name: 'Example', slug: 'example' }, checks: [], sections };
  const main = node();
  const pmain = node();
  main.set('.pmain', pmain);
  main.set('.spl', node());
  main.set('.toc', node());
  render(main, P);
  return pmain.innerHTML;
}

function overview(html) {
  const section = html.split('id="overview"')[1].split('<section ')[0];
  const count = Number((section.match(/<em class="pc2">(\d+)<\/em>/) || [])[1]);
  const rows = section.split('<div class="rw">').slice(1).map(block => ({
    title: (block.match(/<div class="rt">([^<]*)<\/div>/) || [])[1],
    hrefs: [...block.matchAll(/href="([^"]+)"/g)].map(h => h[1]),
  }));
  return { count, rows };
}

test('a16z overview is five rows, in order, with founders merged and file numbers gone', () => {
  const html = draw([{
    key: 'overview',
    count: 12,
    items: [
      { label: 'HQ', value: 'Menlo Park, CA', src: [link(SUM, 'SEC')] },
      { label: 'Legal name', value: 'AH Capital Management, L.L.C.', src: [link(SUM, 'SEC')] },
      { label: 'Other names', value: 'A16Z Capital Management, L.L.C.; Andreessen Horowitz', src: [link(SUM, 'SEC')] },
      { label: 'Type', value: 'Venture capital · SEC-registered investment adviser', src: [link(SUM, 'SEC')] },
      { label: 'Registration', value: 'Approved Apr 11, 2019 · active · latest Form ADV Mar 30, 2026', src: [link(SUM, 'SEC'), link(ADV, 'Form ADV')] },
      { label: 'Owners', value: 'A16Z Holdings, L.L.C. (managing member, 75%+); Marc Andreessen & Ben Horowitz, members', src: [link(ADV, 'Form ADV')] },
      { label: 'Staff', value: '738 employees · 88 in investment roles', src: [link(ADV, 'Form ADV')] },
      { label: 'Founded', value: '2009', src: [link(REU, 'reuters.com')] },
      { label: 'Founders', value: 'Marc Andreessen, Ben Horowitz', src: [link(REU, 'reuters.com')] },
      { label: 'Private funds', value: '119 (Form ADV Schedule D)', src: [link(ADV, 'Form ADV')] },
      { label: 'Legal entity', value: 'Andreessen Horowitz, SEC-registered investment adviser (CRD 160489, SEC 801-114985), active', src: [link(SUM, 'SEC')] },
      { label: 'Not found', value: 'Not found', src: [link(SUM, 'SEC')] },
    ],
  }]);
  const ov = overview(html);
  assert.equal(ov.count, 5);
  assert.deepEqual(ov.rows.map(r => r.title), [
    'HQ: Menlo Park, CA',
    'Legal name: AH Capital Management, L.L.C.',
    'Registration: SEC-registered since 2019, active',
    'Founded: 2009 · Marc Andreessen, Ben Horowitz',
    'Owners: A16Z Holdings, L.L.C. (managing member, 75%+); Marc Andreessen &amp; Ben Horowitz, members',
  ]);
  assert.deepEqual(ov.rows[0].hrefs, [SUM]);
  assert.deepEqual(ov.rows[2].hrefs, [SUM, ADV]);
  assert.deepEqual(ov.rows[3].hrefs, [REU]);
  assert.deepEqual(ov.rows[4].hrefs, [ADV]);
  const shown = ov.rows.map(r => r.title).join('\n');
  assert.doesNotMatch(shown, /Other names|Sanctions|Private funds|Staff:|Type:|CRD |801-114985|Legal entity/);
});

test('Y Combinator overview is three rows: headquarters, legal name, and the ERA registration', () => {
  const html = draw([{
    key: 'overview',
    count: 5,
    items: [
      { label: 'Headquarters', value: '335 Pioneer Way, Mountain View, CA', src: [link(YC_ADV, 'SEC IAPD')] },
      { label: 'Y COMBINATOR MANAGEMENT, LLC', value: 'Adviser · CRD 171730 · SEC exempt reporting adviser (802-80528)', src: [link(YC_ADV, 'SEC IAPD'), link(YC_SITE, 'Y Combinator')] },
      { label: 'Sanctions screening', value: 'No match on 6 lists', src: [link(YC_ADV, 'SEC IAPD')] },
      { label: 'Private funds', value: '19 (Form ADV Schedule D)', src: [link(YC_ADV, 'SEC IAPD')] },
      { label: 'Legal entity', value: 'Y Combinator, SEC exempt reporting adviser (CRD 171730, SEC 802-80528), active', src: [link(YC_SUM, 'adviserinfo.sec.gov')] },
    ],
  }]);
  const ov = overview(html);
  assert.equal(ov.count, 3);
  assert.deepEqual(ov.rows.map(r => r.title), [
    'HQ: 335 Pioneer Way, Mountain View, CA',
    'Legal name: Y Combinator Management, LLC',
    'Registration: SEC exempt reporting adviser, active',
  ]);
  assert.deepEqual(ov.rows[1].hrefs, [YC_ADV, YC_SITE]);
  assert.deepEqual(ov.rows[2].hrefs, [YC_SUM]);
  const shown = ov.rows.map(r => r.title).join('\n');
  assert.doesNotMatch(shown, /CRD |802-80528|171730|Sanctions|Private funds|Y COMBINATOR/);
});

test('file numbers are stripped from rows that stay, empty rows drop, and other sections are left alone', () => {
  const items = [
    { label: 'HQ', value: 'Not found in public records', src: [link('https://example.com/hq', 'SEC')] },
    { label: 'Owners', value: 'Holding Co (CRD 160489, SEC 801-114985)', src: [link('https://example.com/own', 'ADV')] },
    { label: 'Recent changes', value: 'New managing member in 2024', src: [link('https://example.com/chg', 'Filing')] },
    { label: 'Website description', value: 'Invests in software', src: [link('https://example.com/web', 'Site')] },
    { label: 'Overview', value: 'Example Capital, CRD 12, SEC 801-99999, active', src: [link('https://example.com/ov', 'Note')] },
  ];
  const html = draw([
    { key: 'overview', count: 9, items },
    { key: 'funds', count: 7, items: [{ label: 'Private funds', value: '119 (CRD 160489)', src: [link(ADV, 'Form ADV')] }] },
  ]);
  const ov = overview(html);
  assert.equal(ov.count, 4);
  assert.deepEqual(ov.rows.map(r => r.title), [
    'Owners: Holding Co',
    'Recent changes: New managing member in 2024',
    'Website description: Invests in software',
    'Overview: Example Capital, active',
  ]);
  const funds = html.split('id="funds"')[1];
  assert.match(funds, /<em class="pc2">7<\/em>/);
  assert.match(funds, /Private funds: 119 \(CRD 160489\)/);
  const secs = pageSecs({ sections: [{ key: 'overview', count: 2, items: [{ label: 'Staff', value: '10', src: [link('https://example.com/s', 'SEC')] }] }] });
  assert.equal(secs.some(s => s.key === 'overview'), false);
});
