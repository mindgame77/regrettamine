"""Signed-in users only read their own profile_id and linkedin_url on reviews."""
import os

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_signed_in_users_cannot_read_other_review_authors():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into auth.users (id, email) values (gen_random_uuid(), 'ra@x.test') returning id")
        ada = cur.fetchone()[0]
        cur.execute("insert into auth.users (id, email) values (gen_random_uuid(), 'rb@x.test') returning id")
        bea = cur.fetchone()[0]
        cur.execute(
            """insert into firms (slug, name, published, data_status)
               values ('zz-privacy', 'ZZ Privacy', true, 'real') returning id"""
        )
        fid = cur.fetchone()[0]
        cur.execute(
            """insert into reviews (firm_id, body, profile_id, linkedin_url, moderation_status)
               values (%s, 'mine', %s, 'https://www.linkedin.com/in/ada', 'pending') returning id""",
            (fid, ada),
        )
        mine = cur.fetchone()[0]
        cur.execute(
            """insert into reviews (firm_id, body, profile_id, moderation_status)
               values (%s, 'theirs', %s, 'pending')""",
            (fid, bea),
        )

        cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(ada),))
        cur.execute("set role authenticated")
        for col in ("profile_id", "linkedin_url"):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                with conn.transaction():
                    cur.execute(f"select {col} from reviews")
        cur.execute("select id, body from reviews where firm_id = %s", (fid,))
        assert cur.fetchall() == [(mine, "mine")]
        cur.execute("select id, profile_id, linkedin_url from my_review_private()")
        assert cur.fetchall() == [(mine, ada, "https://www.linkedin.com/in/ada")]

        cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(bea),))
        cur.execute("select id from my_review_private()")
        assert mine not in [r[0] for r in cur.fetchall()]

        cur.execute("reset role")
        cur.execute("set role anon")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            with conn.transaction():
                cur.execute("select * from my_review_private()")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            with conn.transaction():
                cur.execute("select * from activity_legacy_map")
        cur.execute("reset role")
        conn.rollback()
