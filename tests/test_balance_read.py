"""check_balance / my_account fast path: same amounts, row created once, bonus granted once."""
import os
import uuid

import pytest

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_balance_read_same_results_no_duplicate_grants():
    psycopg = pytest.importorskip("psycopg")
    anon = str(uuid.uuid4())
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            # signed out: first call creates the row, later calls are plain reads with the same amount
            for _ in range(3):
                cur.execute("select check_balance(%s)", (anon,))
                assert cur.fetchone()[0]["left"] == 2
            cur.execute("select count(*) from check_balances where anon_id = %s", (anon,))
            assert cur.fetchone()[0] == 1
            with pytest.raises(psycopg.errors.RaiseException):
                cur.execute("savepoint s; select check_balance(null)")
            cur.execute("rollback to savepoint s")
            # signed in: bonus granted once, repeated reads keep 4
            cur.execute("insert into auth.users (id, email) values (gen_random_uuid(), %s) returning id",
                        (f"br-{anon[:8]}@example.com",))
            uid = str(cur.fetchone()[0])
            cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid,))
            for _ in range(3):
                cur.execute("select check_balance(null)")
                assert cur.fetchone()[0]["left"] == 4
                cur.execute("select my_account()")
                assert cur.fetchone()[0]["left"] == 4
            cur.execute("select count(*) from check_events e join check_balances b on b.id = e.balance_id"
                        " where b.user_id = %s and e.kind = 'grant_signup'", (uid,))
            assert cur.fetchone()[0] == 1
        conn.rollback()
