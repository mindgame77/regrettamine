/* Landing list. Data is injected by the build from data/home.json. */
const HOME = JSON.parse(document.getElementById('home-data').textContent);
const VCS = HOME.funds;
const STATS = HOME.stats;
const UPD = HOME.updates;

const BANDS = FundList.BANDS;
const SIZES = [['s', 'Under $20B', a => a < 20], ['m', '$20–50B', a => a >= 20 && a < 50], ['l', '$50B+', a => a >= 50]];
const S = {q: '', band: new Set(), size: new Set(), legal: false, min: 0, max: 100, sort: 'score'};
const $ = id => document.getElementById(id);

function match(f, skip) {
  if (skip != 'q' && S.q && !(f.name + ' ' + (f.short || '')).toLowerCase().includes(S.q.toLowerCase())) return false;
  if (skip != 'band' && S.band.size && !S.band.has(f.band)) return false;
  if (skip != 'range' && (f.score < S.min || f.score > S.max)) return false;
  if (skip != 'size' && S.size.size && !SIZES.some(z => S.size.has(z[0]) && z[2](f.aum))) return false;
  if (skip != 'legal' && S.legal && !f.legal) return false;
  return true;
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
  const lo = Math.min(S.min, S.max), hi = Math.max(S.min, S.max);
  $('rfill').style.left = lo + '%';
  $('rfill').style.width = (hi - lo) + '%';
  $('rvTxt').textContent = lo + '–' + hi;
  let L = VCS.filter(f => match(f));
  const cmp = {
    score: (a, b) => b.score - a.score || a.name.localeCompare(b.name),
    name: (a, b) => a.name.localeCompare(b.name),
    aum: (a, b) => b.aum - a.aum,
    upd: (a, b) => b.updatedTs.localeCompare(a.updatedTs) || a.name.localeCompare(b.name)
  }[S.sort];
  L.sort(cmp);
  const total = fullList ? VCS.length : (HOME.fundTotal || VCS.length);
  $('cnt').innerHTML = FundList.countHtml(L.length, total);
  const A = [];
  if (S.q) A.push(['q', '“' + S.q + '”']);
  S.band.forEach(b => A.push(['band:' + b, b]));
  if (S.min > 0 || S.max < 100) A.push(['range', 'Score ' + lo + '–' + hi]);
  S.size.forEach(s => A.push(['size:' + s, 'AUM ' + SIZES.find(z => z[0] == s)[1]]));
  if (S.legal) A.push(['legal', 'Has active legal matters']);
  $('active').innerHTML = A.length
    ? A.map(a => `<span class="ac">${a[1]}<i data-x="${a[0]}">×</i></span>`).join('') + '<span class="clr" id="clr">Clear all</span>'
    : '';
  $('active').querySelectorAll('[data-x]').forEach(x => x.onclick = () => {
    const [k, v] = x.dataset.x.split(':');
    if (k == 'q') { S.q = ''; $('q').value = ''; $('hq').value = ''; }
    else if (k == 'range') { S.min = 0; S.max = 100; $('smin').value = 0; $('smax').value = 100; }
    else if (k == 'legal') S.legal = false;
    else S[k].delete(v);
    render();
  });
  if ($('clr')) $('clr').onclick = reset;
  $('out').innerHTML = FundList.table(L, {});
  lockRows();
}
const FREE_ROWS = 3;
let fullList = false;
function skeletonRow() {
  return '<div class="tr2 skel" aria-hidden="true"><div class="nm"><b></b><div class="m"></div></div><div class="sc"><span class="ring"></span><span class="tag"></span></div><div><span class="lgc"></span></div><div><b></b><div class="m"></div></div><div></div></div>';
}
function lockRows() {
  if (fullList || (window.Regret && Regret.user)) return;
  const total = HOME.fundTotal || VCS.length;
  const hidden = total - FREE_ROWS;
  if (hidden <= 0) return;
  const table = $('out').querySelector('.tbl');
  if (!table) return;
  const lock = document.createElement('div');
  lock.className = 'lock';
  lock.setAttribute('role', 'button');
  lock.tabIndex = 0;
  lock.setAttribute('aria-label', 'Log in to see all ' + total + ' funds');
  let bars = '';
  for (let i = 0; i < hidden; i++) bars += skeletonRow();
  lock.innerHTML = bars + '<span class="lockpill"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>Log in to see all ' + total + ' funds</span>';
  lock.onclick = openListLogin;
  lock.onkeydown = e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openListLogin(); } };
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
  if (!window.Regret || !Regret.user || !Regret.landingFunds) return;
  const rows = await Regret.landingFunds();
  if (!rows || !rows.length) return;
  VCS.splice(0, VCS.length, ...rows);
  fullList = true;
  render();
}
function reset() {
  S.q = ''; $('q').value = ''; $('hq').value = '';
  ['band', 'size'].forEach(k => S[k].clear());
  S.legal = false; S.min = 0; S.max = 100;
  $('smin').value = 0; $('smax').value = 100;
  render();
}
function setQ(v) { S.q = v; $('q').value = v; $('hq').value = v; render(); }
$('q').oninput = e => setQ(e.target.value);
$('hq').oninput = e => setQ(e.target.value);
$('hgo').onclick = () => $('list').scrollIntoView({behavior: 'smooth'});
$('hq').onkeydown = e => { if (e.key == 'Enter') $('list').scrollIntoView({behavior: 'smooth'}); };
$('smin').oninput = e => { S.min = Math.min(+e.target.value, S.max); e.target.value = S.min; render(); };
$('smax').oninput = e => { S.max = Math.max(+e.target.value, S.min); e.target.value = S.max; render(); };
$('fLegal').onclick = () => { S.legal = !S.legal; render(); };
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
    return `<div class="fi"><span class="dt">Update #${u.no}<small>${u.ds}</small></span><span class="fd">${name}</span><span class="ev"><span class="k ${u.k}" style="margin-right:8px">${u.k}</span>${u.t}</span><span class="sr"><a href="${u.u}" ${ext ? 'target="_blank" rel="noopener"' : ''}>${u.src} ↗</a><span>${u.v == 'ver' ? 'verified by us' : u.v == 'ours' ? 'our analysis' : 'via Toxy, unverified'}</span></span></div>`;
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
  Regret.onChange(() => { if (Regret.user) revealFunds(); });
}
render();
