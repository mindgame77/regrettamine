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
  // Only cases where the checked firm is a party get a status (and count); same rule as _firm_cases() in the DB.
  const nonParty = (t) => /\bnon-party\b|\bnot a party\b/i.test(t);
  function caseStatus(f) {
    if (!isCase(f)) return null;
    const t = f.text || '';
    if (nonParty(t)) return null;
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
      const row = d.closest('.row'); row.classList.add('tog', 'open');
      row.onclick = (e) => { if (!e.target.closest('a')) row.classList.toggle('open'); };
    });
  }
  window.regretShowDetails = showDetails;
  // Option A locked state: gray lines from firm_case_outline() (row, kind, year, status only). Nothing else is sent.
  const ROWT = {};
  if (main) main.querySelectorAll('.row').forEach(r => { const g = r.querySelector('.gl'); if (g) ROWT[g.dataset.row] = r.querySelector('.tx b').textContent; });
  const spill = (st) => st === 'active' ? '<span class="cs cs-act">Active</span>' : st === 'closed' ? '<span class="cs cs-cl">Closed</span>' : '';
  function showOutline(rows) {
    if (main.classList.contains('unlocked')) return;
    const by = {}; (rows || []).forEach(r => by[r.row] = r.items || []);
    main.querySelectorAll('.gl').forEach(g => {
      g.innerHTML = (by[g.dataset.row] || []).map((e, i) => {
        const w1 = 20 + ((e.kind || '').length * 7 + i * 13) % 45;
        return '<button type="button" class="gc' + (e.status === 'active' ? ' act' : '') + '" data-row="' + esc(g.dataset.row) + '" data-kind="' + esc(e.kind) + '" data-year="' + esc(e.year || '') + '" data-st="' + esc(e.status || '') + '">'
          + '<span class="y">' + esc(e.year || '—') + '</span><span class="k">' + esc(e.kind) + '</span><span class="bl"><span class="bar" style="width:' + w1 + '%"></span><span class="bar" style="width:22%"></span></span>'
          + spill(e.status) + '<span class="lkk">🔒 Open</span></button>';
      }).join('');
    });
  }
  let BAL = null; const FIRM = main ? ((main.querySelector('.sb.big input') || {}).defaultValue || '') : '';
  async function openPay(gc) {
    const pc = $('#pcase');
    const firm = FIRM, ST = { active: 'Active', closed: 'Closed' };
    const parts = gc ? [gc.dataset.kind, gc.dataset.year, ST[gc.dataset.st]].filter(Boolean) : ['All ' + (main.dataset.total || '') + ' facts'];
    pc.innerHTML = '<span>🔒 You clicked: <b>' + esc(parts.join(' · ')) + '</b></span> <span>· ' + esc(firm) + (gc && ROWT[gc.dataset.row] ? ' · ' + esc(ROWT[gc.dataset.row]) : '') + '</span>';
    pc.dataset.row = gc ? gc.dataset.row : ''; // for tests
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
  async function tryUnlock(spend) {
    if (!sb) return;
    const { data, error } = await sb.rpc('unlock_firm', { p_slug: main.dataset.firm, p_anon: anonId(), p_spend: spend });
    if (error || !data) { if (spend) $('#pmsg2').textContent = 'Something went wrong, try again.'; return; }
    if (data.status === 'ok') { closeOv($('#paycase')); return showDetails(data.details); }
    if (!spend) return data.status;
    if (data.status === 'need_signup') { $('#pmsg2').textContent = "You've used your free checks. Sign in below for 4 more."; const g = $('#panon'); g.hidden = false; g.classList.add('hi'); $('#usecheck').disabled = true; }
    if (data.status === 'out') { $('#pmsg2').textContent = "You're out of checks. Buy more below."; $('#usecheck').disabled = true; }
  }
  // No check is spent on page open: already-unlocked firms show details (free re-open); otherwise the gray
  // outline shows and a check is spent only when the user presses "Use 1 check" in the popup.
  async function load() {
    const st = await tryUnlock(false);
    if (st === 'locked' || st === undefined) { const { data } = await sb.rpc('firm_case_outline', { p_slug: main.dataset.firm }); showOutline(data); }
  }
  if (main && u) {
    u.onclick = () => openPay(null);
    main.addEventListener('click', (e) => { const gc = e.target.closest('.gc'); if (gc) openPay(gc); });
    $('#usecheck').onclick = () => { $('#usecheck').disabled = true; tryUnlock(true).then(paint).finally(async () => { BAL = await balance(); if (BAL && BAL.left > 0 && !main.classList.contains('unlocked')) $('#usecheck').disabled = false; }); };
    if (sb) { load().then(paint); sb.auth.onAuthStateChange((ev) => { if (ev === 'SIGNED_IN' && !main.classList.contains('unlocked')) setTimeout(() => tryUnlock(false).then(paint), 500); }); }
  }
  if (!main) paint();
})();
