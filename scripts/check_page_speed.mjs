// Times firm_page for every live firm (firm_sitemap) as anon via firm_page_speed (rolled back, records nothing).
// REGRET_FIRMS overrides that list for a manual run. Fails if any firm exceeds LIMIT_MS (default 2000). Never prints the key.
const URL_ = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const KEY = process.env.SUPABASE_ANON_KEY || '';
const LIMIT = Number(process.env.PAGE_SPEED_LIMIT_MS || 2000);
if (!URL_ || !KEY) { console.error('page speed: SUPABASE_URL / SUPABASE_ANON_KEY not set'); process.exit(1); }
async function firmSlugs() {
  const fromEnv = (process.env.REGRET_FIRMS || '').split(',').map((s) => s.trim()).filter(Boolean);
  if (fromEnv.length) return fromEnv;
  const slugs = [];
  for (let page = 1; ; page++) {
    const r = await fetch(URL_ + '/rest/v1/rpc/firm_sitemap', {
      method: 'POST',
      headers: { apikey: KEY, Authorization: 'Bearer ' + KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_page: page, p_size: 1000 }),
    });
    if (!r.ok) { console.error('page speed: firm_sitemap HTTP ' + r.status); process.exit(1); }
    const rows = await r.json();
    if (!Array.isArray(rows)) { console.error('page speed: firm_sitemap did not return a list'); process.exit(1); }
    for (const row of rows) if (row && row.slug) slugs.push(row.slug);
    if (rows.length < 1000) break;
  }
  if (!slugs.length) { console.error('page speed: firm_sitemap returned no firms'); process.exit(1); }
  return slugs;
}
const FIRMS = await firmSlugs();
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
