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
  $('tot').textContent = VCS.length;
  $('cnt').innerHTML = FundList.countHtml(L.length, VCS.length);
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
  $('out').innerHTML = FundList.table(L, {});
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
