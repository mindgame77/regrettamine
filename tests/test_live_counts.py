"""Lab pills come from findings and the IAPD row. A non-lab pill stays stored."""
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = [pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set"), pytest.mark.skip(reason="checks are off (Alex 2026-10-28): firm_check_rows is no longer filled")]


def _page(cur, slug):
    raw = cur.execute(
        "select firm_page(%s, %s, true)", (slug, str(uuid.uuid4()))
    ).fetchone()[0]
    return raw if isinstance(raw, dict) else __import__("json").loads(raw)


def test_lab_pill_follows_findings_and_the_iapd_row():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        slug = "live-" + uuid.uuid4().hex[:8]
        other = "liveo-" + uuid.uuid4().hex[:8]
        cur.execute(
            "insert into firms(slug, name, primary_domain, published, data_status) "
            "values (%s, 'Live Lab', 'live.example', true, 'real') returning id",
            (slug,),
        )
        fid = cur.fetchone()[0]
        oid = cur.execute(
            "insert into firms(slug, name, primary_domain, published, data_status) "
            "values (%s, 'Live Other', 'other.example', true, 'real') returning id",
            (other,),
        ).fetchone()[0]
        cur.execute(
            "insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) "
            "on conflict (key) do update set value = case when ingest_settings.value like %s then ingest_settings.value "
            "else coalesce(ingest_settings.value, '') || ',' || excluded.value end",
            (slug, "%" + slug + "%"),
        )
        cur.execute(
            "insert into firm_check_rows(firm_id, n, title, descr, state, count_label) "
            "select %s, n, 'T' || n, 'D', 'clear', case when n = 7 then '1 non-party mention' end "
            "from generate_series(1, 10) n",
            (fid,),
        )
        cur.execute(
            "update firm_check_rows set state = 'nc', count_label = null where firm_id = %s and n = 8",
            (fid,),
        )
        cur.execute(
            "insert into firm_check_rows(firm_id, n, title, descr, state, count_label) "
            "select %s, n, 'T' || n, 'D', 'review', '2 actions' from generate_series(1, 10) n",
            (oid,),
        )
        cur.execute(
            "insert into vc_source_facts(firm_id, fact_type, section, value, source_url, data_status, retrieved_at) "
            "values (%s, 'fund_fact', 'fund_fact', "
            "'{\"field\":\"registration_status\",\"value\":\"SEC-registered investment adviser; status Approved; ACTIVE\"}'::jsonb, "
            "'https://adviserinfo.sec.gov/firm/summary/1', 'real', now())",
            (fid,),
        )
        assert cur.execute(
            "select state, count_label from _lab_live_pill(%s, 8)", (fid,)
        ).fetchone() == ("clear", None)
        assert cur.execute(
            "select state, count_label from _lab_live_pill(%s, 7)", (fid,)
        ).fetchone()[:1] == ("nc",)
        dry = cur.execute(
            "select item, live from lab_live_counts(false) where slug = %s order by item",
            (slug,),
        ).fetchall()
        got = dict(dry)
        assert got["check 8"].startswith("clear")
        assert got["check 7"].startswith("nc")
        assert cur.execute(
            "select count_label from firm_check_rows where firm_id = %s and n = 7", (fid,)
        ).fetchone()[0] == "1 non-party mention"
        page = _page(cur, slug)
        by_n = {c["n"]: c for c in page["checks"]}
        assert by_n[8]["state"] == "clear" and by_n[7]["state"] == "nc"
        other_page = _page(cur, other)
        assert {c["n"]: c["state"] for c in other_page["checks"]}[4] == "review"
        vid = cur.execute("select id from score_versions limit 1").fetchone()
        if vid:
            cur.execute(
                "insert into score_results(firm_id, version_id, total, is_current) values (%s, %s, 1, true)",
                (fid, vid[0]),
            )
        wrote = cur.execute(
            "select count(*) from lab_live_counts(true) where slug = %s", (slug,)
        ).fetchone()[0]
        assert wrote >= 1
        assert cur.execute(
            "select count_label from firm_check_rows where firm_id = %s and n = 7", (fid,)
        ).fetchone()[0] is None
        assert cur.execute(
            "select count(*) from live_count_backup where firm_id = %s and kind = 'pill'", (fid,)
        ).fetchone()[0] == 10
        if vid:
            assert cur.execute(
                "select is_current from score_results where firm_id = %s", (fid,)
            ).fetchone()[0] is False
        conn.rollback()
