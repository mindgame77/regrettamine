// Activity fund tile: a raised amount stays, a $0 or missing amount uses an earlier fund, else AUM.
// node --test tests/fund_tile.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = (rel) => fs.readFileSync(new URL(rel, root), 'utf8');
const copy = JSON.parse(read('launch/copy.json'));

function el() {
  return {
    hidden: false, innerHTML: '', textContent: '', style: {}, className: '', dataset: {},
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
  main.querySelectorAll = () => [];
  main.set = (sel, child) => { kids[sel] = child; return child; };
  return main;
}

const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement() { return el(); } },
  console,
  URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(read('launch/js/dates.js'), sandbox, { filename: 'dates.js' });
vm.runInContext(read('launch/js/company.js'), sandbox, { filename: 'company.js' });
const { render } = sandbox.window.RegretCompany;

const EDGAR = 'https://www.sec.gov/Archives/edgar/data/1906948/000206235726000016/0002062357-26-000016-index.htm';
const ADV = 'https://reports.adviserinfo.sec.gov/reports/ADV/157373/PDF/157373.pdf';

function paint(extra) {
  const main = mainEl();
  const act = el();
  main.set('.m', el());
  main.set('.ph h1', el());
  main.set('.actw', act);
  const toc = el();
  toc.querySelectorAll = () => [];
  main.set('.toc', toc);
  main.set('.csum', el());
  const lock = el();
  const lockB = el(), lockP = el();
  lock.querySelector = (sel) => sel === 'b' ? lockB : sel === 'p' ? lockP : null;
  main.set('#lockcard', lock);
  main.set('.spl', el());
  main.set('.pmain', el());
  main.set('.rgt-n', el());
  const P = Object.assign({
    open: true,
    firm: { name: 'Sequoia Capital', slug: 'sequoia', hq: 'Menlo Park, CA', short_name: 'Sequoia', website: 'https://sequoiacap.com/' },
    hero: [],
    checks: [],
    sections: [],
    activity: {},
  }, extra);
  render(main, P);
  return act.innerHTML;
}

function tile(html) {
  const m = html.match(/<div class="att afd">([\s\S]*?)<\/div>/);
  return m ? m[0] : '';
}

const sequoiaFunds = {
  key: 'funds',
  items: [
    { label: 'Assets under management', value: '$82.2B · form_adv_raum', src: [{ label: 'SEC IAPD', url: ADV }] },
    { label: 'Funds', value: 'Item 5F regulatory AUM $82,165,771,068; Schedule D lists 60 private funds.', src: [{ label: 'SEC IAPD', url: ADV }] },
    { label: 'Funds', value: 'Regulatory AUM (Form ADV Item 5F) · $106.5B · 2026-09-01', src: [{ label: 'SEC IAPD', url: ADV }] },
    { label: 'Funds', value: 'Sequoia Capital Fund, L.P. · $22.7B · 2026-02-05', src: [{ label: 'SEC EDGAR', url: EDGAR }] },
    { label: 'Funds', value: 'Sequoia Capital Fund Feeder, L.P. · $7.0B · 2026-02-05', src: [{ label: 'SEC EDGAR', url: 'https://www.sec.gov/Archives/edgar/data/1906966/feeder' }] },
    { label: 'Funds', value: 'Sequoia Capital DIV-2026 Principals Fund · 2026-09-28', src: [] },
  ],
};

test('a latest fund that raised money stays the Latest fund tile', () => {
  const html = paint({
    firm: { name: 'Andreessen Horowitz', slug: 'a16z', hq: 'Menlo Park, CA', short_name: 'a16z', website: 'https://a16z.com/', assets: '$106.5B' },
    hero: [{ label: 'Regulatory AUM', value: '$106.5B', src: [{ label: 'SEC IAPD', url: 'https://reports.adviserinfo.sec.gov/reports/ADV/160489/PDF/160489.pdf' }] }],
    sections: [sequoiaFunds],
    activity: { latest_fund: { name: 'a16z Growth Fund V', raised_usd: 8500000000, date: '2026-08-31', url: 'https://a16z.com/expanding-the-a16z-growth-fund-and-platform/' } },
  });
  const fund = tile(html);
  assert.match(fund, /<small>Latest fund<\/small><b>\$8\.5B<\/b>/);
  assert.match(fund, /a16z Growth Fund V · \$8\.5B raised · <a href="https:\/\/a16z\.com\/expanding-the-a16z-growth-fund-and-platform\/"/);
  assert.match(fund, />Filing ↗<\/a>/);
  assert.doesNotMatch(fund, /Feb 5, 2026|Aug 31, 2026|Assets under management|Sequoia Capital Fund/);
});

