"""Step 1 activity columns: additive, and visitors only read public founder reviews."""
import os

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_visitors_only_read_public_founder_reviews():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute(
            """insert into firms (slug, name, published, data_status)
               values ('zz-activity', 'ZZ Activity', true, 'real') returning id"""
        )
        fid = cur.fetchone()[0]
        rows = [
            ("founder", True, "approved", "k1"),
            ("founder", None, "approved", "k2"),
            ("firm_voice", True, "approved", "k3"),
            ("founder", True, "pending", "k4"),
        ]
        for t, pub, mod, key in rows:
            cur.execute(
                """insert into reviews (firm_id, body, review_type, is_public, moderation_status, dedupe_key)
                   values (%s, 'x', %s, %s, %s, %s)""",
                (fid, t, pub, mod, key),
            )
        with pytest.raises(psycopg.errors.UniqueViolation):
            with conn.transaction():
                cur.execute("insert into reviews (firm_id, body, dedupe_key) values (%s, 'dup', 'k1')", (fid,))

        cur.execute("set role anon")
        cur.execute("select review_type, is_public from reviews where firm_id = %s", (fid,))
        assert cur.fetchall() == [("founder", True)]
        for col in ("profile_id", "linkedin_url"):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                with conn.transaction():
                    cur.execute(f"select {col} from reviews")
        cur.execute("reset role")
        conn.rollback()
