"""Fix 1: latest_fund is the fund with the newest real date; heading labels are never fund names."""
import os

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_latest_fund_needs_a_real_date():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("""insert into firms (slug, name, published, data_status)
                       values ('zz-fix1', 'ZZ Fix1', true, 'real') returning id""")
        fid = cur.fetchone()[0]

        def latest():
            cur.execute("select _firm_activity(%s, true)->'latest_fund'", (fid,))
            v = cur.fetchone()[0]
            return None if v is None else v.get("name")

        # Undated rows (with or without an amount) never make a latest fund.
        cur.execute("""insert into funds (firm_id, name, raised_usd, data_status) values
                       (%s, 'ZZ Big Undated', 900000000, 'real'), (%s, 'ZZ Bare', null, 'real')""", (fid, fid))
        assert latest() is None
        # A vintage counts as a date.
        cur.execute("insert into funds (firm_id, name, vintage, data_status) values (%s, 'ZZ Vintage 2024', 2024, 'real')", (fid,))
        assert latest() == "ZZ Vintage 2024"
        # A closed_on date newer than the vintage year wins; an older one does not.
        cur.execute("insert into funds (firm_id, name, closed_on, data_status) values (%s, 'ZZ Old Close', '2019-05-01', 'real')", (fid,))
        assert latest() == "ZZ Vintage 2024"
        cur.execute("insert into funds (firm_id, name, closed_on, data_status) values (%s, 'ZZ New Close', '2025-03-01', 'real')", (fid,))
        assert latest() == "ZZ New Close"
        # Rows that are not real data are still ignored.
        cur.execute("insert into funds (firm_id, name, closed_on, data_status) values (%s, 'ZZ Proof', '2026-01-01', 'needs_proof')", (fid,))
        assert latest() == "ZZ New Close"
        conn.rollback()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_heading_labels_are_not_fund_names():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("""insert into firms (slug, name, published, data_status)
                       values ('zz-fix1h', 'ZZ Fix1 H', true, 'real') returning id""")
        fid = cur.fetchone()[0]
        for name in ("Funds", "Regulatory AUM", "Assets under management", "Fund gross assets",
                     "Newest funds", "Private funds on file", "  funds  "):
            cur.execute("select _fund_heading_name(%s)", (name,))
            assert cur.fetchone()[0] is True, name
            with pytest.raises(psycopg.errors.CheckViolation):
                with conn.transaction():
                    cur.execute("insert into funds (firm_id, name, data_status) values (%s, %s, 'real')", (fid, name))
        for name in ("ZZ Growth Fund V", "Funds of Funds I, L.P.", None):
            cur.execute("select _fund_heading_name(%s)", (name,))
            assert cur.fetchone()[0] is False, name
        conn.rollback()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_held_cleanup_takes_the_name_from_the_value():
    from pathlib import Path

    sql = (Path(__file__).resolve().parents[1] / "supabase" / "migrations" / "20261029260000_fix1_latest_fund.sql").read_text()
    body = sql.split("FUNCTION public.lab_held_cleanup", 1)[1].split("$function$", 2)[1]
    assert "'Fund'), 300)" not in body  # no made-up 'Fund' name
    assert "_fund_heading_name(x.label)" in body and "split_part(x.value, ' · ', 1)" in body
    assert "no fund name (only a heading label" in body
