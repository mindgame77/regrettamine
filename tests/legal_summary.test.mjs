// Legal case summary under the pills (Alex 2026-10-29): text <= 300, date in the site date style, source link.
// node --test tests/legal_summary.test.mjs
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
const { render } = sandbox.window.RegretCompany;
const src = [{ label: 'CourtListener', url: 'https://www.courtlistener.com/docket/1/x/' }];
const row = (title, extra) => Object.assign({ grp: 'case', title, year: '2023', state: 'Active', status: '', note: '', role: 'Defendant', src }, extra || {});
function page(items) {
  const P = { open: true, firm: { name: 'Example Capital', slug: 'example' }, checks: [], sections: [{ key: 'legal', count: items.length, items }] };
  const main = node(), pmain = node(); main.set('.pmain', pmain); render(main, P); return pmain.innerHTML;
}
const fdate = (d) => sandbox.window.RegretDate.format(d);

test('summary renders under the pills with date and source link', () => {
  const html = page([row('A v. B', { summary: 'Filed <x> & more.', summary_date: '2026-10-29', summary_url: 'https://www.courtlistener.com/docket/9/a-v-b/' })]);
  const i = html.indexOf('<div class="rm">'), j = html.indexOf('<div class="lsum">');
  assert.ok(i > 0 && j > i, 'summary comes after the pills');
  assert.match(html, /<p class="lsum-t">Filed &lt;x&gt; &amp; more\.<\/p>/);
  assert.ok(html.includes('<span>Summary ' + fdate('2026-10-29') + '</span>'));
  assert.match(html, /<a href="https:\/\/www\.courtlistener\.com\/docket\/9\/a-v-b\/" target="_blank" rel="noopener">Source: courtlistener\.com ↗<\/a>/);
});

test('no summary, or no source link: nothing drawn', () => {
  assert.doesNotMatch(page([row('A v. B')]), /lsum/);
  assert.doesNotMatch(page([row('A v. B', { summary: 'text', summary_date: '2026-10-29' })]), /lsum/);
  assert.doesNotMatch(page([row('A v. B', { summary: 'text', summary_url: 'javascript:alert(1)' })]), /lsum/);
});

test('over 300 characters is trimmed, not dropped', () => {
  const html = page([row('A v. B', { summary: 'x'.repeat(350), summary_url: 'https://www.sec.gov/a' })]);
  const t = html.match(/<p class="lsum-t">([^<]*)<\/p>/)[1];
  assert.equal(t.length, 300);
});

test('copy and style use design tokens', () => {
  assert.equal(copy.company.legal.summary_date, 'Summary {d}');
  assert.equal(copy.company.legal.summary_source, 'Source: {site}');
  const css = fs.readFileSync(new URL('launch/style.css', root), 'utf8');
  assert.match(css, /\.lsum\{[^}]*var\(--viobg\)/);
  assert.match(css, /\.lsum \.lsm a\{[^}]*var\(--vio\)/);
});
