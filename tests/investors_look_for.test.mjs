// What investors look for: after Thesis, before Team. Five summary rows.
// Show all opens the same list popup as the other sections, with every quote.
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
const made = {};
function el() {
  return {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', id: '', dataset: {},
    classList: { toggle() {}, add() {}, remove() {} },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute() {},
    remove() {},
    insertAdjacentElement() { return null; },
    getAttribute() { return null; },
  };
}
function resetModals() { for (const k of Object.keys(made)) delete made[k]; }
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
    body: { appendChild(n) { made[n.id] = n; } },
    addEventListener(type, fn) { if (type === 'click') clicks.push(fn); },
    getElementById(id) { return made[id] || null; },
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

function page(items, checks, extra) {
  return {
    open: true,
    checks: checks || [],
    firm: { name: 'Andreessen Horowitz', slug: 'a16z', short_name: 'a16z' },
    sections: [thesis, { key: 'investors', items }, people].concat(extra || []),
  };
}
function popup(id) {
  const ov = made[id];
  assert.ok(ov, id + ' popup');
  assert.equal(ov.className, 'ov tall');
  assert.equal(ov.hidden, true);
  assert.match(ov.innerHTML, /class="md w amd" role="dialog" aria-modal="true"/);
  assert.match(ov.innerHTML, /<button class="x" data-close aria-label="Close">/);
  assert.match(ov.innerHTML, /<div class="amh">/);
  assert.match(ov.innerHTML, /<div class="amb">/);
  return ov.innerHTML;
}
function draw(P) {
  resetModals();
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

const openPage = { open: true, firm: { name: 'Andreessen Horowitz', slug: 'a16z' } };
function quotesInPopup(items) {
  resetModals();
  const pageHtml = investorsHtml(items, openPage);
  const open = popup('actinvestors');
  return { pageHtml, open };
}

test('one row and five rows: summaries on the page, quotes only in the shared popup', () => {
  for (const n of [1, 5]) {
    const items = Array.from({ length: n }, (_, i) => row(i + 1));
    const { pageHtml, open } = quotesInPopup(items);
    assert.equal(count(pageHtml, 'class="ipr"'), n);
    assert.equal(count(pageHtml, 'class="ipq"'), 0);
    assert.equal(count(pageHtml, 'class="ipi"'), n);
    assert.equal(count(pageHtml, '<button type="button" class="ash" data-open="actinvestors">'), 1);
    assert.match(pageHtml, />Show all</);
    assert.doesNotMatch(pageHtml, /Exact quote body|data-rows|data-investors|Show more/);
    assert.match(pageHtml, /Summary line 1 stays a takeaway/);
    assert.match(pageHtml, /Investor 1 · General Partner · 2016/);
    assert.doesNotMatch(pageHtml, /role_source_url|team\/investor/);
    assert.equal(count(open, 'class="ipr"'), n);
    assert.equal(count(open, 'class="ipq"'), n);
    assert.equal(count(open, 'class="ips"'), n);
    assert.equal(count(open, 'class="ipi"'), n);
    assert.match(open, /aria-label="What investors look for"/);
    assert.match(open, /<b>What investors look for<\/b>/);
    assert.doesNotMatch(open, /Show all|data-rows|data-investors|<em/);
    assert.match(open, /Summary line 1 stays a takeaway/);
    assert.match(open, /Exact quote body 1 is longer than the summary and is not the summary/);
    const parts = open.split('class="ipr"').slice(1);
    assert.equal(parts.length, n);
    const first = parts[0];
    assert.equal(count(first, '<a '), 1);
    const quote = first.slice(first.indexOf('class="ipq"'));
    assert.doesNotMatch(quote, /General Partner|Summary:|2016|https:|class="ipi"|class="ipa"/);
  }
});

test('twelve rows: five on the page, all twelve quotes in the popup', () => {
  const long = 'Word '.repeat(400) + 'tail-of-the-quote';
  const items = Array.from({ length: 12 }, (_, i) => row(i + 1, i === 11 ? { quote: long } : {}));
  const { pageHtml, open } = quotesInPopup(items);
  assert.equal(count(pageHtml, 'class="ipr"'), 5);
  assert.equal(count(pageHtml, 'class="ipq"'), 0);
  assert.equal(count(pageHtml, '<button type="button" class="ash" data-open="actinvestors">'), 1);
  assert.match(pageHtml, />Show all</);
  assert.doesNotMatch(pageHtml, /Show more|data-rows|data-investors|Investor 6|Exact quote body|tail-of-the-quote/);
  assert.equal(count(open, 'class="ipr"'), 12);
  assert.equal(count(open, 'class="ipq"'), 12);
  assert.equal(count(open, 'class="ipi"'), 12);
  assert.equal(count(open, 'class="ipa"'), 12);
  assert.equal(count(open, 'class="ips"'), 12);
  assert.doesNotMatch(open, /<button type="button" class="ash"|Show all|data-rows|data-investors/);
  assert.match(open, /Investor 12 · General Partner · 2016/);
  assert.match(open, /tail-of-the-quote/);
  const twelfth = open.split('class="ipr"').pop();
  assert.equal(count(twelfth, '<a '), 1);
  assert.match(twelfth, /href="https:\/\/a16z\.com\/quote-12" target="_blank" rel="noopener"/);
  assert.doesNotMatch(twelfth, /a16z\.com\/quote-12[\s\S]*a16z\.com\/quote-12/);
  const quote = twelfth.slice(twelfth.indexOf('class="ipq"'));
  assert.doesNotMatch(quote, /General Partner|Summary:|2016|https:|class="ipi"|class="ipa"/);
  assert.doesNotMatch(open, /team\/investor/);
});

test('summary and quote stay different, and the source icon is the only link', () => {
  const same = row(1, { summary: 'Same words.', quote: 'Same words.' });
  assert.equal(investorsHtml([same], openPage), '');
  resetModals();
  const html = investorsHtml([row(1, { summary: 'Short takeaway.', quote: '"Short takeaway is not this."' })], openPage);
  assert.match(html, /Short takeaway\./);
  assert.doesNotMatch(html, /Short takeaway is not this/);
  assert.match(html, /href="https:\/\/a16z\.com\/quote-1" target="_blank" rel="noopener"/);
  assert.match(html, /aria-label="Source"/);
  assert.match(html, /width="12" height="12"/);
  assert.match(html, new RegExp('d="' + iconPath.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '"'));
  assert.equal(count(html, '<a '), 1);
  assert.equal(count(html, '<button type="button" class="ash" data-open="actinvestors">'), 1);
  assert.doesNotMatch(html, /tabindex|onclick|role="button"|data-rows|data-investors/);
  assert.match(html, /^<div class="iprs"><div class="ipr">/);
  const open = popup('actinvestors');
  assert.match(open, /Short takeaway is not this/);
  assert.equal(count(open, '<a '), 1);
});

test('nothing on the page expands a row; Show all is the shared popup', () => {
  assert.doesNotMatch(read('launch/js/company.js'), /data-investors|data-rows/);
  const caught = clicks.some(fn => {
    let saw = false;
    try {
      fn({ target: { closest(sel) { if (sel === 'button[data-investors]') saw = true; return null; }, classList: {} } });
    } catch (err) { /* other listeners expect a fuller event */ }
    return saw;
  });
  assert.equal(caught, false);
  const items = Array.from({ length: 6 }, (_, i) => row(i + 1));
  const drawn = draw(page(items));
  const block = between(drawn.body, 'id="investors"', 'id="people"');
  assert.equal(count(block, 'class="ipr"'), 5);
  assert.equal(count(block, 'class="ipq"'), 0);
  assert.match(block, /data-open="actinvestors">Show all<\/button>/);
  assert.doesNotMatch(block, /Exact quote body/);
  const open = popup('actinvestors');
  assert.equal(count(open, 'class="ipq"'), 6);
  assert.match(open, /Exact quote body 1/);
});

test('investor Show all uses the same popup shell as the other lists', () => {
  const items = Array.from({ length: 12 }, (_, i) => row(i + 1));
  const lps = Array.from({ length: 7 }, (_, i) => ({ label: 'Endowment ' + i, value: '$' + (i + 1) + 'M', src: [{ label: 'Report', url: 'https://example.org/' + i + '.pdf' }] }));
  const press = Array.from({ length: 7 }, (_, i) => ({ head: 'Story ' + i, outlet: 'News', url: 'https://example.org/n' + i, date: '2024-01-0' + ((i % 9) + 1), snippet: 'A line.' }));
  draw(page(items, [], [{ key: 'lps', items: lps }, { key: 'press', items: press }]));
  for (const id of ['actinvestors', 'actlps', 'actnews']) {
    const html = popup(id);
    assert.match(html, /role="dialog" aria-modal="true"/);
    assert.match(html, /data-close/);
  }
  assert.equal(count(popup('actinvestors'), 'class="ipq"'), 12);
  assert.equal(count(popup('actlps'), 'class="rw lpl"'), 7);
  assert.equal(count(popup('actnews'), 'class="pi '), 7);
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
