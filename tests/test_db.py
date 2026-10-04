"""Migrations, seed, identical site, score, RLS, and one stress insert."""
import json
import os
from pathlib import Path

import pytest

pytest.importorskip("psycopg")

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")

ROOT = Path(__file__).resolve().parents[1]


def test_seed_matches_json_and_hides_stress():
    import psycopg

    from build import build_home, render_fund_page
    from regrettamine.assemble import assemble_site
    from regrettamine.score_v2 import score_v2
    from scripts.seed import main as seed_main
    from scripts.stress_fixture import insert_stress

    seed_main()
    home = json.loads((ROOT / "data" / "home.json").read_text(encoding="utf-8"))
    fund = json.loads((ROOT / "data" / "funds" / "a16z.json").read_text(encoding="utf-8"))

    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute("select published_site_bundle()")
            bundle = cur.fetchone()[0]
        assembled_home, assembled_funds = assemble_site(bundle)
        assert assembled_home == home
        assert assembled_funds["a16z"] == fund
        assert build_home(assembled_home) == build_home(home)
        assert render_fund_page(assembled_funds["a16z"], "../../") == render_fund_page(fund, "../../")

        with conn.cursor() as cur:
            cur.execute(
                """
                select si.section_code, si.name, si.value_numeric, si.value_text, si.max_numeric
                from score_inputs si
                join score_results sr on sr.id = si.result_id
                join score_versions sv on sv.id = sr.version_id
                join firms f on f.id = sr.firm_id
                where f.slug = 'a16z' and sv.code = 'v2' and sr.is_current
                order by si.sort_order
                """
            )
            inputs = [
                {
                    "section_code": section,
                    "name": name,
                    "value_numeric": value,
                    "value_text": text,
                    "max_numeric": maximum,
                }
                for section, name, value, text, maximum in cur.fetchall()
            ]
        from decimal import Decimal

        result = score_v2(inputs)
        assert result["sections"]["s1"] == Decimal("60")
        assert result["sections"]["s2"] == Decimal("14.25")
        assert result["sections"]["s3"] == Decimal("16.6")
        assert result["sections"]["s4"] == Decimal("4")
        assert result["sections"]["bonus"] == Decimal("3")
        assert result["sections"]["pen"] == Decimal("-2.5")
        assert result["total"] == Decimal("95.4")

        with conn.cursor() as cur:
            cur.execute(
                "select anonymous_free_reports, registered_extra_reports, dwell_ms from gating_policies where code = 'default'"
            )
            assert cur.fetchone() == (2, 5, 2000)
            insert_stress(conn)
            conn.commit()
            cur.execute("select count(*) from portfolio_companies c join investments i on i.company_id = c.id join firms f on f.id = i.firm_id where f.slug = 'stress-fixture'")
            assert cur.fetchone()[0] == 1000
            cur.execute("select count(*) from reviews r join firms f on f.id = r.firm_id where f.slug = 'stress-fixture'")
            assert cur.fetchone()[0] == 100
            cur.execute("select count(*) from funds u join firms f on f.id = u.firm_id where f.slug = 'stress-fixture'")
            assert cur.fetchone()[0] == 3
            cur.execute("select count(*) from fund_people fp join firms f on f.id = fp.firm_id where f.slug = 'stress-fixture'")
            assert cur.fetchone()[0] == 20
            cur.execute("select count(*) from fact_sources fs join firms f on f.id = fs.firm_id where f.slug = 'stress-fixture'")
            assert cur.fetchone()[0] == 150
            cur.execute("select published, is_test from firms where slug = 'stress-fixture'")
            assert cur.fetchone() == (False, True)
            with pytest.raises(psycopg.errors.CheckViolation):
                cur.execute(
                    "update firms set published = true where slug = 'stress-fixture'"
                )
            conn.rollback()

        with psycopg.connect(DATABASE_URL) as conn2:
            with conn2.cursor() as cur:
                cur.execute("select published_site_bundle()")
                public = cur.fetchone()[0]
            slugs = [firm["slug"] for firm in public["firms"]]
            assert "stress-fixture" not in slugs
            assert "a16z" in slugs
            with conn2.cursor() as cur:
                cur.execute("set role anon")
                cur.execute("select count(*) from firms")
                assert cur.fetchone()[0] == 11
                cur.execute("select count(*) from firms where is_test")
                assert cur.fetchone()[0] == 0
                cur.execute("savepoint anon_write")
                with pytest.raises(psycopg.Error):
                    cur.execute(
                        "insert into firms (slug, name, published, is_test) values ('anon-nope', 'Nope', true, false)"
                    )
                cur.execute("rollback to savepoint anon_write")
                cur.execute("reset role")
