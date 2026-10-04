"""The account lists reuse the landing fund list, and the auth pages build."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_shared_list_and_auth_pages(monkeypatch):
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.delenv("SUPABASE_ANON_KEY", raising=False)
    from build import main

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
    assert 'id="wlOut"' in account and 'id="hsOut"' in account
    assert "js/fund-list.js" in account and "css/list.css" in account
    assert 'class="save"' in fund and 'data-firm="a16z"' in fund
    assert (ROOT / "site" / "login" / "index.html").is_file()
    assert (ROOT / "site" / "login" / "reset" / "index.html").is_file()
    config = (ROOT / "site" / "js" / "supabase-config.js").read_text(encoding="utf-8")
    assert "REGRET_CONFIG" in config
    assert "sb_secret" not in config

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
    assert privacy.count('class="ph"') == 3
    assert ">contact email<" in privacy and "mailto:" not in privacy
    assert terms.count('class="ph"') == 3
    assert ">jurisdiction<" in terms and ">contact email<" in terms
    assert "within 30 days of account deletion, and from backups within 90 days" in privacy
    assert "at most 30 days after you submit them" in privacy
    assert 'class="ph">30 days' not in privacy and 'class="ph">90 days' not in privacy
    assert "limited to the greater of USD 100 or the amount you paid us in the 12 months before the claim" in terms
    assert "by emailing us" in terms
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
    assert "Court dockets, regulator filings, press and founder reviews" not in how
    assert "We pull the public record." in how
    assert "It counts only if it links, names the fund and shows its role." in how
    assert "0 to 100, higher is safer, from published rules." in how
    assert "Read the report, save the fund, get alerts when it changes." in how
    assert "What we check" in how
    assert 'href="../scoring/">How scoring works' in how
    assert 'href="../login/?mode=signup"' in how
    assert 'href="../account/#share">Request a correction' in how
    assert "−0.5 for each calendar year with at least one partner departure, up to −2" in scoring
    assert "Partner departures cost points, up to" not in scoring
    assert "Old method." in scoring
    assert "95.4" in scoring and "coverage 39%" in scoring
    assert 'class="stk"' in scoring and 'class="scbs"' in scoring
    assert 'href="../vc/a16z/"' in scoring
    assert "__SCORE_EXAMPLE__" not in scoring

    linked = {
        "index": ("how/", "scoring/", "account/#share"),
        "account": ("../how/", "../scoring/", "../account/#share"),
        "fund": ("../../how/", "../../scoring/", "../../account/#share"),
        "login": (None, "../scoring/", "../account/#share"),
        "reset": (None, "../../scoring/", "../../account/#share"),
        "privacy": ("../how/", "../scoring/", "../account/#share"),
        "terms": ("../how/", "../scoring/", "../account/#share"),
        "how": ("../how/", "../scoring/", "../account/#share"),
        "scoring": ("../how/", "../scoring/", "../account/#share"),
    }
    pages = {
        "index": index, "account": account, "fund": fund, "login": login, "reset": reset,
        "privacy": privacy, "terms": terms, "how": how, "scoring": scoring,
    }
    for name, html in pages.items():
        how_href, scoring_href, share_href = linked[name]
        assert f'href="{scoring_href}">Scoring' in html, name
        assert f'href="{share_href}">Corrections' in html, name
        assert 'href="#">How it works' not in html, name
        assert 'href="#">Scoring' not in html, name
        if how_href:
            assert f'href="{how_href}">How it works' in html, name
        if "Report a VC" in html:
            assert f'href="{share_href}">Report a VC' in html, name
            assert 'href="#">Report a VC' not in html, name


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
