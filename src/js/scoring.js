/* Scoring page. The corrections card is paid-only; the form is not the founder review. */
(function () {
  const $ = id => document.getElementById(id);
  let chosen = null;
  let token = 0;

  function paid() {
    return !!(window.Regret && Regret.user && Regret.tier === 'paid');
  }

  function paint() {
    const card = $('correctionsCard');
    const row = $('accessRow');
    const show = paid();
    if (card) card.hidden = !show;
    if (row) row.classList.toggle('one', !show);
    if (!show && $('correctForm')) $('correctForm').hidden = true;
  }

  function pageUrl(slug) {
    return new URL('vc/' + slug + '/', Regret.siteRoot()).href;
  }

  function showPicked(name, slug) {
    chosen = { name: name, slug: slug };
    $('correctPicked').hidden = false;
    $('correctPicked').innerHTML = '<b>' + Regret.esc(name) + '</b><small>' + Regret.esc(pageUrl(slug)) + '</small>';
    $('correctPick').hidden = true;
  }

  async function prefill() {
    const slug = new URLSearchParams(location.search).get('fund') || '';
    if (!/^[a-z0-9-]{1,80}$/.test(slug)) return;
    const client = Regret.sb && Regret.sb();
    if (!client) return;
    const { data } = await client.rpc('search_funds', { q: slug });
    const hit = (data || []).find(row => (row.slug || row.id) === slug);
    if (!hit || !$('correctForm')) return;
    showPicked(hit.name, hit.slug || hit.id);
    if (location.hash === '#correction') {
      $('correctForm').hidden = false;
      $('correctionsCard').scrollIntoView({ block: 'start' });
    }
  }

  async function showFunds() {
    const q = $('correctIn').value.trim();
    const dd = $('correctDD');
    if (!q) { dd.classList.remove('on'); dd.innerHTML = ''; return; }
    const mine = ++token;
    const client = Regret.sb && Regret.sb();
    if (!client) return;
    const { data } = await client.rpc('search_funds', { q: q });
    if (mine !== token) return;
    const rows = data || [];
    if (!rows.length) {
      dd.innerHTML = '<div class="none">No fund found</div>';
      dd.classList.add('on');
      return;
    }
    dd.innerHTML = rows.map((f, i) => {
      const id = f.id || f.slug;
      return '<button type="button" class="opt' + (i ? '' : ' hi') + '" data-firm="' + Regret.esc(id) + '" data-name="' + Regret.esc(f.name) + '"><div class="on2"><b>' + Regret.esc(f.name) + '</b><small>' + Regret.esc(f.hq || id) + '</small></div></button>';
    }).join('');
    dd.classList.add('on');
  }

  function fail(text) {
    const err = $('correctErr');
    err.hidden = !text;
    err.textContent = text || '';
  }

  $('correctOpen').addEventListener('click', () => {
    if (!paid()) return;
    $('correctForm').hidden = false;
    if (!chosen) $('correctIn').focus();
  });

  $('correctIn').addEventListener('input', showFunds);
  $('correctDD').addEventListener('click', e => {
    const btn = e.target.closest('[data-firm]');
    if (!btn) return;
    showPicked(btn.dataset.name, btn.dataset.firm);
    $('correctDD').classList.remove('on');
    $('correctIn').value = '';
  });

  $('correctForm').addEventListener('submit', async e => {
    e.preventDefault();
    fail('');
    if (!paid()) { fail('A paid plan is required.'); return; }
    if (!chosen) { fail('Choose a fund.'); return; }
    const message = $('correctMsg').value.trim();
    const source = $('correctSource').value.trim();
    if (!message) { fail('Say what is wrong.'); return; }
    if (!/^https?:\/\//i.test(source)) { fail('The source has to be an http or https link.'); return; }
    const client = Regret.sb();
    const { data: firmId, error: lookup } = await client.rpc('public_firm_id', { p_slug: chosen.slug });
    if (lookup || !firmId) { fail('That fund is not on the list.'); return; }
    const { error } = await client.from('corrections').insert({
      user_id: Regret.user.id,
      fund_id: firmId,
      page_url: pageUrl(chosen.slug),
      message: message,
      source_url: source,
      status: 'pending'
    });
    if (error) { fail('Could not send that. A paid plan is required.'); return; }
    $('correctForm').outerHTML = '<div class="card done" id="correctDone"><b>Submitted.</b><p>We review every request.</p></div>';
  });

  function boot() {
    paint();
    if (paid()) prefill();
  }
  if (window.Regret && Regret.ready) Regret.ready.then(boot);
  else boot();
  if (window.Regret && Regret.onChange) Regret.onChange(boot);
})();
