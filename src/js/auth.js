/* Supabase auth, nav, login card, and watchlist save. Google and email + password only. */
(function (global) {
  const GOOGLE = '<svg width="16" height="16" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"/><path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"/><path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z"/><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"/></svg>';
  const ANON_KEY = 'regret.anon.v1';
  const listeners = [];
  let client = null;
  let user = null;
  let carriedFor = null;
  const limits = { anon: 2, extra: 5, dwell: 2000 };
  const watch = { slugs: new Set() };

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  }
  function root() {
    const m = document.querySelector('meta[name="regret-root"]');
    return m ? m.content : '';
  }
  function siteRoot() {
    return new URL(root() || './', location.href);
  }
  function sb() {
    if (client) return client;
    const cfg = global.REGRET_CONFIG || {};
    if (!cfg.url || !cfg.key || !global.supabase || !global.supabase.createClient) return null;
    client = global.supabase.createClient(cfg.url, cfg.key, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    });
    return client;
  }
  function confirmed(person) {
    return !!(person && (person.email_confirmed_at || person.confirmed_at));
  }
  let tier = 'visitor';
  let profileName = '';
  let profileGen = 0;
  const alerts = { slugs: new Set(), opened: new Set(), rows: [] };
  function capFor(person) {
    if (tier === 'paid') return Infinity;
    if (!person) return limits.anon;
    return limits.anon + limits.extra;
  }
  function anonState() {
    try {
      const raw = localStorage.getItem(ANON_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (parsed && Array.isArray(parsed.funds)) return parsed;
      }
    } catch (e) { /* ignore broken storage */ }
    const state = { anonKey: (global.crypto && crypto.randomUUID) ? crypto.randomUUID() : String(Date.now()), funds: [] };
    localStorage.setItem(ANON_KEY, JSON.stringify(state));
    return state;
  }
  function saveAnon(state) {
    localStorage.setItem(ANON_KEY, JSON.stringify(state));
  }
  function personName(person) {
    if (profileName && profileName.trim()) return profileName.trim();
    const meta = (person && person.user_metadata) || {};
    return (meta.full_name || meta.name || '').trim();
  }
  function initials(person) {
    const name = personName(person);
    if (name) {
      const bits = name.split(/\s+/);
      return ((bits[0][0] || '') + (bits[1] ? bits[1][0] : bits[0][1] || '')).toUpperCase();
    }
    return (person.email || 'ME').slice(0, 2).toUpperCase();
  }
  function label(person) {
    const name = personName(person);
    if (name) return name.split(/\s+/)[0];
    return (person.email || 'You').split('@')[0];
  }
  async function refreshProfile() {
    const gen = ++profileGen;
    const clientNow = sb();
    if (!user || !clientNow) {
      if (gen === profileGen) profileName = '';
      return;
    }
    const { data } = await clientNow.from('profiles').select('display_name').eq('id', user.id).maybeSingle();
    if (gen !== profileGen) return;
    profileName = (data && data.display_name) || '';
  }
  function paintPayFail(notice) {
    let banner = document.getElementById('payFail');
    if (!notice) {
      if (banner) banner.hidden = true;
      return;
    }
    if (!banner) {
      const nav = document.querySelector('nav.pillnav');
      if (!nav) return;
      nav.insertAdjacentHTML('afterend', '<div class="fail" id="payFail" data-pay-fail><i>!</i><span></span><button class="b d sm" type="button" data-stripe="portal">Update card</button></div>');
      banner = document.getElementById('payFail');
    }
    const text = banner.querySelector('span');
    if (text) text.textContent = notice;
    banner.hidden = false;
  }
  function paintNav(person) {
    const slot = document.getElementById('navSlot');
    if (!slot) return;
    const base = root();
    if (!person) {
      slot.innerHTML = '<a class="b w" href="' + base + 'login/">Log in</a><a class="b v" href="' + base + 'account/#alerts">Get alerts</a>';
      return;
    }
    slot.innerHTML = '<div class="av" id="av"><i>' + esc(initials(person)) + '</i>' + esc(label(person))
      + '<svg width="12" height="12" viewBox="0 0 12 12"><path d="M3 4.5l3 3 3-3" stroke="#8C88A3" stroke-width="1.8" fill="none" stroke-linecap="round"/></svg>'
      + '<div class="menu"><small>' + esc(person.email || '') + '</small>'
      + '<a href="' + base + 'account/#watchlist">Watchlist</a>'
      + '<a href="' + base + 'account/#alerts">Alerts</a>'
      + '<a href="' + base + 'plans/">Pricing</a>'
      + '<a href="' + base + 'account/#share">Share / Report a VC</a>'
      + '<a href="' + base + 'settings/#account">Settings</a>'
      + '<button type="button" id="logout">Log out</button></div></div>';
    document.getElementById('av').onclick = function (e) {
      if (e.target.closest('#logout') || e.target.closest('a')) return;
      e.currentTarget.classList.toggle('open');
    };
    document.getElementById('logout').onclick = async function () {
      const clientNow = sb();
      if (clientNow) await clientNow.auth.signOut();
      location.href = siteRoot().href;
    };
  }
  function paintSave() {
    const btn = document.getElementById('save');
    if (!btn) return;
    const slug = document.body.dataset.firm;
    const saved = !!(slug && watch.slugs.has(slug));
    const full = watch.slugs.size >= 100 && !saved;
    btn.classList.toggle('on', saved);
    btn.classList.toggle('full', !!user && full);
    btn.dataset.tip = user && full ? 'Watchlist full (100/100)' : saved ? 'Saved' : 'Save';
    btn.setAttribute('aria-pressed', saved ? 'true' : 'false');
    if (user && full) btn.setAttribute('aria-disabled', 'true');
    else btn.removeAttribute('aria-disabled');
  }
  function paintOneAlert(tog, on, locked) {
    tog.classList.toggle('on', !!on && !locked);
    tog.classList.toggle('off', !!locked);
    tog.setAttribute('aria-checked', on && !locked ? 'true' : 'false');
    if (locked) tog.setAttribute('aria-disabled', 'true');
    else tog.removeAttribute('aria-disabled');
  }
  async function paintAlert() {
    const tog = document.getElementById('alertTog');
    const note = document.getElementById('alertNote');
    if (!tog) return;
    const slug = document.body.dataset.firm;
    let locked = false;
    if (user && tier !== 'paid' && slug) {
      const opened = alerts.opened.has(slug) || (await seen()).has(slug);
      locked = !opened;
    }
    const on = !!(slug && alerts.slugs.has(slug));
    paintOneAlert(tog, on, locked);
    if (note) note.hidden = !locked;
  }
  async function firmMap() {
    return {};
  }
  async function landingFunds() {
    const clientNow = sb();
    if (!clientNow) return null;
    const { data, error } = await clientNow.rpc('landing_funds');
    if (error || !data || !Array.isArray(data.funds)) return null;
    if (data.tier) tier = data.tier;
    return data;
  }
  async function firmId(slug) {
    const clientNow = sb();
    if (!clientNow || !slug) return null;
    const { data, error } = await clientNow.rpc('firm_id_for_slug', { p_slug: slug });
    if (error) return null;
    return data || null;
  }
  async function loadReport(slug) {
    const clientNow = sb();
    if (!clientNow) return null;
    const anon = anonState();
    const { data, error } = await clientNow.rpc('open_report', {
      p_slug: slug,
      p_anon_key: user ? null : anon.anonKey
    });
    if (error || !data) return { ok: false, reason: 'error' };
    if (data.tier) tier = data.tier;
    if (data.ok && user && slug) alerts.opened.add(slug);
    if (data.ok && !user && !anon.funds.includes(slug)) {
      anon.funds.push(slug);
      saveAnon(anon);
    }
    return data;
  }
  async function loadLimits() {
    const clientNow = sb();
    if (!clientNow) return;
    const { data } = await clientNow.from('gating_policies').select('anonymous_free_reports,registered_extra_reports,dwell_ms').eq('code', 'default').maybeSingle();
    if (!data) return;
    limits.anon = data.anonymous_free_reports;
    limits.extra = data.registered_extra_reports;
    limits.dwell = data.dwell_ms;
  }
  async function refreshTier() {
    const clientNow = sb();
    if (!clientNow || !user) {
      if (!user) tier = 'visitor';
      return tier;
    }
    const { data, error } = await clientNow.rpc('access_tier');
    if (!error && data) tier = data;
    return tier;
  }
  async function refreshAlerts() {
    alerts.slugs = new Set();
    alerts.opened = new Set();
    alerts.rows = [];
    const clientNow = sb();
    if (!user || !clientNow) return alerts;
    const { data } = await clientNow.rpc('my_alert_funds');
    (data || []).forEach(row => {
      if (!row || !row.slug) return;
      alerts.rows.push(row);
      if (row.alerts) alerts.slugs.add(row.slug);
      if (row.opened) alerts.opened.add(row.slug);
    });
    return alerts;
  }
  async function refreshWatch() {
    watch.slugs = new Set();
    const clientNow = sb();
    if (!user || !clientNow) return watch;
    const { data } = await clientNow.rpc('my_watch_slugs');
    (data || []).forEach(slug => { if (slug) watch.slugs.add(slug); });
    return watch;
  }
  async function seen() {
    if (!user) return new Set(anonState().funds);
    const clientNow = sb();
    if (!clientNow) return new Set();
    const { data } = await clientNow.rpc('my_report_slugs');
    return new Set(data || []);
  }
  async function carry() {
    if (!user || carriedFor === user.id) return;
    carriedFor = user.id;
    const clientNow = sb();
    if (!clientNow) return;
    await clientNow.rpc('carry_anon_views', { p_anon_key: anonState().anonKey });
  }
  async function record(slug) {
    if (user) return;
    const state = anonState();
    if (!state.funds.includes(slug)) state.funds.push(slug);
    saveAnon(state);
  }
  async function touch() {}
  async function addWatch(slug) {
    if (!user) return { needAuth: true };
    if (watch.slugs.has(slug)) return { saved: true };
    if (watch.slugs.size >= 100) return { full: true };
    const clientNow = sb();
    if (!clientNow) return { error: 'Sign-in is not configured on this build.' };
    const { data, error } = await clientNow.rpc('watch_fund', { p_slug: slug });
    if (error) return { error: error.message };
    if (data && data.saved) watch.slugs.add(slug);
    return data || { error: 'Could not save' };
  }
  async function removeWatch(slug) {
    const clientNow = sb();
    if (!clientNow || !user) return;
    await clientNow.rpc('unwatch_fund', { p_slug: slug });
    watch.slugs.delete(slug);
    alerts.slugs.delete(slug);
    alerts.rows = alerts.rows.filter(row => row.slug !== slug);
  }
  async function setFundAlert(slug, on) {
    if (!user) return { needAuth: true };
    const clientNow = sb();
    if (!clientNow) return { error: 'Sign-in is not configured on this build.' };
    const { data, error } = await clientNow.rpc('set_fund_alert', { p_slug: slug, p_on: !!on });
    if (error) return { error: error.message };
    if (data && data.ok) {
      if (data.on) watch.slugs.add(slug);
      await refreshAlerts();
    }
    return data || { error: 'Could not update alerts' };
  }

  function cardHtml() {
    return '<div class="auth" role="dialog" aria-labelledby="ah" data-mode="login">'
      + '<button type="button" class="x" id="authClose" aria-label="Close"><svg width="16" height="16" viewBox="0 0 16 16"><path d="M3 3l10 10M13 3L3 13" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button>'
      + '<div class="dots gate-only gate-flex" id="authDots" aria-hidden="true"></div>'
      + '<h2 id="ah" class="gate-only">Two funds in.<br>Don\'t <span class="mark">regret the third</span>.</h2>'
      + '<h2 class="page-only">Check first.<br><span class="mark">Sign second</span>.</h2>'
      + '<h2 class="list-only">Log in to see<br><span class="mark">all <span id="listN"></span> funds</span>.</h2>'
      + '<p class="sub list-only">Free account. No card.</p>'
      + '<h2 class="pay-only">You\'ve checked 7 funds.<br>The 8th could be the one you <span class="mark">regret</span>.</h2>'
      + '<h2 class="plans-only">Plans</h2>'
      + '<h2 class="confirm-only">Confirm your email.</h2>'
      + '<h2 class="forgot-only">Reset your password.</h2>'
      + '<h2 class="reset-only">Choose a new password.</h2>'
      + '<p class="sub gate-only">A free account unlocks 5 more reports. No card.</p>'
      + '<p class="sub pay-only">Unlimited reports and alerts when a fund you\'re talking to gets sued.</p>'
      + '<p class="sub plans-only">Unlimited reports, when pricing is ready. Nothing to pay today.</p>'
      + '<p class="sub confirm-only">The extra 5 reports open after you confirm. We sent the link to your inbox.</p>'
      + '<p class="sub forgot-only">We\'ll email you a link to set a new password.</p>'
      + '<p class="sub reset-only">Use at least 6 characters.</p>'
      + '<div class="plans plans-only"><div><b>Founder</b><span>Unlimited reports and alerts. Price not set yet.</span></div>'
      + '<div><b>Team / accelerator</b><span>Shared seats. Seats and price not set yet.</span></div></div>'
      + '<button class="b v google" id="googleBtn" type="button"><span class="g">' + GOOGLE + '</span>Continue with Google</button>'
      + '<div class="or">or</div>'
      + '<form class="pf" id="authForm">'
      + '<label class="fld email-row"><input type="email" id="authEmail" placeholder="Email" aria-label="Email" autocomplete="email" required></label>'
      + '<label class="fld pw-row"><input type="password" id="authPassword" placeholder="Password" aria-label="Password" autocomplete="current-password" minlength="6"><button type="button" class="fp in-only" id="forgotBtn">Forgot password?</button></label>'
      + '<label class="fld pw2-row"><input type="password" id="authPassword2" placeholder="Confirm password" aria-label="Confirm password" autocomplete="new-password" minlength="6"></label>'
      + '<button class="b s" id="submitBtn" type="submit"><span class="up-only">Create account</span><span class="in-only">Log in</span><span class="forgot-only">Send reset link</span><span class="reset-only">Update password</span></button>'
      + '</form>'
      + '<div class="pay-only pay-flex" style="flex-direction:column;gap:10px"><button class="b c" type="button" id="seePlans">See plans</button><button class="b s" type="button" id="later">Maybe later</button></div>'
      + '<button class="b c confirm-only" type="button" id="resendBtn" style="margin-top:8px">Resend email</button>'
      + '<button class="b s plans-only" type="button" id="closePlans" style="margin-top:16px">Close</button>'
      + '<p class="fine"><span class="agree up-only">By creating an account you agree to the <a href="' + root() + 'terms/">Terms</a> and <a href="' + root() + 'privacy/">Privacy</a></span>'
      + '<span class="up-only">Have an account? <button type="button" class="link" data-to="login">Log in</button></span>'
      + '<span class="in-only">New here? <button type="button" class="link" data-to="signup">Create account</button></span>'
      + '<span class="forgot-only"><button type="button" class="link" data-to="login">Back to log in</button></span></p>'
      + '<p class="err" id="authErr" hidden></p><p class="ok" id="authOk" hidden></p>'
      + '</div>';
  }

  function ensureCard() {
    let card = document.querySelector('.auth');
    if (card) return card;
    const veil = document.createElement('div');
    veil.className = 'auth-veil';
    veil.id = 'authVeil';
    veil.hidden = true;
    veil.innerHTML = cardHtml();
    document.body.appendChild(veil);
    bindCard(veil.querySelector('.auth'));
    return veil.querySelector('.auth');
  }
  function msg(text, ok) {
    const err = document.getElementById('authErr');
    const good = document.getElementById('authOk');
    if (err) { err.hidden = !text || !!ok; err.textContent = ok ? '' : (text || ''); }
    if (good) { good.hidden = !text || !ok; good.textContent = ok ? text : ''; }
  }
  function setMode(mode, gate) {
    const card = ensureCard();
    card.dataset.mode = mode;
    card.classList.toggle('is-gate', !!gate);
    const email = document.getElementById('authEmail');
    const pw = document.getElementById('authPassword');
    if (email) email.required = mode !== 'reset';
    if (pw) pw.required = mode === 'login' || mode === 'signup' || mode === 'reset';
    if (mode === 'signup' || mode === 'login') {
      const dots = document.getElementById('authDots');
      if (dots) {
        let html = '';
        for (let i = 0; i < limits.anon; i++) html += '<i class="used"></i>';
        for (let i = 0; i < limits.extra; i++) html += '<i class="more"></i>';
        dots.innerHTML = html + '<b>+' + limits.extra + '</b>';
      }
    }
    msg('');
    const veil = document.getElementById('authVeil');
    if (veil && !document.body.classList.contains('is-auth-page')) veil.hidden = false;
  }
  function close() {
    const veil = document.getElementById('authVeil');
    if (veil) veil.hidden = true;
    const card = document.querySelector('.auth');
    if (card) card.classList.remove('is-list');
    msg('');
    sessionStorage.removeItem('regret.after');
  }
  function pendingAfter() {
    const pending = sessionStorage.getItem('regret.after') || '';
    if (!/^[a-z0-9./_#?-]+$/i.test(pending) || pending.indexOf('//') !== -1) return '';
    return pending;
  }
  function consumeAfter() {
    const pending = pendingAfter();
    if (pending) sessionStorage.removeItem('regret.after');
    return pending;
  }
  function goNext() {
    const pending = consumeAfter();
    if (pending) {
      location.href = new URL(pending, siteRoot()).href;
      return;
    }
    if (!document.body.classList.contains('is-auth-page')) {
      location.reload();
      return;
    }
    const params = new URLSearchParams(location.search);
    const next = params.get('next') || '';
    const view = params.get('view') || '';
    if (next && /^[a-z0-9./_-]+$/i.test(next) && next.indexOf('//') === -1) {
      const url = new URL(next, siteRoot());
      if (view && /^[a-z0-9-]+$/i.test(view)) url.hash = view;
      location.href = url.href;
      return;
    }
    location.href = siteRoot().href;
  }
  function needConfig() {
    if (sb()) return false;
    msg('Sign-in is not configured on this build.');
    return true;
  }
  async function onSubmit(e) {
    e.preventDefault();
    const card = document.querySelector('.auth');
    const mode = card.dataset.mode;
    const email = document.getElementById('authEmail').value.trim();
    const password = document.getElementById('authPassword').value;
    const password2 = document.getElementById('authPassword2').value;
    msg('');
    if (needConfig()) return;
    const clientNow = sb();
    if (mode === 'forgot') {
      const { error } = await clientNow.auth.resetPasswordForEmail(email, { redirectTo: new URL('login/reset/', siteRoot()).href });
      if (error) msg(error.message);
      else msg('Reset link sent. Check your email.', true);
      return;
    }
    if (mode === 'reset') {
      if (password.length < 6) { msg('Use at least 6 characters.'); return; }
      if (password !== password2) { msg('Those passwords don\'t match.'); return; }
      const { error } = await clientNow.auth.updateUser({ password: password });
      if (error) msg(error.message);
      else { msg('Password updated.', true); setTimeout(() => { location.href = siteRoot().href; }, 600); }
      return;
    }
    if (password.length < 6) { msg('Use at least 6 characters.'); return; }
    if (mode === 'signup') {
      if (password !== password2) { msg('Those passwords don\'t match.'); return; }
      const { data, error } = await clientNow.auth.signUp({
        email: email,
        password: password,
        options: { emailRedirectTo: siteRoot().href }
      });
      if (error) { msg(error.message); return; }
      if (data.session) goNext();
      else setMode('confirm', false);
      return;
    }
    const { error } = await clientNow.auth.signInWithPassword({ email: email, password: password });
    if (error) msg(error.message);
    else goNext();
  }
  function bindCard(card) {
    card.querySelector('#authClose').onclick = close;
    card.querySelectorAll('[data-to]').forEach(btn => {
      btn.onclick = () => setMode(btn.dataset.to, card.classList.contains('is-gate'));
    });
    card.querySelector('#forgotBtn').onclick = () => setMode('forgot', false);
    card.querySelector('#authForm').onsubmit = onSubmit;
    card.querySelector('#googleBtn').onclick = async () => {
      if (needConfig()) return;
      const { error } = await sb().auth.signInWithOAuth({ provider: 'google', options: { redirectTo: siteRoot().href } });
      if (error) msg(error.message);
    };
    const plans = card.querySelector('#seePlans');
    if (plans) plans.onclick = () => setMode('plans', false);
    const later = card.querySelector('#later');
    if (later) later.onclick = close;
    const closePlans = card.querySelector('#closePlans');
    if (closePlans) closePlans.onclick = close;
    const resend = card.querySelector('#resendBtn');
    if (resend) resend.onclick = async () => {
      const email = document.getElementById('authEmail').value.trim();
      if (!email || needConfig()) { msg('Enter the email you signed up with.'); return; }
      const { error } = await sb().auth.resend({ type: 'signup', email: email, options: { emailRedirectTo: siteRoot().href } });
      if (error) msg(error.message);
      else msg('Sent again.', true);
    };
    const veil = document.getElementById('authVeil');
    if (veil) veil.addEventListener('click', ev => { if (ev.target === veil) close(); });
  }

  function openReport(ev) {
    const link = ev.target.closest('a[href*="account/#share"]');
    if (!link) return false;
    ev.preventDefault();
    const menu = document.querySelector('.av.open');
    if (menu) menu.classList.remove('open');
    if (!user) {
      sessionStorage.setItem('regret.after', 'account/#share');
      if (document.body.dataset.page === 'login') return true;
      if (document.body.classList.contains('is-auth-page')) {
        location.href = new URL('login/', siteRoot()).href;
        return true;
      }
      setMode('login', false);
      return true;
    }
    if (document.getElementById('shareForm')) {
      if (location.hash !== '#share') location.hash = 'share';
      else window.scrollTo(0, 0);
      return true;
    }
    location.href = new URL('account/#share', siteRoot()).href;
    return true;
  }

  document.addEventListener('click', async ev => {
    if (openReport(ev)) return;
    const save = ev.target.closest('#save');
    if (save) {
      ev.preventDefault();
      const slug = document.body.dataset.firm;
      if (!user) { setMode('login', false); return; }
      if (save.classList.contains('full') && !watch.slugs.has(slug)) return;
      const result = watch.slugs.has(slug) ? (await removeWatch(slug), { saved: false }) : await addWatch(slug);
      if (result && result.full) paintSave();
      if (result && result.error) {
        save.dataset.tip = 'Could not save';
      }
      paintSave();
      return;
    }
    const alertTog = ev.target.closest('#alertTog, [data-alert]');
    if (alertTog) {
      ev.preventDefault();
      const slug = alertTog.dataset.alert || document.body.dataset.firm;
      if (!user) { setMode('login', false); return; }
      if (alertTog.classList.contains('off') || alertTog.getAttribute('aria-disabled') === 'true') return;
      const next = !alertTog.classList.contains('on');
      const result = await setFundAlert(slug, next);
      if (result && result.reason === 'unopened') {
        alertTog.classList.add('off');
        alertTog.setAttribute('aria-disabled', 'true');
        const note = alertTog.parentElement && alertTog.parentElement.querySelector('.fnote');
        if (note) note.hidden = false;
      }
      await paintAlert();
      listeners.forEach(fn => fn(user));
      return;
    }
    if (!ev.target.closest('.av')) {
      const open = document.querySelector('.av.open');
      if (open) open.classList.remove('open');
    }
  });
  document.addEventListener('keydown', e => {
    if (e.key !== 'Escape') return;
    const av = document.querySelector('.av.open');
    if (av) av.classList.remove('open');
    close();
  });

  const ready = (async () => {
    const clientNow = sb();
    if (clientNow) {
      const { data } = await clientNow.auth.getSession();
      user = data.session && data.session.user;
      await loadLimits();
      if (user) {
        await carry();
        await refreshTier();
        await refreshWatch();
        await refreshAlerts();
        await refreshProfile();
      }
      clientNow.auth.onAuthStateChange(async (event, session) => {
        const next = session && session.user;
        const changed = (next && next.id) !== (user && user.id);
        user = next || null;
        if (event === 'PASSWORD_RECOVERY') setMode('reset', false);
        if (event === 'SIGNED_OUT') {
          watch.slugs = new Set();
          alerts.slugs = new Set();
          alerts.opened = new Set();
          alerts.rows = [];
          tier = 'visitor';
          profileName = '';
          carriedFor = null;
        }
        if (user && changed) {
          await carry();
          await refreshTier();
          await refreshWatch();
          await refreshAlerts();
          await refreshProfile();
        }
        paintNav(user);
        paintSave();
        await paintAlert();
        listeners.forEach(fn => fn(user));
      });
    }
    paintNav(user);
    paintSave();
    await paintAlert();
    if (user && pendingAfter()) {
      const target = new URL(pendingAfter(), siteRoot());
      const same = target.pathname === location.pathname && target.hash === location.hash;
      sessionStorage.removeItem('regret.after');
      if (!same) {
        location.replace(target.href);
        return;
      }
    }
    const page = document.body.dataset.page;
    if (page === 'login' || page === 'reset') {
      const slot = document.getElementById('authPage');
      const card = ensureCard();
      if (slot && card.parentElement !== slot) slot.appendChild(card);
      const veil = document.getElementById('authVeil');
      if (veil) veil.hidden = true;
      const params = new URLSearchParams(location.search);
      setMode(page === 'reset' ? 'reset' : (params.get('mode') === 'signup' ? 'signup' : 'login'), false);
      if (page === 'login') {
        const veilNow = document.getElementById('authVeil');
        if (veilNow) veilNow.hidden = true;
      }
    }
  })();

  global.Regret = {
    sb, root, siteRoot, limits, watch, alerts, ready, esc, paintSave, paintAlert,
    get user() { return user; },
    get tier() { return tier; },
    confirmed, capFor, anonState, seen, record, touch, firmId, firmMap,
    addWatch, removeWatch, refreshWatch, refreshAlerts, setFundAlert, landingFunds, loadReport,
    refreshProfile, paintNav: function () { paintNav(user); }, paintPayFail,
    onChange(fn) { listeners.push(fn); }
  };
  global.RegretAuth = { open: setMode, close, setMode };
})(window);
