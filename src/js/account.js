/* Account tabs. Watchlist and history render through FundList, the landing list. */
(function () {
  const HOME = JSON.parse(document.getElementById('home-data').textContent);
  const BY_ID = Object.fromEntries(HOME.funds.map(f => [f.id, f]));
  const READ_KEY = 'regret.alerts.read';
  const KINDS = { Court: 'Legal', Regulator: 'Regulator', Rescore: 'Score' };
  const $ = id => document.getElementById(id);

  function go() {
    const v = (location.hash || '#watchlist').replace('#', '') || 'watchlist';
    const name = ['watchlist', 'alerts', 'history', 'share'].includes(v) ? v : 'watchlist';
    document.querySelectorAll('.view').forEach(el => el.classList.toggle('on', el.id === name));
    document.querySelectorAll('.anav a').forEach(a => a.classList.toggle('on', a.dataset.v === name));
  }
  addEventListener('hashchange', go);
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

  function renderMeter(used) {
    const total = Regret.limits.anon + Regret.limits.extra;
    const freeUsed = Math.min(used, Regret.limits.anon);
    const extraUsed = Math.min(Math.max(used - Regret.limits.anon, 0), Regret.limits.extra);
    const left = Math.max(total - used, 0);
    function slots(n, on, cls) {
      let html = '';
      for (let i = 0; i < n; i++) html += '<i class="' + (i < on ? cls : '') + '"></i>';
      return html;
    }
    $('meter').innerHTML = '<div class="mt"><div><b class="d">' + used + ' of ' + total + '</b><span>free reports used</span></div><div class="segs">'
      + '<div class="grp"><div class="bar">' + slots(Regret.limits.anon, freeUsed, 'u') + '</div><small>Free</small></div>'
      + '<div class="grp g5"><div class="bar">' + slots(Regret.limits.extra, extraUsed, 'u ac') + '</div><small>With account</small></div>'
      + '<div class="grp pd"><div class="bar"><i class="inf"></i></div><small>Plan</small></div></div></div>'
      + '<div class="mb"><span>' + left + ' left. After that, unlimited reports come with a plan. Re-opening a fund is always free.</span>'
      + '<button type="button" class="b c sm" id="plansBtn">See plans</button></div>';
    $('plansBtn').onclick = () => RegretAuth.open('plans', false);
  }

  async function historySlugs() {
    const client = Regret.sb();
    if (!client || !Regret.user) return [];
    const { data } = await client.from('report_views').select('counted, first_opened_at, firms(slug)').eq('profile_id', Regret.user.id).order('first_opened_at', { ascending: true });
    return (data || []).filter(row => row.counted && row.firms && row.firms.slug).map(row => row.firms.slug);
  }

  async function renderHistory() {
    const slugs = await historySlugs();
    const rows = slugs.map(id => BY_ID[id]).filter(Boolean);
    renderMeter(slugs.length);
    const total = Regret.limits.anon + Regret.limits.extra;
    FundList.mount($('hsOut'), rows, {
      total: total,
      prefix: '../',
      note: '<span class="none">Re-opening a fund is always free.</span>',
      empty: '<div class="empty"><b>No reports yet.</b>Open a fund and it will show up here.</div>'
    });
  }

  function fillFunds() {
    const sel = $('revFund');
    sel.innerHTML = HOME.funds.map(f => '<option value="' + Regret.esc(f.id) + '">' + Regret.esc(f.name) + '</option>').join('');
  }
  function anonHint() {
    $('anonHint').textContent = 'Shown as "' + $('revRole').value + ', ' + $('revRound').value + '"';
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
  $('revRole').onchange = anonHint;
  $('revRound').onchange = anonHint;
  document.querySelectorAll('#verify .chip').forEach(chip => {
    chip.onclick = () => {
      const on = chip.classList.contains('on');
      document.querySelectorAll('#verify .chip').forEach(x => x.classList.remove('on'));
      if (!on) chip.classList.add('on');
    };
  });

  $('shareForm').onsubmit = async e => {
    e.preventDefault();
    const err = $('shareErr');
    err.hidden = true;
    if (!Regret.user || !Regret.sb()) {
      err.hidden = false;
      err.textContent = 'Log in before you send a review.';
      return;
    }
    const slug = $('revFund').value;
    const firm = await Regret.firmId(slug);
    if (!firm) { err.hidden = false; err.textContent = 'That fund is not in the database yet.'; return; }
    const method = (document.querySelector('#verify .chip.on') || {}).dataset;
    const ratings = [...document.querySelectorAll('.pips')].map(p => {
      const on = [...p.querySelectorAll('button.on')].length;
      return on ? { dimension: p.dataset.dim, score: on } : null;
    }).filter(Boolean);
    const { data, error } = await Regret.sb().from('reviews').insert({
      firm_id: firm,
      profile_id: Regret.user.id,
      body: $('revBody').value.trim() || null,
      first_hand: true,
      verification_status: 'unverified',
      moderation_status: 'pending',
      anonymous: $('anonTog').classList.contains('on'),
      role_label: $('revRole').value,
      round_label: $('revRound').value,
      would_again: document.querySelector('#again button.on').dataset.yes === 'yes',
      verification_method: method && method.method ? method.method : null
    }).select('id').single();
    if (error) { err.hidden = false; err.textContent = error.message; return; }
    if (ratings.length) {
      const { error: rateErr } = await Regret.sb().from('review_ratings').insert(ratings.map(r => ({ review_id: data.id, dimension: r.dimension, score: r.score })));
      if (rateErr) { err.hidden = false; err.textContent = rateErr.message; return; }
    }
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
    fillFunds();
    anonHint();
    renderWatch();
    renderAlerts();
    await loadPrefs();
    await renderHistory();
  });
})();
