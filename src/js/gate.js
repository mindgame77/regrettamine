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

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
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

  function scoreRing(score) {
    const size = 180, stroke = 12, r = (size - stroke) / 2, c = 2 * Math.PI * r;
    const off = c * (1 - Math.max(0, Math.min(100, score)) / 100);
    return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 ' + size + ' ' + size + '">'
      + '<circle cx="' + (size / 2) + '" cy="' + (size / 2) + '" r="' + r + '" stroke="#F1EFF7" stroke-width="' + stroke + '" fill="none"/>'
      + '<circle cx="' + (size / 2) + '" cy="' + (size / 2) + '" r="' + r + '" stroke="#6C3BFF" stroke-width="' + stroke + '" fill="none" stroke-linecap="round" stroke-dasharray="' + c + '" stroke-dashoffset="' + off + '"/>'
      + '</svg>';
  }

  function showClosed(result) {
    const mount = document.getElementById('report');
    if (!mount) return;
    const wait = mount.querySelector('.report-wait');
    if (wait) wait.remove();
    const summary = (result && result.summary) || {};
    const score = summary.score == null || summary.score === '' ? null : Number(summary.score);
    const band = summary.band || '';
    const range = summary.lo != null && summary.hi != null ? 'likely ' + summary.lo + '–' + summary.hi : '';
    let card = mount.querySelector('.gatecard');
    if (!card) {
      mount.insertAdjacentHTML('beforeend', '<div class="gatecard" id="gateCard"></div>');
      card = mount.querySelector('.gatecard');
    }
    const ring = score == null || !isFinite(score) ? '' : '<div class="ringBox">' + scoreRing(score) + '<div class="num"><div><b>' + esc(score) + '</b><span>out of 100</span></div></div></div>';
    card.innerHTML = ring
      + (band ? '<span class="bandPill">' + esc(band) + '</span>' : '')
      + (range ? '<div class="rng">' + esc(range) + '</div>' : '')
      + '<p>The score is here. The full report opens with an account.</p>'
      + '<button class="b c" type="button" id="gateJoin">Create account to see the full report</button>';
    const join = document.getElementById('gateJoin');
    if (join) join.onclick = () => RegretAuth.open(Regret.user ? 'paywall' : 'signup', !Regret.user);
  }

  Regret.ready.then(async () => {
    const result = await Regret.loadReport(slug);
    if (!result) {
      showWait('This report is not available on this build.');
      return;
    }
    if (!result.ok) {
      if (result.plans) {
        location.href = new URL('plans/', Regret.siteRoot()).href;
        return;
      }
      if (result.reason === 'unpublished') {
        showWait('This report is not available on this build.');
        await Regret.paintAlert();
        return;
      }
      showClosed(result);
      document.body.classList.add('gated');
      await Regret.paintAlert();
      if (!Regret.user) RegretAuth.open('signup', true);
      else RegretAuth.open('paywall', false);
      return;
    }
    const mount = document.getElementById('report');
    if (result.html && mount) {
      mount.innerHTML = result.html;
      if (window.RegretFund) RegretFund.start();
      Regret.paintSave();
      await Regret.paintAlert();
    } else {
      showWait('This report is not available on this build.');
      await Regret.paintAlert();
    }
    if (result.tier === 'paid') return;
    nudge(await Regret.seen());
  });
})();
