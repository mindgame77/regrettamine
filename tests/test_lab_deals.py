"""Lab firms copy a deal-shaped timeline line into investments. Other firms do not."""
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def test_only_a_lab_firm_copies_a_timeline_deal():
    import psycopg
    with psycopg.connect(DATABASE_URL) as c:
        lab = "ld-" + uuid.uuid4().hex[:8]
        other = "od-" + uuid.uuid4().hex[:8]
        lid = c.execute("insert into firms(slug, name, published, data_status) values (%s, 'Lab Deal', true, 'real') returning id", (lab,)).fetchone()[0]
        oid = c.execute("insert into firms(slug, name, published, data_status) values (%s, 'Other Deal', true, 'real') returning id", (other,)).fetchone()[0]
        c.execute("insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) on conflict (key) do update set value = excluded.value", (lab,))
        c.execute("""insert into timeline_events(firm_id, date_label, kind, body, sort_order, check_mark)
                     values (%s, '2026-10-21', 'Reported', 'Sequoia led Blacksmith''s $66M Series C.', 1, 'not_checked')""", (lid,))
        n = c.execute("""select count(*) from investments i join portfolio_companies p on p.id = i.company_id
                         where i.firm_id = %s and p.name = 'Blacksmith' and i.round_name = 'Series C' and i.amount = 66000000""", (lid,)).fetchone()[0]
        assert n == 1
        c.execute("""insert into timeline_events(firm_id, date_label, kind, body, sort_order, check_mark)
                     values (%s, '2026-10-21', 'Reported', 'Sequoia led Blacksmith''s $66M Series C.', 1, 'not_checked')""", (oid,))
        assert c.execute("select count(*) from investments where firm_id = %s", (oid,)).fetchone()[0] == 0
        c.rollback()
