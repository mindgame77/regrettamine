"""Lab aliases stay for checks. Search matches the name, the short name, and the website."""
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def test_checked_names_are_searchable_and_each_check_keeps_its_own_list():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        slug = "srch-" + uuid.uuid4().hex[:8]
        other = "srcho-" + uuid.uuid4().hex[:8]
        crd = uuid.uuid4().hex[:12]
        fid = cur.execute(
            "insert into firms(slug, name, short_name, legal_name, primary_domain, sec_crd, published, data_status) "
            "values (%s, 'Search Lab', 'SL', 'ZZ Legal Management, L.L.C.', 'zzlab.example', %s, true, 'real') returning id",
            (slug, crd),
        ).fetchone()[0]
        oid = cur.execute(
            "insert into firms(slug, name, legal_name, primary_domain, published, data_status) "
            "values (%s, 'Search Other', 'Other Legal LLC', 'other.example', true, 'real') returning id",
            (other,),
        ).fetchone()[0]
        cur.execute(
            "insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) "
            "on conflict (key) do update set value = case when ingest_settings.value like %s then ingest_settings.value "
            "else coalesce(ingest_settings.value, '') || ',' || excluded.value end",
            (slug, "%" + slug + "%"),
        )
        cur.execute(
            "insert into funds(firm_id, name, data_status, source_urls) values "
            "(%s, 'ZZ Growth Fund V', 'real', %s), "
            "(%s, 'Funds', 'real', %s), "
            "(%s, 'ZZ News Fund', 'real', %s)",
            (fid, ["https://zzlab.example/funds"], fid, ["https://reports.adviserinfo.sec.gov/reports/ADV/1/PDF/1.pdf"],
             fid, ["https://techcrunch.com/zz"]),
        )
        cur.execute(
            "insert into funds(firm_id, name, data_status, filing_url) values (%s, 'ZZ Register Fund, L.P.', 'real', %s)",
            (fid, "https://www.sec.gov/Archives/edgar/data/1/index.htm"),
        )
        cur.execute(
            "insert into funds(firm_id, name, data_status, filing_url) values (%s, 'Other Register Fund, L.P.', 'real', %s)",
            (oid, "https://www.sec.gov/Archives/edgar/data/2/index.htm"),
        )
        dry = cur.execute(
            "select alias_type, added from lab_search_aliases(false) where slug = %s order by alias_type",
            (slug,),
        ).fetchall()
        assert dict(dry) == {"fund_entity": 2, "legal": 1, "website": 1}
        assert cur.execute(
            "select count(*) from firm_aliases where firm_id = %s", (fid,)
        ).fetchone()[0] == 0
        cur.execute("select lab_search_aliases(true)")
        rows = {
            r[0]: r[1]
            for r in cur.execute(
                "select alias, alias_type from firm_aliases where firm_id = %s", (fid,)
            ).fetchall()
        }
        assert rows == {
            "ZZ Legal Management, L.L.C.": "legal",
            "zzlab.example": "website",
            "ZZ Growth Fund V": "fund_entity",
            "ZZ Register Fund, L.P.": "fund_entity",
        }
        assert cur.execute(
            "select count(*) from firm_aliases where firm_id = %s", (oid,)
        ).fetchone()[0] == 0
        cur.execute("select lab_search_aliases(true)")
        assert cur.execute(
            "select coalesce(sum(added), 0) from lab_search_aliases(false) where slug = %s", (slug,)
        ).fetchone()[0] == 0

        cur.execute(
            "insert into firm_aliases(firm_id, alias, source, alias_type) values (%s, 'SL', 'previous_display', 'old_name')",
            (fid,),
        )
        assert cur.execute(
            "select action from lab_short_name_aliases(true) where slug = %s", (slug,)
        ).fetchone()[0] == "retype"
        assert cur.execute(
            "select alias_type, source from firm_aliases where firm_id = %s and alias = 'SL'", (fid,)
        ).fetchone() == ("short_name", "firm_site")
        cur.execute(
            "insert into firm_aliases(firm_id, alias, source, alias_type) values (%s, 'Other Legal LLC', 'sec_legal', 'legal')",
            (oid,),
        )

        def slugs(q):
            return [r["slug"] for r in cur.execute("select firm_suggest(%s)", (q,)).fetchone()[0]]

        assert slug in slugs("Search Lab")
        assert slug in slugs("SL")
        assert slug in slugs("zzlab.example")
        assert slug not in slugs("ZZ Legal Management")
        assert slug not in slugs("ZZ Growth Fund V")
        assert slug not in slugs("ZZ Register Fund")
        assert slug not in slugs("ZZ News Fund")
        assert cur.execute(
            "select count(*) from firm_aliases where firm_id = %s and alias_type = 'legal'", (fid,)
        ).fetchone()[0] == 1
        assert other in slugs("Other Legal")

        one = cur.execute("select alias from lab_check_search_names(%s, 1) order by alias", (fid,)).fetchall()
        six = cur.execute("select alias from lab_check_search_names(%s, 6) order by alias", (fid,)).fetchall()
        assert [r[0] for r in one] == [r[0] for r in six]
        assert "zzlab.example" not in [r[0] for r in one]
        assert "ZZ Growth Fund V" in [r[0] for r in one]
        assert cur.execute("select count(*) from lab_check_search_names(%s, 2)", (fid,)).fetchone()[0] == 0
        assert cur.execute("select count(*) from lab_check_search_names(%s, 1)", (oid,)).fetchone()[0] == 0
        conn.rollback()
