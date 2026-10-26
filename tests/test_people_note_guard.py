"""Bot research notes stored as people rows are flagged hidden (text kept in internal_note) and never reach the page."""
import os

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
NOTE = ("ADV Schedule A individuals: A One (CLO, since 02/2022); B Two (COO). "
        "https://reports.adviserinfo.sec.gov/x.pdf. Bot people records: 11; 3 match a Schedule A surname.")


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_people_note_hidden_and_not_rendered():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into firms (slug, name, published, data_status) values ('zz-people', 'ZZ People', true, 'real') returning id")
        fid = cur.fetchone()[0]
        cur.execute("insert into sources (url, publisher) values ('https://zz.example/adv', 'SEC IAPD') returning id")
        sid = cur.fetchone()[0]
        ids = {}
        for k, name, kind in (("note", NOTE, "officer"), ("board", "Form D (ZZ ES20, LLC) related persons: A; B; C", "board"),
                              ("ok", "Kenneth Howery — Member, since 06/2005 (ADV Schedule A)", "officer")):
            cur.execute("""insert into firm_people_roles (id, firm_id, kind, person_name, role, sort_order)
                           values (gen_random_uuid(), %s, %s, %s, '', 1) returning id, hidden, internal_note""", (fid, kind, name))
            ids[k] = cur.fetchone()
            cur.execute("insert into fact_sources (source_id, firm_id, fact_type, fact_id) values (%s, %s, 'firm_people_roles', %s)", (sid, fid, ids[k][0]))
        assert ids["note"][1] is True and ids["note"][2] == NOTE
        assert ids["board"][1] is True
        assert ids["ok"][1] is False and ids["ok"][2] is None
        cur.execute("select _sec_items('people', %s)::text", (fid,))
        out = cur.fetchone()[0]
        assert "Kenneth Howery" in out and "Bot people records" not in out and "related persons" not in out
        cur.execute("select person_name from firm_people_roles where id = %s", (ids["note"][0],))
        assert cur.fetchone()[0] == NOTE  # nothing deleted or rewritten
        conn.rollback()
