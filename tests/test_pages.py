"""The account lists reuse the landing fund list, and the auth pages build."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_shared_list_and_auth_pages(monkeypatch):
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.delenv("SUPABASE_ANON_KEY", raising=False)
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "sb_secret_service_role_test")
    from build import main, render_fund_page, load_local

    main()
    home_js = (ROOT / "src" / "js" / "home.js").read_text(encoding="utf-8")
    list_js = (ROOT / "src" / "js" / "fund-list.js").read_text(encoding="utf-8")
    account_js = (ROOT / "src" / "js" / "account.js").read_text(encoding="utf-8")
    auth_js = (ROOT / "src" / "js" / "auth.js").read_text(encoding="utf-8")
    assert "FundList.table" in home_js
    assert "old method" not in home_js
    assert "Active legal" in list_js
    assert "FundList.mount" in account_js
    assert "old method" not in account_js
    assert "signInWithOAuth" in auth_js
    assert "provider: 'google'" in auth_js
    assert "signInWithOtp" not in auth_js
    assert "github" not in auth_js.lower()

    index = (ROOT / "site" / "index.html").read_text(encoding="utf-8")
    account = (ROOT / "site" / "account" / "index.html").read_text(encoding="utf-8")
    fund = (ROOT / "site" / "vc" / "a16z" / "index.html").read_text(encoding="utf-8")
    assert "css/list.css" in index and "js/fund-list.js" in index
    assert 'id="wlOut"' in account and 'id="hsOut"' not in account
    assert 'class="acc pane"' in account
    assert account.index('data-view="watchlist"') < account.index('id="wlOut"') < account.index('data-view="share"')
    assert 'data-v="history"' not in account and ">History<" not in account
    assert 'data-view="watchlist"' in account and 'data-view="share"' in account
    assert 'data-view="alerts"' not in account and 'id="fundAlerts"' not in account
    redirect = (ROOT / "site" / "account" / "alerts" / "index.html").read_text(encoding="utf-8")
    assert "#watchlist" in redirect
    assert 'id="share"' not in account
    assert "js/fund-list.js" in account and "css/list.css" in account
    assert 'class="save"' in fund and 'data-firm="a16z"' in fund
    assert 'id="alertTog"' in fund and "Open this report to get alerts" in fund
    full_report = render_fund_page(load_local()[1]["a16z"], "../../")
    assert "out of 100" in full_report and 'id="evidence"' in full_report
    from build import assign_list_ranks
    _, ranked_funds = load_local()
    assign_list_ranks(ranked_funds)
    assert '<i>#1</i> of 11 funds' in render_fund_page(ranked_funds["a16z"], "../../")
    assert "Top 1" not in render_fund_page(ranked_funds["a16z"], "../../")
    assert '<i>#2</i> of 11 funds' in render_fund_page(ranked_funds["battery"], "../../")
    assert '<i>#3</i> of 11 funds' in render_fund_page(ranked_funds["bessemer"], "../../")
    assert '<i>#6</i> of 11 funds' in render_fund_page(ranked_funds["generalcatalyst"], "../../")
    assert "out of 100" not in fund and 'id="evidence"' not in fund
    assert "Loading the report…" in fund
    accel = (ROOT / "site" / "vc" / "accel" / "index.html").read_text(encoding="utf-8")
    assert "Accel <span>I</span>" in accel
    assert "Accel <span>Accel</span>" not in accel
    assert not (ROOT / "site" / "data" / "funds").exists()
    assert (ROOT / "site" / "login" / "index.html").is_file()
    assert (ROOT / "site" / "login" / "reset" / "index.html").is_file()
    config = (ROOT / "site" / "js" / "supabase-config.js").read_text(encoding="utf-8")
    assert "REGRET_CONFIG" in config
    assert "sb_secret" not in config
    assert "service_role" not in config
    shipped = []
    for path in (ROOT / "site").rglob("*"):
        if path.is_file():
            shipped.append(path.read_text(encoding="utf-8", errors="ignore"))
    assert "sb_secret_service_role_test" not in "\n".join(shipped)

    login = (ROOT / "site" / "login" / "index.html").read_text(encoding="utf-8")
    reset = (ROOT / "site" / "login" / "reset" / "index.html").read_text(encoding="utf-8")
    privacy = (ROOT / "site" / "privacy" / "index.html").read_text(encoding="utf-8")
    terms = (ROOT / "site" / "terms" / "index.html").read_text(encoding="utf-8")
    assert 'href="privacy/"' in index and 'href="terms/"' in index
    assert 'href="../../privacy/"' in fund and 'href="../../terms/"' in fund
    assert 'href="../privacy/"' in account and 'href="../terms/"' in account
    assert 'href="../privacy/"' in login and 'href="../terms/"' in login
    assert 'href="../../privacy/"' in reset and 'href="../../terms/"' in reset
    assert "By creating an account you agree to the" in auth_js
    assert "terms/" in auth_js and "privacy/" in auth_js
    assert 'class="agree up-only"' in auth_js
    assert "Privacy Policy" in privacy and "Terms of Service" in terms
    mailto = '<a href="mailto:malytskyyo@gmail.com">malytskyyo@gmail.com</a>'
    assert "Know Your Group INC." in privacy and "Alex Malytskyy" not in privacy
    assert privacy.count(mailto) == 3 and privacy.count('class="ph"') == 0
    assert "Know Your Group INC." in terms and "Alex Malytskyy" not in terms
    assert terms.count(mailto) == 1 and terms.count('class="ph"') == 0
    assert terms.count("the State of Delaware") == 2
    assert "State of Delaware, USA" not in terms
    assert ">jurisdiction<" not in terms and ">contact email<" not in terms
    assert "within 30 days of account deletion, and from backups within 90 days" in privacy
    assert "Payments (later)" not in privacy and "once paid plans launch" not in privacy
    assert "We never store card numbers" in privacy and "<b>Stripe</b>" in privacy
    assert "name and website" in privacy
    assert "at most 30 days after you submit them" in privacy
    assert 'class="ph">30 days' not in privacy and 'class="ph">90 days' not in privacy
    assert "limited to the greater of USD 100 or the amount you paid us in the 12 months before the claim" in terms
    assert "delete your account yourself in Settings" in terms
    assert "by emailing us" not in terms
    assert "Monthly at $49" in terms and "Annual at $352.80" in terms
    assert "Settings &gt; Billing" in terms or "Settings > Billing" in terms
    assert "24 hours" in terms and "Stripe processes payments" in terms
    assert "account settings" not in terms
    assert 'href="../terms/#corrections"' in privacy
    assert "How are you connected?" in account
    assert "Pitched but no deal" in account and "Co-investor" in account
    assert 'data-dim="honesty"' in account and 'data-dim="support_after_check"' in account
    assert 'data-dim="founder_friendly_terms"' in account and 'data-dim="responsiveness"' in account
    assert 'data-dim="hard_times"' in account
    assert "linkedin.com/in/your-name" in account
    assert "work_email" not in account and "cap_table" not in account
    assert "FundList.ring" in account_js and "connection_type" in account_js
    assert "first_hand" not in account_js and "verification_status" not in account_js

    auth_css = (ROOT / "src" / "css" / "auth.css").read_text(encoding="utf-8")
    assert ".auth .pw2-row{display:none}" in auth_css
    assert ".auth[data-mode=signup] .pw2-row,.auth[data-mode=reset] .pw2-row{display:flex}" in auth_css
    assert ".auth[data-mode=reset] .email-row{display:none}" in auth_css
    assert ".auth[data-mode=forgot] .pw-row" in auth_css
    assert auth_js.count("Those passwords don\\'t match.") == 2
    assert 'id="authPassword2"' in auth_js
    assert "Confirm password" in auth_js

    how = (ROOT / "site" / "how" / "index.html").read_text(encoding="utf-8")
    scoring = (ROOT / "site" / "scoring" / "index.html").read_text(encoding="utf-8")
    assert "location.replace('../scoring/')" in how
    assert 'url=../scoring/' in how
    assert "We pull the public record." not in how
    assert "Court dockets, regulator filings, press and founder reviews" not in scoring
    assert "From public record to score." in scoring
    assert "We pull the public record." in scoring
    assert scoring.count("It counts only if it links, names the fund and shows its role.") == 1
    assert scoring.count("0 to 100, higher is safer") == 1
    assert "Copycat names are excluded." in scoring
    assert "Anonymous-only claims don't count." in scoring
    assert "Read the report, save the fund, get alerts when it changes." in scoring
    assert "What we check" in scoring
    assert 'href="#rules"' in scoring
    assert 'href="../login/?mode=signup"' in scoring
    assert 'href="../account/#share">Request a correction' not in scoring
    assert 'id="correctionsCard" hidden' in scoring
    assert 'id="correctForm"' in scoring and 'id="correctSource"' in scoring
    assert "No account needed." not in scoring and "It's free" not in scoring
    assert "Spotted a wrong fact?" in scoring
    assert "How the score works." in scoring
    assert "Plans are coming" not in scoring
    assert "Request a correction" in scoring
    admin = (ROOT / "site" / "admin" / "index.html").read_text(encoding="utf-8")
    assert 'id="reviewQueue"' in admin and 'id="correctionQueue"' in admin
    assert "Founder reviews" in admin and "Corrections" in admin
    assert "−0.5 for each calendar year with at least one partner departure, up to −2" in scoring
    assert "Partner departures cost points, up to" not in scoring
    assert "Old method." not in scoring
    assert "95.4" in scoring and "coverage 39%" in scoring
    assert 'class="stk"' in scoring and 'class="scbs"' in scoring
    assert 'href="../vc/a16z/"' in scoring
    assert "__SCORE_EXAMPLE__" not in scoring
    assert "How it works" not in index and "how/" not in index

    home_payload = json.loads(index.split('id="home-data" type="application/json">', 1)[1].split("</script>", 1)[0])
    assert [fund["id"] for fund in home_payload["funds"]] == ["a16z", "battery", "bessemer"]
    assert home_payload["fundTotal"] == 11
    assert {fund["id"] for fund in home_payload["funds"]}.isdisjoint({"accel", "sequoia", "insightpartners"})
    assert len(home_payload["updates"]) == 8
    assert all(item["no"] != 9 for item in home_payload["updates"])
    assert "Ten funds" not in index
    published_home = json.loads((ROOT / "site" / "data" / "home.json").read_text(encoding="utf-8"))
    assert published_home["funds"] == home_payload["funds"]
    assert (ROOT / "site" / "vc" / "accel" / "index.html").is_file()
    assert 'placeholder="Andreessen Horowitz"' in index
    assert "Search a VC fund" not in index and 'class="hints"' not in index
    assert "Higher score = safer" not in index and "No filters applied" not in index
    assert "All 11 funds are on Toxy Score v2" not in index
    assert "Toxy, unverified" not in list_js and 'class="ar"' not in list_js
    assert "grid-template-columns:2.3fr 1.7fr 1.1fr 1fr 1fr;" in (ROOT / "src" / "css" / "list.css").read_text(encoding="utf-8")
    assert "font-size:64px" in (ROOT / "src" / "css" / "home.css").read_text(encoding="utf-8")
    assert "Log in to see all" in home_js and "fact_record_count" in home_js and "FEED_SHOWN = 7" in home_js
    assert "landing_funds" in auth_js and "list-only" in auth_js
    assert "loadReport" in auth_js and "open_report" in auth_js
    assert "search_funds" in home_js and "plans/" in home_js
    gate_js = (ROOT / "src" / "js" / "gate.js").read_text(encoding="utf-8")
    assert "plans/" in gate_js and "loadReport" in gate_js
    assert "Create account to see the full report" in gate_js and "showClosed" in gate_js
    plans = (ROOT / "site" / "plans" / "index.html").read_text(encoding="utf-8")
    assert "Check first." in plans and "Sign second" in plans
    assert "One plan with everything. Pay monthly or yearly." in plans
    assert "$49" in plans and "$29.40" in plans and "$352.80" in plans and "$588" in plans
    assert "Save 40%" in plans and "Recommended" in plans
    assert plans.count("Every fund report, no limit") == 2
    assert plans.count("Alerts on the funds you watch") == 2
    assert plans.count("Watchlist up to 100 funds") == 2
    assert "Not ready? Read 2 reports free, and 5 more with a free account." in plans
    assert 'data-checkout="monthly"' in plans and 'data-checkout="annual"' in plans
    assert "stripe.com" not in plans and "checkout.stripe" not in plans
    assert "Paid plans are coming soon." not in plans
    assert 'data-checkout="test"' in plans and "$1 test purchase" in plans
    assert 'src="../js/plans.js"' in plans and 'src="../js/stripe-config.js"' in plans
    stripe_cfg = (ROOT / "src" / "js" / "stripe-config.js").read_text(encoding="utf-8")
    plans_js = (ROOT / "src" / "js" / "plans.js").read_text(encoding="utf-8")
    assert "buy.stripe.com/test_bJedR97cM6zM82XcM48Vi02" in stripe_cfg
    assert "buy.stripe.com/test_8x2fZh7cM2jwab5bI08Vi03" in stripe_cfg
    assert "buy.stripe.com/test_28E5kDdBaf6iab58vO8Vi00" in stripe_cfg
    assert "billing.stripe.com/p/login/test_6oU7sL0OoaQ23MHdQ88Vi01" in stripe_cfg
    assert 'monthlyLink: ""' not in stripe_cfg and 'annualLink: ""' not in stripe_cfg
    assert "client_reference_id" in plans_js and "prefilled_email" in plans_js
    assert "Current plan" in plans_js and "Switch plan" in plans_js and "portalUrl" in plans_js
    assert "openBillingPortal" in plans_js
    assert "login/" in plans_js and "next=plans/" in plans_js
    assert "create table public.subscriptions" in (ROOT / "supabase" / "migrations" / "20261004210000_access_tiers.sql").read_text(encoding="utf-8")
    assert "apply_subscription" in (ROOT / "supabase" / "migrations" / "20261004210000_access_tiers.sql").read_text(encoding="utf-8")
    alerts_sql = (ROOT / "supabase" / "migrations" / "20261004220000_alert_funds.sql").read_text(encoding="utf-8")
    assert "create table public.fund_alert_settings" in alerts_sql
    assert "can_alert_fund" in alerts_sql
    assert "New legal matter" in account_js and "Score change" in account_js
    assert "setWatchAlertKind" in account_js and "my_watch_alerts" in auth_js
    assert "set_fund_alert" in auth_js and "set_fund_alert_kind" in auth_js and "set_watch_alert_kind" in auth_js
    assert "grid-template-columns:2.3fr 1.7fr 1.1fr 1fr 1fr 40px" in (ROOT / "src" / "css" / "list.css").read_text(encoding="utf-8")
    assert 'id="fundAlerts"' not in account
    assert 'data-v="alerts"' not in account
    assert "v === 'alerts'" in account_js and "#watchlist" in account_js
    assert "create table public.fact_events" in (ROOT / "supabase" / "migrations" / "20261004200000_fact_events.sql").read_text(encoding="utf-8")

    assert "account/#watchlist" in auth_js and "account/#alerts" not in auth_js
    assert "ACCOUNT_NAV" in auth_js and auth_js.count("Share experience") == 1
    assert "Share / Report a VC" not in auth_js
    assert "path: 'plans/'" in auth_js and "path: 'settings/'" in auth_js
    assert 'plans/">See plans' in home_js
    assert 'id="accountNav"' in account and 'id="accountNav"' in (ROOT / "src" / "settings.html").read_text(encoding="utf-8")
    settings = (ROOT / "site" / "settings" / "index.html").read_text(encoding="utf-8")
    settings_js = (ROOT / "src" / "js" / "settings.js").read_text(encoding="utf-8")
    assert "<h1>Account</h1>" in settings and "<h1>Billing</h1>" in settings
    assert 'id="nameIn"' in settings and 'id="siteIn"' in settings
    assert "Change email" in settings and "Delete account" in settings
    assert "No card on file" in settings and "No payments yet." in settings
    assert "Manage card" in settings
    assert 'data-stripe="checkout"' in settings and 'data-stripe="portal"' in settings
    assert 'id="payFail"' in settings and "payment_failed" in settings_js
    assert 'id="payNote"' in settings
    assert "Payment received, your plan will update in a few seconds" in settings
    assert "tab" in settings_js and "paid" in settings_js and "30000" in settings_js
    assert "next_charge_label" in settings_js
    assert "signInWithPassword" in settings_js and "updateUser" in settings_js
    assert "Password updated" in settings_js
    assert "deleted/" in settings_js
    deleted = (ROOT / "site" / "deleted" / "index.html").read_text(encoding="utf-8")
    assert "Your account was deleted" in deleted
    missing = (ROOT / "site" / "404.html").read_text(encoding="utf-8")
    assert "Page not found" in missing
    assert 'href="/regrettamine/"' in missing and 'href="/regrettamine/scoring/"' in missing
    assert 'href="/regrettamine/css/common.css"' in missing
    assert 'href="css/' not in missing
    assert "search_funds" in (ROOT / "src" / "js" / "notfound.js").read_text(encoding="utf-8")
    assert "Your name is hidden" in account and "Your name will be shown" in account_js
    assert "scroll-margin-top:120px" in (ROOT / "src" / "css" / "settings.css").read_text(encoding="utf-8")
    assert "scrollIntoView" in settings_js
    full = render_fund_page(load_local()[1]["a16z"], "../../")
    visible = full.split('<script id="evidence"', 1)[0]
    assert visible.count("DOJ is investigating a16z partners") == 1
    assert "Interlocking board seats at Databricks and Fivetran. Open, no charges." not in visible
    assert "delete-account" in settings_js
    assert "We couldn't cancel your plan, contact malytskyyo@gmail.com" in settings_js
    assert "Too many sign-ups right now, try again in a few minutes" in auth_js
    qa_sql = (ROOT / "supabase" / "migrations" / "20261004260000_billing_qa.sql").read_text(encoding="utf-8")
    assert "stripe_forgotten_customers" in qa_sql and "flagged" in qa_sql
    delete_fn = (ROOT / "supabase" / "functions" / "delete-account" / "index.ts").read_text(encoding="utf-8")
    assert "stripe_secret_key" in delete_fn and "DELETE" in delete_fn
    assert "Access-Control-Allow-Origin" in delete_fn and "OPTIONS" in delete_fn
    assert "We couldn't cancel your plan, contact malytskyyo@gmail.com" in delete_fn
    portal_fn = (ROOT / "supabase" / "functions" / "billing-portal" / "index.ts").read_text(encoding="utf-8")
    assert "billing_portal/sessions" in portal_fn
    assert "Access-Control-Allow-Origin" in portal_fn and "OPTIONS" in portal_fn
    assert "bpc_1UMuvYHcbGkfjKgmIKZWNWhe" in portal_fn
    assert "settings/?tab=billing" in portal_fn
    assert "stripe_secret_key" in portal_fn
    assert "payment_methods" in portal_fn and "cardOnly" in portal_fn
    assert "card_last4" in (ROOT / "supabase" / "migrations" / "20261004300000_gate_card.sql").read_text(encoding="utf-8")
    assert "openBillingPortal" in auth_js and "billing-portal" in auth_js and "portalUrl" in auth_js
    assert "Alex" not in settings and "4242" not in settings
    assert "paintPayFail" in auth_js
    assert "regret.after" in auth_js
    assert "setMode('login', false)" in auth_js
    assert "querySelector('.av.open')" in auth_js
    assert "scrollTo(0, 0)" in account_js
    assert "'history'" not in account_js
    schema = (ROOT / "supabase" / "migrations" / "20261004120000_schema.sql").read_text(encoding="utf-8")
    assert "create table public.report_views" in schema

    linked = {
        "index": ("scoring/", "account/#share"),
        "account": ("../scoring/", "../account/#share"),
        "fund": ("../../scoring/", "../../account/#share"),
        "login": ("../scoring/", "../account/#share"),
        "reset": ("../../scoring/", "../../account/#share"),
        "privacy": ("../scoring/", "../account/#share"),
        "terms": ("../scoring/", "../account/#share"),
        "scoring": ("../scoring/", "../account/#share"),
        "plans": ("../scoring/", "../account/#share"),
        "settings": ("../scoring/", "../account/#share"),
    }
    pages = {
        "index": index, "account": account, "fund": fund, "login": login, "reset": reset,
        "privacy": privacy, "terms": terms, "scoring": scoring, "plans": plans, "settings": settings,
    }
    for name, html in pages.items():
        scoring_href, share_href = linked[name]
        assert html.count(f'href="{scoring_href}">Scoring') == 2, name
        pricing_href = scoring_href.replace("scoring/", "plans/")
        assert f'href="{pricing_href}">Pricing' in html, name
        footer = html.split("<footer", 1)[1].split("</footer>", 1)[0]
        assert "Sources" not in footer and "Corrections" not in footer, name
        assert f'href="{scoring_href}">Scoring' in footer, name
        assert "Privacy" in footer and "Terms" in footer, name
        assert f'href="{share_href}">Report a VC' in html, name
        assert "How it works" not in html or name == "scoring", name
        assert 'href="#">Scoring' not in html, name
        assert "how/" not in html, name


def test_legal_config_values():
    from build import legal_html

    assert legal_html("", "contact email", email=True) == '<span class="ph">contact email</span>'
    assert legal_html("  ", "jurisdiction") == '<span class="ph">jurisdiction</span>'
    assert legal_html("hello@regrettamine.com", "contact email", email=True) == (
        '<a href="mailto:hello@regrettamine.com">hello@regrettamine.com</a>'
    )
    assert legal_html("not-an-email", "contact email", email=True) == "not-an-email"
    assert legal_html("Delaware", "jurisdiction") == "Delaware"
    assert legal_html("<script>", "jurisdiction") == "&lt;script&gt;"
