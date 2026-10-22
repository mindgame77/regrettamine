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
  // Search
  document.querySelectorAll('[data-search]').forEach(f => f.onsubmit = (e) => {
    e.preventDefault(); const q = f.q.value.trim(); if (!q) return;
    const slug = (window.REGRET_FIRMS || {})[q.toLowerCase()];
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
  const main = $('main[data-firm]'), u = $('#unlock');
  async function showDetails(rows) {
    main.classList.add('unlocked');
    (rows || []).forEach(r => { const d = main.querySelector('.det[data-row="' + r.row + '"]'); if (d) d.innerHTML = r.html; });
  }
  async function tryUnlock(spend) {
    if (!sb) return;
    const { data, error } = await sb.rpc('unlock_firm', { p_slug: main.dataset.firm, p_anon: anonId(), p_spend: spend });
    if (error) return;
    if (data.status === 'ok') return showDetails(data.details);
    if (data.status === 'need_signup') { $('#suh').textContent = "You've used your 2 free checks"; open('signup'); }
    if (data.status === 'out') { $('#pwh').textContent = "You're out of checks"; open('paywall'); }
  }
  if (main && u) { u.onclick = () => tryUnlock(true).then(paint); tryUnlock(false); }
  paint();
})();
