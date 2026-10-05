/* Landing list. Data is injected by the build from data/home.json. */
const HOME = JSON.parse(document.getElementById('home-data').textContent);
const VCS = HOME.funds;
const STATS = HOME.stats;
const UPD = HOME.updates;

const BANDS = FundList.BANDS;
const SIZES = [
  ['u', 'Under $100M', a => typeof a == 'number' && a < 0.1],
  ['s', '$100M–$1B', a => typeof a == 'number' && a >= 0.1 && a < 1],
  ['m', '$1B–$10B', a => typeof a == 'number' && a >= 1 && a < 10],
  ['l', '$10B+', a => typeof a == 'number' && a >= 10]
];
const S = {q: '', band: new Set(), size: new Set(), legal: false, recent: false, min: 0, max: 100, sort: 'score'};
function updatedWithin30(f, today) {
  const raw = String((f && (f.updated || f.updatedTs)) || '').slice(0, 10);
  const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (!parts) return false;
  const updated = Date.UTC(+parts[1], +parts[2] - 1, +parts[3]);
  const now = today || new Date();
  const day = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  const days = Math.round((day - updated) / 86400000);
  return days >= 0 && days <= 30;
}
const $ = id => document.getElementById(id);
function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

function match(f, skip) {
  if (skip != 'q' && S.q && !(f.name + ' ' + (f.short || '')).toLowerCase().includes(S.q.toLowerCase())) return false;
  if (skip != 'band' && S.band.size && !S.band.has(f.band)) return false;
  if (skip != 'range' && (f.score < S.min || f.score > S.max)) return false;
  if (skip != 'size' && S.size.size && !SIZES.some(z => S.size.has(z[0]) && z[2](f.aum))) return false;
  if (skip != 'legal' && S.legal && !f.legal) return false;
  if (skip != 'recent' && S.recent && !updatedWithin30(f)) return false;
  return true;
}
function listFiltered() {
  return S.band.size || S.size.size || S.legal || S.recent || S.min > 0 || S.max < 100;
}
function chipGroup(el, items, set, key, test, extra) {
  $(el).innerHTML = items.map(it => {
    const n = VCS.filter(f => match(f, key) && test(f, it)).length;
    return `<span class="chip${set.has(it[0]) ? ' on' : ''}${n ? '' : ' zero'}" data-k="${it[0]}">${extra ? extra(it) : ''}${it[1]} <span class="n">${n}</span></span>`;
  }).join('');
  $(el).querySelectorAll('.chip').forEach(c => c.onclick = () => {
    const k = c.dataset.k;
    set.has(k) ? set.delete(k) : set.add(k);
    render();
  });
}
function render() {
  chipGroup('fBand', BANDS, S.band, 'band', (f, it) => f.band == it[0], it => `<span class="sw" style="background:${it[2]}"></span>`);
  chipGroup('fSize', SIZES, S.size, 'size', (f, it) => it[2](f.aum));
  $('fLegal').classList.toggle('on', S.legal);
  $('fRecent').classList.toggle('on', S.recent);
  const lo = Math.min(S.min, S.max), hi = Math.max(S.min, S.max);
  $('rfill').style.left = lo + '%';
  $('rfill').style.width = (hi - lo) + '%';
  $('rvTxt').textContent = lo + '–' + hi;
  let nameOnly = [];
  let L;
  if (S.q && searchHits) {
    const filtering = listFiltered();
    const detailed = searchHits.filter(f => f.score != null);
    nameOnly = filtering ? [] : searchHits.filter(f => f.score == null);
    L = detailed.filter(f => match(f, 'q'));
  } else {
    L = VCS.filter(f => match(f));
  }
  const cmp = {
    score: (a, b) => b.score - a.score || a.name.localeCompare(b.name),
    name: (a, b) => a.name.localeCompare(b.name),
    aum: (a, b) => b.aum - a.aum,
    upd: (a, b) => b.updatedTs.localeCompare(a.updatedTs) || a.name.localeCompare(b.name)
  }[S.sort];
  L.sort(cmp);
  const total = (catalog && catalog.total) || HOME.fundTotal || VCS.length;
  $('cnt').innerHTML = FundList.countHtml(L.length + nameOnly.length, total);
  const A = [];
  if (S.q) A.push(['q', '“' + S.q + '”']);
  S.band.forEach(b => A.push(['band:' + b, b]));
  if (S.min > 0 || S.max < 100) A.push(['range', 'Score ' + lo + '–' + hi]);
  S.size.forEach(s => A.push(['size:' + s, 'Firm AUM ' + SIZES.find(z => z[0] == s)[1]]));
  if (S.legal) A.push(['legal', 'Has active legal matters']);
  if (S.recent) A.push(['recent', 'Updated in the last 30 days']);
  $('active').innerHTML = A.length
    ? A.map(a => `<span class="ac">${a[1]}<i data-x="${a[0]}">×</i></span>`).join('') + '<span class="clr" id="clr">Clear all</span>'
    : '';
  $('active').querySelectorAll('[data-x]').forEach(x => x.onclick = () => {
    const [k, v] = x.dataset.x.split(':');
    if (k == 'q') { S.q = ''; $('q').value = ''; $('hq').value = ''; }
    else if (k == 'range') { S.min = 0; S.max = 100; $('smin').value = 0; $('smax').value = 100; }
    else if (k == 'legal') S.legal = false;
    else if (k == 'recent') S.recent = false;
    else S[k].delete(v);
    render();
  });
  if ($('clr')) $('clr').onclick = reset;
  $('out').innerHTML = FundList.table(L, {});
  if (nameOnly.length) {
    const table = $('out').querySelector('.tbl');
    if (table) nameOnly.forEach(f => table.insertAdjacentHTML('beforeend', nameRow(f)));
  }
  lockRows();
}
const FREE_ROWS = 3;
let catalog = null;
let searchHits = null;
let searchTimer = null;
function nameRow(f) {
  const slug = f.slug || f.id;
  return '<a class="tr2" href="vc/' + esc(slug) + '/"><div class="nm"><b>' + esc(f.name) + '</b><div class="m">' + esc(slug) + '</div></div><div></div><div></div><div></div><div></div></a>';
}
function skeletonRow() {
  return '<div class="tr2 skel" aria-hidden="true"><div class="nm"><b></b><div class="m"></div></div><div class="sc"><span class="ring"></span><span class="tag"></span></div><div><span class="lgc"></span></div><div><b></b><div class="m"></div></div><div></div></div>';
}
function filtersOn() {
  return S.q || listFiltered();
}
function lockRows() {
  if (filtersOn()) return;
  const tier = catalog ? catalog.tier : 'visitor';
  if (tier === 'paid' || (catalog && catalog.limit == null)) return;
  const total = (catalog && catalog.total) || HOME.fundTotal || VCS.length;
  const limit = catalog && catalog.limit != null ? catalog.limit : FREE_ROWS;
  const hidden = total - Math.min(VCS.length, limit);
  if (hidden <= 0) return;
  const table = $('out').querySelector('.tbl');
  if (!table) return;
  const loggedIn = window.Regret && Regret.user;
  const lock = document.createElement('div');
  lock.className = 'lock';
  let bars = '';
  for (let i = 0; i < hidden; i++) bars += skeletonRow();
  if (!loggedIn) {
    const label = 'Log in to see all ' + total + ' funds';
    lock.setAttribute('role', 'button');
    lock.tabIndex = 0;
    lock.setAttribute('aria-label', label);
    lock.innerHTML = bars + '<span class="lockpill"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>' + label + '</span>';
    lock.onclick = openListLogin;
    lock.onkeydown = e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openListLogin(); } };
  } else {
    const base = window.Regret && Regret.root ? Regret.root() : '';
    lock.setAttribute('aria-label', 'More funds are on a paid plan');
    lock.innerHTML = bars + '<a class="lockpill" href="' + base + 'plans/">See plans</a>';
  }
  table.appendChild(lock);
}
function openListLogin() {
  RegretAuth.open('login', false);
  const count = document.getElementById('listN');
  if (count) count.textContent = HOME.fundTotal || VCS.length;
  const card = document.querySelector('.auth');
  if (card) card.classList.add('is-list');
}
async function revealFunds() {
  if (!window.Regret || !Regret.landingFunds) return;
  const rows = await Regret.landingFunds();
  if (!rows || !Array.isArray(rows.funds)) return;
  catalog = rows;
  VCS.splice(0, VCS.length, ...rows.funds);
  render();
}
async function loadSearch(q) {
  const client = window.Regret && Regret.sb && Regret.sb();
  if (!client) {
    searchHits = null;
    render();
    return;
  }
  const { data, error } = await client.rpc('search_funds', { q: q });
  if (S.q.trim() !== q) return;
  searchHits = error ? null : (data || []);
  render();
}
function reset() {
  S.q = ''; $('q').value = ''; $('hq').value = '';
  ['band', 'size'].forEach(k => S[k].clear());
  S.legal = false; S.recent = false; S.min = 0; S.max = 100;
  $('smin').value = 0; $('smax').value = 100;
  render();
}
function setQ(v) {
  S.q = v;
  $('q').value = v;
  $('hq').value = v;
  if (searchTimer) clearTimeout(searchTimer);
  if (!String(v || '').trim()) {
    searchHits = null;
    render();
    return;
  }
  const client = window.Regret && Regret.sb && Regret.sb();
  if (!client) {
    searchHits = null;
    render();
    return;
  }
  searchTimer = setTimeout(() => loadSearch(String(v).trim()), 200);
}
$('q').oninput = e => setQ(e.target.value);
$('hq').oninput = e => setQ(e.target.value);
$('hgo').onclick = () => $('list').scrollIntoView({behavior: 'smooth'});
$('hq').onkeydown = e => { if (e.key == 'Enter') $('list').scrollIntoView({behavior: 'smooth'}); };
$('smin').oninput = e => { S.min = Math.min(+e.target.value, S.max); e.target.value = S.min; render(); };
$('smax').oninput = e => { S.max = Math.max(+e.target.value, S.min); e.target.value = S.max; render(); };
$('fLegal').onclick = () => { S.legal = !S.legal; render(); };
$('fRecent').onclick = () => { S.recent = !S.recent; render(); };
$('sort').onchange = e => { S.sort = e.target.value; render(); };
$('stats').innerHTML = STATS.map(s => `<div class="stat"><div class="n">${s.n.toLocaleString('en-US')}</div><div class="l">${s.l}</div></div>`).join('');
const FEED = UPD.filter((u, i, all) => all.findIndex(x => x.no == u.no && x.d == u.d && x.t == u.t && x.u == u.u) == i);
const FEED_SHOWN = 7;
function paintFeed() {
  const byId = Object.fromEntries(VCS.map(f => [f.id, f]));
  $('feed').innerHTML = FEED.slice(0, FEED_SHOWN).map(u => {
    const linked = u.fid && byId[u.fid] && byId[u.fid].report;
    const name = linked ? `<a href="vc/${byId[u.fid].report}/">${u.f}</a>` : u.f;
    const ext = String(u.u).startsWith('http');
    return `<div class="fi"><span class="dt">Update #${u.no}<small>${u.ds}</small></span><span class="fd">${name}</span><span class="ev"><span class="k ${u.k}" style="margin-right:8px">${u.k}</span>${u.t}</span><span class="sr"><a href="${u.u}" ${ext ? 'target="_blank" rel="noopener"' : ''}>${u.src} ↗</a><span>${u.v == 'ver' ? 'verified by us' : u.v == 'ours' ? 'our analysis' : 'unverified'}</span></span></div>`;
  }).join('');
}
function paintRecordCount(count) {
  const shown = Math.min(FEED_SHOWN, FEED.length);
  $('updTot').textContent = (count == null ? '…' : count) + ' records · showing the newest ' + shown;
}
async function loadRecordCount() {
  paintRecordCount(null);
  const client = window.Regret && Regret.sb && Regret.sb();
  if (!client) return;
  const { data, error } = await client.rpc('fact_record_count');
  if (error || data == null) return;
  paintRecordCount(data);
}
document.addEventListener('click', e => {
  const r = e.target.closest('a.tr2[href="#"]');
  if (r) e.preventDefault();
});
$('reset').onclick = reset;
paintFeed();
if (window.Regret) {
  Regret.ready.then(() => { revealFunds(); loadRecordCount(); });
  Regret.onChange(() => { revealFunds(); });
}
render();
