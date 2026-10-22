/* Regretamin launch: search, check counter, sign-up (Google + magic link), paywall, unknown-firm queue. */
(function () {
  const C = window.REGRET || {}, ROOT = window.REGRET_ROOT || '';
  const sb = C.url && C.key && window.supabase ? window.supabase.createClient(C.url, C.key) : null;
  const $ = (s) => document.querySelector(s);
  const ANON = 'regretamin.anon';
  function anonId() { let a = localStorage.getItem(ANON); if (!a) { a = crypto.randomUUID(); localStorage.setItem(ANON, a); } return a; }
  const open = (id) => { document.querySelectorAll('.ov').forEach(o => o.hidden = true); $('#' + id).hidden = false; };
  document.addEventListener('click', (e) => {
    const t = e.target.closest('[data-open],[data-close],[data-buy]'); if (!t) return;
    e.preventDefault();
    if (t.dataset.open) open(t.dataset.open);
    if (t.dataset.close !== undefined) t.closest('.ov').hidden = true;
    if (t.dataset.buy) buy(t.dataset.buy);
  });
  async function balance() {
    if (!sb) return null;
    const { data, error } = await sb.rpc('check_balance', { p_anon: anonId() });
    return error ? null : data; // {left, signed_in}
  }
  async function paint() {
    const b = await balance(); if (!b) return;
    $('#left').textContent = b.left + (b.signed_in ? '' : ' free') + (b.left === 1 ? ' check left' : ' checks left');
    if (b.signed_in) $('#signin').textContent = 'Account';
  }
  async function buy(kind) {
    if (!sb) return alert('Checkout is not configured yet.');
    const { data: s } = await sb.auth.getSession();
    if (!s.session) { $('#suh').textContent = 'Sign in to buy checks'; return open('signup'); }
    const { data, error } = await sb.functions.invoke('create-checkout', { body: { kind } });
    if (error || !data || !data.url) return alert('Could not start checkout.');
    location.href = data.url;
  }
  // Auth
  const back = () => location.href;
  const g = $('#google'); if (g) g.onclick = () => sb && sb.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: back() } });
  const m = $('#magic'); if (m) m.onclick = async () => {
    if (!sb) return; const email = $('#em').value.trim(); if (!email) return;
    const { error } = await sb.auth.signInWithOtp({ email, options: { emailRedirectTo: back() } });
    $('#sumsg').textContent = error ? error.message : 'Check your inbox for the sign-in link.';
  };
  if (sb) sb.auth.onAuthStateChange(async (ev) => { if (ev === 'SIGNED_IN') { await sb.rpc('claim_anon_checks', { p_anon: anonId() }); paint(); } });
  const main = document.querySelector('main[data-firm]');
  // Search
  document.querySelectorAll('[data-search]').forEach(f => f.onsubmit = (e) => {
    e.preventDefault(); const q = f.q.value.trim(); if (!q) return;
    const slug = (window.REGRET_FIRMS || {})[q.toLowerCase()];
    if (main && slug === main.dataset.firm) return;
    location.href = slug ? ROOT + 'vc/' + slug + '/' : ROOT + 'pending/?q=' + encodeURIComponent(q);
  });
  // Unknown firm
  const pq = $('#pq');
  if (pq) {
    const q = new URLSearchParams(location.search).get('q') || 'This firm'; pq.textContent = q;
    $('#notify').onsubmit = async (e) => {
      e.preventDefault(); if (!sb) return;
      const { error } = await sb.rpc('request_check', { p_query: q, p_email: e.target.email.value, p_anon: anonId() });
      $('#pmsg').textContent = error ? 'Something went wrong, try again.' : "Got it. We'll email you when it's ready.";
    };
  }
  // Result: unlock details with 1 check
  const u = $('#unlock');
  const esc = (x) => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const safeUrl = (u) => /^https?:\/\//i.test(u || '') ? u : null;
  // Case status comes only from the status wording in the DB fact text (firm_details().text, built from
  // vc_source_facts.value title/value; the value has no separate case-status field). Only case-like facts
  // (a case name, or a docket line with filed/terminated) get a pill; anything unclear gets none.
  const isCase = (f) => !!f.case || / v\.? .*\|.*\b(filed|terminated)\b/i.test(f.text || '');
  function caseStatus(f) {
    if (!isCase(f)) return null;
    const t = f.text || '';
    if (/\b(active|pending|ongoing)\b|\bopen\b[,.;:]|\bis investigating\b/i.test(t)) return 'active';
    if (/\boutcome (unverified|not verified)\b/i.test(t)) return null;
    if (/\b(terminated|dismissed|ended in|settled|resolved|closed|affirmed)\b/i.test(t)) return 'closed';
    return null;
  }
  function factHtml(f) {
    const who = f.who && f.who.startsWith('partner:') ? f.who.slice(8) + ' · ' : '';
    const head = f.case ? '<b>' + esc(f.case) + '</b>' + (f.year ? ' · ' + esc(f.year) : '') + '<br>' : '';
    const u = safeUrl(f.url);
    const src = (u ? '<a href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(f.label || 'Source') + ' ↗</a>' : esc(f.label || '')) + (f.date ? ' · retrieved ' + esc(f.date) : '');
    const st = caseStatus(f);
    const pill = st === 'active' ? '<span class="cs cs-act">Active</span>' : st === 'closed' ? '<span class="cs cs-cl">Closed</span>' : '';
    return '<div class="fct' + (st === 'active' ? ' act' : '') + '">' + pill + (f.needs_proof ? '<span class="np">Needs proof</span>' : '') + head + esc(who) + esc(f.text) + '<div class="src">' + src + '</div></div>';
  }
  function showDetails(rows) {
    main.classList.add('unlocked');
    const by = {}; (rows || []).forEach(r => by[r.row] = r.facts || []);
    main.querySelectorAll('.det').forEach(d => {
      const rank = (f) => caseStatus(f) === 'active' ? 0 : 1;
      const fs = (by[d.dataset.row] || []).map((f, i) => [f, i]).sort((a, b) => rank(a[0]) - rank(b[0]) || a[1] - b[1]).map(x => x[0]);
      const na = fs.filter(f => caseStatus(f) === 'active').length;
      const cnt = d.closest('.row').querySelector('.cnt');
      if (na && !(cnt && /active|open/i.test(cnt.textContent))) {
        const pc = d.closest('.row').querySelector('.pc');
        if (pc && !pc.querySelector('.cnt-act')) pc.insertAdjacentHTML('beforeend', '<span class="cnt ca cnt-act">' + na + ' active</span>');
      }
      d.innerHTML = fs.length ? fs.map(factHtml).join('') : '<div class="fct">No sourced facts on file for this check yet.</div>';
      const row = d.closest('.row'); row.classList.add('tog');
      row.onclick = (e) => { if (!e.target.closest('a')) row.classList.toggle('open'); };
    });
  }
  window.regretShowDetails = showDetails;
  async function tryUnlock(spend) {
    if (!sb) return;
    const { data, error } = await sb.rpc('unlock_firm', { p_slug: main.dataset.firm, p_anon: anonId(), p_spend: spend });
    if (error || !data) return;
    if (data.status === 'ok') return showDetails(data.details);
    if (!spend) return;
    if (data.status === 'need_signup') { $('#suh').textContent = "You've used your free checks"; open('signup'); }
    if (data.status === 'out') { $('#pwh').textContent = "You're out of checks"; open('paywall'); }
  }
  // Opening a firm's result page spends the check (revisits are free). Locks only stay if no check is available.
  if (main && u) {
    u.onclick = () => tryUnlock(true).then(paint);
    tryUnlock(true).then(paint);
    if (sb) sb.auth.onAuthStateChange((ev) => { if (ev === 'SIGNED_IN' && !main.classList.contains('unlocked')) setTimeout(() => tryUnlock(true).then(paint), 500); });
  }
  if (!main) paint();
})();
