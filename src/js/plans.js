/* Pricing buttons open Stripe Payment Links. Visitors sign in first. */
(function () {
  const TEST_KEY = 'regret.stripeTest';

  function cfg() {
    return window.REGRET_STRIPE || {};
  }

  function testWanted() {
    if (new URLSearchParams(location.search).get('test') === '1') return true;
    try { return sessionStorage.getItem(TEST_KEY) === '1'; }
    catch (e) { return false; }
  }

  function showTest() {
    const on = testWanted();
    document.querySelectorAll('[data-checkout="test"]').forEach(el => { el.hidden = !on; });
  }

  function linkFor(plan) {
    const stripe = cfg();
    if (plan === 'annual') return stripe.annualLink || '';
    if (plan === 'test') return stripe.testLink || '';
    return stripe.monthlyLink || '';
  }

  showTest();

  document.querySelectorAll('[data-checkout]').forEach(btn => {
    btn.addEventListener('click', async () => {
      const plan = btn.dataset.checkout || 'monthly';
      if (plan === 'test') {
        try { sessionStorage.setItem(TEST_KEY, '1'); } catch (e) { /* private mode */ }
      }
      await Regret.ready;
      if (!Regret.user) {
        location.href = new URL('login/', Regret.siteRoot()).href + '?next=plans/';
        return;
      }
      const link = linkFor(plan);
      if (!link) return;
      const url = new URL(link);
      url.searchParams.set('client_reference_id', Regret.user.id);
      if (Regret.user.email) url.searchParams.set('prefilled_email', Regret.user.email);
      location.href = url.href;
    });
  });
})();
