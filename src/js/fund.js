/* Fund report interactions. Evidence popups and the ask-clipboard text are injected by the build. */
const EV = JSON.parse(document.getElementById('evidence').textContent);
const Q = JSON.parse(document.getElementById('ask-copy').textContent);
const $ = s => document.querySelector(s), $$ = s => [...document.querySelectorAll(s)];
function esc(s) { return String(s).replace(/[&<>"]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c])); }
function openEv(id) {
  const e = EV[id];
  if (!e) return;
  $('#dk').textContent = e.kicker;
  $('#dt').textContent = e.title;
  let h = '<div class="body">' + esc(e.body) + '</div>';
  if (e.tone === 'open') h += '<span class="rt amber dtone">Open · real risk</span>';
  if (e.tone === 'penalty') h += '<span class="rt red dtone">Costs points</span>';
  if (e.rows.length) h += '<table>' + e.rows.map(r => '<tr><td>' + esc(r[0]) + '</td><td>' + esc(r[1]) + '</td></tr>').join('') + '</table>';
  if (e.sources.length) h += '<h5>Sources</h5><div class="srcl">' + e.sources.map(s => '<a href="' + esc(s[1]) + '" target="_blank" rel="noopener"><div>' + esc(s[0]) + '<span>' + esc(s[1].replace(/^https?:\/\//, '').slice(0, 70)) + '</span></div></a>').join('') + '</div>';
  else h += '<h5>Sources</h5><p class="note">No public link for this item. It comes from the scoring method.</p>';
  $('#db').innerHTML = h;
  $('#db').scrollTop = 0;
  $$('[data-ev]').forEach(s => s.classList.toggle('sel', s.dataset.ev === id));
  document.body.classList.add('dopen');
  $('#dx').focus({preventScroll: true});
}
function closeEv() { document.body.classList.remove('dopen'); $$('.sel').forEach(s => s.classList.remove('sel')); }
document.addEventListener('click', ev => {
  const t = ev.target.closest('[data-ev]');
  if (t) { ev.preventDefault(); openEv(t.dataset.ev); return; }
  const g = ev.target.closest('[data-go]');
  if (g) { ev.preventDefault(); tab(g.dataset.go); const tb = $('.tabs'); window.scrollTo({top: tb ? tb.getBoundingClientRect().top + scrollY - 90 : 0}); }
});
$('#dx').onclick = closeEv;
$('.scrim').onclick = closeEv;
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeEv(); });
function tab(n) {
  if (!document.querySelector('[data-panel="' + n + '"]')) n = 'overview';
  $$('[data-tab]').forEach(b => { const on = b.dataset.tab === n; b.classList.toggle('on', on); b.setAttribute('aria-selected', on); });
  $$('[data-panel]').forEach(p => p.classList.toggle('on', p.dataset.panel === n));
  document.body.dataset.tab = n;
  history.replaceState(null, '', '#' + n);
}
$$('[data-tab]').forEach(b => b.onclick = () => tab(b.dataset.tab));
tab((location.hash || '#overview').slice(1).split('&')[0] || 'overview');
function toast(m) { const t = $('.toast'); t.textContent = m; t.classList.add('on'); setTimeout(() => t.classList.remove('on'), 1800); }
$('#copyq').onclick = async () => {
  try { await navigator.clipboard.writeText(Q); }
  catch (e) {
    const a = document.createElement('textarea');
    a.value = Q;
    document.body.appendChild(a);
    a.select();
    document.execCommand('copy');
    a.remove();
  }
  toast(Q.trim().split('\n').filter(line => /^\d+\./.test(line)).length + ' questions copied');
};
$('#pdf').onclick = () => { document.body.classList.add('print-ask'); setTimeout(() => { window.print(); document.body.classList.remove('print-ask'); }, 50); };
function goScore(id) {
  tab('score');
  const tb = $('.tabs');
  let y = tb ? tb.getBoundingClientRect().top + scrollY - 90 : 0;
  const b = id && document.getElementById('sc-' + id);
  if (b) {
    y = b.getBoundingClientRect().top + scrollY - 170;
    $$('.scb').forEach(x => x.classList.remove('flash'));
    void b.offsetWidth;
    b.classList.add('flash');
  }
  window.scrollTo({top: Math.max(0, y), behavior: 'smooth'});
}
$('#ringBtn').onclick = () => goScore(null);
document.addEventListener('click', ev => {
  const t = ev.target.closest('.stk [data-ev],.sleg [data-ev]');
  if (!t) return;
  ev.stopImmediatePropagation();
  ev.preventDefault();
  goScore(t.dataset.ev);
}, true);
$$('.sf').forEach(b => b.onclick = () => {
  const k = b.dataset.sf;
  $$('.sf').forEach(x => x.classList.toggle('on', x === b));
  let n = 0;
  $$('.pubc').forEach(c => { const on = k === 'all' || c.dataset.sent === k; c.hidden = !on; if (on) n++; });
  $('.sempty').hidden = n > 0;
});
