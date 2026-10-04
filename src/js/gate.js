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
    let note = mount.querySelector('.report-wait');
    if (!note) {
      mount.insertAdjacentHTML('beforeend', '<p class="report-wait"></p>');
      note = mount.querySelector('.report-wait');
    }
    note.textContent = text;
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
