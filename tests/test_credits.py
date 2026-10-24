"""Credits: signed-out 2, new account fresh 4, nothing transfers at sign-in."""
import os
import uuid
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]


def test_client_no_claim_and_outlet_host_dedupe():
    app = (ROOT / "launch" / "js" / "app.js").read_text(encoding="utf-8")
    assert "claim_anon_checks" not in app
    js = (ROOT / "launch" / "js" / "company.js").read_text(encoding="utf-8")
    assert "esc(x.outlet) + ' · ' + esc(host)" not in js
    assert ".split(' · ')[0]" in js


DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_anon_2_account_4_no_transfer():
    psycopg = pytest.importorskip("psycopg")
    anon = str(uuid.uuid4())
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute("insert into auth.users (id, email) values (gen_random_uuid(), %s) returning id",
                        (f"cr-{anon[:8]}@example.com",))
            uid = str(cur.fetchone()[0])
            cur.execute("select check_balance(%s)", (anon,))
            assert cur.fetchone()[0]["left"] == 2
            cur.execute("update check_balances set free_left = 1 where anon_id = %s", (anon,))
            cur.execute("select id from check_balances where anon_id = %s", (anon,))
            aid = cur.fetchone()[0]
            cur.execute("insert into check_events(balance_id, kind, amount) values (%s, 'grant_signup', 0)", (aid,))
            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid,))
            cur.execute("select check_balance(null)")
            assert cur.fetchone()[0]["left"] == 4
            cur.execute("select claim_anon_checks(%s)", (anon,))
            cur.execute("select check_balance(null)")
            assert cur.fetchone()[0]["left"] == 4
            cur.execute("select free_left from check_balances where anon_id = %s and user_id is null", (anon,))
            assert cur.fetchone()[0] == 1  # anon row untouched
            cur.execute("select count(*) from check_events where balance_id = %s", (aid,))
            assert cur.fetchone()[0] == 1  # anon events stay put
            cur.execute("select kind, amount from check_events e join check_balances b on b.id = e.balance_id where b.user_id = %s", (uid,))
            assert cur.fetchall() == [("grant_signup", 4)]
        conn.rollback()
