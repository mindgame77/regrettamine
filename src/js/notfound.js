/* 404 search. Paths stay absolute because GitHub Pages serves this file for deep URLs. */
(function () {
  const input = document.getElementById('nfq');
  const dd = document.getElementById('nfdd');
  if (!input || !dd) return;
  let token = 0;
  let client;

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  }

  function sb() {
    if (client) return client;
    const cfg = window.REGRET_CONFIG || {};
    if (!cfg.url || !cfg.key || !window.supabase) return null;
    client = window.supabase.createClient(cfg.url, cfg.key);
    return client;
  }

  input.addEventListener('input', async () => {
    const q = input.value.trim();
    const mine = ++token;
    if (!q) { dd.classList.remove('on'); dd.innerHTML = ''; return; }
    const api = sb();
    if (!api) {
      dd.innerHTML = '<div class="none">Search is not available on this build.</div>';
      dd.classList.add('on');
      return;
    }
    const { data } = await api.rpc('search_funds', { q: q });
    if (mine !== token) return;
    const rows = data || [];
    if (!rows.length) {
      dd.innerHTML = '<div class="none">No fund found</div>';
      dd.classList.add('on');
      return;
    }
    dd.innerHTML = rows.map(f => {
      const slug = f.slug || f.id;
      return '<a class="opt" href="/regrettamine/vc/' + encodeURIComponent(slug) + '/"><b>' + esc(f.name) + '</b></a>';
    }).join('');
    dd.classList.add('on');
  });
})();
