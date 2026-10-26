// The firm page updates its heading. It does not own the search box.
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

function page(value) {
  const input = { value, defaultValue: 'Andreessen Horowitz' };
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

test('a firm-page paint updates the heading and leaves the search box alone', () => {
  const typed = page('y com');
  setFirmName(typed.main, 'Andreessen Horowitz');
  assert.equal(typed.h1.textContent, 'Andreessen Horowitz');
  assert.equal(typed.input.value, 'y com');
  assert.equal(typed.input.defaultValue, 'Andreessen Horowitz');

  const fresh = page('Andreessen Horowitz');
  setFirmName(fresh.main, 'Andreessen Horowitz');
  assert.equal(fresh.input.value, 'Andreessen Horowitz');
});
