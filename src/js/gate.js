/* Count a report after it has stayed open, then show the register or paywall card. */
(function () {
  const slug = document.body && document.body.dataset.firm;
  if (!slug || !window.Regret) return;

  function nudge(seen) {
    const person = Regret.user;
    const total = Regret.capFor(person);
    if (seen.size !== total - 1 || total < 2) return;
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

  Regret.ready.then(async () => {
    const seen = await Regret.seen();
    if (seen.has(slug)) {
      Regret.touch(slug);
      nudge(seen);
      return;
    }
    if (seen.size >= Regret.capFor(Regret.user)) {
      document.body.classList.add('gated');
      if (!Regret.user) RegretAuth.open('signup', true);
      else if (!Regret.confirmed(Regret.user)) RegretAuth.open('confirm', false);
      else RegretAuth.open('paywall', false);
      return;
    }
    const timer = setTimeout(async () => {
      await Regret.record(slug, 'report');
      nudge(await Regret.seen());
    }, Regret.limits.dwell || 2000);
    window.addEventListener('pagehide', () => clearTimeout(timer));
  });
})();
