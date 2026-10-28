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
    'A16Z': 'a16z', 'YC': 'YC', 'ES20': 'ES20', 'US': 'US', 'USA': 'USA', 'UK': 'UK', 'VC': 'VC', 'AI': 'AI', 'II': 'II', 'III': 'III', 'IV': 'IV', 'VI': 'VI',
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
  const HCOPY = COPY.header || {};
  // Regulatory AUM and Fund gross assets stay two figures. A stored "Assets" / "AUM" label that names
  // gross assets (and not regulatory AUM) reads as Fund gross assets; any other assets figure reads as Regulatory AUM.
  function assetLabel(label, value) {
    const blob = (label || '') + ' ' + (value || '');
    if (/^headquarters$/i.test(label || '')) return HCOPY.hq || 'HQ';
    if (/^fund gross assets$/i.test(label || '')) return HCOPY.fund_gross || 'Fund gross assets';
    if (/^regulatory aum$/i.test(label || '')) return HCOPY.regulatory_aum || 'Regulatory AUM';
    if (/^(assets|aum)$/i.test(label || '')) {
      if (/gross asset/i.test(blob) && !/regulatory aum|item 5f|\braum\b/i.test(blob)) return HCOPY.fund_gross || 'Fund gross assets';
      return HCOPY.regulatory_aum || 'Regulatory AUM';
    }
    return label;
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
  }
  // Leads (unconfirmed items) stay on the page but read one way everywhere: a 'Not confirmed' label.
  // Display only: stored rows keep their lead wording, so the data rules (leads never auto-published) still see them.
  const NC = COPY.not_confirmed || 'Not confirmed';
  const LEAD_PRE = /^\s*(?:lead\b(?:\s*\([^)]*\))?\s*:\s*)+/i, LEAD_TAG = /lead\s*\((?:not confirmed|unverified)\)/i;
  const isLeadTag = (t) => /\b(lead|unverified|allegation)\b/i.test(t || '');
  const ncStrip = (t) => String(t == null ? '' : t).replace(LEAD_PRE, '');
  const ncValue = (t) => { const s = String(t == null ? '' : t); if (LEAD_TAG.test(s)) return s.replace(LEAD_TAG, NC);
    return LEAD_PRE.test(s) ? s.replace(LEAD_PRE, '') + ' · ' + NC : s; };
  const ncPill = '<span class="cs cs-cl">' + esc(NC) + '</span> ';
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
    return '<div class="fct"><b>' + esc(x.title ? nice(ncStrip(x.title)) : COPY.table.untitled) + '</b>' + (meta ? ' · ' + meta : '') + (x.note ? '<br>' + esc(nice(x.note)) : '') + sourceHtml(x, false) + '</div>';
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

  // Layout A: one row. Bold title, optional note, then a grey line with the date, status and source pills.
  const showDate = (d) => { if (!d) return ''; const f = fdate(d); return f || String(d); };
  const cleanLead = (t) => String(t == null ? '' : t).replace(LEAD_TAG, '').replace(LEAD_PRE, '').replace(/\s*·\s*·\s*/g, ' · ').replace(/\s*·\s*$/, '').replace(/^\s*·\s*/, '').trim();
  const isLeadVal = (t) => LEAD_TAG.test(t || '') || LEAD_PRE.test(t || '');
  function row(title, date, status, src, note) {
    const st = status ? '<span class="cs ' + (COPY.state[status] || 'cs-cl') + '">' + esc(status) + '</span>' : '';
    const meta = [date ? '<span class="rd">' + esc(showDate(date)) + '</span>' : '', st, chips(src)].filter(Boolean).join(' ');
    return '<div class="rw"><div class="rt">' + esc(title) + '</div>' + (note ? '<div class="rn">' + esc(note) + '</div>' : '') + '<div class="rm">' + meta + '</div></div>';
  }
  function factRow(x) {
    const lead = isLeadVal(x.value) || isLeadVal(x.label);
    const label = nice(assetLabel(x.label, x.value));
    const val = nice(cleanLead(x.value));
    return row(val ? label + ': ' + val : label, '', lead ? NC : '', x.src, '');
  }
  function groupLps(it) {
    const order = [], map = {};
    it.forEach(x => {
      const k = x.label || '';
      if (!map[k]) { map[k] = { label: k, values: [], src: [], lead: false }; order.push(k); }
      const g = map[k];
      if (x.value) g.values.push(x.value);
      g.src = g.src.concat(x.src || []);
      if (isLeadVal(x.value)) g.lead = true;
    });
    return order.map(k => {
      const g = map[k], n = g.values.length;
      const title = nice(g.label) + (n > 1 ? ' · ' + fmt(COPY.commitments || '{n} commitments', { n }) : '');
      const seen = {}, src = [];
      g.src.forEach(s => { const id = (s.url || '') + '|' + (s.label || ''); if (!seen[id]) { seen[id] = 1; src.push(s); } });
      return row(title, '', g.lead ? NC : '', src, g.values.map(v => nice(cleanLead(v))).filter(Boolean).join(' | '));
    }).join('');
  }
  // Overview is cleaned here, when the page draws. Stored rows are not changed, and no other section uses this.
  // Hidden: Other names, Type, Staff, Private funds, Legal entity, Sanctions screening, empty, and "Not found".
  // Legal entity is kept only as the Registration line when that row is missing and the entity text holds the status.
  const OV_LINE = COPY.overview_line || {};
  const LEGAL_SUFFIX = /\b(l\.?l\.?c\.?|l\.?l\.?p\.?|l\.?p\.?|inc\.?|ltd\.?|corp\.?|plc|gmbh|s\.?a\.?r?\.?l\.?|a\.?g\.?|b\.?v\.?|n\.?v\.?|ulc|pte\.?|pty\.?|icav)\b/i;
  function ovSlot(label) {
    const l = String(label || '').replace(/\s+/g, ' ').trim().toLowerCase();
    if (l === 'hq' || l === 'headquarters' || l === 'headquarter') return 'hq';
    if (l === 'legal name') return 'legal';
    if (l === 'registration') return 'registration';
    if (l === 'founded') return 'founded';
    if (l === 'founders' || l === 'founder') return 'founders';
    if (l === 'owners' || l === 'owner') return 'owners';
    if (l === 'recent changes' || l === 'recent change') return 'changes';
    if (l === 'other names' || l === 'type' || l === 'staff' || l === 'private funds' || l === 'legal entity' || l === 'sanctions screening') return 'hide';
    if (LEGAL_SUFFIX.test(String(label || ''))) return 'entity';
    return 'other';
  }
  function blankOverview(v) {
    const t = String(v || '').replace(/\s+/g, ' ').trim();
    return !t || /^(not found( in public records)?|no data yet|n\/a|none|—|–|-|\.{1,3})[.!]?$/i.test(t);
  }
  function stripFileNums(s) {
    let t = String(s || '');
    t = t.replace(/\bCRD\s*#?\s*\d+\b/gi, '');
    t = t.replace(/\bSEC\s*#?\s*\d{3}-\d+\b/gi, '');
    t = t.replace(/\b80[12]-\d{4,6}\b/g, '');
    t = t.replace(/\(\s*(?:,\s*)*\)/g, '');
    t = t.replace(/[ \t]{2,}/g, ' ');
    t = t.replace(/\s*·\s*(·\s*)+/g, ' · ');
    t = t.replace(/\s*,\s*(,\s*)+/g, ', ');
    t = t.replace(/\s+([,;])/g, '$1');
    t = t.replace(/\(\s*,/g, '(').replace(/,\s*\)/g, ')');
    t = t.replace(/^[,\s·;:]+|[,\s·;:]+$/g, '');
    t = t.replace(/\(\s*\)/g, '').replace(/\s{2,}/g, ' ').trim();
    return t;
  }
  function dedupeSrc(list) {
    const seen = {}, out = [];
    (list || []).forEach(s => {
      if (!s) return;
      const url = String(s.url || '').trim().toLowerCase().replace(/\/+$/, '');
      const id = url || ('|' + (s.label || ''));
      if (!id || seen[id]) return;
      seen[id] = 1;
      out.push(s);
    });
    return out;
  }
  function holdsRegStatus(raw) {
    return /exempt reporting adviser|sec-registered|investment adviser|\bapproved\b|\bactive\b/i.test(raw || '');
  }
  function registrationLine(raw) {
    const era = /exempt reporting adviser/i.test(raw || '');
    const inactive = /\b(inactive|withdrawn|terminated|not active)\b/i.test(raw || '');
    const active = /\bactive\b/i.test(raw || '') && !inactive;
    const year = (String(raw || '').match(/\b(?:approved|since|registered|registration)\b[\s\S]{0,40}?((?:19|20)\d{2})\b/i) || [])[1];
    if (era) return active ? (OV_LINE.era_active || 'SEC exempt reporting adviser, active') : (OV_LINE.era || 'SEC exempt reporting adviser');
    if (year && active) return fmt(OV_LINE.sec_active || 'SEC-registered since {year}, active', { year });
    if (year) return fmt(OV_LINE.sec_since || 'SEC-registered since {year}', { year });
    if (active && /sec-registered|investment adviser|\bapproved\b/i.test(raw || '')) return OV_LINE.sec_active_noyear || 'SEC-registered, active';
    return stripFileNums(raw);
  }
  function overviewRows(items) {
    const slot = { hq: [], legal: [], entity: [], registration: [], founded: [], founders: [], owners: [], changes: [], legalEntity: [], other: [] };
    (items || []).forEach((x, i) => {
      const k = ovSlot(x && x.label);
      const row = Object.assign({ _i: i }, x);
      if (k === 'hide') {
        if (String(x.label || '').replace(/\s+/g, ' ').trim().toLowerCase() === 'legal entity') slot.legalEntity.push(row);
        return;
      }
      (slot[k] || slot.other).push(row);
    });
    const out = [];
    const push = (label, value, src, lead) => {
      const core = stripFileNums(cleanLead(value));
      if (blankOverview(core)) return;
      out.push({ label, value: lead ? ('Lead: ' + core) : core, src: dedupeSrc(src) });
    };
    const byIndex = (a, b) => a._i - b._i;
    slot.hq.sort(byIndex).forEach(x => push(x.label || 'HQ', x.value, x.src, isLeadVal(x.value) || isLeadVal(x.label)));
    slot.legal.sort(byIndex).forEach(x => push('Legal name', x.value, x.src, isLeadVal(x.value) || isLeadVal(x.label)));
    slot.entity.sort(byIndex).forEach(x => push('Legal name', nice(String(x.label || '').trim()), x.src, isLeadVal(x.label)));
    if (slot.registration.length) {
      slot.registration.sort(byIndex).forEach(x => push('Registration', registrationLine(x.value), x.src, isLeadVal(x.value) || isLeadVal(x.label)));
    } else {
      const hold = slot.legalEntity.find(x => holdsRegStatus(x.value));
      if (hold) push('Registration', registrationLine(hold.value), hold.src, isLeadVal(hold.value));
    }
    if (slot.founded.length || slot.founders.length) {
      let value = '';
      slot.founded.sort(byIndex).forEach(x => {
        const core = stripFileNums(cleanLead(x.value));
        if (blankOverview(core)) return;
        if (value.toLowerCase().indexOf(core.toLowerCase()) < 0) value = value ? value + ' · ' + core : core;
      });
      slot.founders.sort(byIndex).forEach(x => {
        const core = stripFileNums(cleanLead(x.value));
        if (blankOverview(core) || value.toLowerCase().indexOf(core.toLowerCase()) >= 0) return;
        value = value ? value + ' · ' + core : core;
      });
      const src = [];
      slot.founded.forEach(x => (x.src || []).forEach(s => src.push(s)));
      slot.founders.forEach(x => (x.src || []).forEach(s => src.push(s)));
      const lead = slot.founded.concat(slot.founders).some(x => isLeadVal(x.value) || isLeadVal(x.label));
      push('Founded', value, src, lead);
    }
    slot.owners.sort(byIndex).forEach(x => push(x.label || 'Owners', x.value, x.src, isLeadVal(x.value) || isLeadVal(x.label)));
    slot.changes.sort(byIndex).forEach(x => push(x.label || 'Recent changes', x.value, x.src, isLeadVal(x.value) || isLeadVal(x.label)));
    slot.other.sort(byIndex).forEach(x => push(x.label, x.value, x.src, isLeadVal(x.value) || isLeadVal(x.label)));
    return out;
  }
  const yearNum = (x) => { const y = shownYear(x) || (x && x.year) || ''; const m = String(y).match(/(19|20)\d{2}/); return m ? +m[0] : 0; };
  // Display-only order for Legal & regulatory. Active rows first, newest year first, then every other status the same way.
  function legalStatus(x) {
    const lead = x.state === 'Unverified' || isLeadTag(x.status) || LEAD_PRE.test(x.title || x.head || '');
    return lead ? NC : (x.state || (x.status ? x.status[0].toUpperCase() + x.status.slice(1) : ''));
  }
  function orderLegal(xs) {
    return xs.filter(x => x.title || x.head || x.note).slice().sort((a, b) => (legalStatus(a) === 'Active' ? 0 : 1) - (legalStatus(b) === 'Active' ? 0 : 1) || yearNum(b) - yearNum(a));
  }
  // Open-state renderers, keyed by copy.json sections[].renderer. The section is the third argument (LP grouping).
  const R = {
    facts: (it, P, s) => '<div class="rws">' + (s && s.key === 'lps' ? groupLps(it) : it.map(factRow).join('')) + '</div>',
    checks: (it, P) => checkRows(P),
    legal: (it) => group(it, 'grp', COPY.legal, xs => '<div class="rws">' + orderLegal(xs).map(x => {
      const note = [x.role, x.note].filter(Boolean).map(nice).join(' · ');
      return row(nice(ncStrip(x.title || x.head || '')), shownYear(x) || x.year || '', legalStatus(x), x.src, note);
    }).join('') + '</div>'),
    press: (it) => '<div class="pgr">' + it.map(x => card(x, true)).join('') + '</div>',
    news: (it) => '<div class="pgr">' + it.map(x => card(x, true)).join('') + '</div>',
    founders: (it) => '<div class="rws">' + it.map(x => row(nice(ncStrip(x.head || '')), x.date, '', x.src, x.snippet ? nice(x.snippet) : '')).join('') + '</div>',
    people: (it) => group(it.filter(x => !isNoteText(x.head)), 'kind', COPY.people, xs => '<div class="pcards">' + xs.map(x => '<div class="pcard"><b>' + esc(nice(x.head)) + '</b>' + (x.badge ? (isLeadTag(x.badge) ? '<span class="cs cs-cl">' + esc(NC) + '</span>' : '<span class="cs cs-act">' + esc(x.badge) + '</span>') : '') + '<span>' + esc(x.role) + '</span>' + chips(x.src) + '</div>').join('') + '</div>'),
    timeline: (it) => {
      const rows = it.map((x, i) => ({ x, i })).sort((a, b) => {
        const sa = window.RegretDate ? window.RegretDate.stamp(a.x.date) : null, sb = window.RegretDate ? window.RegretDate.stamp(b.x.date) : null;
        if (sa == null && sb == null) return a.i - b.i;
        if (sa == null) return 1;
        if (sb == null) return -1;
        return sb - sa || a.i - b.i;
      });
      return '<div class="tls">' + rows.map(({ x }) => '<div class="tl"><span class="tld">' + esc(fdate(x.date) || x.date || '') + '</span><span><span class="cs cs-cl">' + esc(isLeadTag(x.kind) ? NC : x.kind) + '</span> ' + esc(nice(ncStrip(x.body))) + chips(x.src) + '</span></div>').join('') + '</div>';
    },
  };
  function card(x, logo) {
    const u = safeUrl(x.url), host = u ? new URL(u).hostname.replace(/^www\./, '') : '';
    const court = x.tag === 'Court' || x.tag === 'Filing';
    const fav = !court && logo && x.logo ? '<img class="fav" src="' + esc(ROOT + x.logo) + '" alt="" width="20" height="20">' : '<span class="fav lb">' + esc((x.outlet || x.tag || '?')[0]) + '</span>';
    const tag = x.tag ? '<span class="cs cs-cl">' + esc(x.tag) + '</span>' : '';
    const note = x.outlets > 1 && COPY.outlets ? '<span class="nout">' + esc(pl(COPY.outlets, x.outlets)) + '</span>' : '';
    return '<div class="pi"><div class="pio">' + fav + '<span>' + esc(x.outlet || '') + (host && String(x.outlet || '').split(' · ')[0].trim().toLowerCase().replace(/^www\./, '') !== host ? ' · ' + esc(host) : '') + (x.date ? ' · ' + esc(fdate(x.date) || x.date) : '') + '</span>' + tag + note + '</div>'
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
  // News is drawn here from the press and timeline rows firm_page already returns. Nothing is written back.
  // The link merge, the story grouping and the 2023 cutoff apply only to this list.
  function normLink(u) {
    return String(u || '').trim().toLowerCase().replace(/#.*$/, '').replace(/\?.*$/, '').replace(/^https?:\/\/(?:www\.)?/, '').replace(/\/+$/, '');
  }
  function newsYear(label) {
    const m = String(label || '').match(/(?:19|20)\d{2}/);
    return m ? +m[0] : null;
  }
  function newsStamp(label) {
    if (window.RegretDate) { const s = window.RegretDate.stamp(label); if (s != null) return s; }
    const iso = String(label || '').match(/^(\d{4})-(\d{2})(?:-(\d{2}))?/);
    if (iso) return Date.UTC(+iso[1], +iso[2] - 1, iso[3] ? +iso[3] : 1);
    const y = newsYear(label);
    return y ? Date.UTC(y, 0, 1) : null;
  }
  function newsTag(kind, grp) {
    const k = String(kind || ''), g = String(grp || '');
    if (/^(court|case filed)$/i.test(k)) return 'Court';
    if (/^filing$/i.test(k)) return 'Filing';
    if (/^(fund|fund raise)$/i.test(k)) return 'Fund';
    if (/^(people|people move)$/i.test(k)) return 'People';
    if (/^regulator/i.test(k)) return 'Regulator';
    if (/regulator/i.test(g)) return 'Regulator';
    if (/people/i.test(g)) return 'People';
    if (/fund/i.test(g)) return 'Fund';
    return '';
  }
  const TAG_RANK = { Court: 5, Filing: 4, Regulator: 3, People: 2, Fund: 1 };
  function bumpTag(card, tag) { if (tag && (TAG_RANK[tag] || 0) > (TAG_RANK[card.tag] || 0)) card.tag = tag; }
  function addSrc(card, list) {
    (list || []).forEach(s => {
      if (!s || !s.url) return;
      const id = normLink(s.url) + '|' + (s.label || '');
      if (card._seen[id]) return;
      card._seen[id] = 1;
      card.src.push({ label: s.label || '', date: s.date || '', url: s.url });
    });
  }
  function datesMatch(a, b) {
    if (!a || !b) return true;
    if (a === b) return true;
    const sa = newsStamp(a), sb = newsStamp(b);
    return sa != null && sa === sb;
  }
  const STORY_DAYS = 7 * 86400000;
  const STORY_STOP = new Set('a an the of into over and or for at on in to from with by as its their his her board boards seat seats director directors partner partners news report reports reported founder founders focus focuses focused final other outlet outlets firm firms company companies people person opens open draw draws look looks review reviews widens widen new says said after before about than then this that these those was were are is be been being not no nor but under up down out off via per also who what when where why how did does do own post posts across despite names co'.split(' '));
  const STORY_AGENCY_SKIP = new Set('ai gp lp llc inc ltd co us uk eu un vc ceo cfo cto coo pr hr tv ok am pm ii iii iv vi vii viii ix xi xii nyc pac'.split(' '));
  const EVENT_WORD = /\b(probes?|probing|investigat\w*|lawsuits?|sued|suits?|filings?|filed|indict\w*|settl\w*|acqui\w*|raises?|raised|raising|appoint\w*|resign\w*|quits?|closes?|closed|closing|discriminat\w*|charges?|charged|alleg\w*|fines?|fined|bankrupt\w*)\b/ig;
  const escRe = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  function eventStem(w) {
    w = String(w || '').toLowerCase();
    if (/^prob/.test(w)) return 'probe';
    if (/^invest/.test(w)) return 'investigat';
    if (/^lawsuit|^sued|^suit/.test(w)) return 'suit';
    if (/^fil/.test(w)) return 'filing';
    if (/^indict/.test(w)) return 'indict';
    if (/^settl/.test(w)) return 'settle';
    if (/^acqui/.test(w)) return 'acqui';
    if (/^rais/.test(w)) return 'raise';
    if (/^appoint/.test(w)) return 'appoint';
    if (/^resign|^quit/.test(w)) return 'resign';
    if (/^clos/.test(w)) return 'close';
    if (/^discrim/.test(w)) return 'discriminat';
    if (/^charg/.test(w)) return 'charge';
    if (/^alleg/.test(w)) return 'alleg';
    if (/^fin/.test(w)) return 'fine';
    if (/^bankrupt/.test(w)) return 'bankrupt';
    return '';
  }
  function stripAttribution(head) {
    return String(head || '').replace(/,\s+[A-Z][\w .&'"’-]*\breports?\b\.?\s*$/i, '').replace(/\breported by\b.*$/i, '').trim();
  }
  function firmAliases(firm) {
    const out = [];
    ['name', 'short_name', 'sec_name'].forEach(k => {
      const v = firm && firm[k] ? String(firm[k]).trim() : '';
      if (v.length >= 3) out.push(v);
    });
    return out.sort((a, b) => b.length - a.length);
  }
  function storyWhen(label) {
    const t = String(label || '').trim();
    if (!t) return { prec: 'none', stamp: null, year: null, month: null };
    const day = t.match(/^(\d{4})-(\d{2})-(\d{2})\b/);
    if (day) return { prec: 'day', stamp: Date.UTC(+day[1], +day[2] - 1, +day[3]), year: +day[1], month: +day[2] };
    if (window.RegretDate) {
      const s = window.RegretDate.stamp(t);
      if (s != null) { const d = new Date(s); return { prec: 'day', stamp: s, year: d.getUTCFullYear(), month: d.getUTCMonth() + 1 }; }
    }
    const months = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 };
    const isoM = t.match(/^(\d{4})-(\d{2})$/), named = t.match(/^([A-Za-z]+)\.?\s+(\d{4})$/);
    if (isoM && +isoM[2] >= 1 && +isoM[2] <= 12) return { prec: 'month', stamp: null, year: +isoM[1], month: +isoM[2] };
    if (named && months[named[1].toLowerCase().slice(0, 3)]) return { prec: 'month', stamp: null, year: +named[2], month: months[named[1].toLowerCase().slice(0, 3)] };
    if (/^\d{4}$/.test(t)) return { prec: 'year', stamp: null, year: +t, month: null };
    return { prec: 'none', stamp: null, year: null, month: null };
  }
  function storyParts(head, firm) {
    const cleaned = stripAttribution(head);
    const aliases = firmAliases(firm);
    const hasFirm = aliases.some(a => new RegExp('\\b' + escRe(a) + '\\b', 'i').test(cleaned));
    let text = cleaned;
    aliases.forEach(a => { text = text.replace(new RegExp('\\b' + escRe(a) + '\\b', 'gi'), ' '); });
    const events = new Set();
    text.replace(EVENT_WORD, w => { const s = eventStem(w); if (s) events.add(s); return w; });
    const companies = new Set(), agencies = new Set();
    text = text.replace(/\bfund\s+(i{1,3}|iv|vi{0,3}|ix|xi{0,3}|xii|\d+)\b/gi, (_, n) => { companies.add('fund-' + String(n).toUpperCase()); return ' '; });
    text = text.replace(/\bseries\s+([a-z])\b/gi, (_, n) => { companies.add('series-' + n.toLowerCase()); return ' '; });
    const tokens = text.match(/[A-Za-z0-9][A-Za-z0-9'’]*/g) || [];
    tokens.forEach(w => {
      if (/\d/.test(w) && /[A-Za-z]/.test(w) && w.length <= 8 && !STORY_STOP.has(w.toLowerCase())) companies.add(w.toLowerCase());
      if (/^[A-Z]{2,6}$/.test(w)) { const k = w.toLowerCase(); if (!STORY_AGENCY_SKIP.has(k) && !STORY_STOP.has(k)) agencies.add(k); }
    });
    let phrase = [];
    const flush = () => {
      const parts = phrase.filter(w => !STORY_STOP.has(w.toLowerCase()) && !/^[A-Z]{2,6}$/.test(w) && !eventStem(w));
      if (parts.length) companies.add(parts.map(w => w.toLowerCase()).join('-'));
      phrase = [];
    };
    tokens.forEach(w => { if (/^[A-Z][a-z]/.test(w)) phrase.push(w); else flush(); });
    flush();
    return { events, companies, agencies, hasFirm };
  }
  function setShares(a, b) { let n = 0; a.forEach(x => { if (b.has(x)) n++; }); return n; }
  function storyOverlap(a, b, strong) {
    if (!setShares(a.events, b.events)) return 0;
    const comp = setShares(a.companies, b.companies);
    const bothComp = a.companies.size && b.companies.size;
    if (bothComp && !comp) return 0;
    const ag = setShares(a.agencies, b.agencies);
    if (a.agencies.size && b.agencies.size && !ag) return 0;
    let score = comp * 10 + ag * 3;
    if (a.hasFirm && b.hasFirm) score += 1;
    if (!score) return 0;
    if (strong) return comp || (ag && a.hasFirm && b.hasFirm && !bothComp) ? score : 0;
    return comp || (ag && !bothComp) ? score : 0;
  }
  function srcHost(url) {
    const u = safeUrl(url);
    if (!u) return '';
    try { return new URL(u).hostname.replace(/^www\./, '').toLowerCase(); } catch (e) { return ''; }
  }
  function collapseSrc(list) {
    const by = new Map();
    (list || []).forEach(s => {
      if (!s || !s.url) return;
      const host = srcHost(s.url), key = host || String(s.label || '').toLowerCase();
      if (!key) return;
      const cur = by.get(key);
      if (!cur) { by.set(key, s); return; }
      const bare = (label) => String(label || '').replace(/\s*·\s*own media\s*$/i, '').replace(/\s*·\s*other source\s*$/i, '').split(' · ')[0].trim().toLowerCase();
      if (bare(cur.label) === host && bare(s.label) !== host) by.set(key, s);
    });
    return Array.from(by.values());
  }
  function groupStories(cards, firm) {
    const info = cards.map(c => Object.assign(storyWhen(c.date), storyParts(c.head, firm)));
    const n = cards.length, parent = cards.map((_, i) => i);
    const find = (i) => parent[i] === i ? i : (parent[i] = find(parent[i]));
    const membersOf = (root) => { const out = []; for (let i = 0; i < n; i++) if (find(i) === root) out.push(i); return out; };
    const daySpan = (members) => {
      const ds = members.filter(i => info[i].prec === 'day' && info[i].stamp != null).map(i => info[i].stamp);
      return ds.length ? Math.max.apply(null, ds) - Math.min.apply(null, ds) : 0;
    };
    const unionDay = (i, j) => {
      const a = find(i), b = find(j);
      if (a === b) return;
      if (daySpan(membersOf(a).concat(membersOf(b))) > STORY_DAYS) return;
      parent[b] = a;
    };
    const clusterParts = (members) => {
      const events = new Set(), companies = new Set(), agencies = new Set();
      let hasFirm = false;
      members.forEach(i => {
        info[i].events.forEach(e => events.add(e));
        info[i].companies.forEach(e => companies.add(e));
        info[i].agencies.forEach(e => agencies.add(e));
        if (info[i].hasFirm) hasFirm = true;
      });
      return { events, companies, agencies, hasFirm };
    };
    const pair = (wantCompanies) => {
      for (let i = 0; i < n; i++) {
        if (info[i].prec !== 'day' || (info[i].companies.size > 0) !== wantCompanies) continue;
        for (let j = i + 1; j < n; j++) {
          if (info[j].prec !== 'day' || (info[j].companies.size > 0) !== wantCompanies) continue;
          if (Math.abs(info[i].stamp - info[j].stamp) > STORY_DAYS) continue;
          if (!storyOverlap(info[i], info[j], false)) continue;
          unionDay(i, j);
        }
      }
    };
    pair(true); pair(false);
    const dayRoots = () => {
      const s = [], seen = new Set();
      for (let i = 0; i < n; i++) {
        if (info[i].prec !== 'day') continue;
        const r = find(i); if (seen.has(r)) continue; seen.add(r); s.push(r);
      }
      return s;
    };
    dayRoots().filter(r => membersOf(r).every(i => !info[i].companies.size)).forEach(r => {
      const mem = membersOf(r), plain = clusterParts(mem);
      let best = -1, bestScore = 0, bestStamp = -1, ties = 0;
      dayRoots().forEach(cr => {
        if (cr === r) return;
        const cm = membersOf(cr);
        if (!cm.some(i => info[i].companies.size) || daySpan(mem.concat(cm)) > STORY_DAYS) return;
        const score = storyOverlap(plain, clusterParts(cm), true);
        const stamp = Math.max.apply(null, cm.map(i => info[i].stamp || 0));
        if (!score) return;
        if (score > bestScore || (score === bestScore && stamp > bestStamp)) { best = cr; bestScore = score; bestStamp = stamp; ties = 1; }
        else if (score === bestScore) ties++;
      });
      if (bestScore && ties === 1) parent[r] = best;
    });
    for (let i = 0; i < n; i++) {
      if ((info[i].prec !== 'year' && info[i].prec !== 'month') || find(i) !== i) continue;
      let best = -1, bestScore = 0, bestStamp = -1, ties = 0;
      const seen = new Set();
      for (let j = 0; j < n; j++) {
        if (info[j].prec !== 'day') continue;
        const cr = find(j); if (seen.has(cr)) continue; seen.add(cr);
        const days = membersOf(cr).filter(k => info[k].prec === 'day');
        if (!days.length || daySpan(days) > STORY_DAYS) continue;
        const years = new Set(days.map(k => info[k].year)), months = new Set(days.map(k => info[k].month));
        if (info[i].prec === 'year' && (years.size !== 1 || !years.has(info[i].year))) continue;
        if (info[i].prec === 'month' && (years.size !== 1 || months.size !== 1 || !years.has(info[i].year) || !months.has(info[i].month))) continue;
        const score = storyOverlap(info[i], clusterParts(days), true);
        const stamp = Math.max.apply(null, days.map(k => info[k].stamp || 0));
        if (!score) continue;
        if (score > bestScore || (score === bestScore && stamp > bestStamp)) { best = cr; bestScore = score; bestStamp = stamp; ties = 1; }
        else if (score === bestScore) ties++;
      }
      if (bestScore && ties === 1) parent[i] = best;
    }
    const groups = new Map();
    for (let i = 0; i < n; i++) { const r = find(i); if (!groups.has(r)) groups.set(r, []); groups.get(r).push(i); }
    const keep = [];
    groups.forEach(mem => {
      const days = mem.filter(i => info[i].prec === 'day');
      const pool = (days.length ? days : mem).slice().sort((a, b) => (info[b].stamp || 0) - (info[a].stamp || 0) || a - b);
      const k = pool[0];
      mem.forEach(i => { if (i === k) return; addSrc(cards[k], cards[i].src); bumpTag(cards[k], cards[i].tag); });
      if (mem.length > 1) {
        cards[k].src = collapseSrc(cards[k].src);
        cards[k].outlets = cards[k].src.length;
      }
      keep.push(cards[k]);
    });
    return keep;
  }
  function buildNews(press, timeline, firm) {
    const cards = [];
    (press || []).map((x, i) => ({ x, i })).sort((a, b) => {
      const sa = newsStamp(a.x.date), sb = newsStamp(b.x.date);
      if (sa == null && sb == null) return a.i - b.i;
      if (sa == null) return 1;
      if (sb == null) return -1;
      return sb - sa || a.i - b.i;
    }).forEach(({ x }) => {
      const url = x.url || '', norm = normLink(url);
      if (!norm) return;
      const tag = newsTag('', x.group);
      const src = (x.src && x.src.length) ? x.src : [{ label: String(x.outlet || '').split(' · ')[0], date: x.date || '', url }];
      const keeper = cards.find(c => c.origin === 'press' && c.norm === norm);
      if (keeper) { addSrc(keeper, src); bumpTag(keeper, tag); return; }
      const card = { origin: 'press', head: x.head || '', outlet: x.outlet || '', date: x.date || '', url, snippet: x.snippet || '', logo: x.logo || '', tag, norm, norms: [norm], src: [], _seen: {}, _year: newsYear(x.date) };
      addSrc(card, src);
      cards.push(card);
    });
    (timeline || []).forEach(x => {
      const tag = newsTag(x.kind, ''), ty = newsYear(x.date);
      const links = (x.src || []).filter(s => s && s.url);
      for (let i = 0; i < links.length; i++) {
        const norm = normLink(links[i].url);
        if (!norm) continue;
        const keeper = cards.find(c => c.origin === 'press' && c.norm === norm);
        if (!keeper) continue;
        const py = keeper._year;
        if (!(ty == null || ty >= 2023 || (py != null && py < 2023))) continue;
        addSrc(keeper, links);
        bumpTag(keeper, tag);
        return;
      }
      const norms = links.map(s => normLink(s.url)).filter(Boolean);
      const other = cards.find(c => c.origin === 'timeline' && norms.some(n => c.norms.indexOf(n) >= 0) && datesMatch(c.date, x.date || ''));
      if (other) {
        addSrc(other, links);
        bumpTag(other, tag);
        norms.forEach(n => { if (other.norms.indexOf(n) < 0) other.norms.push(n); });
        return;
      }
      const card = { origin: 'timeline', head: x.body || x.head || '', outlet: (links[0] && links[0].label) || '', date: x.date || '', url: (links[0] && links[0].url) || '', snippet: '', logo: '', tag, norm: norms[0] || '', norms, src: [], _seen: {}, _year: ty };
      addSrc(card, links);
      cards.push(card);
    });
    const shown = cards.filter(c => { const y = c._year != null ? c._year : newsYear(c.date); return y == null || y >= 2023; });
    return groupStories(shown, firm).sort((a, b) => {
      const sa = newsStamp(a.date), sb = newsStamp(b.date);
      if (sa == null && sb == null) return 0;
      if (sa == null) return 1;
      if (sb == null) return -1;
      return sb - sa;
    }).map(c => {
      const pub = { head: c.head, outlet: c.outlet, date: c.date, url: c.url, snippet: c.snippet, logo: c.logo, tag: c.tag, src: c.src, origin: c.origin };
      if (c.outlets > 1) pub.outlets = c.outlets;
      return pub;
    });
  }
  // Sections the new page draws. "The 10 checks" is not one of them. An LP with several commitments counts once.
  // News is not a stored section: it is press and timeline combined at display time.
  function pageSecs(P) {
    const byKey = Object.fromEntries((P.sections || []).map(s => [s.key, s]));
    const newsItems = buildNews((byKey.press && byKey.press.items) || [], (byKey.timeline && byKey.timeline.items) || [], P && P.firm);
    return CFG.sections.list.filter(c => c.key !== 'checks' && (c.key === 'news' ? newsItems.length : byKey[c.key])).map(c => {
      if (c.key === 'news') return Object.assign({}, c, { count: newsItems.length, items: newsItems, teaser: (newsItems[0] && newsItems[0].head) || '' });
      const s = Object.assign({}, byKey[c.key], c);
      if (s.key === 'lps') { const n = new Set((s.items || []).map(x => x.label)).size; if (n) s.count = n; }
      if (s.key === 'overview') {
        const items = overviewRows(s.items || []);
        if (!items.length) return null;
        s.items = items;
        s.count = items.length;
      }
      return s;
    }).filter(Boolean);
  }
  function checkSummaryHtml(P) {
    if (!P.open || !P.checks || !P.checks.length) return '';
    return '<section id="check-summary" class="ps"><h2>' + esc(COPY.summary) + ' <em class="pc2">' + P.checks.length + '</em></h2><div class="cks">'
      + P.checks.map(r => '<a class="ck" href="#panel-checks" data-tab="checks"><span class="ckn">' + String(r.n).padStart(2, '0') + '</span>' + esc(r.title) + pill(r.state) + '</a>').join('')
      + '</div><p class="seefull"><a href="#panel-checks" data-tab="checks">' + esc(COPY.full_check) + '</a></p></section>';
  }
  function render(main, P) {
    const firm = P.firm.name, secs = pageSecs(P), total = secs.reduce((a, s) => a + s.count, 0);
    setFirmName(main, firm);
    main.classList.toggle('unlocked', P.open);
    const tocEl = main.querySelector('.toc'), csum = main.querySelector('.csum'), lk = main.querySelector('#lockcard');
    if (tocEl) tocEl.style.display = ''; if (lk) lk.style.display = '';
    const meta = main.querySelector('.m'); if (meta) meta.innerHTML = metaLine(P);
    paintActivity(main, P);
    if (csum) { csum.hidden = true; csum.innerHTML = ''; }
    if (!P.open) {
      if (main.querySelector('.spl')) main.querySelector('.spl').innerHTML = '';
      if (tocEl) { tocEl.innerHTML = ''; tocEl.style.display = 'none'; }
      if (lk) { lk.hidden = true; lk.style.display = 'none'; }
      researchBan(main, false);
      const pmain = main.querySelector('.pmain');
      if (pmain) pmain.innerHTML = P.unchecked ? '<section class="ps">' + ctable(P, false, 0) + '</section>' + gate(P, '') : gate(P, '<section class="ps">' + ghost(P) + '</section>' + ghostSecs());
      return { total: 0, head: () => GT.title };
    }
    const fn = main.querySelector('.rgt-n'); if (fn && total) { fn.textContent = total; fn.hidden = false; }
    const toc = [];
    secs.forEach(s => {
      toc.push(s);
      if (s.key === 'overview' && P.checks && P.checks.length) toc.push({ key: 'check-summary', title: COPY.summary, count: P.checks.length });
    });
    if (P.checks && P.checks.length && !secs.some(s => s.key === 'overview')) toc.unshift({ key: 'check-summary', title: COPY.summary, count: P.checks.length });
    if (main.querySelector('.spl')) main.querySelector('.spl').innerHTML = secs.map(s => '<a class="spp" href="#' + esc(s.key) + '">' + esc(s.title) + ' <em>' + s.count + '</em></a>').join('');
    if (tocEl) tocEl.innerHTML = '<b>' + COPY.toc + '</b>' + toc.map(s => '<a href="#' + esc(s.key) + '">' + esc(s.title) + ' <span>' + s.count + '</span></a>').join('');
    let body = '';
    secs.forEach(s => {
      body += '<section id="' + esc(s.key) + '" class="ps"><h2>' + esc(s.title) + ' <em class="pc2">' + s.count + '</em></h2><p class="psub">' + esc(s.subtitle || '') + '</p>'
        + (R[s.renderer] || R.facts)(s.items || [], P, s) + '</section>';
      if (s.key === 'overview') body += checkSummaryHtml(P);
    });
    if (!secs.some(s => s.key === 'overview')) body = checkSummaryHtml(P) + body;
    const pmain = main.querySelector('.pmain'); if (pmain) pmain.innerHTML = body;
    if (tocEl) spy(main);
    const lc = main.querySelector('#lockcard');
    if (lc) { lc.hidden = P.open; lc.querySelector('b').textContent = fmt(COPY.lockcard, { n: total, firm }); lc.querySelector('p').textContent = COPY.lockcard_sub; }
    const pu = document.getElementById('puse'); if (pu) pu.textContent = fmt(COPY.use_line, { n: total, firm });
    const od = P.ondemand;
    researchBan(main, !!(od && od.mine && (od.status === 'queued' || od.status === 'in_progress')));
    main.querySelectorAll('.row.tog').forEach(row => row.onclick = (e) => { if (!e.target.closest('a')) row.classList.toggle('open'); });
    return { total, head: (key) => { const s = secs.find(x => x.key === key); return s ? fmt(COPY.pay_head, { title: s.title, firm, count: s.count }) : fmt(COPY.pay_all, { n: total, firm }); } };
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
    const h1 = main.querySelector('.ph h1') || main.querySelector('.fh h1');
    if (h1) { const save = h1.querySelector('[data-save]'); h1.innerHTML = esc(fmt(CK.title, { firm })) + '<span class="dots">…</span>'; if (save) h1.appendChild(save); }
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
    const side = main.querySelector('.cside'); if (side) side.hidden = !(checking || research);
    if (research) { const ep = main.querySelector('[data-notify] p'); if (ep) ep.textContent = CK.research_email; }
    if (checking) checkingHead(main, P, st);
    else if (research) {
      setFirmName(main, P.firm.name);
      researchBan(main, true);
    } else {
      setFirmName(main, P.firm.name);
      const b = main.querySelector('.cban'); b.hidden = !justDone; b.className = 'cban ok';
      b.innerHTML = justDone ? '<div class="ch"><div><b>' + esc(CK.complete) + '</b> <span>' + esc(CK.complete_sub) + '</span></div></div>' : '';
    }
    const curN = checking && P.open ? P.checks.find(r => r.state === 'nc').n : 0;
    const link = siteLink(P);
    const meta = main.querySelector('.ph .m') || main.querySelector('.m');
    if (checking && !(P.hero && P.hero.length)) {
      if (meta) meta.innerHTML = esc(CK.sources[0]) + ' <b>' + esc(CK.sources[1]) + '</b>' + (link ? ' · ' + link : '');
    } else if (meta) meta.innerHTML = metaLine(P);
    paintActivity(main, P);
    const list = main.querySelector('.list'); if (list) list.innerHTML = P.open ? ctable(P, checking, curN) : P.unchecked ? ctable(P, false, 0) + gate(P, '') : gate(P, ghost(P));
    const fn = main.querySelector('.rgt-n'), ft = pageSecs(P).reduce((a, s) => a + (s.count || 0), 0);
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
      const lab = assetLabel(h.label, h.value), v = nice(h.value), parts = String(v).split(' · ');
      const t = /^(Assets|Regulatory AUM|AUM)$/.test(h.label) ? v + ' ' + lab.toLowerCase() : parts[0] + ' ' + lab.toLowerCase() + (parts.length > 1 ? ' · ' + parts.slice(1).join(' · ') : '');
      return '<a class="sc" href="' + esc(src.url) + '" target="_blank" rel="noopener">' + esc(t) + '</a>'; }).filter(Boolean).slice(0, 7).join('').replace(/^(.+)$/, '<span class="secp">$1</span>');
  }
  const tile = (lab, big, sub, cls) => '<div class="att ' + cls + '"><small>' + esc(lab) + '</small><b>' + big + '</b><span>' + sub + '</span></div>';
  // The new fund box is live only on these firms. Other pages keep the previous tile.
  const LAB_FIRMS = { a16z: 1, 'y-combinator': 1, sequoia: 1, lightspeed: 1, generalcatalyst: 1, plugandplay: 1, accel: 1, greenoaks: 1, 'khosla-ventures': 1, 'mio-partners': 1 };
  const labFirm = (P) => !!(P.firm && LAB_FIRMS[P.firm.slug]);
  // A fund line already on the page: "Name · $22.7B · 2026-02-05". AUM sentences and $0 lines are not funds.
  const amountText = (part) => { const m = String(part || '').trim().match(/^(\$[0-9][0-9,]*(?:\.[0-9]+)?(?:\s*[BMK])?)$/i); return m ? m[1].replace(/\s+/g, '') : ''; };
  const amountNumber = (text) => { const m = String(text || '').replace(/,/g, '').match(/^\$([0-9]*\.?[0-9]+)([BMK])?$/i); if (!m) return 0;
    const n = Number(m[1]); if (!isFinite(n) || n <= 0) return 0; const u = (m[2] || '').toUpperCase();
    return n * (u === 'B' ? 1e9 : u === 'M' ? 1e6 : u === 'K' ? 1e3 : 1); };
  function fundLineText(item) {
    const value = String(item && item.value || '').trim();
    if (value) return value;
    const head = String(item && item.head || '').trim(), label = String(item && item.label || '').trim();
    if (label && head.toLowerCase().startsWith(label.toLowerCase() + ':')) return head.slice(label.length + 1).trim();
    return head;
  }
  function filingUrl(src) {
    const urls = (src || []).map(s => safeUrl(s && s.url)).filter(Boolean);
    return urls.find(u => /(^|\.)sec\.gov\//i.test(u.replace(/^https?:\/\//i, ''))) || urls[0] || '';
  }
  function earlierFund(P) {
    const items = [];
    (P.sections || []).forEach(s => { if (s && s.key === 'funds') (s.items || []).forEach(item => items.push(item)); });
    const rows = [];
    items.forEach((item, i) => {
      const text = fundLineText(item);
      if (!text) return;
      const lab = assetLabel(item.label, text);
      if (lab === (HCOPY.regulatory_aum || 'Regulatory AUM') || lab === (HCOPY.fund_gross || 'Fund gross assets')) return;
      const parts = text.split(/\s*·\s*/).map(p => p.trim()).filter(Boolean);
      if (parts.length < 2) return;
      const name = parts[0];
      if (!name || /^\$/.test(name) || /regulatory aum|assets under management|\baum\b|item\s*5|form adv|gross asset/i.test(name)) return;
      let amount = '', date = '';
      parts.slice(1).forEach(p => {
        if (!amount) { const a = amountText(p); if (a && amountNumber(a) > 0) amount = a; }
        if (!date && /^\d{4}-\d{2}-\d{2}$/.test(p)) date = p;
      });
      if (!amount) return;
      rows.push({ name, amount, date, url: filingUrl(item.src), i });
    });
    rows.sort((a, b) => (b.date || '').localeCompare(a.date || '') || a.i - b.i);
    return rows[0] || null;
  }
  function raisedFundTile(fund) {
    const when = fund.date ? (fdate(fund.date) || fund.date) : '';
    const sub = esc(fund.name) + ' · ' + esc(fmt(AC.raised, { amount: fund.amount }))
      + (when ? ' · ' + esc(when) : '')
      + (fund.url ? ' · <a href="' + esc(fund.url) + '" target="_blank" rel="noopener">' + esc(AC.filing) + ' ↗</a>' : '');
    return tile(AC.fund, esc(fund.amount), sub, 'afd');
  }
  function aumFigure(raw) {
    const s = String(raw || '');
    const compact = s.match(/\$[0-9][0-9,]*(?:\.[0-9]+)?\s*[BMK]\b/i);
    if (compact) return compact[0].replace(/\s+/g, '');
    const dollars = s.match(/\$([0-9][0-9,]*(?:\.[0-9]+)?)/);
    return dollars ? money(Number(dollars[1].replace(/,/g, ''))) : '';
  }
  function secSrc(src) {
    return (src || []).find(c => /(^|\.)sec\.gov\//i.test((safeUrl(c && c.url) || '').replace(/^https?:\/\//i, '').replace(/\/.*/, '/')));
  }
  function aumTile(P) {
    const hero = Array.isArray(P.hero) ? P.hero : [];
    const hit = hero.find(h => h && h.value && assetLabel(h.label, h.value) === (HCOPY.regulatory_aum || 'Regulatory AUM'));
    let value = hit ? aumFigure(hit.value) : '';
    const src = hit ? (secSrc(hit.src) || (hit.src || []).find(c => safeUrl(c && c.url))) : null;
    if (!value) value = aumFigure(P.firm && P.firm.assets);
    if (!value) return '';
    const u = src && safeUrl(src.url);
    const sub = u ? '<a href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(src.label || AC.filing || 'Filing') + ' ↗</a>' : '';
    return tile(AC.aum || 'Assets under management', esc(value), sub, 'afd');
  }
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
    // A fund with an amount raised stays the Latest fund tile. On the 10 lab firms, a $0 or missing
    // amount is skipped for the next fund that raised money, then for assets under management.
    // Every other firm keeps the previous tile. The script is shared, so the limit is the slug.
    const raised = f && money(f.raised_usd);
    if (raised) {
      const u = safeUrl(f.url);
      const sub = esc(fundName(f.name)) + ' · ' + esc(fmt(AC.raised, { amount: raised })) + (u ? ' · <a href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(AC.filing) + ' ↗</a>' : '');
      tiles.push(tile(AC.fund, esc(raised), sub, 'afd'));
    } else if (labFirm(P)) {
      const prev = earlierFund(P);
      if (prev) tiles.push(raisedFundTile(prev));
      else {
        const aum = aumTile(P);
        if (aum) tiles.push(aum);
      }
    } else if (f) {
      const u = safeUrl(f.url);
      const sub = esc(fundName(f.name)) + (u ? ' · <a href="' + esc(u) + '" target="_blank" rel="noopener">' + esc(AC.filing) + ' ↗</a>' : '');
      tiles.push(tile(AC.fund, '<span class="asm">' + esc(fundName(f.name)) + '</span>', sub, 'afd'));
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

  function applyTab(main, which) {
    which = which === 'full' ? 'full' : 'checks';
    main.dataset.tab = which;
    const c = main.querySelector('#panel-checks'), f = main.querySelector('#panel-full');
    if (c) c.hidden = which !== 'checks';
    if (f) f.hidden = which !== 'full';
    main.querySelectorAll('.rgt-tab[data-tab]').forEach(b => {
      const on = b.dataset.tab === which;
      b.classList.toggle('on', on);
      if (b.tagName === 'BUTTON') b.setAttribute('aria-selected', on ? 'true' : 'false');
    });
  }
  // Both tabs are already in the page. paint fills them; switching only shows one, with no reload.
  function paint(main, P, st) {
    const full = render(main, P);
    const view = summary(main, P, st);
    applyTab(main, main.dataset.tab || 'checks');
    view.total = full.total; view.head = full.head;
    return view;
  }
  window.RegretCompany = { render, summary, paint, applyTab, buildNews, pageSecs, overviewRows, setFirmName };
})();
