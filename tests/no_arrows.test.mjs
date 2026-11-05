// Standing rule: no arrows anywhere on the site (launch JS + copy).
// node --test tests/no_arrows.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
// ↓ ↑ → ↗ ← and common HTML-entity spellings of those arrows
const ARROW_RE = /[↓↑→↗←]|&(?:darr|uarr|rarr|nearr|larr);|&#(?:x)?0*219[0-7]\b|&#(?:8592|8593|8594|8595|8599);/i;

function walkFiles(dir, out = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walkFiles(p, out);
    else out.push(p);
  }
  return out;
}

test('launch/js and launch/copy.json contain no arrow characters or entities', () => {
  const targets = [
    ...walkFiles(path.join(root, 'launch/js')).filter((p) => /\.(js|mjs|json|html)$/i.test(p)),
    path.join(root, 'launch/copy.json'),
  ];
  const hits = [];
  for (const file of targets) {
    const text = fs.readFileSync(file, 'utf8');
    text.split(/\n/).forEach((line, i) => {
      if (ARROW_RE.test(line)) {
        hits.push(path.relative(root, file) + ':' + (i + 1) + ':' + line.trim().slice(0, 120));
      }
    });
  }
  assert.equal(hits.length, 0, 'arrows found:\n' + hits.join('\n'));
});
