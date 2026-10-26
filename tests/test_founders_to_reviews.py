"""Founder quotes go to reviews (Activity); old founder cards hide once moved, per card."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _db():
    import psycopg
    return psycopg.connect(DATABASE_URL)


def _firm(c):
    slug = "fr-" + uuid.uuid4().hex[:8]
    fid = c.execute("insert into firms(slug, name, short_name, published, data_status, primary_domain) "
                    "values (%s, 'Fr Test', 'Fr', true, 'real', 'frtest.com') returning id", (slug,)).fetchone()[0]
    c.execute("update ingest_settings set value = '1' where key = 'data_rules_from_enrichment_id'")
    return slug, fid


def _enrich(c, slug, items):
    c.execute("select research_enrich('toxy-enricher', %s::jsonb)",
              (json.dumps({"slug": slug, "sections": {"What founders say": items}}),))


def test_founders_go_to_reviews_deduped_and_merged():
    with _db() as c:
        slug, fid = _firm(c)
        a = {"who": "Ann Lee, CEO of Foo, 2026-10-01", "quote": "They helped us hire.", "source": "https://blog.foo.com/yc/"}
        _enrich(c, slug, [a, dict(a)])
        _enrich(c, slug, [a, {"who": "Bob, Bar", "quote": "They helped us hire.", "source": "https://news.bar.com/x"}])
        rows = c.execute("select review_type, is_public, moderation_status, reviewed_on::text, date_precision, source_urls "
                         "from reviews where firm_id = %s", (fid,)).fetchall()
        assert len(rows) == 1
        t, pub, mod, d, prec, urls = rows[0]
        assert (t, pub, mod, d, prec) == ("founder", True, "approved", "2026-10-01", "day")
        assert sorted(urls) == ["https://blog.foo.com/yc/", "https://news.bar.com/x"]
        assert c.execute("select count(*) from founder_accounts where firm_id = %s", (fid,)).fetchone()[0] == 0
        act = c.execute("select count(*) from publish_checks where firm_id = %s and section = 'founders' and target_table = 'reviews'",
                        (fid,)).fetchone()[0]
        assert act >= 2
        c.rollback()


def test_moved_card_is_hidden_others_stay():
    with _db() as c:
        _, fid = _firm(c)
        ids = [c.execute("insert into founder_accounts(id, firm_id, outlet, date_label, headline, url, snippet, sort_order, independent) "
                         "values (gen_random_uuid(), %s, 'Blog', '2025', %s, %s, 's', 1, true) returning id",
                         (fid, h, "https://b.com/" + h)).fetchone()[0] for h in ("one", "two")]
        for i in ids:
            c.execute("insert into sources(url, retrieved_at, data_status) values ('https://b.com/src', now(), 'real') on conflict (url) do nothing")
            c.execute("insert into fact_sources(id, source_id, firm_id, fact_type, fact_id, data_status) select gen_random_uuid(), id, %s, "
                      "'founder_accounts', %s, 'real' from sources where url = 'https://b.com/src'", (fid, i))
        n = lambda: len(c.execute("select _sec_items('founders', %s)", (fid,)).fetchone()[0])
        assert n() == 2
        rid = c.execute("insert into reviews(firm_id, body, review_type) values (%s, 's', 'founder') returning id", (fid,)).fetchone()[0]
        c.execute("update founder_accounts set moved_to_review = %s where id = %s", (rid, ids[0]))
        assert n() == 1
        assert c.execute("select count(*) from founder_accounts where firm_id = %s", (fid,)).fetchone()[0] == 2
        c.rollback()
