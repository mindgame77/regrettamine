"""Step 3: hidden rows (with a reason) drop out of the page data, stay restorable, and promote never unhides them."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
ADV = "https://adviserinfo.sec.gov/firm/summary/999001"
DOCKET = "https://www.courtlistener.com/docket/999001/hidden-test/"
SECTIONS = {
    "Overview": [{"label": "Founded", "value": "Founded in 1999 in Menlo Park", "source": ADV},
                 {"label": "Offices", "value": "Offices in Menlo Park and London", "source": ADV}],
    "Legal & regulatory": [{"title": "Hidden Test v. Example Corp, 25-cv-01234 (N.D. Cal.)", "allegation": True, "source": DOCKET},
                           {"title": "Other Corp v. Hidden Test, 25-cv-05678 (S.D.N.Y.)", "allegation": True, "source": DOCKET + "2/"}],
    "Timeline": [{"date": "1999", "event": "Firm founded", "source": ADV},
                 {"date": "2010", "event": "Opened London office", "source": ADV}],
    "Press": [{"headline": "Hidden Test raises fund one", "source": "https://news.example.com/a", "outlet": "Example News"},
              {"headline": "Hidden Test opens London office", "source": "https://news.example.com/b", "outlet": "Example News"}],
}


def _db():
    import psycopg
    return psycopg.connect(DATABASE_URL)


def _setup(c):
    slug = "hidden-" + uuid.uuid4().hex[:8]
    fid = c.execute("insert into firms(slug, name, short_name, published, data_status, primary_domain) "
                    "values (%s, 'Hidden Test', 'Ht', true, 'real', 'ht.test') returning id", (slug,)).fetchone()[0]
    c.execute("update ingest_settings set value = '1' where key = 'data_rules_from_enrichment_id'")
    c.execute("update ingest_settings set value = '1' where key = 'auto_promote_enrichment'")
    c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps({"slug": slug, "sections": SECTIONS}),))
    return slug, fid


def _counts(c, fid):
    return {k: c.execute("select jsonb_array_length(_sec_items(%s, %s))", (k, fid)).fetchone()[0]
            for k in ("overview", "legal", "timeline", "press")}


def _one(c, table, fid, col="id"):
    return c.execute(f"select {col} from {table} where firm_id = %s order by sort_order, {col} limit 1", (fid,)).fetchone()[0]


TABLES = [("overview", "firm_profile_facts", "id"), ("legal", "firm_legal_items", "id"),
          ("timeline", "timeline_events", "id"), ("press", "press_item_firms", "press_item_id")]


def test_hide_drops_row_from_page_data_and_restore_brings_it_back():
    with _db() as c:
        slug, fid = _setup(c)
        before = _counts(c, fid)
        assert all(n == 2 for n in before.values()), before
        ids = {}
        for key, table, col in TABLES:
            ids[key] = _one(c, table, fid, col)
            c.execute("select record_removed(%s, %s, %s, 'test: wrong firm', 'pytest', true)", (table, ids[key], fid))
        after = _counts(c, fid)
        assert after == {k: 1 for k in before}, after  # the hidden row is gone, the other one still shows
        # still in the table, flagged with the reason (restorable)
        for key, table, col in TABLES:
            row = c.execute(f"select hidden, hidden_reason, hidden_by from {table} where {col} = %s and firm_id = %s",
                            (ids[key], fid)).fetchone()
            assert row == (True, "test: wrong firm", "pytest")
        # promote (re-submitting the same items) never unhides or re-adds them
        c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps({"slug": slug, "sections": SECTIONS}),))
        assert _counts(c, fid) == after
        # a plain update cannot unhide either
        c.execute("update firm_profile_facts set hidden = false where id = %s", (ids["overview"],))
        assert c.execute("select hidden from firm_profile_facts where id = %s", (ids["overview"],)).fetchone()[0] is True
        # restore_hidden does
        for key, table, col in TABLES:
            assert c.execute("select restore_hidden(%s, %s, %s, 'pytest')", (table, ids[key], fid)).fetchone()[0] is True
        assert _counts(c, fid) == before
        assert c.execute("select count(*) from removed_items where firm_id = %s", (fid,)).fetchone()[0] == 0
        c.rollback()


def test_hidden_rows_skip_hero_assets_and_site_export():
    with _db() as c:
        slug, fid = _setup(c)
        fact = _one(c, "firm_profile_facts", fid)
        c.execute("update firm_profile_facts set value = 'Item 5F regulatory assets $9,999,000', hero_label = 'AUM', hero_value = '$9.9M' where id = %s", (fact,))
        assert c.execute("select _firm_assets(%s)", (fid,)).fetchone()[0] == "$9,999,000"
        c.execute("select record_removed('firm_profile_facts', %s, %s, 'test hide', 'pytest', true)", (fact,fid))
        assert c.execute("select _firm_assets(%s)", (fid,)).fetchone()[0] is None
        press = _one(c, "press_item_firms", fid, "press_item_id")
        c.execute("update firms set indexable = true, is_test = false where id = %s", (fid,))
        c.execute("select record_removed('press_item_firms', %s, %s, 'test hide', 'pytest', true)", (press, fid))
        core = c.execute("select published_site_core()").fetchone()[0]
        mine = [r for r in core["press_item_firms"] if r["firm_id"] == str(fid)]
        assert len(mine) == 1 and mine[0]["press_item_id"] != str(press)
        c.rollback()


def test_record_removed_without_hide_still_works_and_needs_reason():
    with _db() as c:
        slug, fid = _setup(c)
        tid = _one(c, "timeline_events", fid)
        with pytest.raises(Exception):
            with c.transaction():
                c.execute("select record_removed('timeline_events', %s, %s, ' ', 'pytest', true)", (tid, fid))
        c.execute("select record_removed('timeline_events', %s, %s, 'delete next', 'pytest')", (tid, fid))
        assert c.execute("select hidden from timeline_events where id = %s", (tid,)).fetchone()[0] is False
        c.rollback()
