/* Stripe Payment Links. MODE picks which set the site uses; flip to "live" to go live.
   test (sandbox): monthly price_1UMuSQHcbGkfjKgmtUM0PxPv ($49/mo), annual price_1UMuSWHcbGkfjKgmMveP00K0 ($352.80/yr), test price_1UMuSXHcbGkfjKgmGdpD1xxa ($1 once)
   live:           monthly price_1UTpaJHcbGkfjKgmRMq6sZZe ($49/mo), annual price_1UTpaJHcbGkfjKgmInanAnB3 ($352.80/yr), test price_1UMuZWHcbGkfjKgmqk9VD909 ($1 once)
   Live links have allow_promotion_codes on, so Stripe promotion codes Alex creates work at checkout with no site change. */
(function () {
  const MODE = "test";
  const LINKS = {
    test: {
      monthlyLink: "https://buy.stripe.com/test_bJedR97cM6zM82XcM48Vi02",
      annualLink: "https://buy.stripe.com/test_8x2fZh7cM2jwab5bI08Vi03",
      testLink: "https://buy.stripe.com/test_28E5kDdBaf6iab58vO8Vi00",
      portalUrl: "https://billing.stripe.com/p/login/test_6oU7sL0OoaQ23MHdQ88Vi01"
    },
    live: {
      monthlyLink: "https://buy.stripe.com/bJedR97cM6zM82XcM48Vi02",
      annualLink: "https://buy.stripe.com/8x2fZh7cM2jwab5bI08Vi03",
      testLink: "https://buy.stripe.com/6oU7sL0OoaQ23MHdQ88Vi01",
      portalUrl: "" /* TODO: live customer-portal login link from Stripe Dashboard > Settings > Billing > Customer portal */
    }
  };
  window.REGRET_STRIPE = Object.assign({ mode: MODE }, LINKS[MODE]);
})();
