// A click in the firm-page search box must not be treated as the Checks / Full toggle.
// main carries data-tab as the panel that is showing. closest() matches that on every click,
// and cancelling the click stops Check from submitting and stops a suggestion link from opening.
// node --test tests/search_nav.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const src = fs.readFileSync(new URL('../launch/js/app.js', import.meta.url), 'utf8');
const m = src.match(/function firmPageTab\(target, root\) \{[\s\S]*?\n  \}/);
if (!m) throw new Error('firmPageTab is missing from launch/js/app.js');
const firmPageTab = new Function('target', 'root', m[0].slice(m[0].indexOf('{') + 1, m[0].lastIndexOf('}')));

function el(dataset, parent) {
  const node = {
    dataset: dataset || {},
    parent,
    closest(sel) {
      let n = this;
      while (n) {
        if (sel.split(',').some(part => {
          const hit = part.trim().match(/^\[data-tab="([^"]+)"\]$/);
          return hit && n.dataset.tab === hit[1];
        })) return n;
        n = n.parent;
      }
      return null;
    },
    contains(other) {
      let n = other;
      while (n) { if (n === this) return true; n = n.parent; }
      return false;
    },
  };
  return node;
}

const main = el({ tab: 'checks' }, null);
const form = el({}, main);
const input = el({}, form);
const check = el({}, form);
const suggestion = el({}, form);
const fullTab = el({ tab: 'full' }, main);
const checksLink = el({ tab: 'checks' }, main);

test('typing into search and pressing Check is not a tab click', () => {
  assert.equal(firmPageTab(check, main), '');
  assert.equal(firmPageTab(input, main), '');
  assert.equal(firmPageTab(suggestion, main), '');
  assert.equal(firmPageTab(main, main), '');
});

test('the Checks and Full controls still switch panels', () => {
  assert.equal(firmPageTab(fullTab, main), 'full');
  assert.equal(firmPageTab(checksLink, main), 'checks');
});

test('the page click handler uses firmPageTab and only cancels a real tab control', () => {
  assert.match(src, /const which = firmPageTab\(e\.target, main\);\s*if \(which\) \{ e\.preventDefault\(\); goTab\(which\); return; \}/);
});
