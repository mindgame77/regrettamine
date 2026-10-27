/* Search on every page. Home and /vc/<slug>/ both load this file and no other search code.
   Firm and pending links start at the site root, so /vc/<slug>/ and /vc/<slug>/full/ build the same URL. */
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
  document.querySelectorAll('[data-search]').forEach(f => {
    const inp = f.q, box = document.createElement('div'); let hits = [], act = -1, seq = 0, timer;
    box.className = 'sdd'; box.id = 'sdd' + Math.random().toString(36).slice(2, 8); box.setAttribute('role', 'listbox'); box.hidden = true; f.appendChild(box);
    inp.setAttribute('role', 'combobox'); inp.setAttribute('aria-controls', box.id); inp.setAttribute('aria-expanded', 'false'); inp.setAttribute('aria-autocomplete', 'list');
    const show = (on) => { box.hidden = !on; inp.setAttribute('aria-expanded', on); };
    const draw = (q) => {
      box.innerHTML = hits.length ? hits.map((h, i) => '<a role="option" class="so2' + (i === act ? ' on' : '') + '" aria-selected="' + (i === act) + '" href="' + esc(firmUrl(h.slug)) + '"><b>' + mark(h.name, q) + '</b>'
        + (h.short_name && h.short_name !== h.name ? '<em>' + mark(h.short_name, q) + '</em>' : '') + '<span>' + esc(h.hq || '') + '</span></a>').join('')
        : '<a class="so2 none" href="' + esc(liveUrl(q)) + '">' + (T.suggest_none || '') + '</a>';
      show(true);
    };
    inp.addEventListener('input', () => {
      clearTimeout(timer); const q = inp.value.trim(); if (!q || !sb) { hits = []; return show(false); }
      timer = setTimeout(async () => { const n = ++seq; const { data } = await sb.rpc('firm_suggest', { q }); if (n !== seq) return; hits = data || []; act = hits.length ? 0 : -1; draw(q); }, 120);
    });
    inp.addEventListener('keydown', (e) => {
      if (box.hidden || !hits.length) { if (e.key === 'Escape') show(false); return; }
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); act = (act + (e.key === 'ArrowDown' ? 1 : hits.length - 1)) % hits.length; draw(inp.value.trim()); }
      if (e.key === 'Escape') show(false);
    });
    inp.addEventListener('blur', () => setTimeout(() => show(false), 150));
    f.onsubmit = async (e) => {
      e.preventDefault(); const q = inp.value.trim(); if (!q) return;
      let h = choose(q, hits, act, !box.hidden);
      if (!h && sb) { const n = ++seq; const { data } = await Promise.resolve(sb.rpc('firm_suggest', { q })).catch(() => ({})); if (n === seq) h = choose(q, data || [], -1, false); }
      location.href = h ? firmUrl(h.slug) : liveUrl(q);
    };
  });
  window.RegretSearch = { choose, firmUrl, liveUrl };
})();
