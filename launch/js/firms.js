/* /investors/ directory. Columns are the v3 grid. Filters reuse the
   firm-directory concept-2-filters facet sidebar (Region, Headquarters,
   Industries, Investment stages, Legal records, Recorded information,
   Firm status) from /workspace/regretamin-design/firm-directory. */
(function () {
  // Same parent hues as launch/js/company.js. A sub-industry uses its parent. Other stays slate.
  const SECTOR_PALETTE = ['#4B2BD6', '#14D9A5', '#FFB020', '#FF5C8A', '#2EA8FF', '#8A63F5', '#18BBD4', '#FF9566', '#9EDB51', '#788BFF', '#F26C68', '#42CFC3', '#D781EF', '#E6BE45', '#3773DB', '#EC7DA8', '#77C9A1', '#A7A2C2'];
  const SECTOR_COLORS = {
    'AI agents': '#4B2BD6', 'AI models': '#14D9A5', 'Bio': '#FFB020', 'Climate & Energy': '#FF5C8A',
    'Consumer': '#2EA8FF', 'Crypto': '#8A63F5', 'Developer tools': '#18BBD4', 'Education': '#FF9566',
    'Enterprise software': '#9EDB51', 'Fintech': '#788BFF', 'Food & Agriculture': '#F26C68',
    'Hardware & Robotics': '#42CFC3', 'Health': '#D781EF', 'Media & Gaming': '#E6BE45',
    'Mobility': '#3773DB', 'Real estate': '#EC7DA8', 'Security': '#77C9A1', 'Other': '#A7A2C2',
    'Defense': '#C4622D', 'Space': '#3A4FBF', 'Govtech': '#0E8A6A'
  };
  const SUB_PARENT = {
    'AI infrastructure': 'AI models', 'Payments': 'Fintech', 'Insurtech': 'Fintech', 'Wealth': 'Fintech',
    'Digital health': 'Health', 'Medtech': 'Health', 'Wellness': 'Health', 'Biotech': 'Bio',
    'Commerce': 'Consumer', 'Travel': 'Consumer', 'Sports': 'Consumer',
    'HR Tech': 'Enterprise software', 'Legal Tech': 'Enterprise software', 'Marketing': 'Enterprise software',
    'Cloud & Data': 'Developer tools', 'Cybersecurity': 'Security',
    'Hardware': 'Hardware & Robotics', 'Robotics': 'Hardware & Robotics', 'Semiconductors': 'Hardware & Robotics',
    'Manufacturing': 'Hardware & Robotics', 'Materials': 'Hardware & Robotics', 'Deep tech': 'Hardware & Robotics',
    'Telecom': 'Hardware & Robotics', 'Logistics': 'Mobility', 'Construction': 'Real estate',
    'Media': 'Media & Gaming', 'Gaming': 'Media & Gaming', 'Food': 'Food & Agriculture', 'Agriculture': 'Food & Agriculture'
  };
  const PARENT_OF = {};
  Object.keys(SECTOR_COLORS).forEach(function (name) { PARENT_OF[name.toLowerCase()] = name; });
  Object.keys(SUB_PARENT).forEach(function (name) { PARENT_OF[name.toLowerCase()] = SUB_PARENT[name]; });
  function parentIndustry(name) {
    const s = String(name || '').trim();
    if (!s) return '';
    return PARENT_OF[s.toLowerCase()] || s;
  }
  function sectorColor(name) {
    const s = parentIndustry(name);
    if (!s || /^other$/i.test(s)) return SECTOR_COLORS.Other;
    if (Object.prototype.hasOwnProperty.call(SECTOR_COLORS, s)) return SECTOR_COLORS[s];
    const found = Object.keys(SECTOR_COLORS).find(function (k) { return k.toLowerCase() === s.toLowerCase(); });
    if (found) return SECTOR_COLORS[found];
    const hues = SECTOR_PALETTE.slice(0, 17);
    let h = 2166136261;
    const n = s.toLowerCase();
    for (let i = 0; i < n.length; i++) h = Math.imul(h ^ n.charCodeAt(i), 16777619);
    return hues[(h >>> 0) % hues.length];
  }
  window.RegretSectors = { parentIndustry: parentIndustry, sectorColor: sectorColor };

  const list = document.getElementById('firms-list');
  if (!list) return;

  const root = window.REGRET_ROOT || '';
  const copy = ((window.REGRET || {}).copy || {}).site || {};
  const pageCopy = (copy.pages || {}).investors || {};

  const COUNTRY = { US: 'United States', GB: 'United Kingdom', CH: 'Switzerland', KY: 'Cayman Islands' };
  const REGION = {
    US: 'north_america', CA: 'north_america', MX: 'north_america',
    GB: 'europe', CH: 'europe', IE: 'europe', DE: 'europe', FR: 'europe',
    NL: 'europe', SE: 'europe', NO: 'europe', DK: 'europe', FI: 'europe',
    IT: 'europe', ES: 'europe', AT: 'europe', BE: 'europe', PT: 'europe',
    KY: 'latam', BR: 'latam', AR: 'latam', CL: 'latam', CO: 'latam',
    CN: 'asia', JP: 'asia', KR: 'asia', SG: 'asia', IN: 'asia', HK: 'asia', TW: 'asia',
    ZA: 'africa', NG: 'africa', KE: 'africa', EG: 'africa',
    AE: 'middle_east', IL: 'middle_east', SA: 'middle_east', QA: 'middle_east'
  };
  const REGION_OPTIONS = [
    ['north_america', 'US / North America'],
    ['europe', 'Europe'],
    ['asia', 'Asia'],
    ['latam', 'LatAm'],
    ['africa', 'Africa'],
    ['middle_east', 'Middle East'],
    ['unknown', 'Not disclosed']
  ];

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  function fmtDate(v) {
    return (window.RegretDate && RegretDate.format(v)) || '';
  }
  function stamp(v) {
    return (window.RegretDate && RegretDate.stamp(v)) || 0;
  }
  function roundName(r) {
    return String(r || '').replace(/^stage tag:\s*/i, '').trim();
  }
  function prettyCity(s) {
    const t = String(s || '').trim();
    if (!t) return '';
    if (t === t.toUpperCase() && t.length > 3) {
      return t.toLowerCase().replace(/\b\w/g, c => c.toUpperCase());
    }
    return t;
  }
  function cityLabel(f) {
    return prettyCity(f.city) || COUNTRY[f.country] || '';
  }
  function countryLabel(code) {
    return COUNTRY[code] || code || '';
  }
  function regionOf(f) {
    return REGION[f.country] || (f.country ? 'unknown' : 'unknown');
  }
  function keyOf(s) {
    return String(s || '').trim().toLowerCase();
  }
  function sortNewest(rows) {
    return rows.slice().sort((a, b) => (stamp(b.added) - stamp(a.added)) || String(a.name || '').localeCompare(String(b.name || '')));
  }
  function href(slug) { return (window.REGRET_VC_BASE || '/vc/') + encodeURIComponent(slug) + '/'; }
  function invests(f, max) {
    const rows = Array.isArray(f.industries) ? f.industries.filter(Boolean) : [];
    if (!rows.length) return '';
    const n = max || 2;
    const shown = rows.slice(0, n);
    const more = rows.length - shown.length;
    return shown.map(function (name) {
      return '<span style="color:' + sectorColor(name) + '">' + esc(name) + '</span>';
    }).join(', ') + (more > 0 ? ' +' + more : '');
  }
  function row(f) {
    const date = fmtDate(f.added);
    const city = cityLabel(f);
    const inds = invests(f, 2);
    const dealMain = (f.latest_company && f.latest_deal_date)
      ? [f.latest_company, roundName(f.latest_round)].filter(Boolean).join(' · ') : '';
    const dealDate = (f.latest_company && f.latest_deal_date) ? fmtDate(f.latest_deal_date) : '';
    const dealHtml = dealMain
      ? esc(dealMain) + (dealDate ? ' · <span class="dwhen">' + esc(dealDate) + '</span>' : '')
      : '';
    return '<a class="frow" href="' + href(f.slug) + '">'
      + '<span class="fnm"><b>' + esc(f.name) + '</b></span>'
      + '<span class="fcity">' + esc(city) + '</span>'
      + '<span class="finds">' + inds + '</span>'
      + '<span class="fdeal">' + dealHtml + '</span>'
      + (date ? '<span class="rdt">' + esc(date) + '</span>' : '<span class="rdt"></span>')
      + '</a>';
  }
  function searchMatch(f, query) {
    if (!query) return true;
    const name = String(f.name || '').toLowerCase();
    const short = String(f.short_name || '').toLowerCase();
    const site = String(f.website || '').toLowerCase();
    if (name.indexOf(query) !== -1 || (short && short.indexOf(query) !== -1) || (site && site.indexOf(query) !== -1)) return true;
    const hit = function (s) { return String(s || '').toLowerCase().indexOf(query) !== -1; };
    return (f.startups || []).some(hit) || (f.startup_sites || []).some(hit);
  }
  function optionMatch(arr, value) {
    const want = keyOf(value);
    return (arr || []).some(function (v) { return keyOf(v) === want; });
  }
  function countBy(arr, pick) {
    const c = {};
    arr.forEach(function (f) {
      const v = pick(f);
      c[v] = (c[v] || 0) + 1;
    });
    return c;
  }
  function uniqueOptions(firms, valuesOf, labelOf, valueOf) {
    const labels = {};
    const counts = {};
    firms.forEach(function (f) {
      const seen = {};
      valuesOf(f).forEach(function (raw) {
        if (!raw) return;
        const k = keyOf(typeof raw === 'string' ? raw : valueOf(raw));
        if (!k || seen[k]) return;
        seen[k] = true;
        counts[k] = (counts[k] || 0) + 1;
        const label = typeof raw === 'string' ? raw : labelOf(raw);
        if (!labels[k]) labels[k] = label;
        else if (label !== label.toLowerCase() && labels[k] === labels[k].toLowerCase()) labels[k] = label;
        else if (label.length > labels[k].length) { /* keep existing unless current is clearly preferred */ }
      });
    });
    return Object.keys(counts).map(function (k) {
      return { value: k, label: labels[k], count: counts[k] };
    }).sort(function (a, b) { return (b.count - a.count) || a.label.localeCompare(b.label); });
  }

  // Live data: one call to the read-only firm_directory() RPC with the public anon key.
  // Builds without Supabase config fall back to the build-time firms.json.
  const C = window.REGRET || {};
  function loadFirms() {
    if (C.url && C.key) {
      return fetch(C.url + '/rest/v1/rpc/firm_directory', {
        method: 'POST',
        headers: { apikey: C.key, Authorization: 'Bearer ' + C.key, 'Content-Type': 'application/json' },
        body: '{}'
      }).then(function (r) { if (!r.ok) throw new Error('firm_directory'); return r.json(); })
        .then(function (rows) { return { firms: Array.isArray(rows) ? rows : [] }; });
    }
    return fetch(root + 'firms.json', { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error('firms.json'); return r.json(); });
  }
  loadFirms()
    .then(function (data) {
      const firms = (data && data.firms) || [];
      const q = document.getElementById('firms-q');
      const none = document.getElementById('firms-none');
      const sidebar = document.getElementById('firms-sidebar');
      const groupsEl = document.getElementById('facet-groups');
      const panel = document.getElementById('facet-panel');
      const pageRoot = document.querySelector('.firms-pg');
      const backdrop = document.getElementById('filters-backdrop');
      const openBtn = document.getElementById('filters-open');
      const openBadge = document.getElementById('filters-open-badge');
      let sort = 'newest';
      let asc = false;
      let panelKey = null;
      let draft = [];
      const active = { region: [], industry: [], stage: [], legal: [], info: [], status: [] };

      const regionCounts = countBy(firms, regionOf);
      const regionOpts = REGION_OPTIONS.map(function (pair) {
        return { value: pair[0], label: pair[1], count: regionCounts[pair[0]] || 0 };
      }).sort(function (a, b) { return (b.count - a.count) || a.label.localeCompare(b.label); });

      const countryCounts = countBy(firms, function (f) { return f.country || 'unknown'; });
      const countryOpts = Object.keys(countryCounts).map(function (k) {
        return { value: k, label: k === 'unknown' ? 'Not disclosed' : countryLabel(k), count: countryCounts[k] };
      }).sort(function (a, b) { return (b.count - a.count) || a.label.localeCompare(b.label); });

      const industryOpts = uniqueOptions(firms, function (f) { return f.industries || []; });
      const stageOpts = uniqueOptions(firms, function (f) { return f.stages || []; });

      const legalCounts = countBy(firms, function (f) { return f.legal_status || 'unknown'; });
      const legalOpts = [
        { value: 'unknown', label: 'No result available', count: legalCounts.unknown || 0 },
        { value: 'has', label: 'Has records', count: legalCounts.has || 0 },
        { value: 'none', label: 'None found', count: legalCounts.none || 0 }
      ].sort(function (a, b) { return (b.count - a.count) || a.label.localeCompare(b.label); });

      const infoOpts = [
        { value: 'deals', label: 'Deals in last 12 months', count: firms.filter(function (f) { return f.deals_12m > 0; }).length },
        { value: 'lead', label: 'Led deals in 12 months', count: firms.filter(function (f) { return f.led_12m > 0; }).length },
        { value: 'legal', label: 'Legal / regulatory', count: firms.filter(function (f) { return f.legal_records > 0; }).length }
      ];

      const statusCounts = countBy(firms, function (f) { return f.firm_status || 'Active'; });
      const statusOpts = Object.keys(statusCounts).map(function (k) {
        return { value: k, label: k, count: statusCounts[k] };
      }).sort(function (a, b) { return (b.count - a.count) || a.label.localeCompare(b.label); });

      const GROUPS = {
        region: { title: 'Region', singular: 'regions', options: regionOpts },
        industry: { title: 'Industries', singular: 'industries', options: industryOpts },
        stage: { title: 'Investment stages', singular: 'stages', options: stageOpts },
        legal: { title: 'Legal records', singular: 'legal records', options: legalOpts },
        info: { title: 'Recorded information', singular: 'recorded information', options: infoOpts },
        status: { title: pageCopy.filter_status || 'Investor status', singular: 'statuses', options: statusOpts }
      };

      function selectedCount() {
        return Object.keys(active).reduce(function (n, k) { return n + active[k].length; }, 0);
      }
      function facetOption(o, key, inPanel) {
        const checked = (inPanel ? draft : active[key]).indexOf(o.value) !== -1;
        const color = key === 'industry' ? sectorColor(o.label) : '';
        return '<label class="' + (checked ? 'checked' : '') + '" data-facet="' + esc(key) + '" data-value="' + esc(o.value) + '">'
          + '<input type="checkbox"' + (checked ? ' checked' : '') + (inPanel ? ' data-draft="1"' : '') + '>'
          + '<span class="optlabel"' + (color ? ' style="color:' + color + '"' : '') + ' title="' + esc(o.label) + '">' + esc(o.label) + '</span>'
          + '<span class="optcount">' + o.count + '</span></label>';
      }
      function renderFacets() {
        groupsEl.innerHTML = Object.keys(GROUPS).map(function (key) {
          const g = GROUPS[key];
          const open = panel && !panel.hidden && key === panelKey;
          return '<section class="facet" id="facet-' + key + '"><h4>' + esc(g.title)
            + (active[key].length ? '<span class="facet-badge">' + active[key].length + '</span>' : '') + '</h4>'
            + g.options.slice(0, 5).map(function (o) { return facetOption(o, key, false); }).join('')
            + '<button type="button" class="show-all" data-open="' + esc(key) + '" aria-expanded="' + (open ? 'true' : 'false') + '">Show all (' + g.options.length + ')</button>'
            + '</section>';
        }).join('');
      }
      function updateBadge() {
        const n = selectedCount();
        if (openBadge) {
          openBadge.hidden = !n;
          openBadge.textContent = n ? String(n) : '';
        }
      }
      function matchesFilters(f) {
        if (active.region.length && active.region.indexOf(regionOf(f)) === -1) return false;
        if (active.industry.length && !active.industry.some(function (x) { return optionMatch(f.industries, x); })) return false;
        if (active.stage.length && !active.stage.some(function (x) { return optionMatch(f.stages, x); })) return false;
        if (active.legal.length && active.legal.indexOf(f.legal_status || 'unknown') === -1) return false;
        if (active.status.length && active.status.indexOf(f.firm_status || 'Active') === -1) return false;
        if (active.info.length && !active.info.every(function (x) {
          if (x === 'deals') return f.deals_12m > 0;
          if (x === 'lead') return f.led_12m > 0;
          return f.legal_records > 0;
        })) return false;
        return true;
      }
      function cmpBlankLast(av, bv) {
        const aEmpty = !av;
        const bEmpty = !bv;
        if (aEmpty && bEmpty) return 0;
        if (aEmpty) return 1;
        if (bEmpty) return -1;
        return 0;
      }
      function sorted(rows) {
        const dir = asc ? 1 : -1;
        return rows.slice().sort(function (a, b) {
          if (sort === 'city') {
            const blank = cmpBlankLast(cityLabel(a), cityLabel(b));
            if (blank) return blank;
            const d = cityLabel(a).localeCompare(cityLabel(b));
            return d ? d * dir : String(a.name || '').localeCompare(String(b.name || ''));
          }
          if (sort === 'deal') {
            const blank = cmpBlankLast(a.latest_deal_date, b.latest_deal_date);
            if (blank) return blank;
            const d = stamp(a.latest_deal_date) - stamp(b.latest_deal_date);
            return d ? d * dir : String(a.name || '').localeCompare(String(b.name || ''));
          }
          let d = 0;
          if (sort === 'name') d = String(a.name || '').localeCompare(String(b.name || ''));
          else {
            d = stamp(a.added) - stamp(b.added);
          }
          if (!d) d = String(a.name || '').localeCompare(String(b.name || ''));
          return d * dir;
        });
      }
      function headerCell(key, label) {
        const on = sort === key;
        const arrow = on ? (asc ? '↑' : '↓') : '';
        return '<button type="button" data-sort="' + key + '" class="' + (on ? 'sorted' : '') + '" aria-sort="'
          + (on ? (asc ? 'ascending' : 'descending') : 'none') + '">'
          + esc(label) + (arrow ? '<span class="arrow">' + arrow + '</span>' : '') + '</button>';
      }
      function headHtml() {
        return '<div class="frow h" role="row">'
          + headerCell('name', pageCopy.col_firm || 'Investor')
          + headerCell('city', pageCopy.col_city || 'City')
          + '<span class="hunsortable">' + esc(pageCopy.col_invests || 'Invests in') + '</span>'
          + headerCell('deal', pageCopy.col_deal || 'Latest deal')
          + headerCell('newest', pageCopy.col_added || 'Added')
          + '</div>';
      }

      let chips = [];
      const placeholder = (q && q.getAttribute('placeholder')) || '';

      function searchTerms() {
        const terms = chips.map(function (c) { return c.toLowerCase(); });
        const typed = q && q.value ? q.value.trim().toLowerCase() : '';
        if (typed) terms.push(typed);
        return terms;
      }
      function renderChips() {
        const el = document.getElementById('firms-chips');
        if (!el) return;
        el.innerHTML = chips.map(function (c, i) {
          return '<span class="firms-chip"><span class="firms-chip-text">' + esc(c) + '</span>'
            + '<button type="button" data-chip-x="' + i + '" aria-label="Remove ' + esc(c) + '">×</button></span>';
        }).join('');
        if (q) q.placeholder = chips.length ? '' : placeholder;
      }
      function addChip(raw) {
        const t = String(raw || '').trim();
        if (!t) return false;
        const key = t.toLowerCase();
        if (chips.some(function (c) { return c.toLowerCase() === key; })) return false;
        chips.push(t);
        if (q) q.value = '';
        renderChips();
        try { noteSearch(t); } catch (e) {}
        return true;
      }
      function removeChip(i) {
        if (i < 0 || i >= chips.length) return;
        chips.splice(i, 1);
        renderChips();
      }
      let searchLogTimer = 0;
      const seenSearch = Object.create(null);
      // Directory order is newest first. Prefer an exact name, then a name that starts with the term.
      function noteSearch(raw) {
        try {
          const t = String(raw || '').replace(/\s+/g, ' ').trim();
          const log = window.RegretSearch && window.RegretSearch.log;
          if (t.length < 2 || typeof log !== 'function') return;
          const k = t.toLowerCase();
          if (seenSearch[k]) return;
          seenSearch[k] = 1;
          let n = 0, top = null, rank = 9;
          for (let i = 0; i < firms.length; i++) {
            const f = firms[i];
            if (!searchMatch(f, k)) continue;
            n++;
            const name = String(f.name || '').toLowerCase();
            const short = String(f.short_name || '').toLowerCase();
            const slug = String(f.slug || '').toLowerCase();
            let r = 3;
            if (name === k || short === k || slug === k) r = 0;
            else if (name.indexOf(k) === 0 || (short && short.indexOf(k) === 0) || slug.indexOf(k) === 0) r = 1;
            else if (name.indexOf(k) !== -1 || (short && short.indexOf(k) !== -1)) r = 2;
            if (r < rank && f.slug) { rank = r; top = f.slug; }
          }
          log(t, 'investors', n, top);
        } catch (e) {}
      }
      function armSearchLog() {
        try {
          clearTimeout(searchLogTimer);
          if (!q) return;
          const typed = String(q.value || '').replace(/\s+/g, ' ').trim();
          if (typed.length < 2) return;
          searchLogTimer = setTimeout(function () {
            try {
              if (!q || String(q.value || '').replace(/\s+/g, ' ').trim().toLowerCase() !== typed.toLowerCase()) return;
              noteSearch(typed);
            } catch (e) {}
          }, 1500);
        } catch (e) {}
      }
      function commitTyped() {
        if (!q) return;
        const parts = q.value.split(',');
        let added = false;
        parts.forEach(function (part) { if (addChip(part)) added = true; });
        if (q) q.value = '';
        if (added) renderChips();
      }
      function draw() {
        const terms = searchTerms();
        const shown = sorted(firms.filter(function (f) {
          return matchesFilters(f) && (!terms.length || terms.some(function (t) { return searchMatch(f, t); }));
        }));
        list.innerHTML = headHtml() + shown.map(row).join('');
        if (none) none.hidden = shown.length !== 0;
      }
      function toggleFacet(key, val, on) {
        active[key] = on
          ? Array.from(new Set(active[key].concat([val])))
          : active[key].filter(function (x) { return x !== val; });
        renderFacets();
        updateBadge();
        draw();
      }
      function positionPanel() {
        if (!panel || !panelKey) return;
        const facet = document.getElementById('facet-' + panelKey);
        const side = sidebar;
        if (!facet || !side) return;
        const f = facet.getBoundingClientRect();
        const s = side.getBoundingClientRect();
        let left = s.right + 16;
        let top = f.top - 6;
        const pw = Math.min(594, window.innerWidth - 24);
        if (left + pw > window.innerWidth - 8) left = Math.max(8, window.innerWidth - pw - 8);
        if (top + 200 > window.innerHeight) top = Math.max(8, window.innerHeight - 420);
        if (window.innerWidth <= 900) {
          panel.style.left = '8px';
          panel.style.right = '8px';
          panel.style.top = 'auto';
          panel.style.bottom = '8px';
          panel.style.width = 'auto';
          return;
        }
        panel.style.right = 'auto';
        panel.style.bottom = 'auto';
        panel.style.width = '';
        panel.style.left = left + 'px';
        panel.style.top = top + 'px';
      }
      function renderPanel() {
        if (!panelKey) return;
        const opts = GROUPS[panelKey].options;
        const query = (document.getElementById('facet-search').value || '').toLowerCase();
        const selected = opts.filter(function (o) { return draft.indexOf(o.value) !== -1; });
        const remaining = opts.filter(function (o) {
          return draft.indexOf(o.value) === -1 && o.label.toLowerCase().indexOf(query) !== -1;
        });
        document.getElementById('pinned-options').innerHTML = selected.length
          ? '<div class="list-caption">SELECTED <span>' + selected.length + '</span></div><div class="panel-option-grid">'
            + selected.map(function (o) { return facetOption(o, panelKey, true); }).join('') + '</div>'
          : '';
        document.getElementById('remaining-label').textContent = query
          ? 'MATCHING OPTIONS · ' + remaining.length
          : 'ALL ' + GROUPS[panelKey].title.toUpperCase() + ' · ' + remaining.length;
        document.getElementById('full-options').innerHTML = remaining.length
          ? remaining.map(function (o) { return facetOption(o, panelKey, true); }).join('')
          : '<p class="empty-options">No matching options</p>';
        document.getElementById('draft-count').textContent = draft.length + ' selected';
      }
      function openPanel(key) {
        panelKey = key;
        draft = active[key].slice();
        panel.hidden = false;
        document.getElementById('facet-search').value = '';
        document.getElementById('panel-title').textContent = GROUPS[key].title;
        document.getElementById('panel-total').textContent = GROUPS[key].options.length + ' options';
        document.getElementById('facet-search').placeholder = 'Search ' + GROUPS[key].singular;
        positionPanel();
        renderFacets();
        renderPanel();
      }
      function closePanel() {
        if (panel) panel.hidden = true;
        panelKey = null;
        renderFacets();
      }
      function applyPanel() {
        if (!panelKey) return;
        active[panelKey] = draft.slice();
        closePanel();
        updateBadge();
        draw();
      }
      function openMobile() {
        if (pageRoot) pageRoot.classList.add('filters-open');
        if (backdrop) backdrop.hidden = false;
        if (openBtn) openBtn.setAttribute('aria-expanded', 'true');
      }
      function closeMobile() {
        if (pageRoot) pageRoot.classList.remove('filters-open');
        if (backdrop) backdrop.hidden = true;
        if (openBtn) openBtn.setAttribute('aria-expanded', 'false');
      }

      groupsEl.addEventListener('change', function (e) {
        const input = e.target.closest('input[type="checkbox"]');
        if (!input) return;
        const label = input.closest('label');
        if (!label) return;
        toggleFacet(label.getAttribute('data-facet'), label.getAttribute('data-value'), input.checked);
      });
      groupsEl.addEventListener('click', function (e) {
        const btn = e.target.closest('.show-all');
        if (btn) openPanel(btn.getAttribute('data-open'));
      });
      panel.addEventListener('change', function (e) {
        const input = e.target.closest('input[type="checkbox"]');
        if (!input || !input.hasAttribute('data-draft')) return;
        const label = input.closest('label');
        const val = label.getAttribute('data-value');
        draft = input.checked
          ? Array.from(new Set(draft.concat([val])))
          : draft.filter(function (x) { return x !== val; });
        renderPanel();
      });
      document.getElementById('panel-close').addEventListener('click', closePanel);
      document.getElementById('panel-clear').addEventListener('click', function () { draft = []; renderPanel(); });
      document.getElementById('panel-apply').addEventListener('click', applyPanel);
      document.getElementById('facet-search').addEventListener('input', renderPanel);
      document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') { closePanel(); closeMobile(); }
      });
      document.addEventListener('mousedown', function (e) {
        if (panel && !panel.hidden && !panel.contains(e.target) && !e.target.closest('.show-all')) closePanel();
      });
      if (openBtn) openBtn.addEventListener('click', function () {
        if (pageRoot && pageRoot.classList.contains('filters-open')) closeMobile();
        else openMobile();
      });
      if (backdrop) backdrop.addEventListener('click', closeMobile);
      window.addEventListener('resize', function () {
        if (panel && !panel.hidden) positionPanel();
        if (window.innerWidth > 900) closeMobile();
      });
      list.addEventListener('click', function (e) {
        const btn = e.target.closest('.frow.h [data-sort]');
        if (!btn) return;
        e.preventDefault();
        const key = btn.getAttribute('data-sort');
        if (sort === key) asc = !asc;
        else {
          sort = key;
          asc = (key === 'name' || key === 'city');
        }
        draw();
      });
      if (q) {
        q.addEventListener('input', function () {
          if (q.value.indexOf(',') !== -1) {
            const parts = q.value.split(',');
            const rest = parts.pop();
            let added = false;
            parts.forEach(function (part) { if (addChip(part)) added = true; });
            q.value = rest.replace(/^\s+/, '');
            if (added) renderChips();
          }
          draw();
          try { armSearchLog(); } catch (e) {}
        });
        q.addEventListener('keydown', function (e) {
          if (e.isComposing || e.keyCode === 229) return;
          if (e.key === 'Enter') {
            e.preventDefault();
            try { clearTimeout(searchLogTimer); } catch (e2) {}
            if (q.value.trim()) { commitTyped(); draw(); }
          } else if (e.key === 'Backspace' && !q.value && chips.length) {
            e.preventDefault();
            removeChip(chips.length - 1);
            if (q) q.focus();
            draw();
          }
        });
      }
      const chipBox = document.getElementById('firms-chips');
      if (chipBox) chipBox.addEventListener('click', function (e) {
        const btn = e.target.closest('[data-chip-x]');
        if (!btn) return;
        e.preventDefault();
        e.stopPropagation();
        removeChip(Number(btn.getAttribute('data-chip-x')));
        if (q) q.focus();
        draw();
      });

      renderFacets();
      updateBadge();
      draw();
    })
    .catch(function () { /* keep the empty list if firms.json is missing */ });
})();

/* Filters scroll with the page. When the sidebar is taller than the window, its sticky
   top is negative so it stops once its bottom (Investor status) is in view, and the list
   keeps scrolling. Phones (900px or less) use the drawer instead. */
(function () {
  function fit() {
    const s = document.getElementById('firms-sidebar');
    if (!s) return;
    if (innerWidth <= 900) { s.style.top = ''; return; }
    const h = s.offsetHeight;
    s.style.top = (h + 32 > innerHeight ? innerHeight - h - 16 : 16) + 'px';
  }
  addEventListener('resize', fit);
  addEventListener('load', fit);
  document.addEventListener('DOMContentLoaded', fit);
  if (window.ResizeObserver) {
    const ro = new ResizeObserver(fit);
    ro.observe(document.documentElement);
    const s = document.getElementById('firms-sidebar');
    if (s) ro.observe(s);
  }
})();
