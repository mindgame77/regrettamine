/* Pricing buttons open Stripe Payment Links. A paid member switches in the portal. */
(function () {
  const TEST_KEY = 'regret.stripeTest';
  const START = { monthly: '{{sjs:plans.start_cta|monthly}}', annual: '{{sjs:plans.start_cta|annual}}', test: '{{sjs:plans.start_cta|test}}' };

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

  function paidPlan(data) {
    if (!data) return '';
    if (data.plan === '{{sjs:page.plans.monthly}}' || data.plan === '{{sjs:page.plans.annual}}' || data.plan === '{{sjs:js.plans.paid}}') return data.plan;
    if (data.tier === 'paid') return '{{sjs:js.plans.paid}}';
    return '';
  }

  function paintPlans(plan) {
    document.querySelectorAll('[data-checkout]').forEach(btn => {
      const which = btn.dataset.checkout || '';
      if (!plan) {
        btn.disabled = false;
        btn.textContent = START[which] || btn.textContent;
        delete btn.dataset.action;
        return;
      }
      if (which === 'test') {
        btn.hidden = true;
        btn.dataset.action = 'switch';
        return;
      }
      const current = (which === 'monthly' && plan === '{{sjs:page.plans.monthly}}') || (which === 'annual' && plan === '{{sjs:page.plans.annual}}');
      if (current) {
        btn.disabled = true;
        btn.textContent = '{{sjs:js.plans.current_plan}}';
        btn.dataset.action = 'current';
      } else {
        btn.disabled = false;
        btn.textContent = '{{sjs:js.plans.switch_plan}}';
        btn.dataset.action = 'switch';
      }
    });
    if (!plan) showTest();
  }

  async function billing() {
    if (!Regret.sb || !Regret.sb()) return null;
    const { data } = await Regret.sb().rpc('my_billing');
    return data;
  }

  async function refreshPlans() {
    await Regret.ready;
    if (!Regret.user) {
      paintPlans('');
      return;
    }
    paintPlans(paidPlan(await billing()));
  }

  function openPortal() {
    if (window.Regret && typeof Regret.openBillingPortal === 'function') {
      Regret.openBillingPortal();
      return;
    }
    const portal = cfg().portalUrl || '';
    if (portal) location.href = portal;
  }

  showTest();
  refreshPlans();
  if (window.Regret && Regret.onChange) Regret.onChange(() => { refreshPlans(); });

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
      const current = paidPlan(await billing());
      paintPlans(current);
      if (current) {
        const mine = (plan === 'monthly' && current === '{{sjs:page.plans.monthly}}') || (plan === 'annual' && current === '{{sjs:page.plans.annual}}');
        if (mine || btn.disabled) return;
        openPortal();
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
