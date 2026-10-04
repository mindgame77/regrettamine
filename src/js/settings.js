/* Settings. Account fields are the signed-in profile. Billing reads my_billing until Stripe is connected. */
(function () {
  const $ = id => document.getElementById(id);
  let email = '';
  let hasPassword = false;

  function go() {
    const v = (location.hash || '#account').replace('#', '') || 'account';
    const name = v === 'billing' ? 'billing' : 'account';
    document.querySelectorAll('.view').forEach(el => el.classList.toggle('on', el.id === name));
    document.querySelectorAll('.anav a').forEach(a => a.classList.toggle('on', a.dataset.v === name));
  }
  addEventListener('hashchange', () => { go(); scrollTo(0, 0); });
  go();

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
      if (!/^https?:\/\//i.test(raw)) return { error: 'Enter a valid website.' };
    } else {
      raw = 'https://' + raw;
    }
    let url;
    try { url = new URL(raw); }
    catch (e) { return { error: 'Enter a valid website.' }; }
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return { error: 'Enter a valid website.' };
    if (!url.hostname || url.hostname.indexOf('.') === -1 || url.username || url.password) {
      return { error: 'Enter a valid website.' };
    }
    return { value: raw };
  }

  function paintAuth(person) {
    email = (person && person.email) || '';
    hasPassword = hasEmailPassword(person);
    $('emailNow').textContent = email;
    $('cfmIn').placeholder = email ? 'Type DELETE or ' + email : 'Type DELETE';
    $('emailPw').hidden = !hasPassword;
    $('pwCurrent').hidden = !hasPassword;
    $('pwHint').textContent = hasPassword ? '••••••••••' : 'Not set';
    $('pwOpen').textContent = hasPassword ? 'Change password' : 'Set password';
    $('pwSubmit').textContent = hasPassword ? 'Update password' : 'Set password';
  }

  function money(cents) {
    if (cents == null || cents === '') return '';
    const n = Number(cents);
    if (!isFinite(n)) return String(cents);
    return '$' + (n / 100).toFixed(2);
  }

  function paintBilling(row) {
    const data = row || {};
    const paid = data.tier === 'paid' || data.plan === 'Paid' || data.plan === 'Monthly' || data.plan === 'Annual';
    $('planName').textContent = data.plan || (paid ? 'Paid' : 'Free');
    $('planDetail').textContent = data.price_label || (paid ? 'Your paid plan is active.' : 'No charge.');
    if (data.payment_failed && data.next_charge_label) {
      $('nxLabel').textContent = 'Charge failed';
      $('nxVal').textContent = data.next_charge_label;
      $('nxVal').classList.add('bad');
    } else {
      $('nxLabel').textContent = 'Next charge';
      $('nxVal').textContent = data.next_charge_label || '—';
      $('nxVal').classList.remove('bad');
    }
    const card = data.card || null;
    $('cardBrand').hidden = !card;
    $('cardBrand').textContent = card ? (card.brand || '') : '';
    $('cardLabel').textContent = card ? (card.label || 'Card on file') : 'No card on file';
    $('cardMeta').textContent = card && card.expires ? 'Expires ' + card.expires : '';
    const manage = !!(data.manage_card || card);
    if (!card && manage) {
      $('cardLabel').textContent = 'Card on file';
      $('cardMeta').textContent = '';
    }
    $('cardChange').hidden = !manage;
    $('cardChange').textContent = 'Manage card';
    $('cardDelete').hidden = !card;
    const payments = Array.isArray(data.payments) ? data.payments : [];
    $('payEmpty').hidden = payments.length > 0;
    $('payRows').innerHTML = payments.map(item => {
      const status = item.status === 'failed' ? 'bad' : 'ok';
      const label = item.status === 'failed' ? 'Failed' : 'Paid';
      const receipt = item.receipt_url ? '<a class="lnk2" href="' + Regret.esc(item.receipt_url) + '" data-stripe="receipt">Receipt</a>' : '';
      return '<div class="pr"><div>' + Regret.esc(item.date || '') + '</div><div>' + Regret.esc(item.description || '') + '</div><div>' + Regret.esc(item.amount || money(item.amount_cents)) + '</div><div><span class="st ' + status + '">' + label + '</span></div><div>' + receipt + '</div></div>';
    }).join('');
    const banner = $('payFail');
    if (banner) banner.hidden = !data.payment_failed;
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
    if (!name) { showErr('profileErr', 'Enter your name.'); return; }
    const site = normalizeWebsite($('siteIn').value);
    if (site.error) { showErr('profileErr', site.error); return; }
    const { error } = await Regret.sb().from('profiles').update({
      display_name: name,
      website: site.value
    }).eq('id', person.id);
    if (error) { showErr('profileErr', 'Could not save that profile.'); return; }
    $('siteIn').value = site.value || '';
    await Regret.refreshProfile();
    Regret.paintNav();
    $('saveProfile').textContent = 'Saved';
    setTimeout(() => { $('saveProfile').textContent = 'Save'; }, 1200);
  });

  async function recheck(password) {
    const { error } = await Regret.sb().auth.signInWithPassword({ email: email, password: password });
    return error;
  }

  $('emailForm').addEventListener('submit', async e => {
    e.preventDefault();
    showErr('emailErr', '');
    const next = $('emailIn').value.trim();
    if (!next || next.indexOf('@') < 1) { showErr('emailErr', 'Enter a valid email.'); return; }
    if (hasPassword) {
      const bad = await recheck($('emailPwIn').value);
      if (bad) { showErr('emailErr', 'That password does not match.'); return; }
    }
    const { error } = await Regret.sb().auth.updateUser({ email: next });
    if (error) { showErr('emailErr', error.message || 'Could not change that email.'); return; }
    showErr('emailErr', '');
    $('emailForm').querySelector('.help').textContent = 'Confirmation link sent. The change applies once you click it.';
  });

  $('pwForm').addEventListener('submit', async e => {
    e.preventDefault();
    showErr('pwErr', '');
    const next = $('pwIn').value;
    if (next.length < 6) { showErr('pwErr', 'Use at least 6 characters.'); return; }
    if (next !== $('pw2In').value) { showErr('pwErr', "Those passwords don't match."); return; }
    if (hasPassword) {
      const bad = await recheck($('pwCurrentIn').value);
      if (bad) { showErr('pwErr', 'That password does not match.'); return; }
    }
    const { error } = await Regret.sb().auth.updateUser({ password: next });
    if (error) { showErr('pwErr', error.message || 'Could not update that password.'); return; }
    hasPassword = true;
    paintAuth(Regret.user);
    $('pwForm').hidden = true;
    $('pwOpen').hidden = false;
    $('pwIn').value = '';
    $('pw2In').value = '';
    $('pwCurrentIn').value = '';
  });

  $('cfmBtn').addEventListener('click', async () => {
    showErr('delErr', '');
    $('cfmBtn').disabled = true;
    const { error } = await Regret.sb().rpc('delete_my_account');
    if (error) {
      showErr('delErr', 'Could not delete this account.');
      $('cfmBtn').disabled = false;
      return;
    }
    try { await Regret.sb().auth.signOut(); } catch (e) { /* the user row is already gone */ }
    location.href = Regret.siteRoot().href;
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
    const billing = await Regret.sb().rpc('my_billing');
    paintBilling(billing.data || { plan: Regret.tier === 'paid' ? 'Paid' : 'Free' });
  });
})();
