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
