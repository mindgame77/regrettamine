// Times firm_page for the 10 lab firms as anon via firm_page_speed (rolled back, records nothing).
// Fails if any firm exceeds LIMIT_MS (default 2000). Never prints the key.
const URL_ = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const KEY = process.env.SUPABASE_ANON_KEY || '';
const LIMIT = Number(process.env.PAGE_SPEED_LIMIT_MS || 2000);
const FIRMS = (process.env.REGRET_FIRMS || 'a16z,y-combinator,sequoia,lightspeed,generalcatalyst,plugandplay,accel,greenoaks,khosla-ventures,mio-partners').split(',');
if (!URL_ || !KEY) { console.error('page speed: SUPABASE_URL / SUPABASE_ANON_KEY not set'); process.exit(1); }
let bad = 0;
for (const slug of FIRMS) {
  const t = Date.now();
  const r = await fetch(URL_ + '/rest/v1/rpc/firm_page_speed', {
    method: 'POST',
    headers: { apikey: KEY, Authorization: 'Bearer ' + KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_slug: slug }),
  });
  const rt = Date.now() - t;
  if (!r.ok) { console.log(`${slug}: HTTP ${r.status}`); bad++; continue; }
  const ms = Number(await r.json());
  const ok = ms <= LIMIT;
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'SLOW'} ${slug}: firm_page ${ms} ms (round trip ${rt} ms, limit ${LIMIT})`);
}
if (bad) { console.error(`page speed: ${bad} firm(s) failed`); process.exit(1); }
console.log('page speed: all firms under limit');
