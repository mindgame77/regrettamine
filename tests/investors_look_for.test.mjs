// What investors look for: after Thesis, before Team. Five summary rows, then Show all.
// node --test tests/investors_look_for.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const css = read('launch/style.css');
const icon = read('launch/assets/icons/link-simple.svg');
const iconPath = icon.match(/d="([^"]+)"/)[1];

const clicks = [];
function el() {
  return {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
    classList: { toggle() {}, add() {}, remove() {} },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute() {},
    remove() {},
    insertAdjacentElement() { return null; },
  };
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
  document: {
    body: null,
    addEventListener(type, fn) { if (type === 'click') clicks.push(fn); },
    getElementById() { return null; },
    createElement: () => el(),
  },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(read('launch/js/company.js'), sandbox, { filename: 'company.js' });
const { pageSecs, render, investorsHtml } = sandbox.window.RegretCompany;

function row(n, extra) {
  return Object.assign({
    investor_name: 'Investor ' + n,
    investor_title: 'General Partner',
    summary: 'Summary line ' + n + ' stays a takeaway.',
    quote: 'Exact quote body ' + n + ' is longer than the summary and is not the summary.',
    published_at: '2016-05-30',
    source_url: 'https://a16z.com/quote-' + n,
    role_source_url: 'https://a16z.com/team/investor-' + n,
  }, extra || {});
}
const people = { key: 'people', items: [{ head: 'Marc Andreessen', kind: 'team', role: 'Cofounder and General Partner' }] };
const thesis = { key: 'overview', items: [{ label: 'thesis', value: 'We back technical founders.' }] };

function page(items, checks) {
  return {
    open: true,
    checks: checks || [],
    firm: { name: 'Andreessen Horowitz', slug: 'a16z', short_name: 'a16z' },
    sections: [thesis, { key: 'investors', items }, people],
  };
}
function draw(P) {
  const main = mainEl();
  main.set('.actw', el());
  const pmain = main.set('.pmain', el());
  const spl = main.set('.spl', el());
  const toc = main.set('.toc', el());
  main.set('.m', el());
  render(main, P);
  return { body: pmain.innerHTML, chips: spl.innerHTML, nav: toc.innerHTML };
}
function between(html, start, end) {
  const a = html.indexOf(start);
  const b = end ? html.indexOf(end, a + start.length) : html.length;
  assert.ok(a >= 0 && b > a, start + ' .. ' + end);
  return html.slice(a, b);
}
const count = (html, needle) => (html.match(new RegExp(needle, 'g')) || []).length;

test('no rows: no section, chip, or nav entry', () => {
  for (const items of [
    undefined,
    [],
    [row(1, { summary: '   ', quote: 'A real quote that is not empty.' })],
    [row(1, { quote: 'Summary line 1 stays a takeaway.' })],
    [row(1, { source_url: 'http://a16z.com/not-https' })],
    [row(1, { source_url: 'notaurl' })],
    [row(1, { investor_name: '  ' })],
  ]) {
    const secs = items === undefined
      ? pageSecs({ sections: [thesis, people] })
      : pageSecs(page(items));
    assert.equal(secs.find(s => s.key === 'investors'), undefined);
    const html = draw(items === undefined ? { open: true, checks: [], firm: { name: 'Andreessen Horowitz', slug: 'a16z' }, sections: [thesis, people] } : page(items)).body;
    assert.doesNotMatch(html, /id="investors"|What investors look for|class="ipr"/);
  }
});

test('five or fewer: every summary row, no Show all, no quote', () => {
  for (const n of [1, 5]) {
    const items = Array.from({ length: n }, (_, i) => row(i + 1));
    const html = investorsHtml(items, false);
    assert.equal(count(html, 'class="ipr"'), n);
    assert.equal(count(html, 'class="ipq"'), 0);
    assert.equal(count(html, 'class="ipi"'), n);
    assert.doesNotMatch(html, /Show all|data-investors|Exact quote body/);
    assert.match(html, /Summary line 1 stays a takeaway/);
    assert.match(html, /Investor 1 · General Partner · 2016/);
    assert.doesNotMatch(html, /role_source_url|team\/investor/);
  }
});

test('more than five: five summary rows and Show all, quotes only after it', () => {
  const items = Array.from({ length: 6 }, (_, i) => row(i + 1));
  const closed = investorsHtml(items, false);
  assert.equal(count(closed, 'class="ipr"'), 5);
  assert.equal(count(closed, 'class="ipq"'), 0);
  assert.equal(count(closed, '<button type="button" class="ash" data-investors>'), 1);
  assert.match(closed, />Show all</);
  assert.doesNotMatch(closed, /Show more/);
  const visible = closed.replace(/ data-rows="[^"]*"/, '');
  assert.doesNotMatch(visible, /Investor 6|Exact quote body/);
  assert.match(closed, /data-rows="/);
  const open = investorsHtml(items, true);
  assert.equal(count(open, 'class="ipr"'), 6);
  assert.equal(count(open, 'class="ipq"'), 6);
  assert.equal(count(open, 'class="ipi"'), 6);
  assert.equal(count(open, 'class="ipa"'), 6);
  assert.equal(count(open, 'class="ips"'), 6);
  assert.doesNotMatch(open, /<button|Show all|data-rows|data-investors/);
  assert.match(open, /Investor 6 · General Partner · 2016/);
  assert.match(open, /Exact quote body 6 is longer than the summary and is not the summary/);
  const sixth = open.split('class="ipr"').pop();
  assert.equal(count(sixth, '<a '), 1);
  assert.doesNotMatch(sixth, /a16z\.com\/quote-6[\s\S]*a16z\.com\/quote-6/);
  const quote = sixth.slice(sixth.indexOf('class="ipq"'));
  assert.doesNotMatch(quote, /General Partner|Summary:|2016|https:|class="ipi"|class="ipa"/);
  assert.doesNotMatch(open, /team\/investor/);
});

test('summary and quote stay different, and the source icon is the only link', () => {
  const same = row(1, { summary: 'Same words.', quote: 'Same words.' });
  assert.equal(investorsHtml([same], false), '');
  const html = investorsHtml([row(1, { summary: 'Short takeaway.', quote: '"Short takeaway is not this."' })], false);
  assert.match(html, /Short takeaway\./);
  assert.doesNotMatch(html, /Short takeaway is not this/);
  assert.match(html, /href="https:\/\/a16z\.com\/quote-1" target="_blank" rel="noopener"/);
  assert.match(html, /aria-label="Source"/);
  assert.match(html, /width="12" height="12"/);
  assert.match(html, new RegExp('d="' + iconPath.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '"'));
  assert.equal(count(html, '<a '), 1);
  assert.doesNotMatch(html, /<button|tabindex|onclick|role="button"/);
  assert.match(html, /^<div class="iprs"><div class="ipr">/);
});

test('a row click does nothing; Show all is the control that opens quotes', () => {
  const items = Array.from({ length: 6 }, (_, i) => row(i + 1));
  const handler = clicks.find(fn => {
    let saw = false;
    fn({ target: { closest(sel) { if (sel === 'button[data-investors]') saw = true; return null; } } });
    return saw;
  });
  assert.ok(handler, 'show-all click handler is registered');
  let read = false;
  handler({ target: { closest() { return null; } } });
  const box = {
    parentNode: { html: '' },
    getAttribute(name) { read = true; return name === 'data-rows' ? JSON.stringify(items.map(x => ({
      investor_name: x.investor_name, investor_title: x.investor_title, summary: x.summary,
      quote: x.quote, published_at: x.published_at, source_url: x.source_url,
    }))) : null; },
    closest(sel) { return sel === '.iprs' ? box : null; },
    set outerHTML(v) { this.parentNode.html = v; },
  };
  const button = { closest(sel) { return sel === 'button[data-investors]' ? button : sel === '.iprs' ? box : null; } };
  handler({ target: { closest(sel) { return sel === 'button[data-investors]' ? null : null; } } });
  assert.equal(read, false);
  handler({ target: button });
  assert.equal(read, true);
  const opened = box.parentNode.html;
  assert.equal(count(opened, 'class="ipq"'), 6);
  assert.doesNotMatch(opened, /<button|Show all/);
  assert.match(opened, /Exact quote body 1/);
});

test('the section sits after Thesis and before Team, with no count', () => {
  const items = Array.from({ length: 6 }, (_, i) => row(i + 1));
  const checks = [{ n: 1, title: 'Sanctions', state: 'clear' }];
  const secs = pageSecs(page(items, checks));
  const keys = secs.map(s => s.key);
  assert.deepEqual(keys, ['thesis', 'investors', 'people']);
  const inv = secs.find(s => s.key === 'investors');
  assert.equal(inv.title, 'What investors look for');
  assert.equal(inv.nocount, true);
  assert.equal(inv.subtitle, '');
  assert.equal(inv.count, 6);
  const drawn = draw(page(items, checks));
  const thesisAt = drawn.body.indexOf('id="thesis"');
  const checkAt = drawn.body.indexOf('id="check-summary"');
  const invAt = drawn.body.indexOf('id="investors"');
  const teamAt = drawn.body.indexOf('id="people"');
  assert.ok(thesisAt >= 0 && thesisAt < checkAt && checkAt < invAt && invAt < teamAt);
  const block = between(drawn.body, 'id="investors"', 'id="people"');
  assert.match(block, /<h2>What investors look for<\/h2>/);
  assert.doesNotMatch(block, /<h2>What investors look for <em/);
  assert.equal(count(block, 'class="ipr"'), 5);
  assert.match(block, />Show all</);
  assert.doesNotMatch(drawn.chips, /href="#investors">What investors look for <em/);
  assert.match(drawn.chips, /href="#thesis">Thesis<\/a><a class="spp" href="#investors">What investors look for<\/a>/);
  assert.match(drawn.nav, /href="#thesis">Thesis<\/a><a href="#check-summary">/);
  assert.match(drawn.nav, /href="#investors">What investors look for<\/a><a href="#people">Team<\/a>/);
  assert.equal(copy.sections.list.map(s => s.key).indexOf('investors'), copy.sections.list.map(s => s.key).indexOf('overview') + 1);
  assert.ok(copy.sections.list.map(s => s.key).indexOf('investors') < copy.sections.list.map(s => s.key).indexOf('people'));
  assert.equal(copy.company.activity.show_all, 'Show all');
  assert.equal(copy.company.investors.summary, 'Summary:');
});

test('attribution can wrap and nothing in the row is cropped', () => {
  assert.match(css, /\.ipa\{[^}]*flex-wrap:wrap/);
  assert.match(css, /\.ipwho\{[^}]*overflow-wrap:anywhere/);
  assert.match(css, /\.ips\{[^}]*overflow-wrap:anywhere/);
  assert.match(css, /\.ipq\{[^}]*overflow-wrap:anywhere/);
  assert.match(css, /\.iplab\{[^}]*text-transform:uppercase[^}]*color:var\(--mute\)/);
  assert.match(css, /\.ipi svg\{width:12px;height:12px/);
  assert.doesNotMatch(css, /\.ips\{[^}]*line-clamp|\.ipq\{[^}]*line-clamp|\.ipr\{[^}]*overflow:hidden|\.ipr\{[^}]*cursor:pointer/);
});
