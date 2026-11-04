// E2.1/E2.2/E4.2: v2_firm_page must return kind=partner rows with joined_year and left_year.
// node --test tests/partner_years.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const root = new URL('../', import.meta.url);
const mig = fs.readFileSync(new URL('supabase/migrations/20261104235000_v2_firm_page_partner_years.sql', root), 'utf8');
const undo = fs.readFileSync(new URL('supabase/rollbacks/20261104235000_v2_firm_page_partner_years_undo.sql', root), 'utf8');
const js = fs.readFileSync(new URL('launch/js/company.js', root), 'utf8');

test('migration adds partner rows and years to the people section', () => {
  assert.match(mig, /'joined_year',r\.joined_year,'left_year',r\.left_year/);
  assert.match(mig, /r\.kind in \('officer','partner'\)/);
  assert.match(mig, /raise exception/);
});

test('undo restores officer-only, no years', () => {
  assert.match(undo, /\$q\$r\.kind='officer' and r\.is_current\$q\$\);/);
});

test('company.js reads joined_year / left_year, no turnover line, no arrows on cards', () => {
  assert.match(js, /x\.joined_year/);
  assert.match(js, /x\.left_year/);
  const card = js.slice(js.indexOf('function partnerCard'), js.indexOf('function personSection'));
  assert.doesNotMatch(card, /[↑↓→←]|turnover/i);
});
