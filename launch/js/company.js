/* Company page (/vc/<slug>/): section data (count, teaser, items) comes from firm_page(); which sections show,
   their order, titles, subtitles, unit labels and renderer come from copy.json "sections". Exposes window.RegretCompany. */
(function () {
  const CFG = window.REGRET.copy, COPY = CFG.company, PILL = CFG.site.pills;
  const fmt = (t, o) => t.replace(/\{(\w+)\}/g, (_, k) => o[k]);
  const esc = (x) => String(x == null ? '' : x).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  // ALL-CAPS names from filings (SEC, FEC: "KUSHNER, JOSHUA → GROWTH DEMOCRATS") shown in title case, display only.
  // Same rules as secTitle() in launch/edge/firm.mjs and sec_title() in launch/build.py; the stored data is unchanged.
  const SEC_KEEP = {'LLC': 'LLC', 'L.L.C.': 'L.L.C.', 'L.L.C': 'L.L.C', 'LP': 'LP', 'L.P.': 'L.P.', 'L.P': 'L.P', 'LLP': 'LLP', 'L.L.P.': 'L.L.P.',
    'INC': 'Inc', 'INC.': 'Inc.', 'LTD': 'Ltd', 'LTD.': 'Ltd.', 'CO': 'Co', 'CO.': 'Co.', 'CORP': 'Corp', 'CORP.': 'Corp.',
    'PLC': 'PLC', 'GP': 'GP', 'SA': 'SA', 'S.A.': 'S.A.', 'AG': 'AG', 'GMBH': 'GmbH', 'SARL': 'SARL', 'S.A.R.L.': 'S.à r.l.',
    'BV': 'BV', 'B.V.': 'B.V.', 'NV': 'NV', 'AB': 'AB', 'AS': 'AS', 'SPA': 'SpA', 'PTE': 'Pte', 'PTY': 'Pty', 'LLLP': 'LLLP',
    'A16Z': 'a16z', 'US': 'US', 'USA': 'USA', 'UK': 'UK', 'VC': 'VC', 'AI': 'AI', 'II': 'II', 'III': 'III', 'IV': 'IV', 'VI': 'VI',
    'VII': 'VII', 'VIII': 'VIII', 'IX': 'IX', 'XI': 'XI', 'XII': 'XII', 'NEA': 'NEA', 'IVP': 'IVP', 'KKR': 'KKR', 'TPG': 'TPG',
    'GGV': 'GGV', 'USV': 'USV', 'TCV': 'TCV', 'IDG': 'IDG', 'NFX': 'NFX', 'DST': 'DST', 'EQT': 'EQT', 'QED': 'QED', 'SOSV': 'SOSV',
    'HV': 'HV', 'GV': 'GV', 'DCM': 'DCM', 'JMI': 'JMI', 'TA': 'TA', 'RRE': 'RRE', 'FPV': 'FPV', 'AVF': 'AVF', 'ESP': 'ESP', 'HIG': 'HIG',
    'H.I.G.': 'H.I.G.', 'UBS': 'UBS', 'LGT': 'LGT', 'GCM': 'GCM', 'HGGC': 'HGGC', 'BVP': 'BVP',
  'SEC': 'SEC', 'FEC': 'FEC', 'PAC': 'PAC', 'CRD': 'CRD', 'LEI': 'LEI', 'FINRA': 'FINRA', 'OFAC': 'OFAC', 'FCA': 'FCA', 'EU': 'EU', 'UN': 'UN', 'SBIC': 'SBIC', 'ERISA': 'ERISA', 'NYC': 'NYC', 'IAPD': 'IAPD', 'ADV': 'ADV', 'RIA': 'RIA', 'AUM': 'AUM', 'LDA': 'LDA', 'FTX': 'FTX', 'RD': 'Rd', 'RD.': 'Rd.', 'ST.': 'St.', 'AVE': 'Ave', 'AVE.': 'Ave.', 'STE': 'Ste', 'STE.': 'Ste.', 'BLVD': 'Blvd', 'BLVD.': 'Blvd.'};
  const SEC_SMALL = new Set(['A', 'AN', 'AND', 'AT', 'DE', 'DER', 'DES', 'DU', 'ET', 'FOR', 'IN', 'LA', 'LE', 'OF', 'ON', 'THE', 'VAN', 'VON']);
  const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
  function secPart(w) {
    if (!/[A-Z]/.test(w)) return w;
    if (has(SEC_KEEP, w)) return SEC_KEEP[w];
    const core = w.replace(/[^A-Z]/g, '');
    if (/^[IVX]{2,5}$/.test(core)) return w;
    if (core.length <= 4 && !/[AEIOUY]/.test(core)) return w;
    const lo = w.toLowerCase(), i = lo.search(/[a-z]/);
    return lo.slice(0, i) + lo[i].toUpperCase() + lo.slice(i + 1);
  }
  function secTitle(s) {
    s = s || '';
    if (!s || /[a-z]/.test(s)) return s;
    return s.split(' ').map((w, i) => {
      const bare = w.replace(/^[,;()]+|[,;()]+$/g, '');
      if (i && SEC_SMALL.has(bare)) return w.toLowerCase();
      const k = has(SEC_KEEP, bare) ? bare : bare.replace(/[.,]+$/, '');
      if (has(SEC_KEEP, k)) return w.replace(k, SEC_KEEP[k]);
      return w.replace(/[^\s\-/'’&]+/g, secPart);
    }).join(' ');
  }
  // Body text: also keep a 2-letter state/country code after a comma ('MENLO PARK, CA' -> 'Menlo Park, CA').
  // Mixed text ('… adviser SEQUOIA CAPITAL OPERATIONS, LLC, … status ACTIVE, office 2800 SAND HILL RD., …'): a run of 2+ capitalised
  // words with at least two real words (3+ letters with a vowel, not a kept code like SEC/IAPD/CRD), or a status word, gets the same treatment.
  const STATUS_CAPS = new Set(['ACTIVE', 'INACTIVE', 'TERMINATED', 'PENDING', 'APPROVED', 'REGISTERED', 'WITHDRAWN', 'DISMISSED', 'CLOSED', 'OPEN', 'SETTLED']);
  const wordy = (w) => { const c = w.replace(/[^A-Z]/g, ''); return c.length >= 3 && /[AEIOUY]/.test(c) && !has(SEC_KEEP, w.replace(/[,;:)(]+$/, '')) && !has(SEC_KEEP, c); };
  const capsRuns = (t) => t.replace(/\b[A-Z][A-Z0-9.&'’\-\/]*(?:,?\s+[A-Z0-9][A-Z0-9.&'’\-\/]*)*/g, (m) => {
    const ws = m.split(/\s+/);
    if (ws.length >= 2 && ws.filter(wordy).length >= 2) return secTitle(m);
    // A status word stays in normal case wherever it sits in the run ('… SEC 801-122957, ACTIVE' -> '… Active').
    return m.replace(/\b[A-Z]+\b/g, (w) => STATUS_CAPS.has(w) ? w[0] + w.slice(1).toLowerCase() : w); });
  const nice = (t) => t ? capsRuns(secTitle(String(t))).replace(/(,\s*)([A-Z][a-z])(?=$|[\s,;)])/g, (m, a, b) => a + b.toUpperCase()) : t;
  const safeUrl = (u) => /^https?:\/\//i.test(u || '') ? u : null;
  const ROOT = window.REGRET_ROOT || '';
  // Dates: launch/js/dates.js (RegretDate). Date only "Mar 15, 2024"; a time is Pacific.
  const fdate = (d) => window.RegretDate ? window.RegretDate.format(d) : '';
  const shownYear = (x) => {
    if (!window.RegretDate || !x) return '';
    return window.RegretDate.caseYear(x.title || x.head || x.case || x.kind || '', x.note || x.text || '', x.year);
  };
  const MISS = (COPY.header && COPY.header.missing) || 'Not found in public records';
  function headerCards(P) {
    const hero = (Array.isArray(P.hero) ? P.hero : []).filter(h => h && (h.label || h.value));
    if (hero.length) return hero.map(h => Object.assign({}, h, { src: h.src || [] }));
    const H = COPY.header || {};
    const firm = P.firm || {};
    return [
      { label: H.hq || 'HQ', value: firm.hq || MISS, anchor: '', src: [] },
      { label: H.assets || 'Assets', value: firm.assets || MISS, anchor: '', src: [] },
    ];
  }
  function siteLink(P) {
    const u = safeUrl(P.firm && P.firm.website);
    if (!u) return '';
    let host = '';
    try { host = new URL(u).hostname.replace(/^www\./, ''); } catch (e) { return ''; }
    return host ? '<a href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(host) + '</a>' : '';
  }
  function metaLine(P) {
    const firm = P.firm || {};
    const bits = [firm.hq, firm.short_name].filter(Boolean).map(x => esc(nice(x)));
    const link = siteLink(P);
    return bits.join(' · ') + (link ? (bits.length ? ' · ' : '') + link : '');
  }
  function setFirmName(main, name) {
    if (!name) return;
    const h1 = main.querySelector('.ph h1');
    if (h1) {
      const save = h1.querySelector('[data-save]');
      h1.textContent = name;
      if (save) h1.appendChild(save);
    }
    const inp = main.querySelector('form[data-search] input[name=q]');
    if (inp) { inp.value = name; inp.defaultValue = name; }
  }
  function heroBits(h) {
    return '<span>' + esc(h.label) + '</span><b>' + esc(nice(h.value)) + '</b>' + (h.src || []).map(c => '<span class="sc">' + esc(c.label) + (c.date ? ' · ' + esc(fdate(c.date)) : '') + '</span>').join('');
  }
  const chips = (src) => '<div class="scs">' + (src || []).map(s => { const u = safeUrl(s.url); const t = esc(s.label) + (s.date ? ' · ' + esc(fdate(s.date)) : '') + ' ↗';
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
    const y = shownYear(f);
    const head = f.case ? '<b>' + esc(f.case) + '</b>' + (y ? ' · ' + esc(y) : '') + '<br>' : '';
    const u = safeUrl(f.url), st = caseStatus(f);
    const src = (u ? '<a href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(f.label || COPY.source) + ' ↗</a>' : esc(f.label || '')) + (f.date ? ' · ' + COPY.retrieved + esc(fdate(f.date)) : '');
    const p = st === 'active' ? '<span class="cs cs-act">Active</span>' : st === 'closed' ? '<span class="cs cs-cl">Closed</span>' : '';
    return '<div class="fct' + (st === 'active' ? ' act' : '') + '">' + p + (f.needs_proof ? '<span class="np">Needs proof</span>' : '') + head + esc(who) + esc(f.text) + '<div class="src">' + src + '</div></div>';
  }
  function itemHtml(x) {
    const meta = [x.who, shownYear(x), x.status && x.status[0].toUpperCase() + x.status.slice(1)].filter(Boolean).map(esc).join(' · ');
    return '<div class="fct"><b>' + esc(x.title ? nice(x.title) : COPY.table.untitled) + '</b>' + (meta ? ' · ' + meta : '') + (x.note ? '<br>' + esc(nice(x.note)) : '') + '</div>';
  }
  const spill = (st) => st === 'active' ? '<span class="cs cs-act">Active</span>' : st === 'closed' ? '<span class="cs cs-cl">Closed</span>' : '';
  // Unconfirmed same-name hit (firm_page checks[].name_only). The result stays Clear; the list sits in the existing muted line under the check.
  function nameOnlyNotes(r, tag) {
    const lists = Array.isArray(r.name_only) ? r.name_only.filter(Boolean) : [];
    if (!lists.length || (r.state !== 'clear' && r.state !== 'nf') || !COPY.name_only) return '';
    const cls = tag === 'em' ? ' class="srch"' : '';
    return lists.map(list => '<' + tag + cls + '>' + esc(fmt(COPY.name_only, { list })) + '</' + tag + '>').join('');
  }
  // /full/ keeps the 906d82a design: the old 10-checks list with evidence rows (the checks table is only on /vc/<slug>/)
  function checkRows(P) {
    const det = {}, out = {}; (P.details || []).forEach(r => det[r.row] = r.facts || []); (P.outline || []).forEach(r => out[r.row] = r.items || []);
    return '<div class="list">' + P.checks.map(r => {
      const cnt = r.count ? '<span class="cnt ' + (r.state === 'clear' ? 'cg' : 'ca') + '">' + esc(r.count) + '</span>' : '';
      const gl = P.open ? '' : (out[r.n] || []).map((e, i) => '<button type="button" class="gc' + (e.status === 'active' ? ' act' : '') + '" data-sec="checks" data-kind="' + esc(e.kind) + '" data-year="' + esc(shownYear(e)) + '">'
        + '<span class="y">' + esc(shownYear(e) || '—') + '</span><span class="k">' + esc(e.kind) + '</span><span class="bl"><span class="bar" style="width:' + (20 + ((e.kind || '').length * 7 + i * 13) % 45) + '%"></span><span class="bar" style="width:22%"></span></span>'
        + spill(e.status) + '<span class="lkk">' + COPY.locked + '</span></button>').join('');
      const rank = (f) => caseStatus(f) === 'active' ? 0 : 1;
      const fs = (det[r.n] || []).map((f, i) => [f, i]).sort((a, b) => rank(a[0]) - rank(b[0]) || a[1] - b[1]).map(x => x[0]);
      // The row's count ('4 records') comes from the check's itemized findings (firm_page checks[].items, also used on the
      // summary page). With no firm_details facts for the row, show those findings, so the expansion never says
      // 'No sourced facts' under a count; when fewer rows than the count are shown, say how many are itemized.
      const its = (Array.isArray(r.items) ? r.items : []).filter(x => x.title || x.note || x.who), n = cnum(r.count);
      const useIts = !fs.length && its.length > 0, shown = useIts ? its.length : fs.length;
      const part = n > shown && shown ? '<div class="fct">' + esc(fmt(COPY.table.partial, { n, count: r.count, m: shown })) + '</div>' : '';
      const d = P.open ? (useIts ? part + its.map(itemHtml).join('') : fs.length ? part + fs.map(factHtml).join('') : '<div class="fct">' + COPY.no_facts + '</div>') : '';
      return '<div class="row' + (r.n === 10 ? ' last' : '') + (P.open ? ' tog' : '') + '" id="check-' + r.n + '"><span class="n">' + String(r.n).padStart(2, '0') + '</span><div class="tx"><b>' + esc(r.title) + '</b><span>' + esc(r.descr) + '</span>' + nameOnlyNotes(r, 'em') + '</div>'
        + '<div class="pc">' + pill(r.state) + cnt + '</div><span class="lk"></span><div class="gl">' + gl + '</div><div class="det">' + d + '</div></div>';
    }).join('') + '</div>';
  }

  // Open-state renderers, keyed by copy.json sections[].renderer
  const R = {
    facts: (it) => '<div class="kvs">' + it.map(x => '<div class="kv"><span class="k">' + esc(x.label) + '</span><span>' + esc(nice(x.value)) + chips(x.src) + '</span></div>').join('') + '</div>',
    checks: (it, P) => checkRows(P),
    legal: (it) => group(it, 'grp', COPY.legal, xs => xs.filter(x => x.title || x.head || x.note).map(x => '<div class="it' + (x.state === 'Active' ? ' act' : '') + '">'
      + (x.state ? '<span class="cs ' + COPY.state[x.state] + '">' + esc(x.state) + '</span> ' : '') + (x.status ? '<span class="pill ' + (COPY.tone[x.tone] || 'p-g') + '"><i></i>' + esc(x.status) + '</span> ' : '')
      + (x.role ? '<span class="cs cs-cl">' + esc(x.role) + '</span> ' : '') + '<b>' + esc(nice(x.title || x.head || '')) + (shownYear(x) ? ' · ' + esc(shownYear(x)) : '') + '</b>' + (x.note ? ' · ' + esc(nice(x.note)) : '') + chips(x.src) + '</div>').join('')),
    press: (it) => '<div class="pgr">' + it.map(x => card(x, true)).join('') + '</div>',
    founders: (it) => '<div class="pgr">' + it.map(x => card(x, false)).join('') + '</div>',
    people: (it) => group(it, 'kind', COPY.people, xs => '<div class="pcards">' + xs.map(x => '<div class="pcard"><b>' + esc(nice(x.head)) + '</b>' + (x.badge ? '<span class="cs cs-act">' + esc(x.badge) + '</span>' : '') + '<span>' + esc(x.role) + '</span>' + chips(x.src) + '</div>').join('') + '</div>'),
    timeline: (it) => {
      const rows = it.map((x, i) => ({ x, i })).sort((a, b) => {
        const sa = window.RegretDate ? window.RegretDate.stamp(a.x.date) : null, sb = window.RegretDate ? window.RegretDate.stamp(b.x.date) : null;
        if (sa == null && sb == null) return a.i - b.i;
        if (sa == null) return 1;
        if (sb == null) return -1;
        return sb - sa || a.i - b.i;
      });
      return '<div class="tls">' + rows.map(({ x }) => '<div class="tl"><span class="tld">' + esc(fdate(x.date) || x.date || '') + '</span><span><span class="cs cs-cl">' + esc(x.kind) + '</span> ' + esc(nice(x.body)) + chips(x.src) + '</span></div>').join('') + '</div>';
    },
  };
  function card(x, logo) {
    const u = safeUrl(x.url), host = u ? new URL(u).hostname.replace(/^www\./, '') : '';
    const fav = logo && x.logo ? '<img class="fav" src="' + esc(ROOT + x.logo) + '" alt="" width="20" height="20">' : '<span class="fav lb">' + esc((x.outlet || '?')[0]) + '</span>';
    return '<div class="pi"><div class="pio">' + fav + '<span>' + esc(x.outlet) + (host && String(x.outlet || '').split(' · ')[0].trim().toLowerCase().replace(/^www\./, '') !== host ? ' · ' + esc(host) : '') + (x.date ? ' · ' + esc(fdate(x.date)) : '') + '</span></div>'
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
  // Locked page (blur A): firm_page() returns only the check names, so the results area is a generic placeholder in the same
  // layout, blurred, with one "Check with 1 credit" card on top (js/app.js [data-gate]). Nothing in the placeholder is real data.
  const GT = COPY.gate, gbar = (w) => '<i class="gb" style="width:' + w + '%"></i>';
  function ghost(P) {
    const rows = (P.checks && P.checks.length ? P.checks : Array.from({ length: 10 }, (_, i) => ({ n: i + 1, title: '', descr: '' }))).map((r, i) =>
      '<tr class="crow"><td class="kcn">' + String(r.n).padStart(2, '0') + '</td><td class="kct"><b>' + esc(r.title) + '</b><span>' + esc(r.descr) + '</span></td>'
      + '<td class="kcr"><span class="pill gp"></span></td><td class="kcf">' + gbar(40 + (i * 37) % 50) + '</td><td class="kcd">' + gbar(70) + '</td></tr>').join('');
    return '<table class="ctab"><thead><tr><th>#</th><th>' + esc(T.h_check) + '</th><th>' + esc(T.h_result) + '</th><th>' + esc(T.h_found) + '</th><th>' + esc(T.h_date) + '</th></tr></thead><tbody>' + rows + '</tbody></table>';
  }
  const ghostSecs = () => [0, 1, 2].map(k => '<section class="ps"><h2>' + gbar(30 + k * 10) + '</h2>' + [0, 1, 2, 3].map(j => '<div class="fct">' + gbar(90 - ((j + k) * 13) % 40) + gbar(55) + '</div>').join('') + '</section>').join('');
  const gate = (P, inner) => '<div class="gate"><div class="gveil" aria-hidden="true" inert>' + inner + '</div><div class="gcard" role="region" aria-label="' + esc(GT.title) + '"><b>' + esc(GT.title) + '</b><p>'
    + esc(fmt(GT.sub, { firm: P.firm.name })) + '</p><button type="button" class="btn" data-gate>' + esc(GT.button) + '</button><p class="gmsg" role="status"></p></div></div>';
  function render(main, P) {
    const firm = P.firm.name, byKey = Object.fromEntries(P.sections.map(s => [s.key, s])),
      secs = CFG.sections.list.filter(c => byKey[c.key]).map(c => Object.assign({}, byKey[c.key], c)), total = secs.filter(s => s.key !== 'checks').reduce((a, s) => a + s.count, 0);
    setFirmName(main, firm);
    main.classList.toggle('unlocked', P.open);
    main.querySelector('.toc').style.display = ''; const lk = main.querySelector('#lockcard'); if (lk) lk.style.display = '';
    const cards = headerCards(P);
    if (!P.open) {
      main.querySelector('.m').innerHTML = metaLine(P);
      main.querySelector('.hfs').innerHTML = cards.map(h => '<span class="hf">' + heroBits(h) + '</span>').join('');
      main.querySelector('.csum').hidden = true; main.querySelector('.spl').innerHTML = ''; main.querySelector('.toc').innerHTML = ''; main.querySelector('.toc').style.display = 'none';
      main.querySelector('#lockcard').hidden = true; main.querySelector('#lockcard').style.display = 'none';
      researchBan(main, false);
      // 'Not checked yet' page (no research yet): the 10 checks as 'Not checked yet' and the same card (it leads to the request-a-check form)
      main.querySelector('.pmain').innerHTML = P.unchecked ? '<section class="ps">' + ctable(P, false, 0) + '</section>' + gate(P, '') : gate(P, '<section class="ps">' + ghost(P) + '</section>' + ghostSecs());
      return { total: 0, head: () => GT.title };
    }
    main.querySelector('.m').innerHTML = metaLine(P);
    const has = new Set(secs.map(s => s.key));
    main.querySelector('.hfs').innerHTML = cards.map(h => {
      const inner = heroBits(h);
      return h.anchor && has.has(h.anchor) ? '<a class="hf" href="#' + esc(h.anchor) + '">' + inner + '</a>' : '<span class="hf">' + inner + '</span>';
    }).join('');
    main.querySelector('.csum').innerHTML = has.has('checks') ? '<div class="csh"><b>' + COPY.summary + '</b><a href="#checks">' + COPY.full_check + '</a></div><div class="cks">'
      + P.checks.map(r => '<a class="ck" href="#checks"><span class="ckn">' + String(r.n).padStart(2, '0') + '</span>' + esc(r.title) + pill(r.state) + '</a>').join('') + '</div>' : '';
    main.querySelector('.csum').hidden = !has.has('checks');
    const fn = main.querySelector('.rgt-n'); if (fn && total) { fn.textContent = total; fn.hidden = false; }
    main.querySelector('.spl').innerHTML = secs.map(s => '<a class="spp" href="#' + esc(s.key) + '">' + esc(s.title) + ' <em>' + s.count + '</em></a>').join('');
    main.querySelector('.toc').innerHTML = '<b>' + COPY.toc + '</b>' + secs.map(s => '<a href="#' + esc(s.key) + '">' + esc(s.title) + '</a>').join('');
    main.querySelector('.pmain').innerHTML = secs.map(s => '<section id="' + esc(s.key) + '" class="ps"><h2>' + esc(s.title) + ' <em class="pc2">' + esc(label(s)) + '</em></h2><p class="psub">' + esc(s.subtitle || '') + '</p>'
      + (P.open || s.key === 'checks' ? (R[s.renderer] || R.facts)(s.items || [], P) : lockedBody(s)) + '</section>').join('');
    spy(main);
    const lc = main.querySelector('#lockcard'); lc.hidden = P.open;
    lc.querySelector('b').textContent = fmt(COPY.lockcard, { n: total, firm }); lc.querySelector('p').textContent = COPY.lockcard_sub;
    const pu = document.getElementById('puse'); if (pu) pu.textContent = fmt(COPY.use_line, { n: total, firm });
    const od = P.ondemand;
    researchBan(main, !!(od && od.mine && (od.status === 'queued' || od.status === 'in_progress')));
    main.querySelectorAll('.row.tog').forEach(row => row.onclick = (e) => { if (!e.target.closest('a')) row.classList.toggle('open'); });
    return { total, head: (key) => { const s = secs.find(x => x.key === key); return s ? fmt(COPY.pay_head, { title: s.title, firm, count: label(s) }) : fmt(COPY.pay_all, { n: total, firm }); } };
  }

  // Summary page (/vc/<slug>/): name, key-fact chips, the 10 checks (closed), then "See the full check".
  // Dropdowns show info only (status pill + case or summary text, no sources); a row with nothing to show has no dropdown.
  function sumItem(f) {
    const who = f.who && f.who.startsWith('partner:') ? f.who.slice(8) + ' · ' : '';
    const y = shownYear(f);
    const head = f.case ? '<b>' + esc(f.case) + '</b>' + (y ? ' · ' + esc(y) : '') + '<br>' : '';
    const st = caseStatus(f);
    if (!f.case && !f.text && !f.needs_proof && !st) return ''; // nothing to show for this fact
    return '<div class="fct' + (st === 'active' ? ' act' : '') + '">' + spill(st) + (f.needs_proof ? '<span class="np">Needs proof</span>' : '') + head + esc(who) + esc(f.text) + '</div>';
  }
  // Signed-out outline: a bare method label (no status, no year) tells the viewer nothing, so it is not shown.
  const outItem = (e) => { const y = shownYear(e); return !e.status && !y ? '' : '<div class="fct' + (e.status === 'active' ? ' act' : '') + '">' + spill(e.status) + '<b>' + esc(e.kind) + '</b>' + (y ? ' · ' + esc(y) : '') + '</div>'; };
  // Rows with no dropdown: one muted line saying what was searched. "Nothing found" only when the row really is clear / none found; Not checked yet rows get no line (the pill says it).
  const srch = (r) => { const S = COPY.searched || {}, st = PILL[r.state] ? r.state : 'nc';
    const t = st === 'nc' ? '' : S[r.n] ? S[r.n] + (st === 'clear' || st === 'nf' ? ' ' + COPY.searched_nf : '') : '';
    return t ? '<em class="srch">' + esc(t) + '</em>' : ''; };
  // Checking view: only while firm_page / firm_check_status report queue = 'claimed'. An expired normal claim
  // (older than 6 hours, no open paid or request job) is reported as queued, so it does not show Checking.
  // Otherwise not-done rows read "Not checked yet"
  // (no spinner, no Started time). Done rows (state != 'nc' in the data) show their real pill,
  // the first not-done row shows the spinner, the rest "Waiting". No results are invented. js/app.js polls and re-renders.
  // The date this check was searched (firm_check_rows.searched_at), shown next to every check that has one.
  const sdt = (r) => { const d = window.RegretDate && r.searched_at ? window.RegretDate.format(r.searched_at) : '';
    return d ? '<em class="sdt">' + esc(fmt(COPY.searched_on, { date: d })) + '</em>' : ''; };
  const CK = COPY.checking;
  // Same banner the summary page uses after a credit buys research. /full/ shows it too (the confirmation).
  function researchBan(main, on) {
    const b = main.querySelector('.cban'); if (!b) return;
    b.className = 'cban'; b.hidden = !on;
    b.innerHTML = on ? '<div class="ch"><b>' + esc(CK.research) + '</b><span>' + esc(CK.research_sub) + '</span></div>' : '';
  }
  const doneN = (P) => !P.open && P.done != null ? P.done : (P.checks || []).filter(r => r.state !== 'nc').length;
  // Pacific time, same shape as every other dated line: "Started Mar 15, 2024, 3:58 PM PT".
  function startedLine(t) {
    if (!t || isNaN(t) || !window.RegretDate) return '';
    const when = window.RegretDate.formatWhen(t);
    if (!when) return '';
    return '<div class="cs2">' + esc(fmt(CK.started, { when })) + '</div>';
  }
  function checkingHead(main, P, st) {
    const done = doneN(P), cur = (P.checks || []).find(r => r.state === 'nc'), firm = P.firm.name;
    main.querySelector('.fh h1').innerHTML = esc(fmt(CK.title, { firm })) + '<span class="dots">…</span>';
    const s0 = st && st.started_at !== undefined ? st.started_at : P.started_at, t = s0 ? new Date(s0) : null;
    const b = main.querySelector('.cban'); b.className = 'cban'; b.hidden = false;
    b.innerHTML = '<div class="ch"><b>' + esc(fmt(CK.progress, { done, check: cur ? cur.title : '' })) + '</b><span>' + esc(CK.usually) + '</span></div>'
      + '<div class="cbar" role="progressbar" aria-valuemin="0" aria-valuemax="10" aria-valuenow="' + done + '"><i style="width:' + Math.max(done * 10, 4) + '%"></i></div>'
      + startedLine(t);
  }
  function summary(main, P, st) {
    const queue = st && st.queue !== undefined ? st.queue : P.queue;
    const pending = !!(P.checks && P.checks.length) && doneN(P) < 10, checking = pending && queue === 'claimed', justDone = !checking && !!(st && st.just_done);
    // On-demand research this visitor paid for (firm_page ondemand.mine): 'Research in progress' until a bot holds the claim.
    const od = P.ondemand, research = !checking && !!(od && od.mine && (od.status === 'queued' || od.status === 'in_progress'));
    main.classList.toggle('checking', checking);
    setFirmName(main, P.firm.name);
    main.querySelector('.cside').hidden = !(checking || research);
    if (research) { const ep = main.querySelector('[data-notify] p'); if (ep) ep.textContent = CK.research_email; }
    if (checking) checkingHead(main, P, st);
    else if (research) {
      main.querySelector('.fh h1').textContent = P.firm.name;
      researchBan(main, true);
    } else {
      main.querySelector('.fh h1').textContent = P.firm.name;
      const b = main.querySelector('.cban'); b.hidden = !justDone; b.className = 'cban ok';
      b.innerHTML = justDone ? '<div class="ch"><div><b>' + esc(CK.complete) + '</b> <span>' + esc(CK.complete_sub) + '</span></div></div>' : '';
    }
    const curN = checking && P.open ? P.checks.find(r => r.state === 'nc').n : 0;
    const link = siteLink(P);
    if (checking && !(P.hero && P.hero.length)) main.querySelector('.kf').innerHTML = '<span>' + esc(CK.sources[0]) + ' <b>' + esc(CK.sources[1]) + '</b></span>' + (link ? '<span>' + link + '</span>' : '');
    else main.querySelector('.kf').innerHTML = headerCards(P).map(h => '<span>' + esc(h.label) + ' <b>' + esc(nice(h.value)) + '</b>' + (h.src || []).slice(0, 1).map(c => ' <i>· ' + esc(c.label) + (c.date ? ' · ' + esc(fdate(c.date)) : '') + '</i>').join('') + '</span>').join('') + (link ? '<span>' + link + '</span>' : '');
    main.querySelector('.list').innerHTML = P.open ? ctable(P, checking, curN) : P.unchecked ? ctable(P, false, 0) + gate(P, '') : gate(P, ghost(P));
    const fn = main.querySelector('.rgt-n'), ft = (P.sections || []).filter(s => s.key !== 'checks').reduce((a, s) => a + (s.count || 0), 0);
    if (fn && ft) { fn.textContent = ft; fn.hidden = false; }
    bindTable(main);
    return { total: 0, head: () => '', checking, research, pending, queue };
  }

  // Checks table (approved layout 3): #, check, result pill, what was found, date searched. A row with something to show
  // opens a details row underneath: the itemized findings (firm_page checks[].items: only on an unlocked page) and what was
  // searched. Everything shown comes from the data; when the count is higher than the itemized rows the table says so.
  // Pills are only Clear / Review / Worth knowing / Not checked yet; while a bot holds the claim, not-done rows read
  // "Checking…" (the first) and "Waiting".
  const T = COPY.table;
  const tpill = (st) => pill(st === 'red' ? 'review' : st);
  const cnum = (c) => { const m = /^(\d+)\s/.exec(c || ''); return m ? +m[1] : 0; };
  const sdate = (r) => window.RegretDate && r.searched_at ? window.RegretDate.format(r.searched_at) : '';
  function ctable(P, checking, curN) {
    const rows = (P.checks || []).map(r => {
      const nc = r.state === 'nc' || !PILL[r.state], fnd = !nc && r.state !== 'clear' && r.state !== 'nf';
      const items = Array.isArray(r.items) ? r.items : null, n = cnum(r.count), it = r.itemized || 0;
      const res = !nc ? tpill(r.state) : !checking ? pill('nc') : r.n === curN ? '<span class="pill p-cur"><span class="sp" aria-hidden="true"></span>' + esc(CK.current) + '</span>' : '<span class="wt">' + esc(CK.waiting) + '</span>';
      let found = '';
      if (fnd) found = '<b>' + esc(!r.count ? T.found_some : /^\d+ (case|record)s?$/.test(r.count) ? fmt(T.found, { count: r.count }) : r.count) + '</b>'
        + (items && items.length ? '<span class="cts">' + items.slice(0, 2).map(x => esc(nice(x.title || ''))).filter(Boolean).join(', ') + (items.length > 2 ? ' ' + esc(fmt(T.more, { n: items.length - 2 })) : '') + '</span>' : '');
      else if (!nc) found = '<b>' + esc(T.nothing) + '</b>';
      else found = '<span class="ctm">—</span>';
      const S = (COPY.searched || {})[r.n] || '';
      let d = '';
      if (!nc) {
        if (fnd && n > it) d += '<p class="ctn">' + esc(it ? fmt(T.partial, { n, count: r.count, m: it }) : T.none_itemized) + '</p>';
        if (fnd && items) d += items.filter(x => x.title || x.note || x.who).map(x => { const y = shownYear(x); const meta = [x.who, y, x.status && x.status[0].toUpperCase() + x.status.slice(1)].filter(Boolean).map(esc).join(' · ');
          return '<div class="cti"><b>' + esc(x.title ? nice(x.title) : T.untitled) + '</b>' + (meta ? '<span class="ctmeta">' + meta + '</span>' : '') + (x.note ? '<p>' + esc(nice(x.note)) + '</p>' : '') + '</div>'; }).join('');
        else if (fnd && it) d += '<button type="button" class="ctl" data-sec="checks">' + esc(fmt(T.locked, { m: it })) + ' <span>' + COPY.locked + '</span></button>';
        d += '<p class="ctw"><b>' + esc(T.what) + '</b> ' + esc(S) + (sdate(r) ? ' · ' + esc(fmt(COPY.searched_on, { date: sdate(r) })) : '') + (r.state === 'clear' || r.state === 'nf' ? ' · ' + esc(COPY.searched_nf) : '') + '</p>';
      }
      const tog = !!d && !checking;
      return '<tr class="crow' + (tog ? ' tog' : '') + (nc ? (checking && r.n === curN ? ' cur' : ' up') : '') + '" id="check-' + r.n + '"' + (tog ? ' tabindex="0" aria-expanded="false" aria-controls="cdx-' + r.n + '"' : '') + '>'
        + '<td class="kcn">' + String(r.n).padStart(2, '0') + '</td><td class="kct"><b>' + esc(r.title) + '</b><span>' + esc(r.descr) + '</span>' + nameOnlyNotes(r, 'span') + '</td>'
        + '<td class="kcr">' + res + '</td><td class="kcf">' + found + '</td><td class="kcd">' + (sdate(r) ? esc(sdate(r)) : '<span class="ctm">—</span>') + '</td></tr>'
        + (tog ? '<tr class="cdx" id="cdx-' + r.n + '" hidden><td></td><td colspan="4">' + d + '</td></tr>' : '');
    }).join('');
    return '<table class="ctab"><thead><tr><th>#</th><th>' + esc(T.h_check) + '</th><th>' + esc(T.h_result) + '</th><th>' + esc(T.h_found) + '</th><th>' + esc(T.h_date) + '</th></tr></thead><tbody>' + rows + '</tbody></table>';
  }
  function bindTable(main) {
    main.querySelectorAll('tr.crow.tog').forEach(tr => {
      const dx = tr.nextElementSibling;
      const t = (e) => { if (e && e.target.closest('a,button')) return; const o = tr.classList.toggle('open'); dx.hidden = !o; tr.setAttribute('aria-expanded', o); };
      tr.onclick = t; tr.onkeydown = (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); t(); } };
    });
  }
  window.RegretCompany = { render, summary };
})();
