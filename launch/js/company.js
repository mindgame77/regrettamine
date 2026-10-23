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
    const lc = main.querySelector('#lockcard'); lc.hidden = P.open;
    lc.querySelector('b').textContent = fmt(COPY.lockcard, { n: total, firm }); lc.querySelector('p').textContent = COPY.lockcard_sub;
    document.getElementById('puse').textContent = fmt(COPY.use_line, { n: total, firm });
    main.querySelectorAll('.row.tog').forEach(row => row.onclick = (e) => { if (!e.target.closest('a')) row.classList.toggle('open'); });
    return { total, head: (key) => { const s = secs.find(x => x.key === key); return s ? fmt(COPY.pay_head, { title: s.title, firm, count: label(s) }) : fmt(COPY.pay_all, { n: total, firm }); } };
  }
  window.RegretCompany = { render };
})();
