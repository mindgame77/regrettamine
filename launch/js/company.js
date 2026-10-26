/* Company page (/vc/<slug>/): section data (count, teaser, items) comes from firm_page(); which sections show,
   their order, titles, subtitles, unit labels and renderer come from copy.json "sections". Exposes window.RegretCompany. */
(function () {
  const CFG = window.REGRET.copy, COPY = CFG.company, PILL = CFG.site.pills;
  const fmt = (t, o) => String(t == null ? '' : t).replace(/\{(\w+)\}/g, (_, k) => o[k]);
  const pl = (pair, n) => fmt(Array.isArray(pair) ? pair[n === 1 ? 0 : 1] : pair, { n });
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
  // One label for the SEC assets figure. Stored cards still say Assets, Regulatory AUM, or AUM.
  const assetLabel = (label) => (label === 'Assets' || label === 'Regulatory AUM' || label === 'AUM') && COPY.header && COPY.header.assets ? COPY.header.assets : label;
  function headerCards(P) {
    const hero = (Array.isArray(P.hero) ? P.hero : []).filter(h => h && (h.label || h.value));
    if (hero.length) return hero.map(h => Object.assign({}, h, { label: assetLabel(h.label), src: h.src || [] }));
    const H = COPY.header || {};
    const firm = P.firm || {};
    return [
      { label: H.hq || 'HQ', value: firm.hq || MISS, anchor: '', src: [] },
      { label: H.assets, value: firm.assets || MISS, anchor: '', src: [] },
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
  // A person card's name is a short fact about one person. Bot research notes (ADV Schedule A summaries, "Bot people records",
  // Form D related-person lists, anything with a URL or over 300 characters) are hidden in the DB; never draw one as a card either.
  const isNoteText = (t) => { t = String(t || ''); return t.length > 300 || /schedule a individuals|bot people records|related persons|https?:\/\/|www\./i.test(t); };
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
    const meta = caseMeta(x);
    return '<div class="fct"><b>' + esc(x.title ? nice(x.title) : COPY.table.untitled) + '</b>' + (meta ? ' · ' + meta : '') + (x.note ? '<br>' + esc(nice(x.note)) : '') + sourceHtml(x, false) + '</div>';
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
    facts: (it) => '<div class="kvs">' + it.map(x => '<div class="kv"><span class="k">' + esc(assetLabel(x.label)) + '</span><span>' + esc(nice(x.value)) + chips(x.src) + '</span></div>').join('') + '</div>',
    checks: (it, P) => checkRows(P),
    legal: (it) => group(it, 'grp', COPY.legal, xs => xs.filter(x => x.title || x.head || x.note).map(x => '<div class="it' + (x.state === 'Active' ? ' act' : '') + '">'
      + (x.state ? '<span class="cs ' + COPY.state[x.state] + '">' + esc(x.state) + '</span> ' : '') + (x.status ? '<span class="pill ' + (COPY.tone[x.tone] || 'p-g') + '"><i></i>' + esc(x.status) + '</span> ' : '')
      + (x.role ? '<span class="cs cs-cl">' + esc(x.role) + '</span> ' : '') + '<b>' + esc(nice(x.title || x.head || '')) + (shownYear(x) ? ' · ' + esc(shownYear(x)) : '') + '</b>' + (x.note ? ' · ' + esc(nice(x.note)) : '') + chips(x.src) + '</div>').join('')),
    press: (it) => '<div class="pgr">' + it.map(x => card(x, true)).join('') + '</div>',
    founders: (it) => '<div class="pgr">' + it.map(x => card(x, false)).join('') + '</div>',
    people: (it) => group(it.filter(x => !isNoteText(x.head)), 'kind', COPY.people, xs => '<div class="pcards">' + xs.map(x => '<div class="pcard"><b>' + esc(nice(x.head)) + '</b>' + (x.badge ? '<span class="cs cs-act">' + esc(x.badge) + '</span>' : '') + '<span>' + esc(x.role) + '</span>' + chips(x.src) + '</div>').join('') + '</div>'),
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
    if (!P.open) {
      main.querySelector('.m').innerHTML = metaLine(P) + secPills(P);
      paintActivity(main, P);
      main.querySelector('.csum').hidden = true; main.querySelector('.spl').innerHTML = ''; main.querySelector('.toc').innerHTML = ''; main.querySelector('.toc').style.display = 'none';
      main.querySelector('#lockcard').hidden = true; main.querySelector('#lockcard').style.display = 'none';
      researchBan(main, false);
      // 'Not checked yet' page (no research yet): the 10 checks as 'Not checked yet' and the same card (it leads to the request-a-check form)
      main.querySelector('.pmain').innerHTML = P.unchecked ? '<section class="ps">' + ctable(P, false, 0) + '</section>' + gate(P, '') : gate(P, '<section class="ps">' + ghost(P) + '</section>' + ghostSecs());
      return { total: 0, head: () => GT.title };
    }
    main.querySelector('.m').innerHTML = metaLine(P) + secPills(P);
    const has = new Set(secs.map(s => s.key));
    paintActivity(main, P);
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
    else main.querySelector('.kf').innerHTML = '<p class="m">' + metaLine(P) + secPills(P) + '</p>';
    paintActivity(main, P);
    main.querySelector('.list').innerHTML = P.open ? ctable(P, checking, curN) : P.unchecked ? ctable(P, false, 0) + gate(P, '') : gate(P, ghost(P));
    const fn = main.querySelector('.rgt-n'), ft = (P.sections || []).filter(s => s.key !== 'checks').reduce((a, s) => a + (s.count || 0), 0);
    if (fn && ft) { fn.textContent = ft; fn.hidden = false; }
    bindTable(main);
    return { total: 0, head: () => '', checking, research, pending, queue };
  }

  // Checks table (approved layout 3): #, check, result pill, what was found, date searched. A row with something to show
  // opens a details row underneath: the itemized findings (firm_page checks[].items: only on an unlocked page) and what was
  // searched. A Review row with no submission findings lists the firm's saved active cases and open regulator actions.
  // A count with nothing itemized says details are coming and links a court search for the legal name.
  // Pills are only Clear / Review / Worth knowing / Not checked yet; while a bot holds the claim, not-done rows read
  // "Checking…" (the first) and "Waiting".
  const T = COPY.table;
  function caseMeta(x) {
    const y = shownYear(x);
    const st = x.status ? x.status[0].toUpperCase() + x.status.slice(1) : '';
    return [x.who, x.court, y, st].filter(Boolean).map(esc).join(' · ');
  }
  function sourceText(x) {
    const u = safeUrl(x.url);
    if (!u) return '';
    if (/courtlistener\.com/i.test(u)) return T.docket;
    return x.src || '';
  }
  function sourceHtml(x, para) {
    const u = safeUrl(x.url), label = sourceText(x);
    if (!u || !label) return '';
    const a = '<a href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(label) + ' ↗</a>';
    return para ? '<p>' + esc(T.source) + ' ' + a + '</p>' : '<div class="src">' + esc(T.source) + ' ' + a + '</div>';
  }
  function courtSearch(P) {
    const name = (P.firm && (P.firm.sec_name || P.firm.name)) || '';
    return 'https://www.courtlistener.com/?q=' + encodeURIComponent(name);
  }
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
        const shown = items ? items.filter(x => x.title || x.note || x.who) : [];
        if (fnd && n > it && it) d += '<p class="ctn">' + esc(fmt(T.partial, { n, count: r.count, m: it })) + '</p>';
        if (fnd && n > it && !it) d += '<p class="ctn">' + esc(pl(T.coming, n)) + ' <a href="' + esc(courtSearch(P)) + '" target="_blank" rel="noopener">' + esc(T.search_courts) + '</a></p>';
        if (fnd && shown.length && /active cases?/i.test(r.count || '')) d += '<p class="ctn"><b>' + esc(pl(T.active_h, shown.length)) + '</b></p>';
        if (fnd && shown.length) d += shown.map(x => { const meta = caseMeta(x);
          return '<div class="cti"><b>' + esc(x.title ? nice(x.title) : T.untitled) + '</b>' + (meta ? '<span class="ctmeta">' + meta + '</span>' : '') + (x.note ? '<p>' + esc(nice(x.note)) + '</p>' : '') + sourceHtml(x, true) + '</div>'; }).join('');
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
  // Activity (firm_page activity): tiles, the latest deal, the latest founder review. Signed out or locked, "Show all"
  // is a [data-gate] button (js/app.js openPay('')). After a credit it opens a popup with the full list (activity.deals / .reviews).
  const AC = COPY.activity || {};
  const money = (v) => { const n = Number(v); if (!isFinite(n) || n <= 0) return '';
    const u = [[1e9, 'B'], [1e6, 'M'], [1e3, 'K']].find(x => n >= x[0]);
    return u ? '$' + String(+(n / u[0]).toFixed(n / u[0] >= 100 ? 0 : 2)) + u[1] : '$' + n; };
  const hostOf = (u) => { try { return new URL(u).hostname.replace(/^www\./, ''); } catch (e) { return ''; } };
  const roundName = (r) => String(r || '').replace(/^stage tag:\s*/i, '');
  const fundName = (n) => String(n || '').replace(/,?\s*L\.?\s?P\.?$/i, '').trim();
  // SEC facts from the hero list, as linked pills (not cards). HQ is the plain city text in the meta line.
  function secPills(P) {
    const hero = (Array.isArray(P.hero) ? P.hero : []).filter(h => h && h.value && h.label !== 'HQ');
    return hero.map(h => { const src = (h.src || []).find(c => /(^|\.)sec\.gov\//i.test((safeUrl(c.url) || '').replace(/^https?:\/\//i, '').replace(/\/.*/, '/')));
      if (!src) return '';
      const lab = assetLabel(h.label), v = nice(h.value), parts = String(v).split(' · ');
      const t = /^(Assets|Regulatory AUM|AUM)$/.test(h.label) ? v + ' ' + lab.toLowerCase() : parts[0] + ' ' + lab.toLowerCase() + (parts.length > 1 ? ' · ' + parts.slice(1).join(' · ') : '');
      return '<a class="sc" href="' + esc(src.url) + '" target="_blank" rel="noopener">' + esc(t) + '</a>'; }).filter(Boolean).slice(0, 7).join('').replace(/^(.+)$/, '<span class="secp">$1</span>');
  }
  const tile = (lab, big, sub, cls) => '<div class="att ' + cls + '"><small>' + esc(lab) + '</small><b>' + big + '</b><span>' + sub + '</span></div>';
  function dealRows(ds) {
    return '<div class="adl"><div class="ad adh"><span>' + esc(AC.h_company) + '</span><span>' + esc(AC.h_round) + '</span><span>' + esc(AC.h_date) + '</span><span>' + esc(AC.h_source) + '</span></div>'
      + ds.map(d => { const u = safeUrl(d.url);
        return '<div class="ad"><b>' + esc(d.company || '') + '</b><span>' + esc(roundName(d.round)) + '</span><span>' + esc(fdate(d.date) || '') + '</span>'
          + (u ? '<a href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(hostOf(u)) + ' ↗</a>' : '<span></span>') + '</div>'; }).join('') + '</div>';
  }
  // "What people say": source icon (inline SVG, Simple Icons 16.36 / LinkedIn mark from Simple Icons 10.4, CC0;
  // no image files, no hotlinking) or a letter badge, plus an outlined type pill from the review's stored type.
  const SRC_ICONS = {
    x: ['000000', 'M14.234 10.162 22.977 0h-2.072l-7.591 8.824L7.251 0H.258l9.168 13.343L.258 24H2.33l8.016-9.318L16.749 24h6.993zm-2.837 3.299-.929-1.329L3.076 1.56h3.182l5.965 8.532.929 1.329 7.754 11.09h-3.182z'],
    reddit: ['FF4500', 'M12 0C5.373 0 0 5.373 0 12c0 3.314 1.343 6.314 3.515 8.485l-2.286 2.286C.775 23.225 1.097 24 1.738 24H12c6.627 0 12-5.373 12-12S18.627 0 12 0Zm4.388 3.199c1.104 0 1.999.895 1.999 1.999 0 1.105-.895 2-1.999 2-.946 0-1.739-.657-1.947-1.539v.002c-1.147.162-2.032 1.15-2.032 2.341v.007c1.776.067 3.4.567 4.686 1.363.473-.363 1.064-.58 1.707-.58 1.547 0 2.802 1.254 2.802 2.802 0 1.117-.655 2.081-1.601 2.531-.088 3.256-3.637 5.876-7.997 5.876-4.361 0-7.905-2.617-7.998-5.87-.954-.447-1.614-1.415-1.614-2.538 0-1.548 1.255-2.802 2.803-2.802.645 0 1.239.218 1.712.585 1.275-.79 2.881-1.291 4.64-1.365v-.01c0-1.663 1.263-3.034 2.88-3.207.188-.911.993-1.595 1.959-1.595Zm-8.085 8.376c-.784 0-1.459.78-1.506 1.797-.047 1.016.64 1.429 1.426 1.429.786 0 1.371-.369 1.418-1.385.047-1.017-.553-1.841-1.338-1.841Zm7.406 0c-.786 0-1.385.824-1.338 1.841.047 1.017.634 1.385 1.418 1.385.785 0 1.473-.413 1.426-1.429-.046-1.017-.721-1.797-1.506-1.797Zm-3.703 4.013c-.974 0-1.907.048-2.77.135-.147.015-.241.168-.183.305.483 1.154 1.622 1.964 2.953 1.964 1.33 0 2.47-.81 2.953-1.964.057-.137-.037-.29-.184-.305-.863-.087-1.795-.135-2.769-.135Z'],
    ycombinator: ['F0652F', 'M0 24V0h24v24H0zM6.951 5.896l4.112 7.708v5.064h1.583v-4.972l4.148-7.799h-1.749l-2.457 4.875c-.372.745-.688 1.434-.688 1.434s-.297-.708-.651-1.434L8.831 5.896h-1.88z'],
    glassdoor: ['00A162', 'M14.1093.0006c-.0749-.0074-.1348.0522-.1348.127v3.451c0 .0673.0537.1194.121.127 2.619.172 4.6092.9501 4.6092 3.6814H13.086a.1343.1343 0 0 0-.1348.1347v8.9644c0 .0748.06.1347.1348.1347h10.0034c.0748 0 .1347-.0599.1347-.1347V7.342c0-2.2374-.7996-4.0558-2.4159-5.3279C19.3191.8469 17.0874.1428 14.1093.0006ZM.9107 7.387a.1342.1342 0 0 0-.1347.1347v8.9566c0 .0748.06.1347.1347.1347h5.6189c0 2.7313-1.9902 3.5094-4.6091 3.6815-.0674.0075-.1192.0596-.1192.127v3.451c0 .0747.06.1343.1348.1269 2.9781-.1422 5.2078-.8463 6.6969-2.0136 1.6163-1.272 2.4159-3.0905 2.4159-5.3278V7.5217a.1343.1343 0 0 0-.1348-.1347z'],
    trustpilot: ['00B67A', 'M17.227 16.67l2.19 6.742-7.413-5.388 5.223-1.354zM24 9.31h-9.165L12.005.589l-2.84 8.723L0 9.3l7.422 5.397-2.84 8.714 7.422-5.388 4.583-3.326L24 9.311z'],
    youtube: ['FF0000', 'M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z'],
    medium: ['000000', 'M4.21 0A4.201 4.201 0 0 0 0 4.21v15.58A4.201 4.201 0 0 0 4.21 24h15.58A4.201 4.201 0 0 0 24 19.79v-1.093c-.137.013-.278.02-.422.02-2.577 0-4.027-2.146-4.09-4.832a7.592 7.592 0 0 1 .022-.708c.093-1.186.475-2.241 1.105-3.022a3.885 3.885 0 0 1 1.395-1.1c.468-.237 1.127-.367 1.664-.367h.023c.101 0 .202.004.303.01V4.211A4.201 4.201 0 0 0 19.79 0Zm.198 5.583h4.165l3.588 8.435 3.59-8.435h3.864v.146l-.019.004c-.705.16-1.063.397-1.063 1.254h-.003l.003 10.274c.06.676.424.885 1.063 1.03l.02.004v.145h-4.923v-.145l.019-.005c.639-.144.994-.353 1.054-1.03V7.267l-4.745 11.15h-.261L6.15 7.569v9.445c0 .857.358 1.094 1.063 1.253l.02.004v.147H4.405v-.147l.019-.004c.705-.16 1.065-.397 1.065-1.253V6.987c0-.857-.358-1.094-1.064-1.254l-.018-.004zm19.25 3.668c-1.086.023-1.733 1.323-1.813 3.124H24V9.298a1.378 1.378 0 0 0-.342-.047Zm-1.862 3.632c-.1 1.756.86 3.239 2.204 3.634v-3.634z'],
    substack: ['FF6719', 'M22.539 8.242H1.46V5.406h21.08v2.836zM1.46 10.812V24L12 18.11 22.54 24V10.812H1.46zM22.54 0H1.46v2.836h21.08V0z'],
    techcrunch: ['029F00', 'M0 6v4h4v8h4v-8h4V6Zm12 4v8h12v-4h-8v-4zm4 0h8V6h-8z'],
    linkedin: ['0A66C2', 'M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z']
  };
  const srcKey = (h) => h === 'x.com' || h === 'twitter.com' || h === 'mobile.twitter.com' ? 'x'
    : /(^|\.)linkedin\.com$/.test(h) ? 'linkedin' : /(^|\.)reddit\.com$/.test(h) ? 'reddit'
    : h === 'news.ycombinator.com' ? 'ycombinator' : /(^|\.)glassdoor\.[a-z.]+$/.test(h) ? 'glassdoor'
    : /(^|\.)trustpilot\.com$/.test(h) ? 'trustpilot' : /(^|\.)(youtube\.com|youtu\.be)$/.test(h) ? 'youtube'
    : /(^|\.)medium\.com$/.test(h) ? 'medium' : /\.substack\.com$/.test(h) || h === 'substack.com' ? 'substack'
    : h === 'techcrunch.com' ? 'techcrunch' : '';
  const BADGE_COLORS = ['#6C4CF1', '#0E9F6E', '#D9480F', '#1C7ED6', '#C2255C', '#5F3DC4', '#2B8A3E', '#E67700'];
  function srcBadge(h) {
    const k = srcKey(h), I = k && SRC_ICONS[k];
    if (I) return '<span class="arsi" title="' + esc(h) + '"><svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true" fill="#' + I[0] + '"><path d="' + I[1] + '"/></svg></span>';
    const name = String(h || '').replace(/^(www|m|blog|news|en)\./, ''), ch = (name.match(/[a-z0-9]/i) || ['?'])[0].toUpperCase();
    let n = 0; for (const c of name) n = (n * 31 + c.charCodeAt(0)) >>> 0;
    return '<span class="arsl" aria-hidden="true" style="background:' + BADGE_COLORS[n % BADGE_COLORS.length] + '">' + esc(ch) + '</span>';
  }
  const TYPE_PILL = { founder: 'tf', employee: 'te', portfolio: 'tp', company: 'tc', firm_voice: 'tv', aggregator: 'ta' };
  const typePill = (t) => { const T = AC.types || {}, k = t || 'founder'; return T[k] ? '<span class="arty ' + (TYPE_PILL[k] || '') + '">' + esc(T[k]) + '</span>' : ''; };
  function revCard(r) {
    const u = safeUrl(r.url), R = AC.ratings || {};
    const who = r.author || (r.role ? '' : AC.anon), meta = [who && r.role && r.role.indexOf(who) === 0 ? r.role.slice(who.length).replace(/^[\s,]+/, '') : r.role, r.company, roundName(r.round)].filter(Boolean).join(' · ');
    const chipsR = Object.keys(R).filter(k => r.ratings && r.ratings[k]).map(k => '<span class="arc"><span>' + esc(R[k]) + '</span><i>' + '●'.repeat(r.ratings[k]) + '<em>' + '●'.repeat(Math.max(0, 5 - r.ratings[k])) + '</em></i></span>').join('');
    return '<div class="arv"><div class="arh">' + srcBadge(hostOf(u)) + (who ? '<b>' + esc(who) + '</b>' : '') + typePill(r.type) + (meta ? '<span>' + esc(meta) + '</span>' : '') + '<span class="ard">' + esc(fdate(r.date) || '') + '</span></div>'
      + '<p>“' + esc(r.body || '') + '”</p><div class="arf">' + chipsR + (u ? '<a href="' + esc(u) + '" target="_blank" rel="noopener"><span>' + esc(AC.source) + '</span> ' + esc(hostOf(u)) + ' ↗</a>' : '') + '</div></div>';
  }
  const showAll = (P, kind, n) => '<button type="button" class="ash"' + (P.open ? ' data-open="act' + kind + '"' : ' data-gate') + '>' + esc(pl(kind === 'deals' ? AC.all_deals : AC.all_reviews, n)) + ' ↓</button>';
  function actModal(id, title, inner, lazy) {
    let ov = document.getElementById(id);
    if (!ov) { ov = document.createElement('div'); ov.className = 'ov tall'; ov.id = id; ov.hidden = true; document.body.appendChild(ov); }
    ov.innerHTML = '<div class="md w amd" role="dialog" aria-modal="true" aria-label="' + esc(title) + '"><div class="amh"><button class="x" data-close aria-label="' + esc(AC.close) + '">×</button><b>' + esc(title) + '</b></div><div class="amb">' + inner + '</div></div>';
    ov._lazy = lazy || null;
  }
  // Fill a lazy "Show all" popup on first open. One request per popup; a failure leaves it to retry on the next open.
  document.addEventListener('click', async (e) => {
    const t = e.target.closest('.ash[data-open^="act"]'), ov = t && document.getElementById(t.dataset.open);
    if (!ov || !ov._lazy || ov._busy || !window.RegretActList) return;
    const L = ov._lazy, box = ov.querySelector('.amb'); ov._busy = true;
    try {
      const d = await window.RegretActList(L.slug, L.kind);
      if (d && d.status === 'ok' && Array.isArray(d.items) && ov._lazy === L) {
        box.innerHTML = L.kind === 'deals' ? dealRows(d.items) : d.items.map(revCard).join(''); ov._lazy = null;
      }
    } finally { ov._busy = false; }
  });
  function activity(P) {
    const A = P.activity, firm = P.firm.name;
    if (!A) return '';
    const n = A.counts || {}, d0 = A.latest_deal, r0 = A.latest_review, f = A.latest_fund, tiles = [];
    if (A.active) {
      const ld = d0 && d0.date ? fmt(AC.last_deal, { date: fdate(d0.date) }) : f && f.date ? fmt(AC.fund_closed, { date: fdate(f.date) }) : '';
      const sub = d0 ? [d0.company, roundName(d0.round)].filter(Boolean).join(', ') : f ? fundName(f.name) : '';
      tiles.push('<div class="att aon"><i></i><div><b>' + esc(AC.active) + '</b><span>' + esc(ld) + '</span><em>' + esc(sub) + '</em></div></div>');
    }
    if (A.deals_12m > 0) tiles.push(tile(AC.deals_12m, esc(A.deals_12m), '', 'amt'));
    if (f) {
      const amt = money(f.raised_usd), u = safeUrl(f.url);
      const sub = esc(fundName(f.name)) + (amt ? ' · ' + esc(fmt(AC.raised, { amount: amt })) : '') + (u ? ' · <a href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(AC.filing) + ' ↗</a>' : '');
      tiles.push(tile(AC.fund, amt ? esc(amt) : '<span class="asm">' + esc(fundName(f.name)) + '</span>', sub, 'afd'));
    }
    if (!tiles.length && !d0 && !r0) return '';
    let h = '<section class="actv" aria-label="' + esc(AC.reviews) + '">' + (tiles.length ? '<div class="ats" style="grid-template-columns:repeat(' + tiles.length + ',1fr)">' + tiles.join('') + '</div>' : '');
    if (d0) h += '<div class="aps"><b class="apt">' + esc(AC.latest_deal) + '</b>' + dealRows([d0]) + (n.deals > 1 ? showAll(P, 'deals', n.deals) : '') + '</div>';
    if (r0) h += '<div class="aps arvs"><h2>' + esc(AC.reviews) + '</h2>' + revCard(r0) + (n.reviews > 1 ? showAll(P, 'revs', n.reviews) : '') + '</div>';
    // firm_page sends only the first slice (A.lazy); the full list loads once when "Show all" opens (firm_activity_list).
    const full = (k, list, n) => !A.lazy && Array.isArray(list) && list.length > 1 ? list : (n > 1 ? null : undefined);
    const fd = full('deals', A.deals, n.deals), fr = full('revs', A.reviews, n.reviews);
    if (P.open && fd !== undefined) actModal('actdeals', fmt(AC.deals_title, { n: fd ? fd.length : n.deals, firm }), fd ? dealRows(fd) : '', !fd && { slug: P.firm.slug, kind: 'deals' });
    if (P.open && fr !== undefined) actModal('actrevs', fmt(AC.reviews_title, { n: fr ? fr.length : n.reviews, firm }), fr ? fr.map(revCard).join('') : '', !fr && { slug: P.firm.slug, kind: 'revs' });
    return h + '</section>';
  }
  function paintActivity(main, P) {
    const box = main.querySelector('.actw'); if (!box) return;
    const h = activity(P); box.innerHTML = h; box.hidden = !h;
  }

  window.RegretCompany = { render, summary };
})();
