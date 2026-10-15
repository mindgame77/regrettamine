"""needs_proof: never purged, promotable to real with a source, real needs a source, cascade from the firm."""
import os

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def test_needs_proof_lifecycle():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into firms (slug, name, data_status) values ('np-test', 'NP Test', 'real') returning id")
        firm = cur.fetchone()[0]
        cur.execute("insert into vc_partner_history (firm_id, field, value, kind, data_status, source_system, external_id) "
                    "values (%s, 'career_stint', 'x', 'career_stint', 'needs_proof', 't', 'np1') returning id", (firm,))
        np_id = cur.fetchone()[0]
        cur.execute("insert into vc_partner_history (firm_id, field, value, kind, data_status, source_system, external_id) "
                    "values (%s, 'career_stint', 'y', 'career_stint', 'test', 't', 'np2')", (firm,))
        cur.execute("select * from purge_test_data(false)")
        cur.execute("select data_status::text, count(*) from vc_partner_history where firm_id = %s group by 1", (firm,))
        assert dict(cur.fetchall()) == {"needs_proof": 1}
        cur.execute("select promote_source(%s, now(), 'https://example.org/x')", (np_id,))
        assert cur.fetchone()[0] == "vc_partner_history"
        cur.execute("select data_status::text from vc_partner_history where id = %s", (np_id,))
        assert cur.fetchone()[0] == "real"
        with pytest.raises(psycopg.errors.CheckViolation):
            with conn.transaction():
                cur.execute("insert into vc_firm_claims (firm_id, field, value, kind, data_status, source_system, external_id) "
                            "values (%s, 'team_size', '1', 'team_size', 'real', 't', 'np3')", (firm,))
        cur.execute("delete from firms where id = %s", (firm,))
        cur.execute("select count(*) from vc_partner_history where firm_id = %s", (firm,))
        assert cur.fetchone()[0] == 0
        conn.rollback()
