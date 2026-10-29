// Social pills under the firm meta line: compact counts, one pill per account, hidden row when there is no data.
// node --test tests/social_pills.test.mjs
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
const { compactCount, socialPills } = sandbox.window.RegretCompany;

test('compact count: at most 3 significant digits, half up', () => {
  const cases = [[412345, '412K'], [42300, '42.3K'], [4230, '4.23K'], [1234567, '1.23M'], [999, '999'], [0, '0'], [1000, '1K'],
    [96980, '97K'], [133093, '133K'], [27893, '27.9K'], [4235, '4.24K'], [999500, '1M'], [999499, '999K'], [1500000000, '1.5B']];
  for (const [n, s] of cases) assert.equal(compactCount(n), s, String(n));
  assert.equal(compactCount(-1), '');
  assert.equal(compactCount('x'), '');
});

test('one linked pill per account with logo, aria-label and title; count only', () => {
  const html = socialPills({ firm: { social: [
    { platform: 'linkedin', url: 'https://www.linkedin.com/company/example', followers: 412345 },
    { platform: 'x', url: 'https://x.com/example', followers: 1234567 },
  ] } });
  assert.equal((html.match(/<a class="sc soc"/g) || []).length, 2);
  assert.match(html, /href="https:\/\/www\.linkedin\.com\/company\/example"[^>]*aria-label="LinkedIn: 412K" title="LinkedIn"><svg[^>]*aria-hidden="true"/);
  assert.match(html, /aria-label="X: 1.23M" title="X">.*<b>1.23M<\/b>/);
  assert.doesNotMatch(html, /follower/i);
});

test('no data, unknown platform or bad url: nothing drawn', () => {
  assert.equal(socialPills({ firm: {} }), '');
  assert.equal(socialPills({ firm: { social: [] } }), '');
  assert.equal(socialPills({ firm: { social: [{ platform: 'myspace', url: 'https://myspace.com/a', followers: 5 },
    { platform: 'x', url: 'javascript:alert(1)', followers: 5 }, { platform: 'x', url: 'https://x.com/a', followers: null }] } }), '');
});

test('substack pill: orange logo, name from copy.json, rounded count', () => {
  const html = socialPills({ firm: { social: [{ platform: 'substack', url: 'https://a16z.substack.com', followers: 280000 }] } });
  assert.equal((html.match(/<a class="sc soc"/g) || []).length, 1);
  assert.match(html, /href="https:\/\/a16z\.substack\.com"[^>]*aria-label="Substack: 280K" title="Substack"><svg[^>]*aria-hidden="true"[^>]*><path fill="#FF6719"/);
  assert.match(html, /<b>280K<\/b><\/a>$/);
  assert.equal(copy.company.header.social.names.substack, 'Substack');
});

test('regional pill: same pill style, labelled with its region (A15.7); main pill unchanged', () => {
  const main = { platform: 'x', url: 'https://twitter.com/lightspeedvp', followers: 132952 };
  const before = socialPills({ firm: { social: [main] } });
  const html = socialPills({ firm: { social: [main, { platform: 'x', url: 'https://twitter.com/LightspeedIndia', followers: 25873, region: 'India' }] } });
  assert.equal((html.match(/<a class="sc soc"/g) || []).length, 2);
  assert.ok(html.startsWith(before));
  assert.match(html, /href="https:\/\/twitter\.com\/LightspeedIndia"[^>]*aria-label="X · India: 25.9K" title="X · India"><svg[^>]*>.*<\/svg>India <b>25.9K<\/b><\/a>$/);
  assert.equal(copy.company.header.social.regional, '{platform} · {region}');
});

test('rounded count displays like any count (A15.6)', () => {
  const a = socialPills({ firm: { social: [{ platform: 'youtube', url: 'https://www.youtube.com/@a16z', followers: 20100, rounded: true }] } });
  const b = socialPills({ firm: { social: [{ platform: 'youtube', url: 'https://www.youtube.com/@a16z', followers: 20100 }] } });
  assert.equal(a, b);
  assert.match(a, /<b>20.1K<\/b>/);
});
