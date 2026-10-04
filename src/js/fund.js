/* Fund report interactions. The report HTML arrives from open_report, then start() binds it. */
(function (global) {
  let started = false;
  function start() {
    if (started) return;
    const evidence = document.getElementById('evidence');
    const ask = document.getElementById('ask-copy');
    if (!evidence || !ask) return;
    started = true;
    const EV = JSON.parse(evidence.textContent);
    const Q = JSON.parse(ask.textContent);
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

  function pageJson(id) {
    const el = document.getElementById(id);
    return el ? JSON.parse(el.textContent) : null;
  }
  function showMore(buttonId, listId, rows, renderRow) {
    const btn = document.getElementById(buttonId);
    const list = document.getElementById(listId);
    if (!btn || !list || !rows) return;
    const size = +btn.dataset.pageSize || 24;
    let shown = list.children.length;
    btn.addEventListener('click', () => {
      rows.slice(shown, shown + size).forEach(row => list.insertAdjacentHTML('beforeend', renderRow(row)));
      shown = Math.min(rows.length, shown + size);
      const note = document.getElementById(btn.id === 'moreCos' ? 'coCount' : btn.id === 'moreReviews' ? 'reviewCount' : 'pressCount');
      if (note) note.textContent = 'Showing ' + shown + ' of ' + rows.length;
      if (shown >= rows.length) btn.remove();
      const on = document.querySelector('.sf.on');
      if (on && btn.id === 'morePress') on.click();
    });
  }
  showMore('moreCos', 'coList', pageJson('portfolio-data'), row => {
    const bits = [row.round, row.outcome].filter(Boolean);
    if (row.lead) bits.push('lead');
    if (row.board) bits.push('board seat');
    return '<div class="it"><b>' + esc(row.name) + '</b><span>' + esc(bits.join(' · ')) + '</span></div>';
  });
  showMore('moreReviews', 'reviewList', pageJson('review-data'), row => {
    const who = [row.founder, row.company, row.partner].filter(Boolean).join(' · ') || 'Founder';
    const flags = [];
    if (row.firstHand) flags.push('first-hand');
    if (row.verification) flags.push(row.verification);
    const dims = (row.ratings || []).map(r => esc(r.dimension) + ' ' + esc(r.score)).join(' ');
    return '<div class="it review"><div><b>' + esc(who) + '</b><div class="sm">' + esc(row.body || '') + '</div></div><span class="rt gray">' + esc(flags.join(' · ')) + '</span><span class="sm">' + dims + '</span></div>';
  });
  showMore('morePress', 'pressList', pageJson('press-data'), row => {
    const prefix = (document.getElementById('morePress') || {}).dataset.prefix || '';
    const initial = esc((row.publisher || '?').slice(0, 1));
    const fav = '<span class="fav"><img src="' + esc(prefix) + 'assets/fav/' + esc(row.domain) + '.png" alt="" onerror="this.parentNode.classList.add(\'nofav\');this.remove()"><em>' + initial + '</em></span>';
    const sent = {pos: 'Positive', neu: 'Neutral', neg: 'Negative'}[row.sentiment] || row.sentiment;
    return '<a class="pubc" data-sent="' + esc(row.sentiment) + '" href="' + esc(row.url) + '" target="_blank" rel="noopener">'
      + '<span class="pt">' + fav + '<span class="pn"><b>' + esc(row.publisher) + '</b><small>' + esc(row.domain) + ' · ' + esc(row.date) + '</small></span></span>'
      + '<span class="ph4">' + esc(row.headline) + '</span>'
      + '<span class="sw2"><span class="snt ' + esc(row.sentiment) + '">' + esc(sent) + '</span><span class="swy">' + esc(row.why || '') + '</span></span></a>';
  });
  }
  global.RegretFund = { start: start };
})(window);
