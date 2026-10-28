"""Lab soft caps: oldest deals past 200 are marked, negative news is not, leads are hidden."""
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def test_cap_archives_only_the_oldest_deals_and_keeps_a_lawsuit():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        slug = "cap-" + uuid.uuid4().hex[:8]
        other = "capo-" + uuid.uuid4().hex[:8]
        fid = cur.execute(
            "insert into firms(slug, name, primary_domain, published, data_status) "
            "values (%s, 'Cap Lab', 'cap.example', true, 'real') returning id",
            (slug,),
        ).fetchone()[0]
        oid = cur.execute(
            "insert into firms(slug, name, primary_domain, published, data_status) "
            "values (%s, 'Cap Other', 'other.example', true, 'real') returning id",
            (other,),
        ).fetchone()[0]
        cur.execute(
            "insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) "
            "on conflict (key) do update set value = case when ingest_settings.value like %s then ingest_settings.value "
            "else coalesce(ingest_settings.value, '') || ',' || excluded.value end",
            (slug, "%" + slug + "%"),
        )
        cid = cur.execute(
            "insert into portfolio_companies(name) values ('Cap Co') returning id"
        ).fetchone()[0]
        cur.execute(
            "insert into investments(firm_id, company_id, invested_on, data_status) "
            "select %s, %s, current_date - n, 'real' from generate_series(0, 200) n",
            (fid, cid),
        )
        cur.execute(
            "insert into investments(firm_id, company_id, invested_on, data_status) "
            "select %s, %s, current_date - n, 'real' from generate_series(0, 200) n",
            (oid, cid),
        )
        cur.execute(
            "insert into timeline_events(firm_id, date_label, kind, body, sort_order) "
            "values (%s, '2020', 'note', 'A lawsuit was filed', 1)",
            (fid,),
        )
        cur.execute(
            "insert into firm_profile_facts(firm_id, section, label, value, sort_order) values "
            "(%s, 'lps', 'Kept Pension', 'Pension · Confirmed', 1), "
            "(%s, 'lps', 'Hidden Lead', 'Pension · Lead (not confirmed)', 2)",
            (fid, fid),
        )
        dry = {
            row[0]: row[1:]
            for row in cur.execute(
                "select kind, current_n, would_archive, protected_n from lab_soft_caps(false) where slug = %s",
                (slug,),
            ).fetchall()
        }
        assert dry["deals"] == (201, 1, 0)
        assert dry["news"][1:] == (0, 1)
        assert dry["lps"][1:] == (0, 1)
        assert cur.execute(
            "select count(*) from investments where firm_id = %s and archived_at is null", (fid,)
        ).fetchone()[0] == 201
        cur.execute("select lab_soft_caps(true)")
        assert cur.execute(
            "select count(*) from investments where firm_id = %s and archived_at is null", (fid,)
        ).fetchone()[0] == 200
        assert cur.execute(
            "select count(*) from lab_cap_archive where firm_id = %s and kind = 'deals'", (fid,)
        ).fetchone()[0] == 1
        assert cur.execute(
            "select count(*) from investments where firm_id = %s and archived_at is null", (oid,)
        ).fetchone()[0] == 201
        assert cur.execute(
            "select hidden from firm_profile_facts where firm_id = %s and label = 'Hidden Lead'", (fid,)
        ).fetchone()[0] is True
        assert cur.execute(
            "select hidden from firm_profile_facts where firm_id = %s and label = 'Kept Pension'", (fid,)
        ).fetchone()[0] is False
        assert cur.execute(
            "select count(*) from lab_cap_alerts where firm_id = %s", (fid,)
        ).fetchone()[0] == 1
        cur.execute("select lab_soft_caps(true)")
        assert cur.execute(
            "select count(*) from lab_cap_alerts where firm_id = %s", (fid,)
        ).fetchone()[0] == 1
        act = cur.execute("select _firm_activity(%s, true)", (fid,)).fetchone()[0]
        assert act["counts"]["deals"] == 201 and act["deals_12m"] == 201
        cur.execute("update app_settings set value = 'false' where key = 'lock_enabled'")
        listed = cur.execute(
            "select firm_activity_list(%s, gen_random_uuid(), 'deals')", (slug,)
        ).fetchone()[0]
        assert listed["status"] == "ok" and len(listed["items"]) == 201
        conn.rollback()


def test_archived_newest_deal_stays_in_tiles_show_all_and_sector():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        slug = "arch-" + uuid.uuid4().hex[:8]
        fid = cur.execute(
            "insert into firms(slug, name, primary_domain, published, data_status) "
            "values (%s, 'Archive Count', 'arch.example', true, 'real') returning id",
            (slug,),
        ).fetchone()[0]
        newest = cur.execute(
            "insert into portfolio_companies(name, sector) values ('Newest Co', 'Fintech') returning id"
        ).fetchone()[0]
        mid = cur.execute(
            "insert into portfolio_companies(name, sector) values ('Mid Co', 'Health') returning id"
        ).fetchone()[0]
        old = cur.execute(
            "insert into portfolio_companies(name, sector) values ('Old Co', 'Climate') returning id"
        ).fetchone()[0]
        blank = cur.execute(
            "insert into portfolio_companies(name, sector) values ('Blank Co', '  ') returning id"
        ).fetchone()[0]
        cur.execute(
            "insert into investments(firm_id, company_id, round_name, invested_on, data_status, archived_at) values "
            "(%s, %s, 'Series A', current_date, 'real', now()), "
            "(%s, %s, 'Seed', current_date - 10, 'real', now()), "
            "(%s, %s, 'Pre-seed', current_date - 400, 'real', now()), "
            "(%s, %s, 'Seed', current_date - 1, 'real', now())",
            (fid, newest, fid, mid, fid, old, fid, blank),
        )
        act = cur.execute("select _firm_activity(%s, true)", (fid,)).fetchone()[0]
        assert act["counts"]["deals"] == 4
        assert act["deals_12m"] == 3
        assert act["latest_deal"]["company"] == "Newest Co"
        assert act["latest_deal"]["round"] == "Series A"
        cur.execute("update app_settings set value = 'false' where key = 'lock_enabled'")
        listed = cur.execute(
            "select firm_activity_list(%s, gen_random_uuid(), 'deals')", (slug,)
        ).fetchone()[0]
        assert listed["status"] == "ok"
        assert [row["company"] for row in listed["items"]] == ["Newest Co", "Blank Co", "Mid Co", "Old Co"]
        sectors = dict(
            cur.execute("select sector, n from deal_sector_12m(%s)", (fid,)).fetchall()
        )
        assert sectors == {"Fintech": 1, "Health": 1, "Not stated": 1}
        conn.rollback()
