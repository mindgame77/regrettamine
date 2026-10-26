"""firm_page() 'activity' key: live tiles, latest deal/review, full lists only after a credit, no author ids."""
import json
import os

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_activity_key_live_and_private():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("""insert into firms (slug, name, published, data_status, indexable)
                       values ('zz-activity', 'ZZ Activity', true, 'real', true) returning id""")
        fid = cur.fetchone()[0]

        def act(open_):
            cur.execute("select _firm_activity(%s, %s)", (fid, open_))
            return cur.fetchone()[0]

        a = act(True)
        assert a["active"] is False and a["deals_12m"] == 0 and a["latest_deal"] is None
        assert a["latest_fund"] is None and a["counts"] == {"deals": 0, "reviews": 0}

        cur.execute("insert into portfolio_companies (name, domain) values ('ZZ Co', 'zz.example') returning id")
        cid = cur.fetchone()[0]
        cur.execute("""insert into investments (firm_id, company_id, round_name, invested_on, source_urls, data_status)
                       values (%s, %s, 'Seed', current_date - 3, '{https://zz.example/news}', 'real')""", (fid, cid))
        cur.execute("""insert into investments (firm_id, company_id, round_name, invested_on, data_status)
                       values (%s, %s, 'Pre-seed', current_date - 500, 'real')""", (fid, cid))
        cur.execute("""insert into funds (firm_id, name, raised_usd, close_status, closed_on, filing_url, data_status)
                       values (%s, 'ZZ Fund I', 1710000000, 'raised', current_date - 30, 'https://www.sec.gov/x', 'real')""", (fid,))
        cur.execute("insert into auth.users (id, email) values (gen_random_uuid(), 'act@x.test') returning id")
        uid = cur.fetchone()[0]
        cur.execute("""insert into reviews (firm_id, company_id, body, profile_id, linkedin_url, author_name, review_type,
                       is_public, moderation_status, reviewed_on, honesty, source_urls, anonymous)
                       values (%s, %s, 'Good', %s, 'https://www.linkedin.com/in/zz', 'Zed', 'founder', true, 'approved',
                       current_date - 2, 4, '{https://blog.example/p}', false)""", (fid, cid, uid))
        cur.execute("""insert into reviews (firm_id, body, review_type, is_public, moderation_status)
                       values (%s, 'Pending one', 'founder', true, 'pending')""", (fid,))

        a = act(True)
        assert a["active"] is True and a["deals_12m"] == 1 and a["counts"] == {"deals": 2, "reviews": 1}
        assert a["latest_deal"]["company"] == "ZZ Co" and a["latest_deal"]["url"] == "https://zz.example/news"
        assert a["latest_fund"]["name"] == "ZZ Fund I" and float(a["latest_fund"]["raised_usd"]) == 1710000000
        assert a["latest_fund"]["url"] == "https://www.sec.gov/x"
        assert a["latest_review"]["author"] == "Zed" and a["latest_review"]["ratings"] == {"honesty": 4}
        # first slice only; the full lists come from firm_activity_list (unlocked visitors only)
        assert a["lazy"] is True and len(a["deals"]) == 1 and len(a["reviews"]) == 1
        cur.execute("select firm_activity_list('zz-activity', gen_random_uuid(), 'deals')")
        assert cur.fetchone()[0]["status"] == "locked"
        cur.execute("select (_balance('00000000-0000-4000-8000-00000000a11a'::uuid)).id")
        bid = cur.fetchone()[0]
        cur.execute("insert into check_events(balance_id, firm_id, kind, amount) values (%s, %s, 'spend_paid', -1)", (bid, fid))
        cur.execute("select firm_activity_list('zz-activity', '00000000-0000-4000-8000-00000000a11a'::uuid, 'deals')")
        full = cur.fetchone()[0]
        assert full["status"] == "ok" and [d["round"] for d in full["items"]] == ["Seed", "Pre-seed"]
        cur.execute("select firm_activity_list('zz-activity', '00000000-0000-4000-8000-00000000a11a'::uuid, 'revs')")
        revs = cur.fetchone()[0]["items"]
        assert len(revs) == 1 and str(uid) not in json.dumps(revs)
        text = json.dumps(a)
        assert str(uid) not in text and "linkedin" not in text and "profile_id" not in text

        locked = act(False)
        assert locked["deals"] is None and locked["reviews"] is None
        assert locked["latest_deal"] == a["latest_deal"] and locked["counts"] == a["counts"]

        cur.execute("set role anon")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            with conn.transaction():
                cur.execute("select _firm_activity(%s, true)", (fid,))
        cur.execute("reset role")

        cur.execute("select firm_page('zz-activity', gen_random_uuid())")
        page = cur.fetchone()[0]
        assert page["activity"]["latest_deal"]["company"] == "ZZ Co" and page["activity"]["deals"] is None
        conn.rollback()