test('a $0 or missing latest fund uses the most recent earlier fund that raised money', () => {
  for (const raised of [null, 0]) {
    const html = paint({
      sections: [sequoiaFunds],
      hero: [{ label: 'Regulatory AUM', value: '$82.2B', src: [{ label: 'SEC IAPD', url: ADV }] }],
      activity: { latest_fund: { name: 'Sequoia Capital DIV-2026 Principals Fund, L.P.', raised_usd: raised, url: null } },
    });
    const fund = tile(html);
    assert.match(fund, /<small>Latest fund<\/small><b>\$22\.7B<\/b>/);
    assert.match(fund, /Sequoia Capital Fund, L\.P\. · \$22\.7B raised · Feb 5, 2026 · <a href="https:\/\/www\.sec\.gov\/Archives\/edgar\/data\/1906948\/000206235726000016\/0002062357-26-000016-index\.htm"/);
    assert.match(fund, />Filing ↗<\/a>/);
    assert.doesNotMatch(fund, /DIV-2026|\$7\.0B|Assets under management|class="asm"/);
    assert.doesNotMatch(fund, /<b>[^<]*Sequoia Capital Fund/);
  }
  const noLatest = paint({
    sections: [sequoiaFunds],
    activity: { latest_fund: null },
  });
  assert.match(tile(noLatest), /<b>\$22\.7B<\/b>/);
  assert.match(tile(noLatest), /Sequoia Capital Fund, L\.P\./);
});

test('when no fund raised money the tile is assets under management, and nothing when that is missing too', () => {
  assert.equal(copy.company.activity.aum, 'Assets under management');
  const html = paint({
    firm: { name: 'Sequoia Capital', slug: 'sequoia', assets: '$82,165,771,068' },
    hero: [{ label: 'HQ', value: 'Menlo Park, CA' }, { label: 'Regulatory AUM', value: '$82.2B', src: [{ label: 'SEC IAPD', url: ADV }] }, { label: 'Fund gross assets', value: '$1.0B gross assets', src: [{ label: 'SEC', url: ADV }] }],
    sections: [{ key: 'funds', items: [{ label: 'Funds', value: 'Sequoia Capital DIV-2026 Principals Fund · 2026-09-28', src: [] }] }],
    activity: { latest_fund: { name: 'Sequoia Capital DIV-2026 Principals Fund, L.P.', raised_usd: null } },
  });
  const fund = tile(html);
  assert.match(fund, /<small>Assets under management<\/small><b>\$82\.2B<\/b>/);
  assert.match(fund, new RegExp('href="' + ADV.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '"'));
  assert.match(fund, />SEC IAPD ↗<\/a>/);
  assert.doesNotMatch(fund, /DIV-2026|Latest fund|Sequoia Capital Fund|class="asm"|\$1\.0B/);
  const fromAssets = paint({
    firm: { name: 'Lightspeed', slug: 'lightspeed', assets: '$82,165,771,068' },
    activity: {},
  });
  assert.match(tile(fromAssets), /<small>Assets under management<\/small><b>\$82\.17B<\/b>/);
  const none = paint({
    firm: { name: 'Greenoaks', slug: 'greenoaks' },
    activity: { latest_fund: { name: 'Empty Fund, L.P.', raised_usd: 0 } },
  });
  assert.equal(tile(none), '');
  assert.doesNotMatch(none, /Empty Fund|Assets under management|Latest fund/);
  const other = paint({
    firm: { name: 'Other', slug: 'other-firm', assets: '$82,165,771,068' },
    hero: [{ label: 'Regulatory AUM', value: '$82.2B', src: [{ label: 'SEC IAPD', url: ADV }] }],
    sections: [sequoiaFunds],
    activity: { latest_fund: { name: 'Other Fund, L.P.', raised_usd: null } },
  });
  const old = tile(other);
  assert.match(old, /<small>Latest fund<\/small><b><span class="asm">Other Fund<\/span><\/b>/);
  assert.match(old, /<span>Other Fund<\/span>/);
  assert.doesNotMatch(old, /Assets under management|\$22\.7B|\$82\.2B/);
});
