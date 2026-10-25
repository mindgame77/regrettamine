"""Out-of-credits popup: plans and email go to Checkout. The Sign in popup stays as it is."""
import json
import os
import pathlib
import subprocess
import uuid

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
COPY = json.loads((ROOT / "launch" / "copy.json").read_text())
APP = (ROOT / "launch" / "js" / "app.js").read_text()
CHECKOUT = (ROOT / "supabase" / "functions" / "create-checkout" / "index.ts").read_text()
WEBHOOK = (ROOT / "supabase" / "functions" / "regretamin-stripe-webhook" / "index.ts").read_text()
CLAIM = (ROOT / "supabase" / "functions" / "claim-checkout" / "index.ts").read_text()


def test_signup_popup_copy_unchanged_and_buy_path_does_not_use_it():
    su = COPY["site"]["signup"]
    assert su["title"] == "Get 4 more free credits"
    assert su["sub"] == "Create a free account. No card needed."
    assert su["trust"] == ["Free account", "No card needed"]
    assert su["google"] == "Continue with Google"
    assert "sign_buy" not in APP
    assert "classList.add('buy')" not in APP
    oc = COPY["site"]["outcredits"]
    assert oc["title"] == "You've used your free checks"
    assert oc["sub"] == "Pick a plan to check this firm."
    assert oc["google"] == "Continue with Google"
    assert oc["checkout"] == "Continue to checkout"
    assert oc["fine"] == "Your account is created from this email after payment."
    assert "No card needed" not in json.dumps(oc)
    assert "Sign in to buy" not in json.dumps(oc)


def test_guest_checkout_prefills_email_and_webhook_creates_the_user():
    assert "ensurePaidUser" not in CHECKOUT
    assert "customer_email: guest!" in CHECKOUT
    assert "user_id: user.id" in CHECKOUT
    assert "{CHECKOUT_SESSION_ID}" in CHECKOUT
    assert 'return err(body.email ? "bad email" : "sign in"' in CHECKOUT
    assert "password" not in CHECKOUT.lower()
    assert "ensurePaidUser" in WEBHOOK and "grant_checks" in WEBHOOK
    assert "guest ? s.id : ev.id" in WEBHOOK
    assert "generateLink" in CLAIM and "password:" not in CLAIM and "password:" not in CHECKOUT
    assert "grant_checks" not in CLAIM
    assert "verify_jwt = true" in (ROOT / "supabase" / "config.toml").read_text().split("[functions.claim-checkout]")[1][:80]


def test_built_pages_keep_sign_in_and_add_the_plan_popup():
    subprocess.run(["python3", "launch/build.py"], cwd=ROOT, check=True, capture_output=True)
    home = (ROOT / "site-launch" / "index.html").read_text()
    su, oc = home.split('id="signup"', 1)[1].split('id="outcredits"', 1)
    assert "Get 4 more free credits" in su and "Create a free account. No card needed." in su and "No card needed" in su
    assert "You've used your free checks" in oc
    assert "Continue to checkout" in oc and "Continue with Google" in oc
    assert 'id="outem"' in oc and 'id="outgo"' in oc and 'id="outplans"' in oc
    assert "No card needed" not in oc and "Sign in to buy" not in oc
    # Prices are not baked into the popup; app.js fills them from copy.json plans.
    assert "$10" not in oc and "$19" not in oc and "$49" not in oc
    assert "C.copy.plans" in APP and "O.line_month" in APP
    firm = (ROOT / "site-launch" / "_tpl" / "summary.html").read_text()
    assert 'id="outcredits"' in firm and "Create a free account. No card needed." in firm
    login = (ROOT / "site-launch" / "login" / "index.html").read_text()
    assert login.count('id="google"') == 1  # the Sign in form keeps the only google id


DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_user_id_for_email_is_service_role_only():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        email = "paid-link-" + uuid.uuid4().hex[:12] + "@example.com"
        cur.execute(
            "insert into auth.users (id, email) values (gen_random_uuid(), %s) returning id",
            (email,),
        )
        uid = cur.fetchone()[0]
        cur.execute("select public.user_id_for_email(%s)", (email.upper(),))
        assert cur.fetchone()[0] == uid
        cur.execute("select public.user_id_for_email('missing-paid-link@example.com')")
        assert cur.fetchone()[0] is None
        cur.execute("set role anon")
        cur.execute("savepoint locked")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            cur.execute("select public.user_id_for_email(%s)", (email,))
        cur.execute("rollback to savepoint locked")
        cur.execute("reset role")
