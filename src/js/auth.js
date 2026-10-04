/* Supabase auth, nav, login card, and watchlist save. Google and email + password only. */
(function (global) {
  const GOOGLE = '<svg width="16" height="16" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"/><path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"/><path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z"/><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"/></svg>';
  const ANON_KEY = 'regret.anon.v1';
  const listeners = [];
  let client = null;
  let user = null;
  let firms = null;
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
  function capFor(person) {
    if (!person || !confirmed(person)) return limits.anon;
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
  function initials(person) {
    const meta = person.user_metadata || {};
    const name = meta.full_name || meta.name || '';
    if (name.trim()) {
      const bits = name.trim().split(/\s+/);
      return ((bits[0][0] || '') + (bits[1] ? bits[1][0] : bits[0][1] || '')).toUpperCase();
    }
    return (person.email || 'ME').slice(0, 2).toUpperCase();
  }
  function label(person) {
    const meta = person.user_metadata || {};
    const name = meta.full_name || meta.name || '';
    if (name.trim()) return name.trim().split(/\s+/)[0];
    return (person.email || 'You').split('@')[0];
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
      + '<div class="menu"><small>' + esc(person.email || '') + '</small><button type="button" id="logout">Log out</button></div></div>';
    document.getElementById('av').onclick = function (e) {
      if (e.target.closest('#logout')) return;
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
  async function firmMap() {
    if (firms) return firms;
    firms = {};
    const clientNow = sb();
    if (!clientNow) return firms;
    const { data } = await clientNow.from('firms').select('id,slug');
    (data || []).forEach(row => { firms[row.slug] = row.id; });
    return firms;
  }
  async function firmId(slug) {
    const map = await firmMap();
    return map[slug] || null;
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
  async function refreshWatch() {
    watch.slugs = new Set();
    const clientNow = sb();
    if (!user || !clientNow) return watch;
    const { data } = await clientNow.from('watchlist').select('firm_id, firms(slug)');
    (data || []).forEach(row => {
      const slug = row.firms && row.firms.slug;
      if (slug) watch.slugs.add(slug);
    });
    return watch;
  }
  async function seen() {
    if (!user) return new Set(anonState().funds);
    const clientNow = sb();
    if (!clientNow) return new Set();
    const { data } = await clientNow.from('report_views').select('counted, firms(slug)').eq('profile_id', user.id);
    const out = new Set();
    (data || []).forEach(row => {
      if (row.counted && row.firms && row.firms.slug) out.add(row.firms.slug);
    });
    return out;
  }
  async function carry() {
    if (!user || carriedFor === user.id) return;
    carriedFor = user.id;
    const clientNow = sb();
    if (!clientNow) return;
    const state = anonState();
    const already = await seen();
    const room = capFor(user) - already.size;
    let left = room;
    for (const slug of state.funds) {
      if (already.has(slug) || left <= 0) continue;
      const id = await firmId(slug);
      if (!id) continue;
      const { error } = await clientNow.from('report_views').insert({
        profile_id: user.id,
        firm_id: id,
        source: 'carry',
        dwell_ms: limits.dwell,
        counted: true
      });
      if (!error) {
        already.add(slug);
        left -= 1;
      }
    }
  }
  async function record(slug, source) {
    if (!user) {
      const state = anonState();
      if (!state.funds.includes(slug)) state.funds.push(slug);
      saveAnon(state);
      return;
    }
    const clientNow = sb();
    const id = await firmId(slug);
    if (!clientNow || !id) return;
    const { data } = await clientNow.from('report_views').select('id').eq('profile_id', user.id).eq('firm_id', id).maybeSingle();
    const now = new Date().toISOString();
    if (data) {
      await clientNow.from('report_views').update({ last_opened_at: now, counted: true, dwell_ms: limits.dwell }).eq('id', data.id);
    } else {
      await clientNow.from('report_views').insert({
        profile_id: user.id,
        firm_id: id,
        source: source || 'report',
        dwell_ms: limits.dwell,
        counted: true
      });
    }
  }
  async function touch(slug) {
    if (!user) return;
    const clientNow = sb();
    const id = await firmId(slug);
    if (!clientNow || !id) return;
    await clientNow.from('report_views').update({ last_opened_at: new Date().toISOString() }).eq('profile_id', user.id).eq('firm_id', id);
  }
  async function addWatch(slug) {
    if (!user) return { needAuth: true };
    if (watch.slugs.has(slug)) return { saved: true };
    if (watch.slugs.size >= 100) return { full: true };
    const clientNow = sb();
    const id = await firmId(slug);
    if (!clientNow || !id) return { error: 'Sign-in is not configured on this build.' };
    const { error } = await clientNow.from('watchlist').insert({ profile_id: user.id, firm_id: id });
    if (error) {
      if (/full/i.test(error.message || '')) return { full: true };
      return { error: error.message };
    }
    watch.slugs.add(slug);
    return { saved: true };
  }
  async function removeWatch(slug) {
    const clientNow = sb();
    const id = await firmId(slug);
    if (!clientNow || !id || !user) return;
    await clientNow.from('watchlist').delete().eq('profile_id', user.id).eq('firm_id', id);
    watch.slugs.delete(slug);
  }

  function cardHtml() {
    return '<div class="auth" role="dialog" aria-labelledby="ah" data-mode="login">'
      + '<button type="button" class="x" id="authClose" aria-label="Close"><svg width="16" height="16" viewBox="0 0 16 16"><path d="M3 3l10 10M13 3L3 13" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button>'
      + '<div class="dots gate-only gate-flex" id="authDots" aria-hidden="true"></div>'
      + '<h2 id="ah" class="gate-only">Two funds in.<br>Don\'t <span class="mark">regret the third</span>.</h2>'
      + '<h2 class="page-only">Check first.<br><span class="mark">Sign second</span>.</h2>'
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
    msg('');
  }
  function goNext() {
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

  document.addEventListener('click', async ev => {
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
    if (!ev.target.closest('.av')) {
      const open = document.querySelector('.av.open');
      if (open) open.classList.remove('open');
    }
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') close();
  });

  const ready = (async () => {
    const clientNow = sb();
    if (clientNow) {
      const { data } = await clientNow.auth.getSession();
      user = data.session && data.session.user;
      await loadLimits();
      if (user) {
        await carry();
        await refreshWatch();
      }
      clientNow.auth.onAuthStateChange(async (event, session) => {
        const next = session && session.user;
        const changed = (next && next.id) !== (user && user.id);
        user = next || null;
        if (event === 'PASSWORD_RECOVERY') setMode('reset', false);
        if (event === 'SIGNED_OUT') {
          watch.slugs = new Set();
          carriedFor = null;
        }
        if (user && changed) {
          await carry();
          await refreshWatch();
        }
        paintNav(user);
        paintSave();
        listeners.forEach(fn => fn(user));
      });
    }
    paintNav(user);
    paintSave();
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
    sb, root, siteRoot, limits, watch, ready, esc,
    get user() { return user; },
    confirmed, capFor, anonState, seen, record, touch, firmId, firmMap,
    addWatch, removeWatch, refreshWatch,
    onChange(fn) { listeners.push(fn); }
  };
  global.RegretAuth = { open: setMode, close, setMode };
})(window);
