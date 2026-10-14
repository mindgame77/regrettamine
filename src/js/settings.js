/* Settings. Account fields are the signed-in profile. Billing reads my_billing. */
(function () {
  const $ = id => document.getElementById(id);
  let email = '';
  let hasPassword = false;

  let scrollBilling = false;

  function go() {
    const v = (location.hash || '#account').replace('#', '') || 'account';
    const name = v === 'billing' ? 'billing' : 'account';
    document.querySelectorAll('.setcol .view').forEach(el => el.classList.toggle('on', el.id === name));
    document.querySelectorAll('[data-set]').forEach(a => a.classList.toggle('on', a.dataset.set === name));
    if (scrollBilling && name === 'billing') {
      scrollBilling = false;
      const heading = document.querySelector('#billing .vh h1');
      if (heading) heading.scrollIntoView();
      return;
    }
    window.scrollTo(0, 0);
  }
  addEventListener('hashchange', go);

  function consumeReturn() {
    const params = new URLSearchParams(location.search);
    let tab = (params.get('tab') || '').toLowerCase();
    const justPaid = params.get('paid') === '1';
    if (justPaid && tab !== 'account') tab = 'billing';
    if (tab === 'billing' && (params.has('tab') || justPaid)) scrollBilling = true;
    let changed = false;
    if (tab === 'billing' || tab === 'account') {
      if (location.hash !== '#' + tab) {
        location.hash = tab;
        changed = true;
      }
    }
    if (params.has('tab') || params.has('paid')) {
      history.replaceState(null, '', location.pathname + location.hash);
    }
    if (!changed) go();
    const note = $('payNote');
    if (note && justPaid) note.hidden = false;
    return justPaid;
  }
  const justPaid = consumeReturn();

  function showErr(id, text) {
    const node = $(id);
    if (!node) return;
    node.hidden = !text;
    node.textContent = text || '';
  }

  function hasEmailPassword(person) {
    const ids = (person && person.identities) || [];
    if (ids.length) return ids.some(row => row.provider === 'email');
    const providers = (person && person.app_metadata && person.app_metadata.providers) || [];
    return providers.indexOf('email') !== -1;
  }

  function normalizeWebsite(value) {
    let raw = String(value || '').trim();
    if (!raw) return { value: null };
    if (/^[a-z][a-z0-9+.-]*:/i.test(raw)) {
      if (!/^https?:\/\//i.test(raw)) return { error: '{{sjs:js.settings.enter_a_valid_website}}' };
    } else {
      raw = 'https://' + raw;
    }
    let url;
    try { url = new URL(raw); }
    catch (e) { return { error: '{{sjs:js.settings.enter_a_valid_website}}' }; }
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return { error: '{{sjs:js.settings.enter_a_valid_website}}' };
    if (!url.hostname || url.hostname.indexOf('.') === -1 || url.username || url.password) {
      return { error: '{{sjs:js.settings.enter_a_valid_website}}' };
    }
    return { value: raw };
  }

  function paintAuth(person) {
    email = (person && person.email) || '';
    hasPassword = hasEmailPassword(person);
    $('emailNow').textContent = email;
    $('cfmIn').placeholder = email ? '{{sjs:js.settings.type_delete_or}}' + email : '{{sjs:js.settings.type_delete}}';
    $('emailPw').hidden = !hasPassword;
    $('pwCurrent').hidden = !hasPassword;
    $('pwHint').textContent = hasPassword ? '••••••••••' : '{{sjs:js.settings.not_set}}';
    $('pwOpen').textContent = hasPassword ? '{{sjs:page.settings.change_password}}' : '{{sjs:js.settings.set_password}}';
    $('pwSubmit').textContent = hasPassword ? '{{sjs:page.settings.update_password}}' : '{{sjs:js.settings.set_password}}';
  }

  function money(cents) {
    if (cents == null || cents === '') return '';
    const n = Number(cents);
    if (!isFinite(n)) return String(cents);
    return '$' + (n / 100).toFixed(2);
  }

  function paintBilling(row) {
    const data = row || {};
    const paid = data.tier === 'paid' || data.plan === '{{sjs:js.plans.paid}}' || data.plan === '{{sjs:page.plans.monthly}}' || data.plan === '{{sjs:page.plans.annual}}';
    const cancel = $('planCancel');
    if (cancel) cancel.hidden = !paid;
    $('planName').textContent = data.plan || (paid ? '{{sjs:js.plans.paid}}' : '{{sjs:page.settings.free}}');
    $('planDetail').textContent = data.price_label || (paid ? '{{sjs:js.settings.your_paid_plan_is_active}}' : '{{sjs:js.settings.no_charge}}');
    if (data.payment_failed && data.payment_failed_on) {
      $('nxLabel').textContent = '{{sjs:js.settings.charge_failed_on}}';
      $('nxVal').textContent = data.payment_failed_on;
      $('nxVal').classList.add('bad');
    } else {
      $('nxLabel').textContent = '{{sjs:page.settings.next_charge}}';
      $('nxVal').textContent = data.next_charge_label || '—';
      $('nxVal').classList.remove('bad');
    }
    const card = data.card || null;
    $('cardBrand').hidden = !card;
    $('cardBrand').textContent = card ? (card.brand || '') : '';
    $('cardLabel').textContent = card ? (card.label || '{{sjs:js.settings.card_on_file}}') : '{{sjs:page.settings.no_card_on_file}}';
    $('cardMeta').textContent = card && card.expires ? 'Expires ' + card.expires : '';
    const manage = !!(data.manage_card || card);
    if (!card && manage) {
      $('cardLabel').textContent = '{{sjs:js.settings.card_on_file}}';
      $('cardMeta').textContent = '';
    }
    $('cardChange').hidden = !manage;
    $('cardChange').textContent = '{{sjs:page.settings.manage_card}}';
    $('cardDelete').hidden = !card;
    const change = $('changePlan');
    if (change) {
      if (paid) {
        change.textContent = '{{sjs:js.settings.switch_plan}}';
        change.dataset.stripe = 'portal';
        change.href = '#';
      } else {
        change.textContent = '{{sjs:page.settings.change_plan}}';
        change.dataset.stripe = 'checkout';
        change.href = '../plans/';
      }
    }
    const payments = Array.isArray(data.payments) ? data.payments : [];
    $('payEmpty').hidden = payments.length > 0;
    $('payRows').innerHTML = payments.map(item => {
      const status = item.status === 'failed' ? 'bad' : 'ok';
      const label = item.status === 'failed' ? '{{sjs:js.settings.failed}}' : '{{sjs:js.plans.paid}}';
      const receipt = item.receipt_url ? '<a class="lnk2" href="' + Regret.esc(item.receipt_url) + '" data-stripe="receipt">{{sjs:js.settings.receipt}}</a>' : '';
      return '<div class="pr"><div>' + Regret.esc(item.date || '') + '</div><div>' + Regret.esc(item.description || '') + '</div><div>' + Regret.esc(item.amount || money(item.amount_cents)) + '</div><div><span class="st ' + status + '">' + label + '</span></div><div>' + receipt + '</div></div>';
    }).join('');
    const notice = !data.payment_failed ? '' : (data.lapsed
      ? "{{s:js.settings.your_payment_didn_t_go}}"
      : "{{s:page.settings.we_couldn_t_charge_your}}");
    if (window.Regret && Regret.paintPayFail) Regret.paintPayFail(notice);
  }

  document.querySelectorAll('[data-open]').forEach(btn => {
    btn.addEventListener('click', () => {
      $(btn.dataset.open).hidden = false;
      btn.hidden = true;
    });
  });
  document.querySelectorAll('[data-close]').forEach(btn => {
    btn.addEventListener('click', () => {
      $(btn.dataset.close).hidden = true;
      const open = document.querySelector('[data-open="' + btn.dataset.close + '"]');
      if (open) open.hidden = false;
    });
  });
  document.querySelectorAll('[data-modal]').forEach(btn => {
    btn.addEventListener('click', () => { $(btn.dataset.modal).hidden = false; });
  });
  document.querySelectorAll('.auth-veil').forEach(veil => {
    veil.addEventListener('click', e => { if (e.target === veil) veil.hidden = true; });
    veil.querySelectorAll('[data-x]').forEach(btn => btn.addEventListener('click', () => { veil.hidden = true; }));
  });
  addEventListener('keydown', e => {
    if (e.key === 'Escape') document.querySelectorAll('.auth-veil').forEach(veil => { veil.hidden = true; });
  });

  $('cfmIn').addEventListener('input', () => {
    const typed = $('cfmIn').value.trim();
    $('cfmBtn').disabled = !(typed === 'DELETE' || (email && typed.toLowerCase() === email.toLowerCase()));
  });

  $('profileForm').addEventListener('submit', async e => {
    e.preventDefault();
    showErr('profileErr', '');
    const person = Regret.user;
    if (!person) return;
    const name = $('nameIn').value.trim();
    if (!name) { showErr('profileErr', '{{sjs:js.settings.enter_your_name}}'); return; }
    const site = normalizeWebsite($('siteIn').value);
    if (site.error) { showErr('profileErr', site.error); return; }
    const { error } = await Regret.sb().from('profiles').update({
      display_name: name,
      website: site.value
    }).eq('id', person.id);
    if (error) { showErr('profileErr', '{{sjs:js.settings.could_not_save_that_profile}}'); return; }
    $('siteIn').value = site.value || '';
    await Regret.refreshProfile();
    Regret.paintNav();
    $('saveProfile').textContent = '{{sjs:js.auth.saved}}';
    setTimeout(() => { $('saveProfile').textContent = '{{sjs:page.settings.save}}'; }, 1200);
  });

  async function recheck(password) {
    const { error } = await Regret.sb().auth.signInWithPassword({ email: email, password: password });
    return error;
  }

  $('emailForm').addEventListener('submit', async e => {
    e.preventDefault();
    showErr('emailErr', '');
    const next = $('emailIn').value.trim();
    if (!next || next.indexOf('@') < 1) { showErr('emailErr', '{{sjs:js.settings.enter_a_valid_email}}'); return; }
    if (hasPassword) {
      const bad = await recheck($('emailPwIn').value);
      if (bad) { showErr('emailErr', '{{sjs:js.settings.that_password_does_not_match}}'); return; }
    }
    const { error } = await Regret.sb().auth.updateUser({ email: next });
    if (error) {
      const text = Regret.authError ? Regret.authError(error.message) : error.message;
      showErr('emailErr', text || '{{sjs:js.settings.could_not_change_that_email}}');
      return;
    }
    showErr('emailErr', '');
    $('emailForm').querySelector('.help').textContent = '{{sjs:js.settings.confirmation_link_sent_the_change}}';
  });

  $('pwForm').addEventListener('submit', async e => {
    e.preventDefault();
    showErr('pwErr', '');
    const next = $('pwIn').value;
    if (next.length < 6) { showErr('pwErr', '{{sjs:js.auth.use_at_least_6_characters}}'); return; }
    if (next !== $('pw2In').value) { showErr('pwErr', "{{s:js.auth.those_passwords_don_t_match}}"); return; }
    if (hasPassword) {
      const bad = await recheck($('pwCurrentIn').value);
      if (bad) { showErr('pwErr', '{{sjs:js.settings.that_password_does_not_match}}'); return; }
    }
    const { error } = await Regret.sb().auth.updateUser({ password: next });
    if (error) { showErr('pwErr', error.message || '{{sjs:js.settings.could_not_update_that_password}}'); return; }
    hasPassword = true;
    paintAuth(Regret.user);
    $('pwForm').hidden = true;
    $('pwOpen').hidden = false;
    $('pwIn').value = '';
    $('pw2In').value = '';
    $('pwCurrentIn').value = '';
    $('pwOk').hidden = false;
    $('pwOk').textContent = '{{sjs:js.settings.password_updated}}';
  });

  async function deleteError(error) {
    const fallback = "{{s:js.settings.could_not_delete_this_account}}";
    const planned = "{{s:js.settings.we_couldn_t_cancel_your}}";
    try {
      const ctx = error && error.context;
      if (ctx && typeof ctx.json === 'function') {
        const body = await ctx.json();
        if (body && body.message) return body.message;
      }
    } catch (e) { /* the body was not json */ }
    if (error && /cancel your plan/i.test(error.message || '')) return planned;
    return fallback;
  }

  $('cfmBtn').addEventListener('click', async () => {
    showErr('delErr', '');
    $('cfmBtn').disabled = true;
    const { error } = await Regret.sb().functions.invoke('delete-account');
    if (error) {
      showErr('delErr', await deleteError(error));
      $('cfmBtn').disabled = false;
      return;
    }
    try { await Regret.sb().auth.signOut(); } catch (e) { /* the user row is already gone */ }
    location.href = new URL('deleted/', Regret.siteRoot()).href;
  });

  Regret.ready.then(async () => {
    if (!Regret.sb()) return;
    if (!Regret.user) {
      const view = (location.hash || '#account').replace('#', '') || 'account';
      location.href = new URL('login/', Regret.siteRoot()).href + '?next=settings/&view=' + encodeURIComponent(view);
      return;
    }
    paintAuth(Regret.user);
    const { data } = await Regret.sb().from('profiles').select('display_name, website').eq('id', Regret.user.id).maybeSingle();
    if (document.activeElement !== $('nameIn')) $('nameIn').value = (data && data.display_name) || '';
    if (document.activeElement !== $('siteIn')) $('siteIn').value = (data && data.website) || '';
    await watchPayment(justPaid);
  });

  async function refreshCard(row) {
    if (!row || row.card || !row.manage_card) return row;
    const { error } = await Regret.sb().functions.invoke('billing-portal', { body: { cardOnly: true } });
    if (error) return row;
    const billing = await Regret.sb().rpc('my_billing');
    return billing.data || row;
  }

  async function loadBilling() {
    const billing = await Regret.sb().rpc('my_billing');
    let row = billing.data || { plan: Regret.tier === 'paid' ? '{{sjs:js.plans.paid}}' : '{{sjs:page.settings.free}}' };
    row = await refreshCard(row);
    paintBilling(row);
    return row;
  }

  function chargeReady(row) {
    const payments = Array.isArray(row && row.payments) ? row.payments : [];
    return !!(row && row.next_charge_label) && payments.length > 0;
  }

  async function watchPayment(waiting) {
    let row = await loadBilling();
    if (!waiting) return;
    const note = $('payNote');
    if (note) note.hidden = false;
    if (chargeReady(row)) {
      if (note) note.hidden = true;
      return;
    }
    const deadline = Date.now() + 30000;
    while (Date.now() < deadline) {
      await new Promise(resolve => setTimeout(resolve, 2000));
      row = await loadBilling();
      if (chargeReady(row)) {
        if (note) note.hidden = true;
        return;
      }
    }
  }
})();
