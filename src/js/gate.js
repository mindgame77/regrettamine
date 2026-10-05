/* Load a fund report through open_report. The server counts the view and refuses past the cap. */
(function () {
  const slug = document.body && document.body.dataset.firm;
  if (!slug || !window.Regret) return;

  function nudge(seen) {
    const person = Regret.user;
    const total = Regret.capFor(person);
    if (!isFinite(total) || seen.size !== total - 1 || total < 2) return;
    let note = document.getElementById('nudge');
    if (!note) {
      const crumb = document.querySelector('.crumb');
      if (!crumb) return;
      crumb.insertAdjacentHTML('afterend', '<div class="nudge" id="nudge"></div>');
      note = document.getElementById('nudge');
    }
    note.hidden = false;
    note.textContent = '1 free report left. Make it count.';
  }

  function showWait(text) {
    const mount = document.getElementById('report');
    if (!mount) return;
    const card = mount.querySelector('.gatecard');
    if (card) card.remove();
    let note = mount.querySelector('.report-wait');
    if (!note) {
      mount.insertAdjacentHTML('beforeend', '<p class="report-wait"></p>');
      note = mount.querySelector('.report-wait');
    }
    note.textContent = text;
  }

  function ringSvg() {
    const size = 240, stroke = 20, score = 64, r = (size - stroke) / 2, c = 2 * Math.PI * r;
    const off = c * (1 - score / 100), half = size / 2;
    return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 ' + size + ' ' + size + '">'
      + '<defs><linearGradient id="veilrg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#19C37D"/>'
      + '<stop offset=".5" stop-color="#3FA9F5"/><stop offset="1" stop-color="#6C3BFF"/></linearGradient></defs>'
      + '<circle cx="' + half + '" cy="' + half + '" r="' + r + '" stroke="#F1EFF7" stroke-width="' + stroke + '" fill="none"/>'
      + '<circle cx="' + half + '" cy="' + half + '" r="' + r + '" stroke="url(#veilrg)" stroke-width="' + stroke + '" fill="none" stroke-linecap="round" stroke-dasharray="' + c + '" stroke-dashoffset="' + off + '"/>'
      + '</svg>';
  }

  function lorem(n) {
    const line = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore.';
    let out = '';
    for (let i = 0; i < n; i++) out += (i ? ' ' : '') + line;
    return out;
  }

  function veilHtml() {
    const take = [0, 1, 2].map(i =>
      '<article class="tkc t' + i + '"><div class="ix">' + (i + 1) + '</div><h4>Lorem ipsum dolor</h4><p>' + lorem(1) + '</p><div class="src"><span>Lorem source</span><span class="open">Lorem</span></div></article>'
    ).join('');
    const row = '<div class="lrow"><span class="ly">0000</span><span class="ls">Lorem ipsum dolor sit amet<small>Lorem ipsum dolor sit amet</small></span><span class="lr"><span class="rt gray">Lorem</span><span class="chev">›</span></span></div>';
    const bars = ['sb1', 'sb2', 'sb3', 'sb4'].map(cls =>
      '<span class="sb ' + cls + '" style="flex:1 0 0"><span class="fill" style="width:60%"></span></span>'
    ).join('');
    const legs = ['One', 'Two', 'Three', 'Four', 'Five', 'Six'].map(name =>
      '<span class="k1"><span><i></i>' + name + '</span><b>0</b></span>'
    ).join('');
    return '<div class="report-veil" inert aria-hidden="true">'
      + '<div class="meta"><span class="mi">Lorem</span><span class="mi">Ipsum</span><span class="mi">Dolor</span></div>'
      + '<div class="heroW"><span class="rankb"><i>#0</i> of 00 funds</span>'
      + '<span class="float f1"><i style="background:#6C3BFF">L</i>Lorem ipsum <small>lorem</small></span>'
      + '<span class="float f2"><i style="background:#19C37D">L</i>Lorem ipsum <small>lorem</small></span>'
      + '<div class="hero"><div><div class="ringBox">' + ringSvg() + '<div class="num"><div><b>64</b><span>out of 100</span></div></div></div>'
      + '<span class="bandPill">Lorem band</span><span class="rng">lorem 00–00</span></div>'
      + '<div><div class="q">Lorem</div><div class="dv">Lorem ipsum dolor sit amet</div>'
      + '<div class="vsub">' + lorem(1) + '</div>'
      + '<div class="bdgs"><span class="bdg"><i class="dt ok"></i>Lorem ipsum</span><span class="bdg"><i class="dt am"></i>Dolor sit</span></div>'
      + '<div class="ovx"><div class="bart"><span>Lorem ipsum dolor</span><span class="lnk">Lorem</span></div>'
      + '<div class="stk">' + bars + '</div><div class="sleg">' + legs + '</div></div></div></div></div>'
      + '<div class="tabsW"><div class="tabs" role="tablist">'
      + '<button class="on" type="button">Overview</button><button type="button">Score</button>'
      + '<button type="button">Legal <i>0</i></button><button type="button">Fund &amp; people</button>'
      + '<button type="button">Public <i>0</i></button><button type="button">Portfolio</button><button type="button">Ask the fund</button>'
      + '</div></div>'
      + '<section data-panel="overview" class="on"><div class="blk sumb"><div class="lab">Summary</div><div><p class="big">' + lorem(2) + '</p></div></div>'
      + '<div class="sech"><h2 class="h2">Takeaways</h2></div><div class="tkg tk6">' + take + '</div>'
      + '<div class="sech"><h2 class="h2">Top legal matters</h2></div><div class="pc lstc"><div class="lst">' + row + row + '</div></div></section>'
      + '<section data-panel="score" class="on"><div class="scbs"><div class="scb k1"><div class="scbh"><span class="wl">Lorem</span><span class="scbar"><b style="width:40%"></b></span><span class="wv"><b>0</b><small>of 0</small></span></div><p>' + lorem(1) + '</p></div>'
      + '<div class="scb k2"><div class="scbh"><span class="wl">Ipsum</span><span class="scbar"><b style="width:55%"></b></span><span class="wv"><b>0</b><small>of 0</small></span></div><p>' + lorem(1) + '</p></div></div></section>'
      + '<section data-panel="legal" class="on"><div class="pc"><div class="ph3"><h3>Lorem ipsum</h3><small>Lorem</small></div><p>' + lorem(2) + '</p></div></section>'
      + '<section data-panel="fund" class="on"><div class="pc"><h2 class="h2">Lorem ipsum</h2><p>' + lorem(2) + '</p></div></section>'
      + '<section data-panel="public" class="on"><div class="pubh"><h2 class="h2">Lorem</h2></div><a class="pubc"><span class="ph4">Lorem ipsum dolor sit amet</span><span class="sw2"><span class="snt neu">Lorem</span><span class="swy">' + lorem(1) + '</span></span></a></section>'
      + '<section data-panel="portfolio" class="on"><div class="pc"><h2 class="h2">Lorem</h2><p>' + lorem(1) + '</p></div></section>'
      + '<section data-panel="ask" class="on"><div class="askbar"><div><h2 class="h2">Lorem ipsum</h2><p>' + lorem(1) + '</p></div></div></section>'
      + '<p class="fnote">Lorem ipsum dolor sit amet.</p></div>';
  }

  function showVeil(result) {
    const mount = document.getElementById('report');
    if (!mount) return;
    const h1 = mount.querySelector('h1');
    const heading = h1 ? h1.innerHTML : '';
    const crumb = mount.querySelector('.crumb');
    const crumbHtml = crumb ? crumb.outerHTML : '';
    const plans = !!(result && result.plans);
    const pitch = plans ? 'A plan opens this report.' : 'A free account opens this report.';
    const label = plans ? 'See plans' : 'Create account';
    mount.innerHTML = crumbHtml
      + '<div class="fh np"><div><h1>' + heading + '</h1></div></div>'
      + veilHtml()
      + '<div class="gatecard" id="gateCard"><p>' + pitch + '</p>'
      + '<button class="b c" type="button" id="gateJoin">' + label + '</button></div>';
    const join = document.getElementById('gateJoin');
    if (join) {
      join.onclick = () => {
        if (plans) location.href = new URL('plans/', Regret.siteRoot()).href;
        else RegretAuth.open('signup', true);
      };
    }
    document.body.classList.add('gated');
    Regret.paintSave();
  }

  const CACHE = 'regret.reporthtml.v1';
  function hasSession() {
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i) || '';
        if (key.indexOf('sb-') === 0 && key.indexOf('auth-token') !== -1) {
          const raw = localStorage.getItem(key) || '';
          if (raw.indexOf('access_token') !== -1) return true;
        }
      }
    } catch (e) { /* private mode */ }
    return false;
  }
  function readCache(id) {
    try {
      const all = JSON.parse(sessionStorage.getItem(CACHE) || '{}');
      const hit = all[id];
      if (!hit || !hit.html || Date.now() - hit.at > 600000) return '';
      const opened = (Regret.anonState().funds || []).indexOf(id) !== -1;
      if (!opened && !hasSession()) return '';
      return hit.html;
    } catch (e) { return ''; }
  }
  function writeCache(id, html) {
    try {
      const all = JSON.parse(sessionStorage.getItem(CACHE) || '{}');
      all[id] = { html: html, at: Date.now() };
      sessionStorage.setItem(CACHE, JSON.stringify(all));
    } catch (e) { /* quota */ }
  }
  function dropCache(id) {
    try {
      const all = JSON.parse(sessionStorage.getItem(CACHE) || '{}');
      if (!all[id]) return;
      delete all[id];
      sessionStorage.setItem(CACHE, JSON.stringify(all));
    } catch (e) { /* private mode */ }
  }
  function showReport(html, bind) {
    const mount = document.getElementById('report');
    if (!html || !mount) return;
    mount.innerHTML = html;
    if (bind && window.RegretFund) RegretFund.start();
    Regret.paintSave();
    Regret.paintAlert();
  }
  const early = readCache(slug);
  if (early) showReport(early, false);
  const sessionKnown = hasSession() && Regret.sessionReady ? Regret.sessionReady : Promise.resolve();
  sessionKnown.then(() => Regret.loadReport(slug)).then(async (result) => {
    if (!result) {
      if (!early) showWait('This report is not available on this build.');
      return;
    }
    if (!result.ok) {
      if (result.reason === 'limit') {
        dropCache(slug);
        showVeil(result);
        await Regret.paintAlert();
        return;
      }
      if (result.reason === 'unpublished') {
        if (!early) showWait('This report is not available on this build.');
        await Regret.paintAlert();
        return;
      }
      if (!early) showWait('This report is not available on this build.');
      return;
    }
    if (result.html) {
      writeCache(slug, result.html);
      showReport(result.html, true);
    } else if (!early) {
      showWait('This report is not available on this build.');
      await Regret.paintAlert();
    }
    if (result.tier === 'paid') return;
    nudge(await Regret.seen());
  });
})();
