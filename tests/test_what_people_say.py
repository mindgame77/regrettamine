"""What people say: every public approved review shows with its stored type; founder reviews lead;
company reviews read 'portfolio' only when our investments data says the firm backed the company."""
import os

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_review_types_and_portfolio_rule():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("""insert into firms (slug, name, published, data_status)
                       values ('zz-wps', 'ZZ WPS', true, 'real') returning id""")
        fid = cur.fetchone()[0]
        cur.execute("insert into portfolio_companies (name) values ('Backed Co') returning id")
        backed = cur.fetchone()[0]
        cur.execute("insert into portfolio_companies (name) values ('Other Co') returning id")
        other = cur.fetchone()[0]
        cur.execute("insert into investments (firm_id, company_id, data_status) values (%s, %s, 'real')", (fid, backed))
        rows = [
            ("founder", None, "current_date - 30", True),
            ("company", backed, "current_date - 1", True),
            ("company", other, "current_date - 2", True),
            ("firm_voice", None, "current_date - 3", True),
            ("aggregator", None, "current_date - 4", True),
            ("employee", None, "current_date - 5", False),
        ]
        for t, cid, d, pub in rows:
            cur.execute(f"""insert into reviews (firm_id, company_id, body, review_type, is_public, moderation_status, reviewed_on)
                            values (%s, %s, %s, %s, %s, 'approved', {d})""", (fid, cid, t, t, pub))
        cur.execute("select _firm_activity(%s, true)", (fid,))
        a = cur.fetchone()[0]
        assert a["counts"]["reviews"] == 5
        assert a["latest_review"]["type"] == "founder"
        cur.execute("select (_balance('00000000-0000-4000-8000-00000000b22b'::uuid)).id")
        bid = cur.fetchone()[0]
        cur.execute("insert into check_events(balance_id, firm_id, kind, amount) values (%s, %s, 'spend_paid', -1)", (bid, fid))
        cur.execute("select firm_activity_list('zz-wps', '00000000-0000-4000-8000-00000000b22b'::uuid, 'revs')")
        items = cur.fetchone()[0]["items"]
        assert [(i["type"], i["company"]) for i in items] == [
            ("founder", None), ("portfolio", "Backed Co"), ("company", "Other Co"), ("firm_voice", None), ("aggregator", None)]
        conn.rollback()
