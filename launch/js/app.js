/* Regretamin launch: search, check counter, sign-up (Google + magic link), paywall, unknown-firm queue, account menu, Account and My checks pages. */
(function () {
  const C = window.REGRET || {}, ROOT = window.REGRET_ROOT || '';
  const sb = C.url && C.key && window.supabase ? window.supabase.createClient(C.url, C.key) : null;
  const $ = (s) => document.querySelector(s);
  const ANON = 'regretamin.anon';
  function anonId() { let a = localStorage.getItem(ANON); if (!a) { a = crypto.randomUUID(); localStorage.setItem(ANON, a); } return a; }
  const syncBody = () => document.body.classList.toggle('ppopen', !!document.querySelector('.ov:not([hidden])'));
  const open = (id) => { const ov = document.getElementById(id); if (!ov) return; document.querySelectorAll('.ov').forEach(o => o.hidden = true); ov.hidden = false; const pw = $('#pwmsg'); if (pw) pw.textContent = ''; syncBody(); };
  if (new URLSearchParams(location.search).get('pricing') === '1') { history.replaceState(null, '', location.pathname + location.hash); setTimeout(() => open('paywall')); } // from /pricing/
  const closeOv = (o) => { if (o) { o.hidden = true; syncBody(); } };
  // Close any popup with x, Esc or a click on the backdrop
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') document.querySelectorAll('.ov:not([hidden])').forEach(closeOv); });
  document.addEventListener('mousedown', (e) => { if (e.target.classList && e.target.classList.contains('ov')) closeOv(e.target); });
  const PEND = 'regretamin.pendingBuy';
  const setPend = (k, code) => localStorage.setItem(PEND, JSON.stringify({ k, code, t: Date.now() }));
  const clearPend = () => localStorage.removeItem(PEND);
  const takePend = () => { try { const p = JSON.parse(localStorage.getItem(PEND) || 'null'); localStorage.removeItem(PEND); return p && Date.now() - p.t < 30 * 60e3 ? p : null; } catch (_) { return null; } };
  const PAID_SID = (() => { // Stripe return: drop the session id from the address bar before anything else reads it
    const q = new URLSearchParams(location.search);
    if (q.get('paid') !== '1') return '';
    const sid = q.get('session_id') || '';
    history.replaceState(null, '', location.pathname + location.hash);
    return sid;
  })();
  document.addEventListener('click', (e) => {
    const t = e.target.closest('[data-open],[data-close],[data-buy]'); if (!t) return;
    if (t.dataset.open && !document.getElementById(t.dataset.open)) return; // real /plans/ or /login/ link when that popup is not on this page
    e.preventDefault();
    if (t.dataset.open === 'signup') signupMode('new');
    if (t.dataset.open) open(t.dataset.open);
    if (t.dataset.close !== undefined) closeOv(t.closest('.ov'));
    if (t.dataset.buy) buy(t.dataset.buy);
  });
  async function balance(ms = 5000) { // null on error or after ms (5s) so callers never hang
    if (!sb) return null;
    let to; const late = new Promise(r => { to = setTimeout(() => r({ error: 'timeout' }), ms); });
    try { const { data, error } = await Promise.race([sb.rpc('check_balance', { p_anon: anonId() }), late]); return error ? null : data; } // {left, signed_in}
    catch (_) { return null; } finally { clearTimeout(to); }
  }
  // Copy and plans come from launch/copy.json (window.REGRET.copy). fmt fills {name}; pl picks [one, many] by count.
  const T = C.copy.js, B = C.copy.site.billing, SU = C.copy.site.signup;
  // New-account card vs existing-account sign-in. Same Google button and email link either way.
  // The +4 shows only on the new-account card. Signing in does not grant credits.
  function signupMode(mode) {
    const card = document.querySelector('.sgcard'); if (!card || !SU) return;
    const inn = mode === 'in';
    card.classList.toggle('signin', inn);
    const h = $('#suh'); if (h) h.textContent = inn ? SU.sign_title : SU.title;
    const s = $('#sus'); if (s) s.textContent = inn ? SU.sign_sub : SU.sub;
    const a = $('#sufootnew'), b = $('#sufootin'); if (a) a.hidden = inn; if (b) b.hidden = !inn;
    const sg = $('#signup'); if (sg) sg.classList.remove('buy');
  }
  const sul = (id, mode) => { const b = document.getElementById(id); if (b) b.onclick = (e) => { e.preventDefault(); signupMode(mode); }; };
  sul('sulinkin', 'in'); sul('sulinknew', 'new');
  // Stripe billing portal (Account "Manage" and the "You already have a plan" link); out = element for the failure message
  async function portal(out) {
    out.textContent = '';
    const { data, error } = await sb.functions.invoke('billing-portal', { body: { returnUrl: location.href.split('#')[0] } });
    if (error || !data || !data.url) return (out.textContent = T.portal_fail);
    location.href = data.url;
  }
  // Subscription plans by kind (m10, m30 and their yearly y10, y30) for the account menu, Account and My checks.
  const PLANS = {};
  Object.entries(C.copy.plans).filter(([, p]) => p.monthly).forEach(([k, p]) => {
    PLANS[k] = { name: p.name, checks: p.checks, price: p.price + B.per_month };
    if (p.yearly) PLANS[p.yearly.kind] = { name: p.name, checks: p.checks, price: p.yearly.price + B.per_year, yearly: true };
  });
  const planOf = (a) => a.plan === 'custom' ? { name: a.plan_name || '', checks: a.monthly_checks || 0, price: '', yearly: !!a.next_refill } : a.plan && PLANS[a.plan];
  const fmt = (t, o) => t.replace(/\{(\w+)\}/g, (_, k) => o[k]), pl = (n, t, o) => fmt(t[n === 1 ? 0 : 1], o);
  const fmtDate = (d) => window.RegretDate ? window.RegretDate.format(d) : '';
  const leftOf = (a) => { const P = planOf(a); return P && a.left <= P.checks ? fmt(T.left_of, { left: a.left, n: P.checks }) : String(a.left); };
  let ACCT = null; // { email, plan, left, period_end, cancel_at_period_end, has_customer } once signed in
  // Header auth state: the inline <head> script set html.au-in / html.au-out / html.au-wait from the cached Supabase session in
  // localStorage, so the first frame already shows the account button (or Sign in), never a Sign in flash. hdr() sets the real state.
  const hdr = (signedIn, email) => {
    $('#signin').hidden = signedIn; $('#acct').hidden = !signedIn;
    if (signedIn && email && !$('#av').textContent) $('#av').textContent = email[0].toUpperCase();
    document.documentElement.classList.remove('au-in', 'au-out', 'au-wait');
  };
  if (window.REGRET_AU && window.REGRET_AU.email) { $('#av').textContent = window.REGRET_AU.email[0].toUpperCase(); $('#ddem').textContent = window.REGRET_AU.email; }
  const session = async (ms = 8000) => { // null when signed out or when the auth client stalls past ms
    if (!sb) return null;
    let to; const late = new Promise(r => { to = setTimeout(() => r({ data: {} }), ms); });
    try { const { data } = await Promise.race([sb.auth.getSession(), late]); return (data && data.session) || null; } catch (_) { return null; } finally { clearTimeout(to); }
  };
  // paint() can run before the auth client is ready: a cold load with an expired access token waits on a token refresh, and a refresh
  // or RPC can fail once. Never settle on "signed out" or an empty Account page while a session is still cached: retry with backoff,
  // and repaint on every auth event that brings a session (INITIAL_SESSION, TOKEN_REFRESHED, SIGNED_IN) until the account is painted.
  let PAINT_TRY = 0, PAINT_T = 0, PAINTING = null;
  const cached = () => !!(window.REGRET_AU && window.REGRET_AU.email !== undefined);
  // Exponential backoff (1s, 2s, 4s, 8s; at most 4 retries). A retry reuses a good check_balance answer from the last 30 s
  // instead of calling it again; only a failed or signed-out answer is fetched again.
  let BAL_OK = null;
  const retry = () => { if (PAINT_TRY < 4) { PAINT_TRY++; clearTimeout(PAINT_T); PAINT_T = setTimeout(paint, 1000 * 2 ** (PAINT_TRY - 1)); return true; } return false; };
  function paint() { // one paint at a time; a call during a paint queues one more
    if (PAINTING) { PAINTING.again = true; return PAINTING.p; }
    const st = { again: false }; PAINTING = st;
    st.p = paintOnce().catch(() => { retry(); }).finally(() => { PAINTING = null; if (st.again) paint(); });
    return st.p;
  }
  async function paintOnce() {
    const b = PAINT_TRY > 0 && BAL_OK && BAL_OK.signed_in && Date.now() - BAL_OK.t < 30000 ? BAL_OK.b : await balance(5000 + 3000 * PAINT_TRY); // slow network: give each retry longer
    if (b && b.signed_in) BAL_OK = { b, t: Date.now() };
    const s = (!b || !b.signed_in) ? await session() : null;
    if (!b || (!b.signed_in && s)) { // check_balance failed, or ran before the refreshed token was ready: keep the header from the session
      if (s) hdr(true, s.user && s.user.email);
      else if (!cached() || PAINT_TRY > 0) { hdr(false); document.querySelectorAll('[data-out]').forEach(x => x.hidden = false); }
      retry(); return;
    }
    if (!b.signed_in && cached() && PAINT_TRY < 2) { retry(); return; } // cached session still being restored: don't flash signed-out yet
    $('#left').textContent = pl(b.left, T.nav_left, { n: b.left, free: b.signed_in ? '' : T.free });
    hdr(b.signed_in);
    document.querySelectorAll('[data-out]').forEach(x => x.hidden = b.signed_in);
    if (!b.signed_in) { PAINT_TRY = 0; ACCT = null; document.querySelectorAll('[data-in]').forEach(x => x.hidden = true); return; }
    const [ss, { data: a, error }] = await Promise.all([session(), sb.rpc('my_account')]);
    const email = (ss && ss.user && ss.user.email) || (window.REGRET_AU && window.REGRET_AU.email) || '';
    if (error || !a) { retry(); return; } // transient failure: try again instead of leaving the page as a bare heading
    PAINT_TRY = 0;
    ACCT = Object.assign({ email }, a);
    $('#av').textContent = (ACCT.email[0] || 'A').toUpperCase();
    $('#ddem').textContent = ACCT.email;
    const P = planOf(ACCT);
    $('#ddplan').textContent = P ? fmt(T.plan_menu, { name: P.name, n: P.checks }) : T.plan_free;
    $('#ddleft').textContent = leftOf(ACCT);
    document.querySelectorAll('[data-in]').forEach(x => x.hidden = false);
    if ($('#account')) await paintAccount(); if ($('#mychecks')) await paintMyChecks(); if ($('#myfirms')) await paintMyFirms();
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
    const a = ACCT, P = planOf(a);
    $('#aem').textContent = a.email;
    $('#aplan2').textContent = P ? (P.price ? fmt(T.plan_line, { n: P.checks, price: P.price }) : fmt(T.plan_menu, { name: P.name, n: P.checks })) : T.no_plan;
    $('#aleft').textContent = leftOf(a);
    $('#aleft2').textContent = P ? (P.yearly && a.next_refill ? fmt(T.resets_monthly, { n: P.checks, date: fmtDate(a.next_refill) }) : fmt(T.resets, { n: P.checks })) : pl(a.left, T.any_time, {});
    const ending = !!(P && a.cancel_at_period_end), end = a.period_end ? fmtDate(a.period_end) : '';
    $('#aplan').innerHTML = esc(P ? P.name : T.plan_free) + (ending ? '<span class="tag">' + T.tag_cancelling + '</span>' : '');
    if (ending && end) $('#aleft2').textContent = fmt(T.usable_until, { date: end });
    $('#arenl').textContent = ending ? T.cancels_on : T.renews;
    $('#aren').textContent = P && end ? end : '—'; $('#aren').classList.toggle('cx', ending);
    $('#aren2').textContent = ending ? T.wont_renew : P ? (P.yearly ? T.renews_yearly : T.renews_monthly) : T.nothing_renews;
    $('#cban').hidden = !ending;
    if (ending) $('#cban').innerHTML = pl(a.left, T.banner, { plan: esc(P.name), date: esc(end), left: esc(a.left) });
    $('#manage').hidden = !P && !a.has_customer; $('#pick').hidden = !!P;
    $('#cancel').hidden = !P || ending; $('#resume').hidden = !ending;
    $('#buymore').className = ending ? 'btn o' : 'btn';
    $('#canh').textContent = P ? fmt(T.cancel_title, { plan: P.name }) : '';
    $('#cans').innerHTML = fmt(T.cancel_sub, { date: esc(end || T.period_end_fallback) });
    const live = P && !ending;
    $('#dzp').textContent = live ? T.delete_desc_sub : T.delete_desc;
    $('#cons').innerHTML = [live && fmt(T.cons_sub, { plan: esc(P.name) }), pl(a.left, T.cons_left, { left: esc(a.left) }), T.cons_data]
      .filter(Boolean).map((t, i) => '<li><i>' + (i + 1) + '</i><span>' + t + '</span></li>').join('');
    $('#delgo').textContent = live ? T.delete_go_sub : T.delete_go;
    const { data: rows } = await sb.rpc('my_checks');
    const n = (rows || []).length;
    $('#mcn').textContent = n ? pl(n, T.checked_n, { n }) : T.no_checks;
    $('#mcl').textContent = n ? fmt(T.latest, { name: rows[0].name, date: fmtDate(rows[0].checked_at) }) : T.first_check;
  }
  const BM = '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2.4" stroke-linejoin="round"><path d="M6 3h12v18l-6-4-6 4z"/></svg>';
  if ($('#account')) {
    $('#manage').onclick = () => portal($('#amsg'));
    $('#emform').onsubmit = async (e) => {
      e.preventDefault(); const email = $('#nem').value.trim(); if (!email) return;
      const { error } = await sb.auth.updateUser({ email }, { emailRedirectTo: location.href.split('#')[0] });
      $('#emmsg').textContent = error ? error.message : fmt(T.email_sent, { email });
    };
    // Optional exit answer for the cancel / delete modals ({} when nothing was picked or typed)
    const why = (k) => {
      const r = document.querySelector('input[name="' + k + 'why"]:checked'), o = $('#' + k + 'other').value.trim().slice(0, 500), b = {};
      if (r) b.reason = r.value; if (o) b.other = o; return b;
    };
    const failMsg = async (error, m) => { try { const j = error && error.context && await error.context.json(); if (j && j.message) return j.message; } catch (_) { /* keep default */ } return m; };
    const setPlan = async (body, btn, out) => {
      btn.disabled = true; out.textContent = body.resume ? T.resuming : T.cancelling;
      const { data, error } = await sb.functions.invoke('cancel-subscription', { body });
      btn.disabled = false;
      if (error || !data) { out.textContent = await failMsg(error, T.plan_fail); return; }
      out.textContent = ''; ACCT.cancel_at_period_end = data.cancel_at_period_end; if (data.period_end) ACCT.period_end = data.period_end;
      closeOv($('#cancelsub')); paintAccount();
    };
    $('#cango').onclick = () => setPlan(why('can'), $('#cango'), $('#canmsg'));
    $('#resume').onclick = () => setPlan({ resume: true }, $('#resume'), $('#amsg'));
    $('#delgo').onclick = async () => {
      const go = $('#delgo'); go.disabled = true; $('#delmsg').textContent = T.deleting;
      const { data, error } = await sb.functions.invoke('delete-account', { body: why('del') });
      if (error || !data || !data.deleted) {
        $('#delmsg').textContent = await failMsg(error, T.delete_fail); go.disabled = false; return;
      }
      await sb.auth.signOut(); location.href = ROOT;
    };
  }
  // My firms page (/account/firms/): saved + checked firms from my_firms(); falls back to my_checks() until that rpc is live.
  // Results = counts of firm_check_rows display labels: Clear (clear/nf), Review (review/red), Worth knowing (wk).
  let MF = [], TAB = 'all';
  async function myFirms() {
    const r = await sb.rpc('my_firms'); if (!r.error) return r.data || [];
    const { data } = await sb.rpc('my_checks'); return (data || []).map(x => Object.assign({ checked: true }, x));
  }
  async function paintMyFirms() {
    MF = (await myFirms()).map(r => Object.assign(r, { checked: !!r.checked_at }));
    $('#flist').hidden = !MF.length; $('#fempty').hidden = !!MF.length; drawFirms();
  }
  function drawFirms() {
    const F = C.copy.site.my_firms, q = $('#fq').value.trim().toLowerCase();
    const n = { all: MF.length, saved: MF.filter(r => r.saved).length, checked: MF.filter(r => r.checked).length };
    Object.keys(n).forEach(k => { $('#fn-' + k).textContent = n[k]; });
    document.querySelectorAll('#myfirms [data-tab]').forEach(t => { const on = t.dataset.tab === TAB; t.classList.toggle('on', on); t.setAttribute('aria-selected', on); });
    const rows = MF.filter(r => (TAB === 'all' || r[TAB]) && (!q || (r.name + ' ' + (r.short_name || '') + ' ' + (r.hq || '')).toLowerCase().includes(q)));
    $('#fnone').hidden = !!rows.length; $('#fnone').textContent = TAB === 'saved' && !q ? F.none_saved : F.none;
    $('#frows').innerHTML = rows.map(r => {
      const url = ROOT + 'vc/' + encodeURIComponent(r.slug) + '/';
      const pill = (k, c) => r[k] ? '<span class="mp ' + c + '"><i></i>' + r[k] + ' ' + esc(F[k]) + '</span>' : '';
      const res = !r.checked ? '<span class="nc">' + esc(F.not_checked) + '</span>' : r.clear == null ? '<span class="nc">—</span>'
        : '<span class="pls">' + pill('clear', 'c') + pill('review', 'r') + pill('wk', 'w') + '</span>';
      return '<div class="mfr"><button type="button" class="star' + (r.saved ? ' on' : '') + '" data-star="' + esc(r.slug) + '" aria-pressed="' + !!r.saved + '" aria-label="' + fmt(r.saved ? T.unsave : T.save, { name: esc(r.name) }) + '">' + (r.saved ? '★' : '☆') + '</button>'
        + '<span class="nm3"><a href="' + esc(url) + '"><b>' + esc(r.name) + '</b></a>' + (r.hq ? '<small>' + esc(r.hq) + '</small>' : '') + '</span>'
        + '<span class="dt">' + (r.checked ? esc(fmtDate(r.checked_at)) : '—') + '</span>' + res
        + (r.checked ? '<a class="btn o" href="' + esc(url) + '">' + esc(F.open) + '</a>' : '<button type="button" class="btn" data-check="' + esc(r.slug) + '">' + esc(F.check) + '</button>') + '</div>';
    }).join('');
  }
  if ($('#myfirms')) {
    $('#fq').oninput = drawFirms;
    document.querySelectorAll('#myfirms [data-tab]').forEach(t => { t.onclick = () => { TAB = t.dataset.tab; drawFirms(); }; });
    $('#frows').onclick = async (e) => {
      // Check · 1 credit: signed out -> sign-in popup; signed in -> the firm page's own unlock flow (paycase confirm, balance,
      // out-of-credits / pick-a-plan path, firm_page(p_spend)) opens right away via ?unlock=1, and the user lands on the firm page.
      const c = e.target.closest('[data-check]');
      if (c) {
        const { data: ss } = await sb.auth.getSession().catch(() => ({ data: {} }));
        if (!(ss && ss.session)) return open('signup');
        location.href = ROOT + 'vc/' + encodeURIComponent(c.dataset.check) + '/full/?unlock=1'; return;
      }
      const b = e.target.closest('[data-star]'); if (!b) return;
      const r = MF.find(x => x.slug === b.dataset.star), on = !r.saved; b.disabled = true;
      const { data, error } = await sb.rpc(on ? 'watch_fund' : 'unwatch_fund', { p_slug: r.slug });
      if (!error && (!on || (data && data.saved))) r.saved = on;
      if (!r.saved && !r.checked) MF = MF.filter(x => x !== r);
      drawFirms();
    };
  }
  // My checks page
  let MC = [];
  async function paintMyChecks() {
    const a = ACCT, P = planOf(a), reset = P && P.yearly ? a.next_refill : a.period_end;
    $('#mbal').innerHTML = pl(a.left, T.mc_left, { left: esc(leftOf(a)) }) + (P ? T.mc_month + (reset ? fmt(T.mc_resets, { date: esc(fmtDate(reset)) }) : '') : '');
    const { data } = await sb.rpc('my_checks'); MC = data || [];
    $('#mlist').hidden = !MC.length; $('#mempty').hidden = !!MC.length; drawChecks();
  }
  function drawChecks() {
    const q = $('#mq').value.trim().toLowerCase(), so = $('#msort').value;
    const rows = MC.filter(r => !q || (r.name + ' ' + (r.short_name || '')).toLowerCase().includes(q))
      .sort((x, y) => so === 'az' ? x.name.localeCompare(y.name) : (so === 'old' ? 1 : -1) * (new Date(x.checked_at) - new Date(y.checked_at)));
    $('#mnone').hidden = !!rows.length || !MC.length;
    $('#mrows').innerHTML = rows.map(r => {
      const d = r.checked_at, url = ROOT + 'vc/' + encodeURIComponent(r.slug) + '/';
      const when = window.RegretDate ? window.RegretDate.formatWhen(d) : '';
      const st = r.active ? pl(r.cases, T.mc_active, r) : r.cases ? pl(r.cases, T.mc_closed, r) : T.mc_none;
      const nm = r.name + (r.short_name && r.short_name !== r.name ? ' (' + r.short_name + ')' : '');
      return '<div class="mr"><button type="button" class="star' + (r.saved ? ' on' : '') + '" data-star="' + esc(r.slug) + '" aria-pressed="' + !!r.saved + '" aria-label="' + fmt(r.saved ? T.unsave : T.save, { name: esc(r.name) }) + '">' + (r.saved ? '★' : '☆') + '</button>'
        + '<span class="nm2"><a href="' + esc(url) + '">' + esc(nm) + '</a></span><span class="dt">' + esc(when) + '</span><span class="st">' + st + '</span><a class="btn o" href="' + esc(url) + '">' + T.open_result + '</a></div>';
    }).join('');
  }
  if ($('#mychecks')) {
    $('#mq').oninput = drawChecks; $('#msort').onchange = drawChecks;
    $('#mrows').onclick = async (e) => {
      // Check · 1 credit: signed out -> sign-in popup; signed in -> the firm page's own unlock flow (paycase confirm, balance,
      // out-of-credits / pick-a-plan path, firm_page(p_spend)) opens right away via ?unlock=1, and the user lands on the firm page.
      const c = e.target.closest('[data-check]');
      if (c) {
        const { data: ss } = await sb.auth.getSession().catch(() => ({ data: {} }));
        if (!(ss && ss.session)) return open('signup');
        location.href = ROOT + 'vc/' + encodeURIComponent(c.dataset.check) + '/full/?unlock=1'; return;
      }
      const b = e.target.closest('[data-star]'); if (!b) return;
      const r = MC.find(x => x.slug === b.dataset.star), on = !r.saved; b.disabled = true;
      const { data, error } = await sb.rpc(on ? 'watch_fund' : 'unwatch_fund', { p_slug: r.slug });
      if (!error && (!on || (data && data.saved))) r.saved = on;
      drawChecks();
    };
  }
  // Pricing popups: Monthly|Yearly toggle, "Have a code?" field and plan cards (both popups), all from copy.json plans.
  const K = C.copy.site.code, PAY = C.copy.site.pay;
  const CHK = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';
  let YEARLY = false, CODE = null; // CODE = validate-code reply for the applied code
  const money = (x) => '$' + (Math.round(x * 100) % 100 ? x.toFixed(2) : String(Math.round(x)));
  const offOf = (c) => c.percent_off ? fmt(T.off_pct, { p: c.percent_off }) : fmt(T.off_amt, { a: money(c.amount_off) });
  // How long a code's discount lasts on this kind, from the coupon's real duration (validate-code) and the plan's billing interval.
  // Stripe discounts every invoice inside a repeating coupon's N months, so on a yearly plan N months = the first ceil(N/12) yearly payments.
  const yearlyKind = (kind) => /^y/.test(kind) || (kind === 'code' && !!CODE && !!CODE.hidden && CODE.hidden.interval === 'year');
  const codeLabel = (c, kind) => {
    const o = { off: offOf(c) };
    if (kind === 'single') return fmt(T.dur_now, o);
    const yr = yearlyKind(kind);
    if (c.duration === 'forever') return fmt(yr ? T.dur_forever_year : T.dur_forever_month, o);
    if (c.duration === 'once') return fmt(yr ? T.dur_first_year : T.dur_once, o);
    return yr ? pl(Math.ceil(c.months / 12), T.dur_years, Object.assign(o, { n: Math.ceil(c.months / 12) })) : pl(c.months, T.dur_repeating, Object.assign(o, { n: c.months }));
  };
  // The plan kind the "Code applied" note describes: the unlocked plan, else a discounted plan on the shown Monthly/Yearly tab, else Single check
  const noteKind = (c) => c.hidden ? 'code' : c.kinds.find(k => k !== 'single' && /^y/.test(k) === YEARLY) || 'single';
  const after = (amt, c) => Math.max(0, c.percent_off ? amt * (1 - c.percent_off / 100) : amt - c.amount_off);
  const off = (kind) => CODE && (kind === 'code' ? CODE.hidden && CODE.hidden.discount : CODE.discount && CODE.kinds.includes(kind)) ? CODE : null; // code discount for this kind, if any
  // One plan card: v = {kind, name, amount, price, unit, per, bill, blurb, button, features, tag, save, rec, hid}
  function card(v, nav) {
    const c = off(v.kind), now = c ? money(after(v.amount, c)) : v.price;
    const old = c ? '<s>' + v.price + '</s>' : '';
    const bill = !c ? v.bill : c.duration === 'forever' || v.kind === 'single' ? fmt(T.disc_bill_forever, { label: codeLabel(c, v.kind) }) : fmt(T.disc_bill, { label: codeLabel(c, v.kind), price: v.price, unit: v.unit });
    const save = v.save ? '<span class="save">' + v.save + '</span>' : '';
    if (nav) return '<div class="pr' + (v.rec ? ' hl' : '') + (v.hid ? ' hid' : '') + '"><h4>' + esc(v.name) + '</h4><b>' + old + now + (v.short ? '<small>' + v.short + '</small>' : '') + '</b>' + save + '<p>' + esc(c ? bill : v.blurb) + '</p><button class="btn' + (v.rec ? '' : ' o') + '" data-buy="' + v.kind + '">' + esc(v.button) + '</button></div>';
    return '<div class="pl' + (v.rec ? ' rec' : '') + (v.hid ? ' hid' : '') + '">' + (v.tag ? '<span class="rtag' + (v.hid ? ' g' : '') + '">' + esc(v.tag) + '</span>' : '') + '<h3>' + esc(v.name) + '</h3>'
      + '<div class="pp-price">' + old + '<b>' + now + '</b><span>' + v.unit + '</span><small>' + fmt(PAY.per_check, { price: v.per }) + '</small></div>' + save + '<p class="bill">' + esc(bill) + '</p>'
      + '<button class="pb ' + (v.rec ? 'c' : 'w') + '" data-buy="' + v.kind + '">' + esc(v.button) + '</button><ul>' + v.features.map(f => '<li><i>' + CHK + '</i>' + f + '</li>').join('') + '</ul></div>';
  }
  function cards() {
    const out = Object.entries(C.copy.plans).filter(([k]) => k[0] !== '_').map(([k, p]) => {
      const y = YEARLY && p.yearly, base = { name: p.name, button: p.pay.button, features: p.pay.features, tag: p.tag, rec: p.highlight };
      if (y) return Object.assign(base, { kind: y.kind, amount: y.amount, price: y.price, unit: B.per_year, short: B.per_year_short, per: y.per_check, bill: y.bill, blurb: y.blurb, save: y.save });
      return Object.assign(base, { kind: k, amount: p.amount, price: p.price, unit: p.monthly ? B.per_month : p.pay.period, short: p.monthly ? B.per_month_short : '', per: p.per_check, bill: p.pay.bill, blurb: p.modal.blurb });
    });
    const h = CODE && CODE.hidden;
    if (h) {
      const yr = h.interval === 'year', amt = h.amount, n = h.checks; // validate-code amounts are in dollars
      out.push({ kind: 'code', hid: true, name: h.name, amount: amt, price: money(amt), unit: yr ? B.per_year : B.per_month, short: yr ? B.per_year_short : B.per_month_short,
        per: money(amt / n / (yr ? 12 : 1)), bill: fmt(yr ? K.hidden_bill_year : K.hidden_bill, { n }), blurb: fmt(K.hidden_blurb, { n }), tag: K.hidden_tag,
        button: fmt(K.hidden_button, { name: h.name }), features: K.hidden_features.map(f => fmt(f, { n })) });
    }
    return out;
  }
  function drawPlans() {
    const cs = cards();
    document.querySelectorAll('[data-plans]').forEach((el) => {
      el.innerHTML = cs.map(v => card(v, el.dataset.plans === 'nav')).join('');
      el.classList.toggle('four', cs.length > 3);
    });
    document.querySelectorAll('.bt button').forEach((b) => { const on = (b.dataset.yearly === '1') === YEARLY; b.classList.toggle('on', on); b.setAttribute('aria-checked', String(on)); });
    document.querySelectorAll('[data-fine]').forEach(f => f.textContent = YEARLY ? B.fine_yearly : PAY.fine);
    if (CODE) codeState('ok', codeNote(CODE), true);
  }
  function codeState(cls, text, applied) {
    document.querySelectorAll('.code').forEach((w) => {
      const f = w.querySelector('[data-code]'), m = w.querySelector('[data-codemsg]');
      f.hidden = false; w.querySelector('[data-codeopen]').hidden = true;
      f.classList.remove('ok', 'bad'); m.classList.remove('ok', 'bad'); if (cls) { f.classList.add(cls); m.classList.add(cls); }
      m.textContent = text; f.querySelector('[data-remove]').hidden = !applied; f.querySelector('[data-apply]').hidden = applied; f.code.readOnly = applied;
    });
  }
  async function applyCode(raw) {
    const code = raw.trim().toUpperCase();
    document.querySelectorAll('[data-code] input').forEach(i => i.value = code);
    if (!code || !sb) return;
    codeState('', T.code_checking, false);
    const { data } = await sb.functions.invoke('validate-code', { body: { code } });
    if (!data || !data.ok) { CODE = null; drawPlans(); return codeState('bad', T.code_bad, false); }
    CODE = data; drawPlans();
  }
  function codeNote(c) {
    const h = c.hidden, label = h ? fmt(h.discount ? T.code_unlock_off : T.code_unlock, { name: h.name, off: h.discount ? codeLabel(c, 'code') : '' }) : codeLabel(c, noteKind(c));
    return fmt(T.code_ok, { label });
  }
  document.addEventListener('click', (e) => {
    const t = e.target.closest('.bt button,[data-codeopen],[data-remove]'); if (!t) return;
    e.preventDefault();
    if (t.matches('.bt button')) { YEARLY = t.dataset.yearly === '1'; return drawPlans(); }
    if (t.dataset.codeopen !== undefined) { codeState('', '', false); return t.closest('.code').querySelector('input').focus(); }
    CODE = null; drawPlans(); codeState('', '', false); document.querySelectorAll('[data-code] input').forEach(i => i.value = '');
  });
  document.addEventListener('click', (e) => { const a = e.target.closest('[data-portal]'); if (a) { e.preventDefault(); portal(a.parentNode); } });
  document.addEventListener('submit', (e) => { const f = e.target.closest('[data-code]'); if (!f) return; e.preventDefault(); if (!f.code.readOnly) applyCode(f.code.value); });
  const O = C.copy.site.outcredits;
  let OUT_KIND = '';
  const highlighted = () => { const hit = Object.entries(C.copy.plans).find(([k, p]) => k[0] !== '_' && p.highlight); return hit ? hit[0] : 'm10'; };
  function outKind() { const r = document.querySelector('#outplans input:checked'); return (r && r.value) || OUT_KIND || highlighted(); }
  function drawOut() {
    const box = $('#outplans'); if (!box || !O) return;
    box.innerHTML = ['single', 'm10', 'm30'].map((k) => {
      const p = C.copy.plans[k]; if (!p) return '';
      const y = p.yearly && OUT_KIND === p.yearly.kind ? p.yearly : null;
      const kind = y ? y.kind : k, on = kind === (OUT_KIND || highlighted());
      const price = y ? y.price + B.per_year_short : (p.monthly ? p.price + B.per_month_short : p.price);
      const line = (y ? y.bill : (p.monthly ? pl(p.checks, O.line_month, { n: p.checks }) : pl(p.checks, O.line_once, { n: p.checks }))) + (!y && p.tag ? ' · ' + p.tag : '');
      return '<label class="orow"><input type="radio" name="outplan" value="' + kind + '"' + (on ? ' checked' : '') + '><span class="tx"><b>' + esc(p.name) + '</b><small>' + esc(line) + '</small></span><em>' + esc(price) + '</em></label>';
    }).join('');
    box.querySelectorAll('input').forEach((r) => { r.onchange = () => { OUT_KIND = r.value; }; });
  }
  function openOut(kind) {
    OUT_KIND = kind || highlighted();
    const firm = PAGE && PAGE.firm && PAGE.firm.name, lab = $('#outfirm');
    if (lab) { lab.hidden = !firm; lab.textContent = firm || ''; }
    const msg = $('#outmsg'); if (msg) msg.textContent = '';
    drawOut(); open('outcredits');
  }
  async function checkout(kind, extra, out) {
    const msg = (t) => { if (out) out.textContent = t; else if (t && !/…$/.test(t)) alert(t); };
    document.querySelectorAll('[data-buy],#outgo').forEach(b => b.disabled = true); msg(T.opening);
    const { data, error } = await sb.functions.invoke('create-checkout', { body: Object.assign({ kind, return_path: location.pathname }, extra || {}, CODE ? { code: CODE.code } : {}) });
    if (error || !data || !data.url) {
      document.querySelectorAll('[data-buy],#outgo').forEach(b => b.disabled = false);
      const j = error && error.context ? await error.context.json().catch(() => null) : null;
      if (j && j.has_plan && out) return (out.innerHTML = esc(T.has_plan) + ' <a href="#" data-portal>' + esc(T.has_plan_link) + '</a>'); // plan changes go through the billing portal
      return msg(T.checkout_fail);
    }
    location.href = data.url;
  }
  async function buy(kind) {
    if (!sb) return alert(T.no_checkout);
    const { data: s } = await sb.auth.getSession();
    const pay = $('#paycase'), inPay = pay && !pay.hidden, oc = $('#outcredits'), inOut = oc && !oc.hidden;
    const out = inPay ? $('#pmsg2') : inOut ? $('#outmsg') : $('#pwmsg');
    if (!s.session) { // a purchase does not rewrite the Sign in popup ("Sign in to buy" / "No card needed")
      if (oc) return openOut(kind);
      location.href = ROOT + 'login/';
      return;
    }
    return checkout(kind, null, out);
  }
  // Auth
  const back = () => location.href.split('#')[0];
  const google = async (e) => {
    if (e && e.preventDefault) e.preventDefault();
    if (!sb) return alert(T.error); // no Supabase client (config or CDN script missing): say so instead of a dead button
    const b = e && e.currentTarget && e.currentTarget.classList.contains('gbx') ? e.currentTarget : null;
    if (b && b._html == null) b._html = b.innerHTML; // original label, restored on error or Back (bfcache)
    const was = b && b._html;
    if (b) { const since = b._pd ? performance.now() - b._pd : 0; b._pd = 0; b.classList.add('prs'); await new Promise(r => setTimeout(r, Math.max(0, 140 - since))); } // keep the pressed frame on screen >=120ms
    if (b) { b.classList.remove('prs'); b.disabled = true; b.classList.add('ld'); b.innerHTML = '<span class="spin" aria-hidden="true"></span><span class="gl">' + esc(T.google_loading) + '</span>'; }
    try { if (/^\/vc\/[^/]+\/(full\/)?$/.test(location.pathname)) sessionStorage.setItem('rg_ret', JSON.stringify({ p: location.pathname, t: Date.now() })); } catch (x) {} // return to this firm page after Google sign-in
    const { error } = await sb.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: back() } }).catch((x) => ({ error: x }));
    if (error && b) { b.disabled = false; b.classList.remove('ld'); b.innerHTML = was; }
  };
  const magic = async (email, out) => {
    if (!sb || !email) return;
    const { error } = await sb.auth.signInWithOtp({ email, options: { emailRedirectTo: back() } });
    out.textContent = error ? error.message : T.magic_sent;
  };
  const m = $('#magic'); if (m) m.onclick = () => magic($('#em').value.trim(), $('#sumsg'));
  document.querySelectorAll('[data-google],#google').forEach(b => b.onclick = (e) => {
    if (b.closest('#outcredits')) setPend(outKind(), CODE && CODE.code); // Google creates the account, then the return continues to checkout
    return google(e);
  });
  const og = $('#outgo'); if (og) og.onclick = () => {
    if (!sb) return alert(T.no_checkout);
    clearPend(); // email checkout must not resume a second purchase after the return signs them in
    const em = $('#outem'); em.value = em.value.trim();
    if (!em.value || !em.checkValidity()) { $('#outmsg').textContent = T.req_bad_email; return; }
    checkout(outKind(), { email: em.value }, $('#outmsg'));
  };
  async function claimPaid(sid) { // paid guest return: sign in from the Checkout session, then ask Supabase to email a magic link
    const { data, error } = await sb.functions.invoke('claim-checkout', { body: { session_id: sid } });
    if (error || !data || data.already || !data.token_hash) return;
    await sb.auth.verifyOtp({ token_hash: data.token_hash, type: data.type || 'magiclink' }).catch(() => ({}));
    if (data.email) await sb.auth.signInWithOtp({ email: data.email, options: { emailRedirectTo: back(), shouldCreateUser: false } }).catch(() => {});
  }
  if (PAID_SID && sb) claimPaid(PAID_SID);
  document.querySelectorAll('.gbx').forEach(b => { // touch: :active is unreliable, so mirror it with a class
    b.addEventListener('pointerdown', () => { b._pd = performance.now(); b.classList.add('prs'); });
    ['pointerup', 'pointercancel', 'pointerleave'].forEach(t => b.addEventListener(t, () => setTimeout(() => b.classList.remove('prs'), Math.max(0, 120 - (performance.now() - (b._pd || 0))))));
  });
  window.addEventListener('pageshow', (ev) => { // Back from Google restores the page from bfcache with the spinner still on
    if (!ev.persisted) return;
    document.querySelectorAll('.gbx.ld').forEach(b => { b.disabled = false; b.classList.remove('ld', 'prs'); if (b._html != null) b.innerHTML = b._html; });
  });
  document.querySelectorAll('[data-magic]').forEach(f => f.onsubmit = (e) => { e.preventDefault(); magic(f.email.value.trim(), f.parentNode.parentNode.querySelector('[data-magicmsg]')); });
  if (sb) sb.auth.onAuthStateChange((ev, session) => {
    if ((ev === 'SIGNED_IN' || ev === 'INITIAL_SESSION') && session) { try { const r = JSON.parse(sessionStorage.getItem('rg_ret') || 'null'); sessionStorage.removeItem('rg_ret'); if (r && Date.now() - r.t < 600000 && typeof r.p === 'string' && /^\/vc\/[^/]+\/(full\/)?$/.test(r.p) && r.p !== location.pathname) { location.replace(location.origin + r.p); return; } } catch (x) {} }
    if (ev === 'SIGNED_IN') setTimeout(() => { PAINT_TRY = 0; paint(); }, 0); // nothing transfers at sign-in: the account has its own 4
    else if ((ev === 'INITIAL_SESSION' || ev === 'TOKEN_REFRESHED') && session && !ACCT && !PAINT_TRY) setTimeout(() => { paint(); }, 0); // session became usable after the first paint
    if (ev === 'SIGNED_OUT') setTimeout(() => { PAINT_TRY = 0; ACCT = null; BAL_OK = null; paint(); }, 0);
    if ((ev === 'SIGNED_IN' || ev === 'INITIAL_SESSION') && session) { const p = takePend(); if (p) setTimeout(async () => { if ($('#paycase')) open('paycase'); YEARLY = /^y/.test(p.k); drawPlans(); if (p.code) await applyCode(p.code); if (p.k !== 'code' || CODE) buy(p.k); }, 0); }
  });
  const main = document.querySelector('main[data-firm]');
  // Search dropdown: firm_suggest() (max 8; prefix, then word, then contains). No match: run a live check.
  const esc = (x) => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  drawPlans();
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
        : '<a class="so2 none" href="' + esc(liveUrl(q)) + '">' + T.suggest_none + '</a>';
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
    // Check: the highlighted suggestion, else an exact name / short name / slug match. On a firm page the box is prefilled with the
    // firm's own name and no suggestions were ever fetched (hits = []), so that name maps straight to this firm; any other query with no
    // fetched hits asks firm_suggest() first, and only a query with no exact match goes to /pending/.
    const same = (x, q) => [x.name, x.short_name, x.slug].some(v => v && v.toLowerCase() === q.toLowerCase());
    f.onsubmit = async (e) => {
      e.preventDefault(); const q = inp.value.trim(); if (!q) return;
      let h = !box.hidden && hits[act] || hits.find(x => same(x, q));
      if (!h && main && q.toLowerCase() === inp.defaultValue.trim().toLowerCase()) h = { slug: main.dataset.firm };
      if (!h && sb) { const n = ++seq; const { data } = await Promise.resolve(sb.rpc('firm_suggest', { q })).catch(() => ({})); if (n === seq) h = (data || []).find(x => same(x, q)); }
      if (main && h && h.slug === main.dataset.firm) {
        show(false);
        if (main.dataset.tab === 'full' && window.RegretCompany && window.RegretCompany.applyTab) {
          window.RegretCompany.applyTab(main, 'checks');
          const base = location.pathname.replace(/full\/$/, '');
          history.pushState({ tab: 'checks' }, '', base + location.search);
        }
        return;
      }
      location.href = h ? firmUrl(h.slug) : liveUrl(q);
    };
  });
  // Unknown firm
  const pq = $('#pq');
  if (pq) {
    const q = new URLSearchParams(location.search).get('q') || T.this_firm; pq.textContent = q;
    $('#notify').onsubmit = async (e) => {
      e.preventDefault(); if (!sb) return;
      // "Request this firm" (docs/FIRM_REQUESTS.md): deduped by name, rate-limited and email-checked in request_firm().
      const { data, error } = await sb.rpc('request_firm', { p_name: q, p_email: e.target.email.value.trim(), p_website: e.target.website.value.trim() || null, p_anon: anonId() });
      const st = data && data.status, m = $('#pmsg');
      if (st === 'exists') { m.innerHTML = esc(T.req_exists) + '<a href="' + esc(firmUrl(data.slug)) + '">' + esc(q) + '</a>'; return; }
      m.textContent = error || !st ? T.error : st === 'ok' ? (data.already_requested ? T.req_dup : T.notify_ok) : st === 'bad_email' ? T.req_bad_email
        : st === 'bad_website' ? T.req_bad_website : st === 'bad_name' ? T.req_bad_name : st === 'rate_limited' ? T.req_rate : T.error;
    };
  }
  // Company page: one firm_page() call returns everything (locked: counts + one line per section only).
  let BAL = null, PAGE = null, VIEW = null, SEC = '';
  // 'Not checked yet' / partial page: 'Check with 1 credit' buys on-demand research (docs/ON_DEMAND.md). Only when the firm has
  // nothing to research from (firm_page answers 'unchecked') is the visitor sent to the request-a-check form instead.
  const toRequest = () => { location.href = liveUrl((PAGE && PAGE.firm && PAGE.firm.name) || main.dataset.firm); };
  // Research still to start (unchecked page, or any of the 10 checks still Not checked yet). The optional
  // ready-email field is only for that case, and only while signed out. A finished firm has no email field.
  function needsResearch() {
    return !!(PAGE && (PAGE.unchecked || (PAGE.done != null && PAGE.done < 10)));
  }
  async function openPay(sec) {
    SEC = sec || '';
    const P = C.copy.site.pay;
    $('#pph').textContent = (PAGE && PAGE.firm && PAGE.firm.name) || '';
    $('#pmsg2').textContent = '';
    const ub = $('#usecheck'); ub.disabled = true; ub.textContent = P.check;
    const ready = $('#pready'), help = $('#preadyh'), sign = $('#psign');
    if (ready) ready.hidden = true; if (help) help.hidden = true;
    open('paycase');
    const { data: ss } = sb ? await sb.auth.getSession().catch(() => ({ data: {} })) : { data: {} }; // session first (local, no network)
    BAL = await balance();
    const signed = !!(BAL && BAL.signed_in) || !!(ss && ss.session);
    const showEmail = !signed && needsResearch();
    if (ready) ready.hidden = !showEmail;
    if (help) help.hidden = !showEmail;
    if (sign) sign.hidden = signed;
    if (!BAL) {
      $('#pmsg2').innerHTML = esc(T.balance_fail) + ' <a href="#" data-retry>' + esc(T.retry) + '</a>';
      $('#pmsg2').querySelector('[data-retry]').onclick = (e) => { e.preventDefault(); openPay(SEC); };
      return;
    }
    ub.disabled = false;
    if (showEmail) {
      const em = ready.querySelector('input[type=email]'), n = main && main.querySelector('[data-notify] input[type=email]');
      if (em && n && n.value.trim() && !em.value.trim()) em.value = n.value.trim();
    }
  }
  // Save button by the firm name, on every firm page (checked or not). Signed out: opens the sign-in popup (data-open, handled above).
  // Signed in: shows the saved state from my_firms() (my_checks() fallback) and toggles watch_fund / unwatch_fund.
  // A click that lands before the session / saved state is known is queued and applied once they are (first click always counts).
  // saveBtn() runs more than once per load: only the newest run wires the button, and a saved-state read that started before
  // a click never overwrites what the click set.
  let SAVE_GEN = 0, SAVE_Q = false, SAVE_N = 0;
  async function saveBtn() {
    const b = main.querySelector('[data-save]'); if (!b || !sb) return;
    const g = ++SAVE_GEN;
    const set = (on) => { b.classList.toggle('on', on); b.setAttribute('aria-pressed', on); b.querySelector('span').textContent = on ? T.saved : T.save_btn; };
    if (!b.dataset.open) b.onclick = () => { SAVE_Q = true; };
    const ss = await session();
    if (g !== SAVE_GEN) return;
    if (!ss) { set(false); b.dataset.open = 'signup'; b.onclick = null; if (SAVE_Q) { SAVE_Q = false; b.click(); } return; }
    delete b.dataset.open;
    const toggle = async () => {
      // Show 'Saved' right away; put it back only if the save fails.
      SAVE_N++; const on = !b.classList.contains('on'); b.disabled = true; set(on);
      const { data: d, error } = await sb.rpc(on ? 'watch_fund' : 'unwatch_fund', { p_slug: main.dataset.firm });
      b.disabled = false; if (error || (on && !(d && d.saved))) set(!on);
    };
    const n = SAVE_N;
    const r = (await myFirms().catch(() => [])).find(x => x.slug === main.dataset.firm);
    if (g !== SAVE_GEN) return;
    if (n === SAVE_N) set(!!(r && r.saved));
    b.onclick = () => { SAVE_Q = false; toggle(); };
    if (SAVE_Q) { SAVE_Q = false; toggle(); }
  }
  // Summary page, 10 checks not all done (page views never move the firm in the queue). While it is queued or claimed, poll every 10 s,
  // re-render with the real rows when a check finishes or the claim changes (the Checking view shows only while claimed),
  // and show "Check complete" when all 10 are done.
  let ST = null, POLL = null, NOTIFY = false;
  async function checking() {
    const live = VIEW && VIEW.pending && (VIEW.queue === 'queued' || VIEW.queue === 'claimed');
    if (!sb || !VIEW || !VIEW.pending) { if (POLL) { clearInterval(POLL); POLL = null; } return; }
    if (!live) { if (POLL) { clearInterval(POLL); POLL = null; } return; }
    if ((VIEW.checking || VIEW.research) && !NOTIFY) notifyBox();
    if (!POLL) POLL = setInterval(pollChecks, 10000);
    if (!ST) pollChecks();
  }
  async function pollChecks() {
    if (document.hidden) return;
    const { data } = await Promise.resolve(sb.rpc('firm_check_status', { p_slug: main.dataset.firm })).catch(() => ({}));
    if (!data || data.status !== 'ok') return;
    // Locked firm_page nulls check states, so a state !== 'nc' count would look finished and reload at once.
    const was = !PAGE ? -1 : PAGE.done != null ? PAGE.done : (PAGE.checks || []).filter(r => r.state !== 'nc').length, wasQ = VIEW ? VIEW.queue : undefined;
    ST = data;
    if (data.done !== was) { if (data.complete) ST.just_done = true; return loadPage(false); }
    if (VIEW && (VIEW.checking || VIEW.research || data.queue !== wasQ)) {
      const y = window.scrollY;
      VIEW = window.RegretCompany.paint(main, PAGE, ST);
      window.scrollTo(0, y);
      checking();
    }
  }
  async function notifyBox() {
    const f = main.querySelector('[data-notify]'); if (!f) return; NOTIFY = true;
    const K = C.copy.company.checking, inp = f.email, msg = f.querySelector('.cmsg');
    const { data: ss } = await sb.auth.getSession().catch(() => ({ data: {} }));
    const em = ss && ss.session && ss.session.user.email;
    if (em) { inp.value = em; inp.readOnly = true; f.querySelector('.cin em').hidden = false; }
    f.onsubmit = async (e) => {
      e.preventDefault(); const b = f.querySelector('button'); b.disabled = true;
      const { data, error } = await sb.rpc('notify_when_checked', { p_slug: main.dataset.firm, p_email: inp.value, p_anon: anonId() });
      b.disabled = false;
      const st = error ? 'err' : data && data.status;
      msg.textContent = st === 'ok' ? K.email_ok.replace('{email}', inp.value.trim()) : st === 'bad_email' ? K.email_bad : st === 'rate_limited' ? K.email_limit : K.email_err;
    };
  }
  function draw(P) {
    PAGE = P; VIEW = window.RegretCompany.paint(main, P, ST); main.classList.remove('ld'); saveBtn(); checking();
    const id = decodeURIComponent(location.hash.slice(1)), t = id && document.getElementById(id);
    if (!t) return;
    if (t.closest('#panel-full')) window.RegretCompany.applyTab(main, 'full');
    else if (t.closest('#panel-checks')) window.RegretCompany.applyTab(main, 'checks');
    t.scrollIntoView();
  }
  // firm_page() failed or took longer than 10 s and nothing is drawn yet: swap the grey skeleton for "Couldn't load this firm" + Retry.
  // Save, the fine print and (on /full/) the unlock card still show. Retry puts the skeleton back and calls firm_page() again.
  const SKEL = main ? main.innerHTML : '';
  function loadFail() {
    if (PAGE) return; // a page is already drawn (e.g. a background refresh failed): keep it
    main.classList.remove('ld'); main.classList.add('lderr');
    main.querySelectorAll('.sk, .skc, .skp').forEach(x => x.remove());
    ['.kf', '.hfs', '.csum', '.spl', '.toc', '.ph .m'].forEach(q => { const x = main.querySelector(q); if (x) x.style.display = 'none'; });
    const box = '<div class="lfail" role="alert"><b>' + esc(T.load_fail_h) + '</b><p>' + esc(T.load_fail_p) + '</p><button type="button" class="btn" data-reload>' + esc(T.load_retry) + '</button></div>';
    const tgt = main.querySelector('.list') || main.querySelector('.pmain'); if (tgt) tgt.innerHTML = box;
    const lc = main.querySelector('#lockcard');
    if (lc) { lc.hidden = false; lc.querySelector('b').textContent = C.copy.company.locked; lc.querySelector('p').textContent = C.copy.company.lockcard_sub; }
    main.querySelector('[data-reload]').onclick = () => { main.innerHTML = SKEL; main.classList.remove('lderr'); main.classList.add('ld'); bindMain(); loadPage(false).then(paint); };
    saveBtn();
  }
  // Optional address for an unresearched firm. Empty is allowed. A finished firm sends nothing.
  function typedEmail() {
    const ready = $('#pready'), em = ready && !ready.hidden && ready.querySelector('input[type=email]');
    const v = em && em.value ? em.value.trim() : '';
    if (v) return v;
    const n = document.querySelector('[data-notify] input[type=email]');
    return n && n.value && n.value.trim() ? n.value.trim() : null;
  }
  async function loadPage(spend, retry) {
    if (!sb) return loadFail();
    const to = new Promise(r => setTimeout(() => r({ error: 'timeout' }), spend ? 20000 : 10000));
    const { data, error } = await Promise.race([Promise.resolve(sb.rpc('firm_page', { p_slug: main.dataset.firm, p_anon: anonId(), p_spend: spend, p_email: spend ? typedEmail() : null })), to]).catch(e => ({ error: e }));
    if ((error || !data) && !spend && !retry && !PAGE) { await new Promise(r => setTimeout(r, 1500)); return loadPage(false, true); } // one quiet retry after a pause (slow session refresh / expired token)
    if (error || !data) { if (spend) $('#pmsg2').textContent = T.error; else loadFail(); return; }
    if (!spend && !['ok', 'need_signup', 'out'].includes(data.status)) return loadFail();
    if (data.status === 'ok') {
      // A slower locked firm_page (the first paint) must not cover an unlock that already landed.
      if (!data.open && PAGE && PAGE.open) return;
      if (data.open) closeOv($('#paycase'));
      return draw(data);
    }
    if (data.status === 'unchecked') return toRequest();
    if (data.status === 'need_signup') { $('#pmsg2').textContent = T.need_signup; const ub = $('#usecheck'); if (ub) ub.disabled = false; }
    if (data.status === 'out') {
      const ub = $('#usecheck'); if (ub) ub.disabled = false;
      const { data: ss } = await sb.auth.getSession().catch(() => ({ data: {} }));
      if (ss && ss.session) buy('single'); else openOut();
    }
  }
  window.RegretActList = async (slug, kind) => { if (!sb) return null; const { data, error } = await Promise.resolve(sb.rpc('firm_activity_list', { p_slug: slug, p_anon: anonId(), p_kind: kind })).catch(e => ({ error: e })); return error ? null : data; };
  // The Checks / Full report control is the one from 843bff8. That commit used a link, which loaded
  // the other URL and drew the header again. Here the two panels are already in the page, so the
  // click only shows one of them. The header above the control is left as it is, and the scroll stays.
  // The tab control is a button or link that carries data-tab. The firm page root carries the same
  // attribute as state, so a click on Check or a suggestion must not count as a tab click.
  function firmPageTab(target, root) {
    const tab = target.closest('[data-tab="checks"], [data-tab="full"]');
    return tab && tab !== root && root.contains(tab) ? tab.dataset.tab : '';
  }
  function goTab(which) {
    if (!window.RegretCompany || !window.RegretCompany.applyTab) return;
    const y = window.scrollY;
    window.RegretCompany.applyTab(main, which);
    const base = location.pathname.replace(/full\/$/, '');
    const url = (which === 'full' ? base + 'full/' : base) + location.search;
    if (location.pathname + location.search !== url) history.pushState({ tab: which }, '', url);
    window.scrollTo(0, y);
  }
  if (main) {
    window.addEventListener('popstate', () => {
      const y = window.scrollY;
      if (window.RegretCompany && window.RegretCompany.applyTab) window.RegretCompany.applyTab(main, /\/full\/$/.test(location.pathname) ? 'full' : 'checks');
      window.scrollTo(0, y);
    });
    // Tab buttons show the other panel in place. Anchors still scroll, and do not jump back to the top.
    // main itself has data-tab for the panel that is showing. closest() would match that on every click
    // in the page, cancel the click, and the search box could neither submit nor follow a suggestion.
    document.addEventListener('click', (e) => {
      const which = firmPageTab(e.target, main);
      if (which) { e.preventDefault(); goTab(which); return; }
      const a = e.target.closest('a[href^="#"]'), id = a && a.getAttribute('href').slice(1), t = id && document.getElementById(id); if (!t) return;
      e.preventDefault(); t.scrollIntoView({ behavior: 'smooth' }); history.pushState(null, '', '#' + id);
    });
    var bindMain = () => { if ($('#unlock')) $('#unlock').onclick = () => openPay(''); };
    bindMain();
    main.addEventListener('click', (e) => { const s = !main.classList.contains('unlocked') && e.target.closest('[data-sec]'); if (s) openPay(s.dataset.sec); });
    // "Check with 1 credit" opens the unlock popup for everyone and does not spend. "Check this firm" spends a
    // credit when one is left (no email required). With none left it starts single-credit checkout.
    main.addEventListener('click', async (e) => {
      const b = e.target.closest('[data-gate]'); if (!b) return;
      if (!sb) return;
      openPay('');
    });
    if ($('#usecheck')) $('#usecheck').onclick = async () => {
      const ub = $('#usecheck'), label = C.copy.site.pay.check;
      const showBusy = () => { ub.disabled = true; ub.innerHTML = '<span class="sp" aria-hidden="true"></span> ' + esc(C.copy.company.checking.current); };
      const showReady = () => { ub.disabled = false; ub.textContent = label; };
      showBusy();
      const ready = $('#pready'), em = ready && !ready.hidden && ready.querySelector('input[type=email]');
      if (em && em.value.trim()) {
        em.value = em.value.trim();
        if (!em.checkValidity()) { $('#pmsg2').textContent = C.copy.company.checking.email_bad; showReady(); return; }
      } else if (em) em.value = '';
      if (!BAL) BAL = await balance();
      if (!BAL) { showReady(); return openPay(SEC); }
      if (BAL.left > 0) {
        loadPage(true).then(paint).finally(async () => { BAL = await balance(); if (!(PAGE && PAGE.open)) showReady(); });
        return;
      }
      showReady();
      const { data: ss } = await sb.auth.getSession().catch(() => ({ data: {} }));
      if (ss && ss.session) buy('single'); else openOut();
    };
    if (!sb) loadFail(); // no Supabase client (config or CDN script missing): never leave the skeleton up
    if (sb) {
      // getSession() can stall (auth lock / token refresh); never let it hold the skeleton: give up after 3 s and load anyway.
      const first = Promise.race([sb.auth.getSession().catch(() => ({ data: {} })), new Promise(r => setTimeout(() => r({ data: {} }), 3000))]).then(({ data }) => { const uid = data && data.session && data.session.user.id; return loadPage(false).then(paint).then(() => uid); });
      // From My firms "Check · 1 credit" (?unlock=1): once the page is drawn and still locked, open the same unlock popup as the lock card.
      if (new URLSearchParams(location.search).get('unlock') === '1') {
        history.replaceState(null, '', location.pathname + location.hash);
        first.then(() => { if (PAGE && !PAGE.open && $('#paycase')) openPay(''); });
      }
      // The session can resolve after the 3 s cutoff (INITIAL_SESSION / TOKEN_REFRESHED late): if the page was loaded without it, load it again with it.
      let LOADED_AS = null; first.then((uid) => { LOADED_AS = uid || null; });
      sb.auth.onAuthStateChange((ev, s) => {
        if (!['SIGNED_IN', 'INITIAL_SESSION', 'TOKEN_REFRESHED'].includes(ev) || !s) return;
        first.then(() => { if (s.user.id !== LOADED_AS && !(PAGE && PAGE.open)) { LOADED_AS = s.user.id; setTimeout(() => loadPage(false).then(paint).then(saveBtn), 300); } });
      });
    }
  }
  if (!main) paint();
})();
