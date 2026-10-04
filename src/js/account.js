/* Account tabs. The watchlist renders through FundList, the landing list. */
(function () {
  const HOME = JSON.parse(document.getElementById('home-data').textContent);
  const BY_ID = Object.fromEntries(HOME.funds.map(f => [f.id, f]));
  const READ_KEY = 'regret.alerts.read';
  const KINDS = { Court: 'Legal', Regulator: 'Regulator', Rescore: 'Score' };
  const $ = id => document.getElementById(id);

  function go() {
    const v = (location.hash || '#watchlist').replace('#', '') || 'watchlist';
    const name = ['watchlist', 'alerts', 'share'].includes(v) ? v : 'watchlist';
    document.querySelectorAll('.view').forEach(el => el.classList.toggle('on', el.dataset.view === name));
    document.querySelectorAll('.anav a').forEach(a => a.classList.toggle('on', a.dataset.v === name));
    if (name === 'share') window.scrollTo(0, 0);
  }
  addEventListener('hashchange', go);
  addEventListener('load', () => { if (location.hash === '#share') window.scrollTo(0, 0); });
  go();

  function readKeys() {
    try { return new Set(JSON.parse(localStorage.getItem(READ_KEY) || '[]')); }
    catch (e) { return new Set(); }
  }
  function storeKeys(set) {
    localStorage.setItem(READ_KEY, JSON.stringify([...set]));
  }
  function alertKey(u) { return (u.no || '') + '|' + (u.fid || '') + '|' + u.k; }

  function watchedFunds() {
    return [...Regret.watch.slugs].map(id => BY_ID[id]).filter(Boolean);
  }

  function renderWatch() {
    const rows = watchedFunds();
    const full = Regret.watch.slugs.size >= 100;
    $('addFund').disabled = full;
    $('addFund').placeholder = full ? 'Watchlist full (100/100)' : 'Add a fund';
    FundList.mount($('wlOut'), rows, {
      total: 100,
      bookmark: true,
      prefix: '../',
      note: '<span class="none">Saved funds. The bookmark removes one.</span>',
      empty: '<div class="empty"><b>Nothing saved yet.</b>Open a fund and tap the bookmark.</div>'
    });
  }

  function renderAlerts() {
    const read = readKeys();
    const items = HOME.updates.filter(u => u.fid && Regret.watch.slugs.has(u.fid) && KINDS[u.k]);
    const unread = items.filter(u => !read.has(alertKey(u)));
    const badge = $('alertCount');
    badge.hidden = unread.length === 0;
    badge.textContent = String(unread.length);
    badge.classList.toggle('hot', unread.length > 0);
    if (!items.length) {
      $('alertFeed').innerHTML = '<div class="empty"><b>No alerts yet.</b>Legal, regulatory, and score changes for saved funds show up here.</div>';
      return;
    }
    $('alertFeed').innerHTML = items.map(u => {
      const fresh = !read.has(alertKey(u));
      const href = String(u.u).startsWith('http') ? u.u : '../' + u.u;
      const ext = String(u.u).startsWith('http') ? ' target="_blank" rel="noopener"' : '';
      return '<div class="fi' + (fresh ? ' new' : '') + '"><i class="ud"></i><div class="dt">' + Regret.esc(u.ds) + '</div><div class="bd"><div class="fd"><span class="k ' + u.k + '">' + KINDS[u.k] + '</span>' + Regret.esc(u.f) + '</div><div class="ev">' + Regret.esc(u.t) + '</div><div class="sr">' + Regret.esc(u.src) + '<a href="' + Regret.esc(href) + '"' + ext + '>Open →</a></div></div></div>';
    }).join('');
  }

  const CONNECTIONS = [
    ['founder_ceo', 'Founder / CEO', 'Founder'],
    ['co_founder', 'Co-founder', 'Co-founder'],
    ['executive', 'Executive', 'Executive'],
    ['employee', 'Employee', 'Employee'],
    ['pitched', 'Pitched but no deal', 'Pitched'],
    ['co_investor', 'Co-investor', 'Co-investor']
  ];
  const LI_URL = /^(https?:\/\/)?((www|[a-z]{2})\.)?linkedin\.com\/in\/[a-z0-9\-_%]+\/?$/i;

  function selectedConnection() {
    const on = document.querySelector('#connect .chip.on');
    return CONNECTIONS.find(row => row[0] === (on && on.dataset.connection)) || CONNECTIONS[0];
  }
  function anonHint() {
    $('anonHint').textContent = 'Shown as "' + selectedConnection()[2] + ', ' + $('revRound').value + '"';
  }
  function ensureGrad() {
    if (!document.getElementById('g2')) document.body.insertAdjacentHTML('afterbegin', FundList.grad());
  }
  function highlight(name, q) {
    const at = name.toLowerCase().indexOf(q.toLowerCase());
    if (at < 0) return Regret.esc(name);
    return Regret.esc(name.slice(0, at)) + '<mark>' + Regret.esc(name.slice(at, at + q.length)) + '</mark>' + Regret.esc(name.slice(at + q.length));
  }
  function showFunds() {
    const input = $('fundIn');
    const dd = $('fundDD');
    const q = input.value.trim();
    if (!q) { dd.classList.remove('on'); dd.innerHTML = ''; return; }
    ensureGrad();
    const rows = HOME.funds.filter(f => (f.name + ' ' + (f.short || '') + ' ' + f.id).toLowerCase().includes(q.toLowerCase()))
      .sort((a, b) => a.name.localeCompare(b.name));
    if (!rows.length) {
      dd.innerHTML = '<div class="none">No fund found</div>';
      dd.classList.add('on');
      return;
    }
    dd.innerHTML = rows.map((f, i) => {
      const color = f.v2 ? 'url(#g2)' : '#C9C5D9';
      return '<button type="button" class="opt' + (i ? '' : ' hi') + '" data-firm="' + Regret.esc(f.id) + '" data-name="' + Regret.esc(f.name) + '">'
        + '<div class="mring">' + FundList.ring(f.score, 32, 3.5, color) + '<b style="' + (f.v2 ? '' : 'color:#A9A5BD') + '">' + Regret.esc(f.score) + '</b></div>'
        + '<div class="on2"><b>' + highlight(f.name, q) + '</b><small>' + Regret.esc(f.hq) + '</small></div>'
        + '<span class="bands"><i style="background:' + FundList.bandColor(f.band) + '"></i>' + Regret.esc(f.band) + '</span></button>';
    }).join('');
    dd.classList.add('on');
  }

  async function loadPrefs() {
    const client = Regret.sb();
    const { data } = await client.from('alert_preferences').select('*').eq('profile_id', Regret.user.id).maybeSingle();
    const prefs = data || { new_legal_matter: true, regulatory_record: true, partner_exit: false, score_change: true };
    document.querySelectorAll('[data-pref]').forEach(el => {
      el.classList.toggle('on', !!prefs[el.dataset.pref]);
    });
    $('prefNote').textContent = 'To ' + (Regret.user.email || 'you') + ', only for watched funds.';
  }

  $('wlOut').addEventListener('click', async e => {
    const btn = e.target.closest('.bm');
    if (!btn) return;
    e.preventDefault();
    e.stopPropagation();
    await Regret.removeWatch(btn.dataset.remove);
    renderWatch();
    renderAlerts();
  });

  $('addFund').addEventListener('input', () => {
    const q = $('addFund').value.trim().toLowerCase();
    const list = $('addList');
    if (!q) { list.hidden = true; list.innerHTML = ''; return; }
    const matches = HOME.funds.filter(f => !Regret.watch.slugs.has(f.id) && f.name.toLowerCase().includes(q)).slice(0, 8);
    list.hidden = matches.length === 0;
    list.innerHTML = matches.map(f => '<button type="button" data-add="' + Regret.esc(f.id) + '">' + Regret.esc(f.name) + '<small>' + Regret.esc(f.hq) + '</small></button>').join('');
  });
  $('addList').addEventListener('click', async e => {
    const btn = e.target.closest('[data-add]');
    if (!btn) return;
    const result = await Regret.addWatch(btn.dataset.add);
    $('addFund').value = '';
    $('addList').hidden = true;
    if (result && result.full) $('addFund').placeholder = 'Watchlist full (100/100)';
    renderWatch();
    renderAlerts();
  });

  $('markRead').onclick = () => {
    const keys = readKeys();
    HOME.updates.forEach(u => { if (u.fid && Regret.watch.slugs.has(u.fid) && KINDS[u.k]) keys.add(alertKey(u)); });
    storeKeys(keys);
    renderAlerts();
  };

  document.querySelectorAll('[data-pref]').forEach(el => {
    el.onclick = async () => {
      if (!Regret.user || !Regret.sb()) return;
      el.classList.toggle('on');
      const patch = {};
      patch[el.dataset.pref] = el.classList.contains('on');
      const { error } = await Regret.sb().from('alert_preferences').update(patch).eq('profile_id', Regret.user.id);
      if (error) el.classList.toggle('on');
    };
  });

  document.querySelectorAll('.pips').forEach(p => {
    p.querySelectorAll('button').forEach((b, i, all) => {
      b.onclick = () => {
        const was = b.classList.contains('on') && ![...all].slice(i + 1).some(x => x.classList.contains('on'));
        all.forEach((x, j) => x.classList.toggle('on', !was && j <= i));
      };
    });
  });
  document.querySelectorAll('#again button').forEach(b => {
    b.onclick = () => { document.querySelectorAll('#again button').forEach(x => x.classList.toggle('on', x === b)); };
  });
  $('anonTog').onclick = () => $('anonTog').classList.toggle('on');
  $('revRound').onchange = anonHint;
  document.querySelectorAll('#connect .chip').forEach(chip => {
    chip.onclick = e => {
      e.preventDefault();
      document.querySelectorAll('#connect .chip').forEach(x => x.classList.toggle('on', x === chip));
      anonHint();
    };
  });
  $('fundIn').addEventListener('input', () => { $('fundIn').dataset.firm = ''; showFunds(); });
  $('fundIn').addEventListener('focus', showFunds);
  $('fundIn').addEventListener('blur', () => $('fundDD').classList.remove('on'));
  $('fundDD').addEventListener('mousedown', e => {
    const opt = e.target.closest('.opt');
    if (!opt) return;
    e.preventDefault();
    $('fundIn').value = opt.dataset.name;
    $('fundIn').dataset.firm = opt.dataset.firm;
    $('fundDD').classList.remove('on');
  });

  $('shareForm').onsubmit = async e => {
    e.preventDefault();
    const err = $('shareErr');
    err.hidden = true;
    const fail = text => { err.hidden = false; err.textContent = text; };
    const slug = $('fundIn').dataset.firm;
    if (!slug) { fail('Pick a fund from the list.'); return; }
    const linkedin = $('revLinkedin').value.trim();
    if (!LI_URL.test(linkedin)) { fail('Use a LinkedIn profile URL like linkedin.com/in/your-name.'); return; }
    const again = document.querySelector('#again button.on');
    if (!again) { fail('Say whether you would take their money again.'); return; }
    if (!Regret.user || !Regret.sb()) { fail('Log in before you send a review.'); return; }
    const firm = await Regret.firmId(slug);
    if (!firm) { fail('That fund is not in the database yet.'); return; }
    const ratings = {};
    document.querySelectorAll('.pips').forEach(p => {
      const on = p.querySelectorAll('button.on').length;
      if (on) ratings[p.dataset.dim] = on;
    });
    const who = selectedConnection();
    const { error } = await Regret.sb().from('reviews').insert({
      firm_id: firm,
      profile_id: Regret.user.id,
      body: $('revBody').value.trim() || null,
      moderation_status: 'pending',
      anonymous: $('anonTog').classList.contains('on'),
      role_label: who[1],
      round_label: $('revRound').value,
      would_again: again.dataset.yes === 'yes',
      verification_method: 'linkedin',
      connection_type: who[0],
      linkedin_url: linkedin,
      honesty: ratings.honesty || null,
      support_after_check: ratings.support_after_check || null,
      founder_friendly_terms: ratings.founder_friendly_terms || null,
      responsiveness: ratings.responsiveness || null,
      hard_times: ratings.hard_times || null
    }).select('id').single();
    if (error) { fail(error.message); return; }
    $('shareForm').outerHTML = '<div class="card done"><b>Submitted.</b><p>It stays hidden until we review it. Nothing here is shown on the fund page before that.</p></div>';
  };

  Regret.ready.then(async () => {
    if (!Regret.sb()) {
      $('wlOut').innerHTML = '<div class="empty"><b>Sign-in is not configured on this build.</b>Add the Supabase URL and publishable key, then rebuild.</div>';
      return;
    }
    if (!Regret.user) {
      const view = (location.hash || '#watchlist').replace('#', '') || 'watchlist';
      location.href = new URL('login/', Regret.siteRoot()).href + '?next=account/&view=' + encodeURIComponent(view);
      return;
    }
    anonHint();
    renderWatch();
    renderAlerts();
    await loadPrefs();
  });
})();
