// "· Founded 1972" at the end of the firm header meta line; nothing when firms.founded_year is empty.
// node --test tests/founded_year.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const copy = JSON.parse(fs.readFileSync(new URL('launch/copy.json', root), 'utf8'));
const sandbox = { window: { REGRET: { copy } }, document: { addEventListener() {}, getElementById() { return null; } }, console, URL };
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(new URL('launch/js/dates.js', root), 'utf8'), sandbox, { filename: 'dates.js' });
vm.runInContext(fs.readFileSync(new URL('launch/js/company.js', root), 'utf8'), sandbox, { filename: 'company.js' });
const { metaLine } = sandbox.window.RegretCompany;
const firm = (x) => ({ firm: Object.assign({ name: 'Sequoia Capital', hq: 'Menlo Park, CA', website: 'https://www.sequoiacap.com/' }, x) });

test('founded year goes last, after the website link', () => {
  const m = metaLine(firm({ founded_year: 1972 }));
  assert.match(m, /<\/a> · Founded 1972$/);
  assert.equal(copy.company.header.founded, 'Founded {y}');
});

test('no founded year, no text and no extra separator', () => {
  for (const y of [null, undefined, '', 0, 'abc', 3000]) {
    const m = metaLine(firm({ founded_year: y }));
    assert.doesNotMatch(m, /Founded/);
    assert.doesNotMatch(m, / · $/);
  }
  assert.equal(metaLine({ firm: { founded_year: 2009 } }), 'Founded 2009');
});
