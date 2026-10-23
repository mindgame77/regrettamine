/* Regretamin launch: search, check counter, sign-up (Google + magic link), paywall, unknown-firm queue, account menu, Account and My checks pages. */
(function () {
  const C = window.REGRET || {}, ROOT = window.REGRET_ROOT || '';
  const sb = C.url && C.key && window.supabase ? window.supabase.createClient(C.url, C.key) : null;
  const $ = (s) => document.querySelector(s);
  const ANON = 'regretamin.anon';
  function anonId() { let a = localStorage.getItem(ANON); if (!a) { a = crypto.randomUUID(); localStorage.setItem(ANON, a); } return a; }
  const syncBody = () => document.body.classList.toggle('ppopen', !!document.querySelector('.ov:not([hidden])'));
  const open = (id) => { document.querySelectorAll('.ov').forEach(o => o.hidden = true); $('#' + id).hidden = false; syncBody(); };
  const closeOv = (o) => { if (o) { o.hidden = true; syncBody(); } };
  // Close any popup with x, Esc or a click on the backdrop
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') document.querySelectorAll('.ov:not([hidden])').forEach(closeOv); });
  document.addEventListener('mousedown', (e) => { if (e.target.classList && e.target.classList.contains('ov')) closeOv(e.target); });
  const PEND = 'regretamin.pendingBuy';
  const setPend = (k) => localStorage.setItem(PEND, JSON.stringify({ k, t: Date.now() }));
  const takePend = () => { try { const p = JSON.parse(localStorage.getItem(PEND) || 'null'); localStorage.removeItem(PEND); return p && Date.now() - p.t < 30 * 60e3 ? p.k : null; } catch (_) { return null; } };
  document.addEventListener('click', (e) => {
    const t = e.target.closest('[data-open],[data-close],[data-buy]'); if (!t) return;
    e.preventDefault();
    if (t.dataset.open) open(t.dataset.open);
    if (t.dataset.close !== undefined) closeOv(t.closest('.ov'));
    if (t.dataset.buy) buy(t.dataset.buy);
  });
  async function balance() {
    if (!sb) return null;
    const { data, error } = await sb.rpc('check_balance', { p_anon: anonId() });
    return error ? null : data; // {left, signed_in}
  }
  const PLANS = { m10: { name: 'Starter', n: 10, price: '$19/month' }, m30: { name: 'Pro', n: 30, price: '$49/month' } };
  const fmtDate = (d) => new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  const leftOf = (a) => a.plan && PLANS[a.plan] && a.left <= PLANS[a.plan].n ? a.left + ' of ' + PLANS[a.plan].n : String(a.left);
  let ACCT = null; // { email, plan, left, period_end, has_customer } once signed in
  async function paint() {
    const b = await balance(); if (!b) return;
    $('#left').textContent = b.left + (b.signed_in ? '' : ' free') + (b.left === 1 ? ' check left' : ' checks left');
    $('#signin').hidden = b.signed_in; $('#acct').hidden = !b.signed_in;
    document.querySelectorAll('[data-out]').forEach(x => x.hidden = b.signed_in);
    if (!b.signed_in) { document.querySelectorAll('[data-in]').forEach(x => x.hidden = true); return; }
    const [{ data: u }, { data: a }] = await Promise.all([sb.auth.getUser(), sb.rpc('my_account')]);
    if (!u.user || !a) return;
    ACCT = Object.assign({ email: u.user.email || '' }, a);
    $('#av').textContent = (ACCT.email[0] || 'A').toUpperCase();
    $('#ddem').textContent = ACCT.email;
    $('#ddplan').textContent = ACCT.plan && PLANS[ACCT.plan] ? PLANS[ACCT.plan].name + ' · ' + PLANS[ACCT.plan].n + ' checks/mo' : 'Free';
    $('#ddleft').textContent = leftOf(ACCT);
    document.querySelectorAll('[data-in]').forEach(x => x.hidden = false);
    if ($('#account')) paintAccount(); if ($('#mychecks')) paintMyChecks();
  }
  // Account menu
  const dd = $('#acctdd'), ab = $('#acctbtn');
  const menu = (on) => { dd.hidden = !on; ab.setAttribute('aria-expanded', on); };
  ab.onclick = (e) => { e.stopPropagation(); menu(dd.hidden); };
  document.addEventListener('click', (e) => { if (!dd.hidden && (!e.target.closest('#acctdd') || e.target.closest('a'))) menu(false); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') menu(false); });
  $('#signout').onclick = async (e) => { e.preventDefault(); if (sb) await sb.auth.signOut(); location.href = ROOT || './'; };
  // Account page
  async function paintAccount() {
    const a = ACCT, P = a.plan && PLANS[a.plan];
    $('#aem').textContent = a.email;
    $('#aplan').textContent = P ? P.name : 'Free';
    $('#aplan2').textContent = P ? P.n + ' checks/mo · ' + P.price : 'No plan. Buy checks any time.';
    $('#aleft').textContent = leftOf(a);
    $('#aleft2').textContent = P ? 'Resets to ' + P.n + ' on renewal' : (a.left === 1 ? 'check' : 'checks') + ' to use any time';
    $('#aren').textContent = P && a.period_end ? fmtDate(a.period_end) : '—';
    $('#aren2').textContent = P ? 'Renews monthly' : 'Nothing renews';
    $('#manage').hidden = !P && !a.has_customer; $('#pick').hidden = !!P;
    $('#dzp').textContent = (P ? 'Cancels your subscription, then permanently deletes' : 'Permanently deletes') + ' your account, remaining checks and history.';
    $('#cons').innerHTML = (P ? '<li><i>1</i><span>Your <b>' + esc(P.name) + ' subscription is cancelled first</b>, so you won’t be charged again.</span></li>' : '')
      + '<li><i>' + (P ? 2 : 1) + '</i><span>Your <b>' + esc(a.left) + ' remaining ' + (a.left === 1 ? 'check is' : 'checks are') + ' lost</b> and aren’t refunded.</span></li>'
      + '<li><i>' + (P ? 3 : 2) + '</i><span>Your list of unlocked firms and your email are permanently deleted.</span></li>';
    $('#delgo').textContent = P ? 'Cancel subscription & delete' : 'Delete account';
    const { data: rows } = await sb.rpc('my_checks');
    const n = (rows || []).length;
    $('#mcn').textContent = n ? 'You’ve checked ' + n + (n === 1 ? ' firm' : ' firms') : 'No checks yet';
    $('#mcl').textContent = n ? 'Latest: ' + rows[0].name + ', ' + fmtDate(rows[0].checked_at) : 'Search a firm to run your first check.';
  }
  if ($('#account')) {
    $('#manage').onclick = async () => {
      $('#amsg').textContent = '';
      const { data, error } = await sb.functions.invoke('billing-portal', { body: { returnUrl: location.href.split('#')[0] } });
      if (error || !data || !data.url) return ($('#amsg').textContent = 'Could not open the billing portal. Try again.');
      location.href = data.url;
    };
    $('#emform').onsubmit = async (e) => {
      e.preventDefault(); const email = $('#nem').value.trim(); if (!email) return;
      const { error } = await sb.auth.updateUser({ email }, { emailRedirectTo: location.href.split('#')[0] });
      $('#emmsg').textContent = error ? error.message : 'Check ' + email + ' for a confirmation link. Your email changes when you open it.';
    };
    $('#deltype').oninput = (e) => { $('#delgo').disabled = e.target.value.trim() !== 'DELETE'; };
    $('#delgo').onclick = async () => {
      const go = $('#delgo'); go.disabled = true; $('#delmsg').textContent = 'Deleting…';
      const { data, error } = await sb.functions.invoke('delete-account', { body: {} });
      if (error || !data || !data.deleted) {
        let m = 'Could not delete this account. Nothing was deleted.';
        try { const j = error && error.context && await error.context.json(); if (j && j.message) m = j.message; } catch (_) { /* keep default */ }
        $('#delmsg').textContent = m; go.disabled = false; return;
      }
      await sb.auth.signOut(); location.href = ROOT;
    };
  }
  // My checks page
  let MC = [];
  async function paintMyChecks() {
    const a = ACCT, P = a.plan && PLANS[a.plan];
    $('#mbal').innerHTML = '<b>' + esc(leftOf(a)) + '</b> ' + (a.left === 1 ? 'check' : 'checks') + ' left' + (P ? ' this month' + (a.period_end ? ' · resets ' + esc(fmtDate(a.period_end)) : '') : '');
    const { data } = await sb.rpc('my_checks'); MC = data || [];
    $('#mlist').hidden = !MC.length; $('#mempty').hidden = !!MC.length; drawChecks();
  }
  function drawChecks() {
    const q = $('#mq').value.trim().toLowerCase(), so = $('#msort').value;
    const rows = MC.filter(r => !q || (r.name + ' ' + (r.short_name || '')).toLowerCase().includes(q))
      .sort((x, y) => so === 'az' ? x.name.localeCompare(y.name) : (so === 'old' ? 1 : -1) * (new Date(x.checked_at) - new Date(y.checked_at)));
    $('#mnone').hidden = !!rows.length || !MC.length;
    $('#mrows').innerHTML = rows.map(r => {
      const d = new Date(r.checked_at), url = ROOT + 'vc/' + encodeURIComponent(r.slug) + '/';
      const when = fmtDate(d) + ' · ' + d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
      const st = r.active ? '<span class="cs cs-act">' + r.active + ' active</span>' + r.active + ' of ' + r.cases + (r.cases === 1 ? ' case' : ' cases') + ' active'
        : r.cases ? '<span class="cs cs-cl">Closed</span>' + r.cases + (r.cases === 1 ? ' case' : ' cases') + ', none active' : 'No court cases found in sources';
      const nm = r.name + (r.short_name && r.short_name !== r.name ? ' (' + r.short_name + ')' : '');
      return '<div class="mr"><button type="button" class="star' + (r.saved ? ' on' : '') + '" data-star="' + esc(r.slug) + '" aria-pressed="' + !!r.saved + '" aria-label="' + (r.saved ? 'Unsave ' : 'Save ') + esc(r.name) + '">' + (r.saved ? '★' : '☆') + '</button>'
        + '<span class="nm2"><a href="' + esc(url) + '">' + esc(nm) + '</a></span><span class="dt">' + esc(when) + '</span><span class="st">' + st + '</span><a class="btn o" href="' + esc(url) + '">Open result</a></div>';
    }).join('');
  }
  if ($('#mychecks')) {
    $('#mq').oninput = drawChecks; $('#msort').onchange = drawChecks;
    $('#mrows').onclick = async (e) => {
      const b = e.target.closest('[data-star]'); if (!b) return;
      const r = MC.find(x => x.slug === b.dataset.star), on = !r.saved; b.disabled = true;
      const { data, error } = await sb.rpc(on ? 'watch_fund' : 'unwatch_fund', { p_slug: r.slug });
      if (!error && (!on || (data && data.saved))) r.saved = on;
      drawChecks();
    };
  }
  async function buy(kind) {
    if (!sb) return alert('Checkout is not configured yet.');
    const { data: s } = await sb.auth.getSession();
    const pay = $('#paycase'), inPay = pay && !pay.hidden, msg = (t) => { if (inPay) $('#pmsg2').textContent = t; else if (t && !/…$/.test(t)) alert(t); };
    if (!s.session) {
      setPend(kind); // after sign-in (Google redirect or magic link) we come back here and continue to checkout
      if (inPay) { const g = $('#panon'); g.hidden = false; g.classList.add('hi'); $('#psgnh').textContent = 'Sign in to continue to checkout'; g.scrollIntoView({ behavior: 'smooth', block: 'center' }); return; }
      $('#suh').textContent = 'Sign in to buy checks'; return open('signup');
    }
    document.querySelectorAll('[data-buy]').forEach(b => b.disabled = true); msg('Opening secure checkout…');
    const { data, error } = await sb.functions.invoke('create-checkout', { body: { kind } });
    if (error || !data || !data.url) { document.querySelectorAll('[data-buy]').forEach(b => b.disabled = false); return msg('Could not start checkout. Try again.'); }
    location.href = data.url;
  }
  // Auth
  const back = () => location.href.split('#')[0];
  const google = () => sb && sb.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: back() } });
  const magic = async (email, out) => {
    if (!sb || !email) return;
    const { error } = await sb.auth.signInWithOtp({ email, options: { emailRedirectTo: back() } });
    out.textContent = error ? error.message : 'Check your inbox for the sign-in link.';
  };
  const g = $('#google'); if (g) g.onclick = google;
  const m = $('#magic'); if (m) m.onclick = () => magic($('#em').value.trim(), $('#sumsg'));
  document.querySelectorAll('[data-google]').forEach(b => b.onclick = google);
  document.querySelectorAll('[data-magic]').forEach(f => f.onsubmit = (e) => { e.preventDefault(); magic(f.email.value.trim(), f.parentNode.parentNode.querySelector('[data-magicmsg]')); });
  if (sb) sb.auth.onAuthStateChange((ev, session) => {
    if (ev === 'SIGNED_IN') setTimeout(async () => { await sb.rpc('claim_anon_checks', { p_anon: anonId() }); paint(); }, 0);
    if ((ev === 'SIGNED_IN' || ev === 'INITIAL_SESSION') && session) { const k = takePend(); if (k) setTimeout(() => { if ($('#paycase')) open('paycase'); buy(k); }, 0); }
  });
  const main = document.querySelector('main[data-firm]');
  // Search dropdown: firm_suggest() (max 8; prefix, then word, then contains). No match: run a live check.
  const esc = (x) => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const mark = (t, q) => { const i = t.toLowerCase().indexOf(q.toLowerCase()); return i < 0 || !q ? esc(t) : esc(t.slice(0, i)) + '<mark>' + esc(t.slice(i, i + q.length)) + '</mark>' + esc(t.slice(i + q.length)); };
  const firmUrl = (slug) => ROOT + 'vc/' + encodeURIComponent(slug) + '/';
  const liveUrl = (q) => ROOT + 'pending/?q=' + encodeURIComponent(q);
  document.querySelectorAll('[data-search]').forEach(f => {
    const inp = f.q, box = document.createElement('div'); let hits = [], act = -1, seq = 0, timer;
    box.className = 'sdd'; box.id = 'sdd' + Math.random().toString(36).slice(2, 8); box.setAttribute('role', 'listbox'); box.hidden = true; f.appendChild(box);
    inp.setAttribute('role', 'combobox'); inp.setAttribute('aria-controls', box.id); inp.setAttribute('aria-expanded', 'false'); inp.setAttribute('aria-autocomplete', 'list');
    const show = (on) => { box.hidden = !on; inp.setAttribute('aria-expanded', on); };
    const draw = (q) => {
      box.innerHTML = hits.length ? hits.map((h, i) => '<a role="option" class="so2' + (i === act ? ' on' : '') + '" aria-selected="' + (i === act) + '" href="' + esc(firmUrl(h.slug)) + '"><b>' + mark(h.name, q) + '</b>'
        + (h.short_name && h.short_name !== h.name ? '<em>' + mark(h.short_name, q) + '</em>' : '') + '<span>' + esc(h.hq || '') + '</span></a>').join('')
        : '<a class="so2 none" href="' + esc(liveUrl(q)) + '">Not in our database yet, run a live check →</a>';
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
    f.onsubmit = (e) => {
      e.preventDefault(); const q = inp.value.trim(); if (!q) return;
      const h = !box.hidden && hits[act] || hits.find(x => [x.name, x.short_name, x.slug].some(v => v && v.toLowerCase() === q.toLowerCase()));
      if (main && h && h.slug === main.dataset.firm) return show(false);
      location.href = h ? firmUrl(h.slug) : liveUrl(q);
    };
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
  // Company page: one firm_page() call returns everything (locked: counts + one line per section only).
  let BAL = null, PAGE = null, VIEW = null, SEC = '';
  async function openPay(sec) {
    SEC = sec || '';
    $('#pph').textContent = VIEW.head(SEC);
    $('#pmsg2').textContent = '';
    const ub = $('#usecheck'), pb = $('#pbal'); ub.disabled = true; pb.textContent = 'Checking your balance…';
    $('#panon').classList.remove('hi'); $('#psgnh').textContent = 'Sign in to buy';
    open('paycase');
    BAL = await balance();
    $('#panon').hidden = !!(BAL && BAL.signed_in);
    if (!BAL) { pb.textContent = 'Could not load your balance'; return; }
    const n = BAL.left, w = n === 1 ? ' check' : ' checks';
    pb.textContent = n > 0 ? 'You have ' + n + (BAL.signed_in ? '' : ' free') + w + ' left' : (BAL.signed_in ? 'You have no checks left' : 'No free checks left on this device');
    if (n <= 0) $('#pmsg2').textContent = BAL.signed_in ? 'Pick a plan below to get more checks.' : 'Sign in below for 4 more free checks, or pick a plan.';
    ub.disabled = n <= 0;
  }
  function draw(P) {
    PAGE = P; VIEW = window.RegretCompany.render(main, P);
    const id = decodeURIComponent(location.hash.slice(1)), t = id && document.getElementById(id);
    if (t) t.scrollIntoView();
  }
  async function loadPage(spend) {
    if (!sb) return;
    const { data, error } = await sb.rpc('firm_page', { p_slug: main.dataset.firm, p_anon: anonId(), p_spend: spend });
    if (error || !data) { if (spend) $('#pmsg2').textContent = 'Something went wrong, try again.'; return; }
    if (data.status === 'ok') { if (data.open) closeOv($('#paycase')); return draw(data); }
    if (data.status === 'need_signup') { $('#pmsg2').textContent = "You've used your free checks. Sign in below for 4 more."; const g = $('#panon'); g.hidden = false; g.classList.add('hi'); $('#usecheck').disabled = true; }
    if (data.status === 'out') { $('#pmsg2').textContent = "You're out of checks. Buy more below."; $('#usecheck').disabled = true; }
  }
  if (main) {
    // In-page anchors: smooth scroll and update the hash
    document.addEventListener('click', (e) => {
      const a = e.target.closest('a[href^="#"]'), id = a && a.getAttribute('href').slice(1), t = id && document.getElementById(id); if (!t) return;
      e.preventDefault(); t.scrollIntoView({ behavior: 'smooth' }); history.pushState(null, '', '#' + id);
    });
    $('#unlock').onclick = () => openPay('');
    main.addEventListener('click', (e) => { const s = !main.classList.contains('unlocked') && e.target.closest('[data-sec]'); if (s) openPay(s.dataset.sec); });
    $('#usecheck').onclick = () => { $('#usecheck').disabled = true; loadPage(true).then(paint).finally(async () => { BAL = await balance(); if (BAL && BAL.left > 0 && !(PAGE && PAGE.open)) $('#usecheck').disabled = false; }); };
    if (sb) {
      const first = sb.auth.getSession().then(({ data }) => { const uid = data.session && data.session.user.id; return loadPage(false).then(paint).then(() => uid); });
      sb.auth.onAuthStateChange((ev, session) => { if (ev === 'SIGNED_IN') first.then((uid) => { if (session && session.user.id !== uid && !(PAGE && PAGE.open)) setTimeout(() => loadPage(false).then(paint), 500); }); });
    }
  }
  if (!main) paint();
})();
