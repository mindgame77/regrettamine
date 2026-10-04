/* Landing list. Data is injected by the build from data/home.json. */
const HOME = JSON.parse(document.getElementById('home-data').textContent);
const VCS = HOME.funds;
const STATS = HOME.stats;
const UPD = HOME.updates;

const BANDS = [['Very low risk', 'Very low', '#19C37D'], ['Low risk', 'Low', '#7BD3A8'], ['Moderate', 'Moderate', '#F2B705'], ['Elevated', 'Elevated', '#FF6B4A'], ['High', 'High', '#D7263D']];
const SIZES = [['s', 'Under $20B', a => a < 20], ['m', '$20–50B', a => a >= 20 && a < 50], ['l', '$50B+', a => a >= 50]];
const S = {q: '', band: new Set(), size: new Set(), legal: false, min: 0, max: 100, sort: 'score'};
const $ = id => document.getElementById(id);
const bandColor = b => (BANDS.find(x => x[0] == b) || [0, 0, '#ccc'])[2];
const fmtAum = a => '$' + (a >= 10 ? a.toFixed(a % 1 ? 1 : 0) : a.toFixed(1)) + 'B';

function ring(s, size, stroke, color) {
  const r = (size - stroke) / 2, c = 2 * Math.PI * r;
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${r}" stroke="#F1EFF7" stroke-width="${stroke}" fill="none"/><circle cx="${size / 2}" cy="${size / 2}" r="${r}" stroke="${color}" stroke-width="${stroke}" fill="none" stroke-linecap="round" stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - s / 100)}"/></svg>`;
}
function grad() {
  return `<svg width="0" height="0" style="position:absolute"><defs><linearGradient id="g2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6C3BFF"/><stop offset="1" stop-color="#19C37D"/></linearGradient></defs></svg>`;
}
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
function fundHref(f) {
  return f.report ? `vc/${f.report}/` : '#';
}
function row(f) {
  const href = fundHref(f);
  return `<a class="tr2${f.v2 ? ' feat' : ''}" href="${href}" data-fund="${f.id}" title="${f.report ? 'Open full report' : 'Full report coming soon'}"><div class="nm"><b>${f.name}</b><div class="m">${f.hq} · since ${f.since}</div></div>
 <div class="sc"><div class="mring">${ring(f.score, 38, 4.5, f.v2 ? 'url(#g2)' : '#C9C5D9')}<b style="${f.v2 ? '' : 'color:#A9A5BD'}">${f.score}</b></div><div><span class="bands"><i style="background:${bandColor(f.band)}"></i>${f.band}</span><span class="tag ${f.v2 ? 'v2' : 'old'}">${f.v2 ? 'v2 · likely ' + f.lo + '–' + f.hi : 'old method'}</span></div></div>
 <div title="${f.legalNote}"><span class="lgc ${f.legal ? 'r' : 'g'}">${f.legal ? f.legal + ' active' : 'None found'}</span><div class="m">${f.v2 ? 'verified' : 'Toxy, unverified'}</div></div>
 <div><b>${fmtAum(f.aum)}</b><div class="m">${f.aumAsOf}${f.aumStale ? ' · stale' : ''}</div></div>
 <div>${f.updatedS}</div>
 <div class="ar">→</div></a>`;
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
  $('tot').textContent = VCS.length;
  $('cnt').innerHTML = `${L.length} ${L.length == 1 ? 'fund' : 'funds'}<small>of ${VCS.length}</small>`;
  const A = [];
  if (S.q) A.push(['q', '“' + S.q + '”']);
  S.band.forEach(b => A.push(['band:' + b, b]));
  if (S.min > 0 || S.max < 100) A.push(['range', 'Score ' + lo + '–' + hi]);
  S.size.forEach(s => A.push(['size:' + s, 'AUM ' + SIZES.find(z => z[0] == s)[1]]));
  if (S.legal) A.push(['legal', 'Has active legal matters']);
  $('active').innerHTML = A.length
    ? A.map(a => `<span class="ac">${a[1]}<i data-x="${a[0]}">×</i></span>`).join('') + '<span class="clr" id="clr">Clear all</span>'
    : '<span class="none">No filters applied · showing every fund we track</span>';
  $('active').querySelectorAll('[data-x]').forEach(x => x.onclick = () => {
    const [k, v] = x.dataset.x.split(':');
    if (k == 'q') { S.q = ''; $('q').value = ''; $('hq').value = ''; }
    else if (k == 'range') { S.min = 0; S.max = 100; $('smin').value = 0; $('smax').value = 100; }
    else if (k == 'legal') S.legal = false;
    else S[k].delete(v);
    render();
  });
  if ($('clr')) $('clr').onclick = reset;
  const empty = `<div class="empty"><b>No funds match these filters.</b>Try widening the score range or clearing a filter.</div>`;
  $('out').innerHTML = grad() + `<div class="tbl"><div class="tr2 th"><div>Fund</div><div>Score</div><div>Active legal</div><div>AUM</div><div>Last update</div><div></div></div>${L.map(row).join('') || empty}</div>`;
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
document.querySelectorAll('.hints a').forEach(a => a.onclick = () => { setQ(a.dataset.q); $('list').scrollIntoView({behavior: 'smooth'}); });
$('smin').oninput = e => { S.min = Math.min(+e.target.value, S.max); e.target.value = S.min; render(); };
$('smax').oninput = e => { S.max = Math.max(+e.target.value, S.min); e.target.value = S.max; render(); };
$('fLegal').onclick = () => { S.legal = !S.legal; render(); };
$('sort').onchange = e => { S.sort = e.target.value; render(); };
$('stats').innerHTML = STATS.map(s => `<div class="stat"><div class="n">${s.n.toLocaleString('en-US')}</div><div class="l">${s.l}</div><div class="s">${s.s}</div>${s.v ? '' : '<span class="uv">' + (s.u || 'Toxy · unverified') + '</span>'}</div>`).join('');
const byId = Object.fromEntries(VCS.map(f => [f.id, f]));
$('feed').innerHTML = UPD.map(u => {
  const linked = u.fid && byId[u.fid] && byId[u.fid].report;
  const name = linked ? `<a href="vc/${byId[u.fid].report}/">${u.f}</a>` : u.f;
  const ext = String(u.u).startsWith('http');
  return `<div class="fi"><span class="dt">Update #${u.no}<small>${u.ds}</small></span><span class="fd">${name}</span><span class="ev"><span class="k ${u.k}" style="margin-right:8px">${u.k}</span>${u.t}</span><span class="sr"><a href="${u.u}" ${ext ? 'target="_blank" rel="noopener"' : ''}>${u.src} ↗</a><span>${u.v == 'ver' ? 'verified by us' : u.v == 'ours' ? 'our analysis' : 'via Toxy, unverified'}</span></span></div>`;
}).join('');
$('updTot').textContent = UPD.length + ' updates so far · newest first, every one sourced';
document.addEventListener('click', e => {
  const r = e.target.closest('a.tr2[href="#"]');
  if (r) e.preventDefault();
});
$('reset').onclick = reset;
render();
