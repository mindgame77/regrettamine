/* Reviewer queue. Founder reviews and corrections share one row layout. */
(function () {
  const $ = id => document.getElementById(id);

  function when(iso) {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  }

  function row(title, lines, id, kind) {
    return '<div class="srow" data-id="' + Regret.esc(id) + '" data-kind="' + kind + '"><div><b>' + Regret.esc(title) + '</b>'
      + lines.map(line => '<span>' + line + '</span>').join('')
      + '</div><div class="acts"><button class="b c sm" type="button" data-status="approved">Approve</button><button class="b w sm" type="button" data-status="rejected">Reject</button></div></div>';
  }

  function names(firms, id) {
    return (firms[id] && firms[id].name) || 'Fund';
  }

  async function firmNames(ids) {
    const unique = [...new Set(ids.filter(Boolean))];
    if (!unique.length) return {};
    const { data } = await Regret.sb().from('firms').select('id, name, slug').in('id', unique);
    return Object.fromEntries((data || []).map(f => [f.id, f]));
  }

  async function load() {
    const client = Regret.sb();
    const reviews = await client.from('reviews').select('id, body, created_at, firm_id, role_label').eq('moderation_status', 'pending').order('created_at', { ascending: false });
    const corrections = await client.from('corrections').select('id, message, source_url, page_url, created_at, fund_id').eq('status', 'pending').order('created_at', { ascending: false });
    const reviewRows = reviews.data || [];
    const correctionRows = corrections.data || [];
    const firms = await firmNames(reviewRows.map(r => r.firm_id).concat(correctionRows.map(r => r.fund_id)));
    $('reviewQueue').innerHTML = reviewRows.length
      ? reviewRows.map(item => row(names(firms, item.firm_id), [Regret.esc(item.role_label || 'Founder') + ' · ' + Regret.esc(when(item.created_at)), Regret.esc(item.body || '')], item.id, 'review')).join('')
      : '<div class="srow"><div><b>Nothing waiting.</b><span>New founder reviews show up here.</span></div></div>';
    $('correctionQueue').innerHTML = correctionRows.length
      ? correctionRows.map(item => row(
        names(firms, item.fund_id),
        [
          Regret.esc(when(item.created_at)),
          Regret.esc(item.message || ''),
          '<a href="' + Regret.esc(item.page_url) + '">Page</a> · <a href="' + Regret.esc(item.source_url) + '">Source</a>'
        ],
        item.id,
        'correction'
      )).join('')
      : '<div class="srow"><div><b>Nothing waiting.</b><span>New corrections show up here.</span></div></div>';
  }

  document.addEventListener('click', async e => {
    const btn = e.target.closest('[data-status]');
    if (!btn) return;
    const wrap = btn.closest('[data-id]');
    if (!wrap) return;
    const status = btn.dataset.status;
    const client = Regret.sb();
    const query = wrap.dataset.kind === 'review'
      ? client.from('reviews').update({ moderation_status: status }).eq('id', wrap.dataset.id)
      : client.from('corrections').update({ status: status }).eq('id', wrap.dataset.id);
    const { error } = await query;
    if (!error) wrap.remove();
  });

  Regret.ready.then(async () => {
    if (!Regret.sb()) return;
    if (!Regret.user) {
      location.href = new URL('login/?next=admin/', Regret.siteRoot()).href;
      return;
    }
    const { data } = await Regret.sb().rpc('is_admin');
    if (!data) {
      location.href = Regret.siteRoot().href;
      return;
    }
    load();
  });
})();
