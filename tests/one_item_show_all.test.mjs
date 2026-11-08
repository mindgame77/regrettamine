// One grey card still gets Show all and its popup. The same builder runs for every firm.
// node --test tests/one_item_show_all.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));
const css = read('launch/style.css');
const src = read('launch/js/company.js');

const made = {};
function el() {
  return {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', id: '', dataset: {},
    classList: { toggle() {}, add() {}, remove() {} },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    appendChild() {},
    setAttribute() {},
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
    body: { appendChild(n) { made[n.id] = n; } },
    addEventListener() {},
    getElementById(id) { return made[id] || null; },
    createElement() { const e = el(); return e; },
  },
  console, URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(src, sandbox, { filename: 'company.js' });
const { render } = sandbox.window.RegretCompany;

function draw(slug, extra) {
  for (const k of Object.keys(made)) delete made[k];
  const main = mainEl();
  main.set('.actw', el());
  const pmain = main.set('.pmain', el());
  main.set('.m', el());
  main.set('.toc', el());
  main.set('.csum', el());
  main.set('.spl', el());
  main.set('.rgt-n', el());
  const lock = el();
  lock.querySelector = () => el();
  main.set('#lockcard', lock);
  const P = Object.assign({
    open: true,
    firm: { name: slug, slug, hq: 'City', short_name: slug, website: 'https://example.com/' },
    hero: [],
    checks: [],
    sections: [],
    activity: {},
  }, extra);
  render(main, P);
  return pmain.innerHTML;
}

const review = {
  author: 'Bipul Sinha', role: 'Co-Founder', company: 'Rubrik', date: '2026',
  url: 'https://lsvp.com/stories/rubrik/', quote: 'Lightspeed helped us tremendously in validating our idea', tone: 'neu',
};
const investor = {
  investor_name: 'Ravi Mhatre', investor_title: 'Partner & Co-Founder',
  summary: 'Looks for people who solve problems.',
  quote: 'A longer exact quote that is not the summary.',
  published_at: '2024-01-01', source_url: 'https://lsvp.com/quote',
};
const legal = {
  grp: 'case', title: 'Example v. Lightspeed', year: '2024', state: 'Active', status: 'Active',
  src: [{ label: 'CourtListener', url: 'https://www.courtlistener.com/docket/1/x/' }],
};
const person = { head: 'Ravi Mhatre', kind: 'team', role: 'Partner & Co-Founder', x_url: 'https://x.com/ravi_lsvp', x_followers: 10400 };

test('Option A team rows are one shared rule, not a firm list', () => {
  const rule = css.slice(css.indexOf('#team .tcard{'));
  assert.match(rule, /#team \.tcard\{flex-direction:row/);
  assert.doesNotMatch(css, /lightspeed|sequoia|a16z/);
  assert.doesNotMatch(src, /slug === ['"]lightspeed|slug === ['"]sequoia|slug === ['"]a16z/);
});

test('one review on any firm gets Show all and the founders popup', () => {
  for (const slug of ['lightspeed', 'sequoia', 'a16z']) {
    const html = draw(slug, { activity: { reviews: [review], counts: { reviews: 1 } } });
    const block = html.slice(html.indexOf('id="reviews"'));
    assert.match(block, /class="arv /, slug);
    assert.match(block, /data-open="actrevs">Show all<\/button>/, slug);
    const ov = made.actrevs;
    assert.ok(ov, slug + ' popup');
    assert.match(ov.innerHTML, /Lightspeed helped us tremendously/);
  }
});

test('one investor row and one legal case get Show all on a non-Sequoia firm', () => {
  const html = draw('lightspeed', {
    sections: [
      { key: 'investors', items: [investor] },
      { key: 'legal', items: [legal] },
      { key: 'people', items: [person] },
    ],
  });
  assert.match(html, /id="investors"[\s\S]*data-open="actinvestors">Show all<\/button>/);
  assert.match(html, /id="legal"[\s\S]*data-open="actlegal">Show all<\/button>/);
  assert.match(html, /id="team"[\s\S]*class="tcard"><b>Ravi Mhatre<\/b><span class="trole">Partner &amp; Co-Founder<\/span>/);
  assert.ok(made.actinvestors && made.actlegal);
});

test('the row fitter does not hide Show all on those three tiles', () => {
  const fn = src.slice(src.indexOf('function fillCard'), src.indexOf('function fillTiles'));
  assert.match(fn, /card\.id === 'legal' && card\.id === 'investors' && card\.id === 'reviews'|card\.id === 'legal' \|\| card\.id === 'investors' \|\| card\.id === 'reviews'/);
  assert.match(fn, /keepShow \? false : !more/);
});
