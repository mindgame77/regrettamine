// Full report: Overview is gone (Alex, 2026-10-29); its slot is the Thesis (overview item labelled 'thesis').
// Heading + text only, 5-line clamp, chip and nav named Thesis, all hidden without a thesis.
// node --test tests/thesis_section.test.mjs
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
    insertAdjacentElement(_where, el) { this._next = el; return el; },
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

function draw(sections, checks) {
  const P = { open: true, firm: { name: 'Example', slug: 'example', founded_year: 2009, hq: 'Menlo Park, CA' }, checks: checks || [], sections };
  const main = node(), pmain = node(), spl = node(), toc = node(), meta = node();
  main.set('.pmain', pmain); main.set('.spl', spl); main.set('.toc', toc); main.set('.m', meta); main.set('.ph .m', meta);
  render(main, P);
  return { body: pmain.innerHTML, chips: spl.innerHTML, nav: toc.innerHTML, meta: meta.innerHTML, intro: meta._next ? meta._next.textContent : '' };
}
const A16Z_OV = [
  { label: 'HQ', value: 'Menlo Park, CA', src: [link(ADV, 'SEC IAPD')] },
  { label: 'Legal name', value: 'AH Capital Management, L.L.C.', src: [link(ADV, 'SEC IAPD')] },
  { label: 'Registration', value: 'SEC-registered since 2019, active', src: [link(SUM, 'SEC IAPD')] },
  { label: 'Founded', value: '2009', src: [link(REU, 'reuters.com')] },
  { label: 'Owners', value: 'A16Z Holdings, L.L.C.', src: [link(ADV, 'SEC Form ADV')] },
  { label: 'Sanctions screening', value: 'No match', src: [link(ADV, 'OFAC')] },
];
const NEWS = { key: 'press', count: 1, items: [{ head: 'A story', date: '2026-01-01', src: [link('https://www.reuters.com/x', 'Reuters')] }] };
const CHECKS = [{ n: 1, title: 'Sanctions', state: 'clear' }];

test('no thesis: overview facts are not a section', () => {
  const r = draw([{ key: 'overview', count: 6, items: A16Z_OV }, NEWS], CHECKS);
  for (const h of [r.body, r.chips, r.nav]) {
    assert.doesNotMatch(h, /Overview|Thesis|id="overview"|id="thesis"|AH Capital|Owners|Registration/);
  }
  assert.equal(pageSecs({ sections: [{ key: 'overview', items: A16Z_OV }] }).length, 0);
});

test('a thesis is the header text, and stored markup stays text', () => {
  const text = 'We back founders early and stay for the long term. <b>not html</b>';
  const r = draw([{ key: 'overview', count: 7, items: A16Z_OV.concat([{ label: 'Thesis', value: '  ' + text + '  ', src: [] }]) }, NEWS], CHECKS);
  assert.equal(r.intro, 'We back founders early and stay for the long term. <b>not html</b>');
  assert.doesNotMatch(r.body, /id="thesis"|id="overview"|Overview|AH Capital/);
});

test('blank thesis is no thesis; label match is exact, case-insensitive', () => {
  assert.equal(pageSecs({ sections: [{ key: 'overview', items: [{ label: 'thesis', value: '   ' }] }] }).length, 0);
  assert.equal(pageSecs({ sections: [{ key: 'overview', items: [{ label: 'Thesis notes', value: 'x' }] }] }).length, 0);
  const s = pageSecs({ sections: [{ key: 'overview', items: [{ label: ' THESIS ', value: 'Seed' }] }] });
  assert.deepEqual(s.map(x => [x.key, x.title, x.items[0].value]), [['thesis', 'Thesis', 'Seed']]);
});

test('founded year still shows in the header meta line (#257)', () => {
  assert.match(draw([{ key: 'overview', items: A16Z_OV }]).meta, /Founded 2009/);
});

test('copy and the 5-line clamp', () => {
  assert.equal(copy.company.thesis.title, 'Thesis');
  const css = fs.readFileSync(new URL('launch/style.css', root), 'utf8');
  assert.match(css, /\.ps \.pth\{[^}]*-webkit-line-clamp:5[^}]*\}/);
});
