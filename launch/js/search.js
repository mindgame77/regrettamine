/* Search on every page. Home and /vc/<slug>/ both load this file and no other search code.
   Firm and pending links start at the site root, so /vc/<slug>/ and /vc/<slug>/full/ build the same URL.
   A finished search is logged once per term per page view, after a 1.5s pause or Enter. The log never blocks the page. */
(function () {
  const C = window.REGRET || {};
  const sb = C.url && C.key && window.supabase ? window.supabase.createClient(C.url, C.key) : null;
  const T = (C.copy && C.copy.js) || {};
  const esc = (x) => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const mark = (t, q) => { const i = String(t).toLowerCase().indexOf(q.toLowerCase()); return i < 0 || !q ? esc(t) : esc(t.slice(0, i)) + '<mark>' + esc(t.slice(i, i + q.length)) + '</mark>' + esc(t.slice(i + q.length)); };
  // Site-root paths. A relative "vc/…" link is resolved against /vc/<slug>/ and becomes /vc/vc/<slug>/.
  const firmUrl = (slug) => '/vc/' + encodeURIComponent(slug) + '/';
  const liveUrl = (q) => '/pending/?q=' + encodeURIComponent(q);
  const same = (x, q) => [x.name, x.short_name, x.slug].some(v => v && String(v).toLowerCase() === q.toLowerCase());
  // Open list: the highlighted row. Otherwise an exact name, short name, or slug. Same on every page.
  function choose(q, hits, act, listOpen) {
    hits = hits || [];
    return (listOpen && hits[act]) || hits.find(x => same(x, q)) || null;
  }
  const sent = Object.create(null);
  // Same device id the rest of the site already keeps. No name, email, or IP.
  function anonKey() {
    try {
      const k = 'regretamin.anon';
      let a = localStorage.getItem(k);
      if (!a) {
        const c = window.crypto;
        const raw = (c && typeof c.randomUUID === 'function')
          ? c.randomUUID()
          : ('r' + Math.random().toString(36).slice(2) + Date.now().toString(36));
        a = String(raw).replace(/[^A-Za-z0-9_-]/g, '').slice(0, 80);
        if (a.length < 8) a = ('r' + Math.random().toString(36).slice(2) + '00000000').slice(0, 16);
        localStorage.setItem(k, a);
      }
      return a;
    } catch (e) { return null; }
  }
  function pageOf() {
    try {
      const p = String(location.pathname || '/');
      if (p === '/' || p === '') return 'home';
      if (p.indexOf('/investors') === 0) return 'investors';
      if (p.indexOf('/vc/') !== -1) return 'firm';
      if (p.indexOf('/account/firms') === 0) return 'my-firms';
      return 'search';
    } catch (e) { return 'search'; }
  }
  function logSearch(term, page, resultCount, topFirmId) {
    try {
      const t = String(term == null ? '' : term).replace(/\s+/g, ' ').trim().slice(0, 100);
      if (t.length < 2) return;
      const pageName = String(page || 'search').replace(/[\u0000-\u001f]/g, '').slice(0, 40);
      const key = pageName + '\n' + t.toLowerCase();
      if (sent[key]) return;
      const cfg = window.REGRET || {};
      if (!cfg.url || !cfg.key || typeof fetch !== 'function') return;
      sent[key] = 1;
      const n = (typeof resultCount === 'number' && resultCount === resultCount) ? (resultCount | 0) : 0;
      fetch(String(cfg.url).replace(/\/$/, '') + '/rest/v1/rpc/log_search', {
        method: 'POST',
        keepalive: true,
        credentials: 'omit',
        headers: { apikey: cfg.key, Authorization: 'Bearer ' + cfg.key, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          p_term: t,
          p_page: pageName,
          p_result_count: n < 0 ? 0 : n,
          p_top_firm_id: topFirmId ? String(topFirmId).slice(0, 80) : null,
          p_anon_key: anonKey()
        })
      }).then(function () {}, function () {});
    } catch (e) {}
  }
  document.querySelectorAll('[data-search]').forEach(f => {
    const inp = f.q, box = document.createElement('div'); let hits = [], act = -1, seq = 0, timer, logTimer, hitsQ = '', logTerm = '', logReady = false;
    box.className = 'sdd'; box.id = 'sdd' + Math.random().toString(36).slice(2, 8); box.setAttribute('role', 'listbox'); box.hidden = true; f.appendChild(box);
    inp.setAttribute('role', 'combobox'); inp.setAttribute('aria-controls', box.id); inp.setAttribute('aria-expanded', 'false'); inp.setAttribute('aria-autocomplete', 'list');
    const show = (on) => { box.hidden = !on; inp.setAttribute('aria-expanded', on); };
    const draw = (q) => {
      box.innerHTML = hits.length ? hits.map((h, i) => '<a role="option" class="so2' + (i === act ? ' on' : '') + '" aria-selected="' + (i === act) + '" href="' + esc(firmUrl(h.slug)) + '"><b>' + mark(h.name, q) + '</b>'
        + (h.short_name && h.short_name !== h.name ? '<em>' + mark(h.short_name, q) + '</em>' : '') + '<span>' + esc(h.hq || '') + '</span></a>').join('')
        : '<a class="so2 none" href="' + esc(liveUrl(q)) + '">' + (T.suggest_none || '') + '</a>';
      show(true);
    };
    const flushLog = () => {
      const term = inp.value.trim();
      if (!logReady || term.length < 2 || term !== logTerm || hitsQ !== term) return;
      logSearch(term, pageOf(), hits.length, hits[0] ? hits[0].slug : null);
    };
    const armLog = (term) => {
      clearTimeout(logTimer);
      logTerm = term;
      logReady = false;
      if (!term || term.length < 2) return;
      logTimer = setTimeout(() => { logReady = true; flushLog(); }, 1500);
    };
    inp.addEventListener('input', () => {
      clearTimeout(timer); const q = inp.value.trim(); armLog(q); if (!q || !sb) { hits = []; hitsQ = ''; return show(false); }
      timer = setTimeout(async () => {
        const n = ++seq; const { data } = await sb.rpc('firm_suggest', { q }); if (n !== seq) return;
        hits = data || []; hitsQ = q; act = hits.length ? 0 : -1; draw(q);
        if (logReady && logTerm === q && inp.value.trim() === q) flushLog();
      }, 120);
    });
    inp.addEventListener('keydown', (e) => {
      if (box.hidden || !hits.length) { if (e.key === 'Escape') show(false); return; }
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); act = (act + (e.key === 'ArrowDown' ? 1 : hits.length - 1)) % hits.length; draw(inp.value.trim()); }
      if (e.key === 'Escape') show(false);
    });
    inp.addEventListener('blur', () => setTimeout(() => show(false), 150));
    f.onsubmit = async (e) => {
      e.preventDefault(); const q = inp.value.trim(); if (!q) return;
      clearTimeout(logTimer); logReady = false;
      let h = choose(q, hits, act, !box.hidden);
      if (!h && sb) {
        const n = ++seq; const { data } = await Promise.resolve(sb.rpc('firm_suggest', { q })).catch(() => ({}));
        if (n === seq) { hits = data || []; hitsQ = q; h = choose(q, hits, -1, false); }
      }
      const answered = hitsQ === q;
      logSearch(q, pageOf(), answered ? hits.length : (h ? 1 : 0), (h && h.slug) || (answered && hits[0] && hits[0].slug) || null);
      location.href = h ? firmUrl(h.slug) : liveUrl(q);
    };
  });
  window.RegretSearch = { choose, firmUrl, liveUrl, log: logSearch };
})();
