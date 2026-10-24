/* Company page (/vc/<slug>/): section data (count, teaser, items) comes from firm_page(); which sections show,
   their order, titles, subtitles, unit labels and renderer come from copy.json "sections". Exposes window.RegretCompany. */
(function () {
  const CFG = window.REGRET.copy, COPY = CFG.company, PILL = CFG.site.pills;
  const fmt = (t, o) => t.replace(/\{(\w+)\}/g, (_, k) => o[k]);
  const esc = (x) => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const safeUrl = (u) => /^https?:\/\//i.test(u || '') ? u : null;
  const ROOT = window.REGRET_ROOT || '';
  const chips = (src) => '<div class="scs">' + (src || []).map(s => { const u = safeUrl(s.url); const t = esc(s.label) + (s.date ? ' · ' + esc(s.date) : '') + ' ↗';
    return u ? '<a class="sc" href="' + esc(u) + '" target="_blank" rel="noopener">' + t + '</a>' : ''; }).join('') + '</div>';
  const pill = (st) => { const p = PILL[st] || PILL.nc; return '<span class="pill ' + p[0] + '"><i></i>' + p[1] + '</span>'; };
  const group = (items, key, labels, body) => Object.keys(labels).map(g => { const xs = items.filter(i => i[key] === g);
    return xs.length ? '<h3>' + esc(labels[g]) + ' · ' + xs.length + '</h3>' + (g === 'context' ? '<p class="psub">' + esc(COPY.legal.contextSub) + '</p>' : '') + body(xs) : ''; }).join('');

  // Check-row facts (firm_details rows): case status from the fact wording, same rule as _firm_cases() in the DB.
  const isCase = (f) => !!f.case || / v\.? .*\|.*\b(filed|terminated)\b/i.test(f.text || '');
  function caseStatus(f) {
    if (!isCase(f)) return null;
    const t = f.text || '';
    if (/\bnon-party\b|\bnot a party\b/i.test(t)) return null;
    if (/\b(active|pending|ongoing)\b|\bopen\b[,.;:]|\bis investigating\b/i.test(t)) return 'active';
    if (/\boutcome (unverified|not verified)\b/i.test(t)) return null;
    if (/\b(terminated|dismissed|ended in|settled|resolved|closed|affirmed)\b/i.test(t)) return 'closed';
    return null;
  }
  function factHtml(f) {
    const who = f.who && f.who.startsWith('partner:') ? f.who.slice(8) + ' · ' : '';
    const head = f.case ? '<b>' + esc(f.case) + '</b>' + (f.year ? ' · ' + esc(f.year) : '') + '<br>' : '';
    const u = safeUrl(f.url), st = caseStatus(f);
    const src = (u ? '<a href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(f.label || COPY.source) + ' ↗</a>' : esc(f.label || '')) + (f.date ? ' · ' + COPY.retrieved + esc(f.date) : '');
    const p = st === 'active' ? '<span class="cs cs-act">Active</span>' : st === 'closed' ? '<span class="cs cs-cl">Closed</span>' : '';
    return '<div class="fct' + (st === 'active' ? ' act' : '') + '">' + p + (f.needs_proof ? '<span class="np">Needs proof</span>' : '') + head + esc(who) + esc(f.text) + '<div class="src">' + src + '</div></div>';
  }
  const spill = (st) => st === 'active' ? '<span class="cs cs-act">Active</span>' : st === 'closed' ? '<span class="cs cs-cl">Closed</span>' : '';
  function checkRows(P) {
    const det = {}, out = {}; (P.details || []).forEach(r => det[r.row] = r.facts || []); (P.outline || []).forEach(r => out[r.row] = r.items || []);
    return '<div class="list">' + P.checks.map(r => {
      const cnt = r.count ? '<span class="cnt ' + (r.state === 'clear' ? 'cg' : 'ca') + '">' + esc(r.count) + '</span>' : '';
      const gl = P.open ? '' : (out[r.n] || []).map((e, i) => '<button type="button" class="gc' + (e.status === 'active' ? ' act' : '') + '" data-sec="checks" data-kind="' + esc(e.kind) + '" data-year="' + esc(e.year || '') + '">'
        + '<span class="y">' + esc(e.year || '—') + '</span><span class="k">' + esc(e.kind) + '</span><span class="bl"><span class="bar" style="width:' + (20 + ((e.kind || '').length * 7 + i * 13) % 45) + '%"></span><span class="bar" style="width:22%"></span></span>'
        + spill(e.status) + '<span class="lkk">' + COPY.locked + '</span></button>').join('');
      const rank = (f) => caseStatus(f) === 'active' ? 0 : 1;
      const fs = (det[r.n] || []).map((f, i) => [f, i]).sort((a, b) => rank(a[0]) - rank(b[0]) || a[1] - b[1]).map(x => x[0]);
      const d = P.open ? (fs.length ? fs.map(factHtml).join('') : '<div class="fct">' + COPY.no_facts + '</div>') : '';
      return '<div class="row' + (r.n === 10 ? ' last' : '') + (P.open ? ' tog' : '') + '" id="check-' + r.n + '"><span class="n">' + String(r.n).padStart(2, '0') + '</span><div class="tx"><b>' + esc(r.title) + '</b><span>' + esc(r.descr) + '</span></div>'
        + '<div class="pc">' + pill(r.state) + cnt + '</div><span class="lk"></span><div class="gl">' + gl + '</div><div class="det">' + d + '</div></div>';
    }).join('') + '</div>';
  }

  // Open-state renderers, keyed by copy.json sections[].renderer
  const R = {
    facts: (it) => '<div class="kvs">' + it.map(x => '<div class="kv"><span class="k">' + esc(x.label) + '</span><span>' + esc(x.value) + chips(x.src) + '</span></div>').join('') + '</div>',
    checks: (it, P) => checkRows(P),
    legal: (it) => group(it, 'grp', COPY.legal, xs => xs.map(x => '<div class="it' + (x.state === 'Active' ? ' act' : '') + '">'
      + (x.state ? '<span class="cs ' + COPY.state[x.state] + '">' + esc(x.state) + '</span> ' : '') + (x.status ? '<span class="pill ' + (COPY.tone[x.tone] || 'p-g') + '"><i></i>' + esc(x.status) + '</span> ' : '')
      + (x.role ? '<span class="cs cs-cl">' + esc(x.role) + '</span> ' : '') + '<b>' + esc(x.title) + (x.year ? ' · ' + esc(x.year) : '') + '</b>' + (x.note ? ' · ' + esc(x.note) : '') + chips(x.src) + '</div>').join('')),
    press: (it) => '<div class="pgr">' + it.map(x => card(x, true)).join('') + '</div>',
    founders: (it) => '<div class="pgr">' + it.map(x => card(x, false)).join('') + '</div>',
    people: (it) => group(it, 'kind', COPY.people, xs => '<div class="pcards">' + xs.map(x => '<div class="pcard"><b>' + esc(x.head) + '</b>' + (x.badge ? '<span class="cs cs-act">' + esc(x.badge) + '</span>' : '') + '<span>' + esc(x.role) + '</span>' + chips(x.src) + '</div>').join('') + '</div>'),
    timeline: (it) => '<div class="tls">' + it.map(x => '<div class="tl"><span class="tld">' + esc(x.date) + '</span><span><span class="cs cs-cl">' + esc(x.kind) + '</span> ' + esc(x.body) + chips(x.src) + '</span></div>').join('') + '</div>',
  };
  function card(x, logo) {
    const u = safeUrl(x.url), host = u ? new URL(u).hostname.replace(/^www\./, '') : '';
    const fav = logo && x.logo ? '<img class="fav" src="' + esc(ROOT + x.logo) + '" alt="" width="20" height="20">' : '<span class="fav lb">' + esc((x.outlet || '?')[0]) + '</span>';
    return '<div class="pi"><div class="pio">' + fav + '<span>' + esc(x.outlet) + ' · ' + esc(host) + (x.date ? ' · ' + esc(x.date) : '') + '</span></div>'
      + (u ? '<a class="pih" href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(x.head) + '</a>' : '<b class="pih">' + esc(x.head) + '</b>')
      + (x.snippet ? '<p class="pis">' + esc(x.snippet) + '</p>' : '') + chips(x.src) + '</div>';
  }
  // Locked: real count, one visible line, gray blocks for the rest. Nothing else is in the RPC reply.
  function lockedBody(s) {
    const bars = Array.from({ length: Math.min(s.count - 1, 4) }, (_, i) => '<span class="gb" style="width:' + (92 - i * 13) + '%"></span>').join('');
    return '<button type="button" class="lsec" data-sec="' + esc(s.key) + '"><span class="lt">' + esc(s.teaser) + '</span>' + bars + '<span class="lkk">' + COPY.locked + '</span></button>';
  }
  const label = (s) => s.count + ' ' + (s.count === 1 ? s.unit_one : s.unit_many);

  // "On this page": highlight the link for the section in view; set it at once on click
  let SPY = null;
  function spy(main) {
    const toc = main.querySelector('.toc'), links = Array.from(toc.querySelectorAll('a[href^="#"]'));
    const on = (id) => links.forEach(a => a.classList.toggle('on', a.getAttribute('href') === '#' + id));
    toc.onclick = (e) => { const a = e.target.closest('a[href^="#"]'); if (a) on(a.getAttribute('href').slice(1)); };
    if (SPY) SPY.disconnect();
    if (!('IntersectionObserver' in window)) return;
    SPY = new IntersectionObserver((es) => es.forEach(e => { if (e.isIntersecting) on(e.target.id); }), { rootMargin: '-30% 0px -60% 0px' });
    main.querySelectorAll('.ps').forEach(s => SPY.observe(s));
  }
  function render(main, P) {
    const firm = P.firm.name, byKey = Object.fromEntries(P.sections.map(s => [s.key, s])),
      secs = CFG.sections.list.filter(c => byKey[c.key]).map(c => Object.assign({}, byKey[c.key], c)), total = secs.filter(s => s.key !== 'checks').reduce((a, s) => a + s.count, 0);
    main.classList.toggle('unlocked', P.open);
    main.querySelector('.m').textContent = [P.firm.hq, P.firm.short_name].filter(Boolean).join(' · ');
    const has = new Set(secs.map(s => s.key));
    main.querySelector('.hfs').innerHTML = P.hero.map(h => '<a class="hf" href="#' + (has.has(h.anchor) ? esc(h.anchor) : '') + '"><span>' + esc(h.label) + '</span><b>' + esc(h.value) + '</b>' + h.src.map(c => '<span class="sc">' + esc(c.label) + (c.date ? ' · ' + esc(c.date) : '') + '</span>').join('') + '</a>').join('');
    main.querySelector('.csum').innerHTML = has.has('checks') ? '<div class="csh"><b>' + COPY.summary + '</b><a href="#checks">' + COPY.full_check + '</a></div><div class="cks">'
      + P.checks.map(r => '<a class="ck" href="#checks"><span class="ckn">' + String(r.n).padStart(2, '0') + '</span>' + esc(r.title) + pill(r.state) + '</a>').join('') + '</div>' : '';
    main.querySelector('.csum').hidden = !has.has('checks');
    main.querySelector('.spl').innerHTML = secs.map(s => '<a class="spp" href="#' + esc(s.key) + '">' + esc(s.title) + ' <em>' + s.count + '</em></a>').join('');
    main.querySelector('.toc').innerHTML = '<b>' + COPY.toc + '</b>' + secs.map(s => '<a href="#' + esc(s.key) + '">' + esc(s.title) + '</a>').join('');
    main.querySelector('.pmain').innerHTML = secs.map(s => '<section id="' + esc(s.key) + '" class="ps"><h2>' + esc(s.title) + ' <em class="pc2">' + esc(label(s)) + '</em></h2><p class="psub">' + esc(s.subtitle || '') + '</p>'
      + (P.open || s.key === 'checks' ? (R[s.renderer] || R.facts)(s.items || [], P) : lockedBody(s)) + '</section>').join('');
    spy(main);
    const lc = main.querySelector('#lockcard'); lc.hidden = P.open;
    lc.querySelector('b').textContent = fmt(COPY.lockcard, { n: total, firm }); lc.querySelector('p').textContent = COPY.lockcard_sub;
    document.getElementById('puse').textContent = fmt(COPY.use_line, { n: total, firm });
    main.querySelectorAll('.row.tog').forEach(row => row.onclick = (e) => { if (!e.target.closest('a')) row.classList.toggle('open'); });
    return { total, head: (key) => { const s = secs.find(x => x.key === key); return s ? fmt(COPY.pay_head, { title: s.title, firm, count: label(s) }) : fmt(COPY.pay_all, { n: total, firm }); } };
  }

  // Summary page (/vc/<slug>/): name, key-fact chips, the 10 checks (closed), then "See the full check".
  // Dropdowns show info only (status pill + case or summary text, no sources); a row with nothing to show has no dropdown.
  function sumItem(f) {
    const who = f.who && f.who.startsWith('partner:') ? f.who.slice(8) + ' · ' : '';
    const head = f.case ? '<b>' + esc(f.case) + '</b>' + (f.year ? ' · ' + esc(f.year) : '') + '<br>' : '';
    const st = caseStatus(f);
    if (!f.case && !f.text && !f.needs_proof && !st) return ''; // nothing to show for this fact
    return '<div class="fct' + (st === 'active' ? ' act' : '') + '">' + spill(st) + (f.needs_proof ? '<span class="np">Needs proof</span>' : '') + head + esc(who) + esc(f.text) + '</div>';
  }
  // Signed-out outline: a bare method label (no status, no year) tells the viewer nothing, so it is not shown.
  const outItem = (e) => !e.status && !e.year ? '' : '<div class="fct' + (e.status === 'active' ? ' act' : '') + '">' + spill(e.status) + '<b>' + esc(e.kind) + '</b>' + (e.year ? ' · ' + esc(e.year) : '') + '</div>';
  // Rows with no dropdown: one muted line saying what was searched. "Nothing found" only when the row really is clear / none found; Not checked yet rows get no line (the pill says it).
  const srch = (r) => { const S = COPY.searched || {}, st = PILL[r.state] ? r.state : 'nc';
    const t = st === 'nc' ? '' : S[r.n] ? S[r.n] + (st === 'clear' || st === 'nf' ? ' ' + COPY.searched_nf : '') : '';
    return t ? '<em class="srch">' + esc(t) + '</em>' : ''; };
  // Checking view: a firm whose 10 checks are not all done. Done rows (state != 'nc' in the data) show their real pill,
  // the first not-done row shows the spinner, the rest "Waiting". No results are invented. js/app.js polls and re-renders.
  const CK = COPY.checking;
  const doneN = (P) => (P.checks || []).filter(r => r.state !== 'nc').length;
  function checkingHead(main, P, st) {
    const done = doneN(P), cur = (P.checks || []).find(r => r.state === 'nc'), firm = P.firm.name;
    main.querySelector('.fh h1').innerHTML = esc(fmt(CK.title, { firm })) + '<span class="dots">…</span>';
    const t = st && st.started_at ? new Date(st.started_at) : null;
    const b = main.querySelector('.cban'); b.className = 'cban'; b.hidden = false;
    b.innerHTML = '<div class="ch"><b>' + esc(fmt(CK.progress, { done, check: cur ? cur.title : '' })) + '</b><span>' + esc(CK.usually) + '</span></div>'
      + '<div class="cbar" role="progressbar" aria-valuemin="0" aria-valuemax="10" aria-valuenow="' + done + '"><i style="width:' + Math.max(done * 10, 4) + '%"></i></div>'
      + (t && !isNaN(t) ? '<div class="cs2">' + esc(fmt(CK.started, { time: t.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }) })) + '</div>' : '');
  }
  function summary(main, P, st) {
    const checking = !!(P.checks && P.checks.length) && doneN(P) < 10, justDone = !checking && !!(st && st.just_done);
    main.classList.toggle('checking', checking);
    main.querySelector('.cside').hidden = !checking;
    if (checking) checkingHead(main, P, st);
    else {
      main.querySelector('.fh h1').textContent = P.firm.name;
      const b = main.querySelector('.cban'); b.hidden = !justDone; b.className = 'cban ok';
      b.innerHTML = justDone ? '<div class="ch"><div><b>' + esc(CK.complete) + '</b> <span>' + esc(CK.complete_sub) + '</span></div></div>' : '';
    }
    const curN = checking ? P.checks.find(r => r.state === 'nc').n : 0;
    if (checking && !P.hero.length) main.querySelector('.kf').innerHTML = '<span>' + esc(CK.sources[0]) + ' <b>' + esc(CK.sources[1]) + '</b></span>';
    else main.querySelector('.kf').innerHTML = P.hero.map(h => '<span>' + esc(h.label) + ' <b>' + esc(h.value) + '</b>' + (h.src || []).slice(0, 1).map(c => ' <i>· ' + esc(c.label) + (c.date ? ' · ' + esc(c.date) : '') + '</i>').join('') + '</span>').join('');
    const det = {}, out = {}; (P.details || []).forEach(r => det[r.row] = r.facts || []); (P.outline || []).forEach(r => out[r.row] = r.items || []);
    const rank = (f) => caseStatus(f) === 'active' ? 0 : 1;
    main.querySelector('.list').innerHTML = P.checks.map(r => {
      const cnt = r.count ? '<span class="cnt ' + (r.state === 'clear' ? 'cg' : 'ca') + '">' + esc(r.count) + '</span>' : '';
      const fs = (det[r.n] || []).map((f, i) => [f, i]).sort((a, b) => rank(a[0]) - rank(b[0]) || a[1] - b[1]).map(x => x[0]);
      const nc = r.state === 'nc' || !PILL[r.state];
      const d = nc ? '' : P.open ? fs.map(sumItem).join('') : (out[r.n] || []).map(outItem).join('');
      const right = !nc ? pill(r.state) + cnt : r.n === curN ? '<span class="pill p-cur"><span class="sp" aria-hidden="true"></span>' + esc(CK.current) + '</span>' : '<span class="wt">' + esc(CK.waiting) + '</span>';
      return '<div class="row' + (r.n === 10 ? ' last' : '') + (d ? ' tog' : '') + (nc ? (r.n === curN ? ' cur' : ' up') : '') + '" id="check-' + r.n + '"' + (d ? ' role="button" tabindex="0" aria-expanded="false"' : '') + '><span class="n">' + String(r.n).padStart(2, '0') + '</span><div class="tx"><b>' + esc(r.title) + '</b><span>' + esc(r.descr) + '</span>' + (d ? '' : srch(r)) + '</div>'
        + '<div class="pc">' + right + '</div>' + (d ? '<div class="det">' + d + '</div>' : '') + '</div>';
    }).join('');
    main.querySelectorAll('.row.tog').forEach(row => {
      const t = () => row.setAttribute('aria-expanded', row.classList.toggle('open'));
      row.onclick = t; row.onkeydown = (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); t(); } };
    });
    return { total: 0, head: () => '', checking };
  }
  window.RegretCompany = { render, summary };
})();
