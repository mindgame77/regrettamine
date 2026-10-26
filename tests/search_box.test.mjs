// The firm page writes its name into the search box when the page draws.
// A query the visitor has already typed must stay, or Check never leaves this firm.
// node --test tests/search_box.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const copy = JSON.parse(fs.readFileSync(new URL('launch/copy.json', root), 'utf8'));
const sandbox = {
  window: { REGRET: { copy } },
  document: { addEventListener() {}, getElementById() { return null; }, createElement() { return {}; } },
  console,
  URL,
};
sandbox.window.window = sandbox.window;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(new URL('launch/js/dates.js', root), 'utf8'), sandbox, { filename: 'dates.js' });
vm.runInContext(fs.readFileSync(new URL('launch/js/company.js', root), 'utf8'), sandbox, { filename: 'company.js' });
const { setFirmName } = sandbox.window.RegretCompany;

function page(value, def) {
  const input = { value, defaultValue: def };
  const h1 = { textContent: 'Old', querySelector() { return null; } };
  const main = {
    querySelector(sel) {
      if (sel === '.ph h1') return h1;
      if (sel === 'form[data-search] input[name=q]') return input;
      return null;
    },
  };
  return { main, input, h1 };
}

test('a paint still fills the search box when the visitor has not typed', () => {
  const p = page('Andreessen Horowitz', 'Andreessen Horowitz');
  setFirmName(p.main, 'Andreessen Horowitz');
  assert.equal(p.input.value, 'Andreessen Horowitz');
  assert.equal(p.input.defaultValue, 'Andreessen Horowitz');
  assert.equal(p.h1.textContent, 'Andreessen Horowitz');
});

test('a paint leaves y com in the box on a firm page', () => {
  const p = page('y com', 'Andreessen Horowitz');
  setFirmName(p.main, 'Andreessen Horowitz');
  assert.equal(p.input.value, 'y com');
  assert.equal(p.input.defaultValue, 'Andreessen Horowitz');
  assert.equal(p.h1.textContent, 'Andreessen Horowitz');
});
