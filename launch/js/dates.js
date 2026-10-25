/* Every date a visitor sees goes through RegretDate. Date only: "Mar 15, 2024".
   A time is Pacific: "Mar 15, 2024, 3:58 PM PT". A YYYY-MM-DD with no time is that
   calendar day (not shifted). Firm timelines sort with stamp() (newest first; undated last). */
(function (root) {
  const TZ = 'America/Los_Angeles';
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const MONTH = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, sept: 8, oct: 9, nov: 10, dec: 11,
    january: 0, february: 1, march: 2, april: 3, june: 5, july: 6, august: 7, september: 8, october: 9, november: 10, december: 11 };

  function clean(v) {
    return String(v).trim().replace(/^retrieved\s+/i, '').replace(/\s*\(retrieved\)$/i, '').trim();
  }
  function dateLine(y, m, day) {
    const mi = +m, di = +day;
    if (!(String(y).length === 4 && mi >= 1 && mi <= 12 && di >= 1 && di <= 31)) return '';
    return MON[mi - 1] + ' ' + di + ', ' + y;
  }
  function parts(d) {
    const fmt = new Intl.DateTimeFormat('en-US', {
      timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit',
      hour: 'numeric', minute: '2-digit', hourCycle: 'h12',
    });
    const o = {};
    fmt.formatToParts(d).forEach(p => { if (p.type !== 'literal') o[p.type] = p.value; });
    return o;
  }
  function fromDate(d, withTime) {
    if (!(d instanceof Date) || isNaN(d)) return '';
    const p = parts(d);
    const date = dateLine(p.year, p.month, p.day);
    if (!date) return '';
    if (!withTime) return date;
    const ap = String(p.dayPeriod || '').toUpperCase();
    return date + ', ' + p.hour + ':' + p.minute + (ap ? ' ' + ap : '') + ' PT';
  }
  function hasTime(t) {
    return /[T ]\d{1,2}:\d{2}/.test(t);
  }
  function namedDate(t) {
    const m = t.match(/^([A-Za-z]+)\.?\s+(\d{1,2}),?\s+(\d{4})$/);
    if (!m || MONTH[m[1].toLowerCase()] == null) return '';
    return dateLine(m[3], MONTH[m[1].toLowerCase()] + 1, m[2]);
  }
  function format(v) {
    if (v == null || v === '') return '';
    if (v instanceof Date) return fromDate(v, false);
    const t = clean(v);
    const day = t.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (day) return dateLine(day[1], day[2], day[3]);
    if (hasTime(t)) {
      const d = new Date(t);
      if (!isNaN(d)) return fromDate(d, false);
    }
    return namedDate(t) || t;
  }
  function formatWhen(v) {
    if (v == null || v === '') return '';
    if (v instanceof Date) return fromDate(v, true);
    const t = clean(v);
    if (!hasTime(t)) return format(t);
    const d = new Date(t);
    if (isNaN(d)) return format(t);
    return fromDate(d, true);
  }
  function stamp(v) {
    if (v == null || v === '') return null;
    if (v instanceof Date) return isNaN(v) ? null : v.getTime();
    const t = clean(v);
    const iso = t.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (iso) {
      if (hasTime(t)) {
        const d = new Date(t);
        return isNaN(d) ? null : d.getTime();
      }
      return Date.UTC(+iso[1], +iso[2] - 1, +iso[3]);
    }
    const named = t.match(/^([A-Za-z]+)\.?\s+(\d{1,2}),?\s+(\d{4})/);
    if (named && MONTH[named[1].toLowerCase()] != null) return Date.UTC(+named[3], MONTH[named[1].toLowerCase()], +named[2]);
    return null;
  }
  // Case year shown on a report. Prefer "filed YYYY" / "filed YYYY-MM-DD" from the court text.
  // A future or missing date is blank. A stored year that appears only inside a docket number is not used.
  function caseYear(title, note, stored) {
    const text = [title, note].filter(x => x != null && String(x).trim() !== '').join(' ');
    const now = parts(new Date());
    const yearNow = +now.year;
    const today = yearNow * 10000 + (+now.month) * 100 + (+now.day);
    const filed = text.match(/\bfiled\s+((?:19|20)\d{2})(?:-(\d{2})-(\d{2}))?\b/i);
    if (filed) {
      const y = +filed[1];
      if (filed[2] && filed[3]) {
        const mo = +filed[2], da = +filed[3];
        if (mo < 1 || mo > 12 || da < 1 || da > 31) return '';
        if (y * 10000 + mo * 100 + da > today) return '';
      } else if (y > yearNow) return '';
      return String(filed[1]);
    }
    const raw = stored == null ? '' : String(stored).trim();
    const ym = raw.match(/^((?:19|20)\d{2})\b/);
    if (!ym) return '';
    if (+ym[1] > yearNow) return '';
    if (!text) return ym[1];
    const stripped = text.replace(/\b\d{1,2}:\d{2}-(?:cv|cr|md|mc|bk)-\d{2,6}\b/gi, ' ');
    if (text.indexOf(ym[1]) !== -1 && stripped.indexOf(ym[1]) === -1) return '';
    return ym[1];
  }

  root.RegretDate = { format, formatWhen, stamp, caseYear, TZ };
})(typeof window !== 'undefined' ? window : globalThis);
