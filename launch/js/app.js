/* Regretamin launch: search, check counter, sign-up (Google + magic link), paywall, unknown-firm queue, account menu, Account and My checks pages. */
(function () {
  const C = window.REGRET || {}, ROOT = window.REGRET_ROOT || '';
  const sb = C.url && C.key && window.supabase ? window.supabase.createClient(C.url, C.key) : null;
  const $ = (s) => document.querySelector(s);
  const ANON = 'regretamin.anon';
  function anonId() { let a = localStorage.getItem(ANON); if (!a) { a = crypto.randomUUID(); localStorage.setItem(ANON, a); } return a; }
  const syncBody = () => document.body.classList.toggle('ppopen', !!document.querySelector('.ov:not([hidden])'));
  const open = (id) => { document.querySelectorAll('.ov').forEach(o => o.hidden = true); $('#' + id).hidden = false; const pw = $('#pwmsg'); if (pw) pw.textContent = ''; syncBody(); };
  const closeOv = (o) => { if (o) { o.hidden = true; syncBody(); } };
  // Close any popup with x, Esc or a click on the backdrop
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') document.querySelectorAll('.ov:not([hidden])').forEach(closeOv); });
  document.addEventListener('mousedown', (e) => { if (e.target.classList && e.target.classList.contains('ov')) closeOv(e.target); });
  const PEND = 'regretamin.pendingBuy';
  const setPend = (k, code) => localStorage.setItem(PEND, JSON.stringify({ k, code, t: Date.now() }));
  const takePend = () => { try { const p = JSON.parse(localStorage.getItem(PEND) || 'null'); localStorage.removeItem(PEND); return p && Date.now() - p.t < 30 * 60e3 ? p : null; } catch (_) { return null; } };
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
  // Copy and plans come from launch/copy.json (window.REGRET.copy). fmt fills {name}; pl picks [one, many] by count.
  const T = C.copy.js, B = C.copy.site.billing;
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
  const fmtDate = (d) => new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  const leftOf = (a) => { const P = planOf(a); return P && a.left <= P.checks ? fmt(T.left_of, { left: a.left, n: P.checks }) : String(a.left); };
  let ACCT = null; // { email, plan, left, period_end, cancel_at_period_end, has_customer } once signed in
  async function paint() {
    const b = await balance(); if (!b) return;
    $('#left').textContent = pl(b.left, T.nav_left, { n: b.left, free: b.signed_in ? '' : T.free });
    $('#signin').hidden = b.signed_in; $('#acct').hidden = !b.signed_in;
    document.querySelectorAll('[data-out]').forEach(x => x.hidden = b.signed_in);
    if (!b.signed_in) { document.querySelectorAll('[data-in]').forEach(x => x.hidden = true); return; }
    const [{ data: u }, { data: a }] = await Promise.all([sb.auth.getUser(), sb.rpc('my_account')]);
    if (!u.user || !a) return;
    ACCT = Object.assign({ email: u.user.email || '' }, a);
    $('#av').textContent = (ACCT.email[0] || 'A').toUpperCase();
    $('#ddem').textContent = ACCT.email;
    const P = planOf(ACCT);
    $('#ddplan').textContent = P ? fmt(T.plan_menu, { name: P.name, n: P.checks }) : T.plan_free;
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
      const d = new Date(r.checked_at), url = ROOT + 'vc/' + encodeURIComponent(r.slug) + '/';
      const when = fmtDate(d) + ' · ' + d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
      const st = r.active ? pl(r.cases, T.mc_active, r) : r.cases ? pl(r.cases, T.mc_closed, r) : T.mc_none;
      const nm = r.name + (r.short_name && r.short_name !== r.name ? ' (' + r.short_name + ')' : '');
      return '<div class="mr"><button type="button" class="star' + (r.saved ? ' on' : '') + '" data-star="' + esc(r.slug) + '" aria-pressed="' + !!r.saved + '" aria-label="' + fmt(r.saved ? T.unsave : T.save, { name: esc(r.name) }) + '">' + (r.saved ? '★' : '☆') + '</button>'
        + '<span class="nm2"><a href="' + esc(url) + '">' + esc(nm) + '</a></span><span class="dt">' + esc(when) + '</span><span class="st">' + st + '</span><a class="btn o" href="' + esc(url) + '">' + T.open_result + '</a></div>';
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
  async function buy(kind) {
    if (!sb) return alert(T.no_checkout);
    const { data: s } = await sb.auth.getSession();
    const pay = $('#paycase'), inPay = pay && !pay.hidden, out = inPay ? $('#pmsg2') : $('#pwmsg'), msg = (t) => { if (out) out.textContent = t; else if (t && !/…$/.test(t)) alert(t); };
    if (!s.session) {
      setPend(kind, CODE && CODE.code); // after sign-in (Google redirect or magic link) we come back here and continue to checkout
      if (inPay) { const g = $('#panon'); g.hidden = false; g.classList.add('hi'); $('#psgnh').textContent = T.sign_checkout; g.scrollIntoView({ behavior: 'smooth', block: 'center' }); return; }
      $('#suh').textContent = T.sign_buy; return open('signup');
    }
    document.querySelectorAll('[data-buy]').forEach(b => b.disabled = true); msg(T.opening);
    const { data, error } = await sb.functions.invoke('create-checkout', { body: CODE ? { kind, code: CODE.code } : { kind } });
    if (error || !data || !data.url) {
      document.querySelectorAll('[data-buy]').forEach(b => b.disabled = false);
      const j = error && error.context ? await error.context.json().catch(() => null) : null;
      if (j && j.has_plan && out) return (out.innerHTML = esc(T.has_plan) + ' <a href="#" data-portal>' + esc(T.has_plan_link) + '</a>'); // plan changes go through the billing portal
      return msg(T.checkout_fail);
    }
    location.href = data.url;
  }
  // Auth
  const back = () => location.href.split('#')[0];
  const google = () => sb && sb.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: back() } });
  const magic = async (email, out) => {
    if (!sb || !email) return;
    const { error } = await sb.auth.signInWithOtp({ email, options: { emailRedirectTo: back() } });
    out.textContent = error ? error.message : T.magic_sent;
  };
  const g = $('#google'); if (g) g.onclick = google;
  const m = $('#magic'); if (m) m.onclick = () => magic($('#em').value.trim(), $('#sumsg'));
  document.querySelectorAll('[data-google]').forEach(b => b.onclick = google);
  document.querySelectorAll('[data-magic]').forEach(f => f.onsubmit = (e) => { e.preventDefault(); magic(f.email.value.trim(), f.parentNode.parentNode.querySelector('[data-magicmsg]')); });
  if (sb) sb.auth.onAuthStateChange((ev, session) => {
    if (ev === 'SIGNED_IN') setTimeout(async () => { await sb.rpc('claim_anon_checks', { p_anon: anonId() }); paint(); }, 0);
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
    const q = new URLSearchParams(location.search).get('q') || T.this_firm; pq.textContent = q;
    $('#notify').onsubmit = async (e) => {
      e.preventDefault(); if (!sb) return;
      const { error } = await sb.rpc('request_check', { p_query: q, p_email: e.target.email.value, p_anon: anonId() });
      $('#pmsg').textContent = error ? T.error : T.notify_ok;
    };
  }
  // Company page: one firm_page() call returns everything (locked: counts + one line per section only).
  let BAL = null, PAGE = null, VIEW = null, SEC = '';
  async function openPay(sec) {
    SEC = sec || '';
    $('#pph').textContent = VIEW.head(SEC);
    $('#pmsg2').textContent = '';
    const ub = $('#usecheck'), pb = $('#pbal'); ub.disabled = true; pb.textContent = C.copy.site.pay.balance_loading;
    $('#panon').classList.remove('hi'); $('#psgnh').textContent = C.copy.site.pay.sign_title;
    open('paycase');
    BAL = await balance();
    $('#panon').hidden = !!(BAL && BAL.signed_in);
    if (!BAL) { pb.textContent = T.balance_fail; return; }
    const n = BAL.left;
    pb.textContent = n > 0 ? pl(n, T.have, { n, free: BAL.signed_in ? '' : T.free }) : (BAL.signed_in ? T.none_signed : T.none_anon);
    if (n <= 0) $('#pmsg2').textContent = BAL.signed_in ? T.pick_more : T.sign_more;
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
    if (error || !data) { if (spend) $('#pmsg2').textContent = T.error; return; }
    if (data.status === 'ok') { if (data.open) closeOv($('#paycase')); return draw(data); }
    if (data.status === 'need_signup') { $('#pmsg2').textContent = T.need_signup; const g = $('#panon'); g.hidden = false; g.classList.add('hi'); $('#usecheck').disabled = true; }
    if (data.status === 'out') { $('#pmsg2').textContent = T.out; $('#usecheck').disabled = true; }
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
