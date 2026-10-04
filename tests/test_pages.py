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
