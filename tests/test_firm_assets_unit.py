"""AUM tile unit (2026-10-29): _firm_assets keeps a unit written after the number."""
import os

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
CASES = [
    ("RAUM $18.27B per Item 5F", "$18.27B"),
    ("Regulatory AUM $3.3 billion", "$3.3 billion"),
    ("Regulatory AUM $450 million", "$450 million"),
    ("Regulatory AUM $900 thousand", "$900 thousand"),
    ("Regulatory AUM $3.5bn", "$3.5bn"),
    ("Regulatory AUM $250 mn", "$250 mn"),
    ("Item 5F $1,234,567", "$1,234,567"),
    ("Item 5F $18.27 by year end", "$18.27"),
    ("Item 5F $20 Mbps", "$20"),
]


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
@pytest.mark.parametrize("value,want", CASES)
def test_assets_unit(value, want):
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into firms (slug, name, published, data_status) values ('zz-aum', 'ZZ Aum', true, 'real') returning id")
        fid = cur.fetchone()[0]
        # Existing (pre fix 3) AUM cards: new ones are blocked by money_home_guard, so load this one like the seed does.
        cur.execute("set local session_replication_role = replica")
        cur.execute("insert into firm_profile_facts (firm_id, label, value, section, sort_order) values (%s, 'AUM', %s, 'overview', 1)",
                    (fid, value))
        cur.execute("set local session_replication_role = origin")
        cur.execute("select public._firm_assets(%s)", (fid,))
        assert cur.fetchone()[0] == want
        conn.rollback()
