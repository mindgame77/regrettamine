"""Lab-firm leads without a source are rejected. Other firms stay held."""
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def test_unsourced_lead_is_rejected_only_for_a_lab_firm():
    import psycopg
    with psycopg.connect(DATABASE_URL) as c:
        lab = "lr-" + uuid.uuid4().hex[:8]
        other = "or-" + uuid.uuid4().hex[:8]
        lid = c.execute("insert into firms(slug, name, published, data_status) values (%s, 'Lab Rules', true, 'real') returning id", (lab,)).fetchone()[0]
        oid = c.execute("insert into firms(slug, name, published, data_status) values (%s, 'Other Rules', true, 'real') returning id", (other,)).fetchone()[0]
        c.execute("insert into ingest_settings(key, value) values ('lab_firm_slugs', %s) on conflict (key) do update set value = excluded.value", (lab,))
        c.execute("""insert into publish_checks(origin, firm_id, kind, item, outcome, reason)
                     values ('enrichment', %s, 'lead', '{"title": "unsourced"}', 'held', 'lead or allegation: held')""", (lid,))
        assert c.execute("select outcome, reason from publish_checks where firm_id = %s", (lid,)).fetchone() == (
            "rejected", "lead: rejected until it has a source")
        c.execute("""insert into publish_checks(origin, firm_id, kind, item, outcome, reason)
                     values ('enrichment', %s, 'lead', '{"title": "unsourced"}', 'held', 'lead or allegation: held')""", (oid,))
        assert c.execute("select outcome from publish_checks where firm_id = %s", (oid,)).fetchone()[0] == "held"
        c.rollback()
