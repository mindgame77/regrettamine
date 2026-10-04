/* One fund list. The landing page, the watchlist, and report history all call this. */
(function (global) {
  const BANDS = [['Very low risk', 'Very low', '#19C37D'], ['Low risk', 'Low', '#7BD3A8'], ['Moderate', 'Moderate', '#F2B705'], ['Elevated', 'Elevated', '#FF6B4A'], ['High', 'High', '#D7263D']];
  const BOOKMARK = '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M6 6a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v14l-6-4.2L6 20z"/></svg>';
  const EMPTY = '<div class="empty"><b>No funds match these filters.</b>Try widening the score range or clearing a filter.</div>';

  function bandColor(b) {
    return (BANDS.find(x => x[0] == b) || [0, 0, '#ccc'])[2];
  }
  function fmtAum(a) {
    return '$' + (a >= 10 ? a.toFixed(a % 1 ? 1 : 0) : a.toFixed(1)) + 'B';
  }
  function ring(s, size, stroke, color) {
    const r = (size - stroke) / 2, c = 2 * Math.PI * r;
    return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${r}" stroke="#F1EFF7" stroke-width="${stroke}" fill="none"/><circle cx="${size / 2}" cy="${size / 2}" r="${r}" stroke="${color}" stroke-width="${stroke}" fill="none" stroke-linecap="round" stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - s / 100)}"/></svg>`;
  }
  function grad() {
    return `<svg width="0" height="0" style="position:absolute"><defs><linearGradient id="g2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6C3BFF"/><stop offset="1" stop-color="#19C37D"/></linearGradient></defs></svg>`;
  }
  function fundHref(f, prefix) {
    if (!f.report) return '#';
    return (prefix || '') + 'vc/' + f.report + '/';
  }
  function countHtml(n, total) {
    return `${n} ${n == 1 ? 'fund' : 'funds'}<small>of ${total}</small>`;
  }
  function row(f, opts) {
    opts = opts || {};
    const href = fundHref(f, opts.prefix || '');
    const mark = opts.bookmark
      ? `<button type="button" class="bm" data-remove="${f.id}" data-tip="Remove" aria-label="Remove from watchlist">${BOOKMARK}</button>`
      : '';
    return `<a class="tr2${f.v2 ? ' feat' : ''}" href="${href}" data-fund="${f.id}" title="${f.report ? 'Open full report' : 'Full report coming soon'}"><div class="nm"><b>${f.name}</b><div class="m">${f.hq} · since ${f.since}</div></div>
 <div class="sc"><div class="mring">${ring(f.score, 38, 4.5, f.v2 ? 'url(#g2)' : '#C9C5D9')}<b style="${f.v2 ? '' : 'color:#A9A5BD'}">${f.score}</b></div><div><span class="bands"><i style="background:${bandColor(f.band)}"></i>${f.band}</span><span class="tag ${f.v2 ? 'v2' : 'old'}">${f.v2 ? 'v2 · likely ' + f.lo + '–' + f.hi : 'old method'}</span></div></div>
 <div title="${f.legalNote}"><span class="lgc ${f.legal ? 'r' : 'g'}">${f.legal ? f.legal + ' active' : 'None found'}</span></div>
 <div><b>${fmtAum(f.aum)}</b><div class="m">${f.aumAsOf}${f.aumStale ? ' · stale' : ''}</div></div>
 <div>${f.updatedS}</div>
 ${mark}</a>`;
  }
  function table(funds, opts) {
    opts = opts || {};
    const head = `<div class="tr2 th"><div>Fund</div><div>Score</div><div>Active legal</div><div>AUM</div><div>Last update</div>${opts.bookmark ? '<div></div>' : ''}</div>`;
    const body = funds.map(f => row(f, opts)).join('') || (opts.empty || EMPTY);
    return grad() + `<div class="tbl${opts.bookmark ? ' bm' : ''}">${head}${body}</div>`;
  }
  function mount(el, funds, opts) {
    opts = opts || {};
    const total = opts.total != null ? opts.total : funds.length;
    const note = opts.note != null ? opts.note : '<span class="none">No filters applied · showing every fund we track</span>';
    el.innerHTML = `<div class="rbar"><span class="cnt">${countHtml(funds.length, total)}</span><div class="active" style="margin:0 0 0 8px">${note}</div></div>` + table(funds, opts);
  }

  global.FundList = { BANDS, bandColor, fmtAum, ring, grad, fundHref, countHtml, row, table, mount };
})(window);
