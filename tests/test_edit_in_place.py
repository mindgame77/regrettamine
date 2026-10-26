"""edit_in_place: fix a live row where it sits (backup, no new row, no hidden copy, no fingerprint), refuse bad edits."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
DOCKET = "https://www.courtlistener.com/docket/999007/edit/"
ADV = "https://adviserinfo.sec.gov/firm/summary/999007"
LONG = ("Doe v. Edit Capital, Inc., District Court, N.D. California 5:13-cv-02054, filed 2013-05-06 — firm-named party: "
        "Edit Capital 2012 Fund, LP, Edit Capital, LLC (role: defendant (Fund, LLC, Opportunity Fund); outcome: dismissed "
        "for lack of personal jurisdiction, judgment for defendants 2014-03-24; docket entries reviewed")


def _db():
    import psycopg
    return psycopg.connect(DATABASE_URL)


def _setup(c):
    slug = "edit-" + uuid.uuid4().hex[:8]
    fid = c.execute("insert into firms(slug, name, short_name, published, data_status, primary_domain) "
                    "values (%s, 'Edit Test', 'Et', true, 'real', 'et.test') returning id", (slug,)).fetchone()[0]
    c.execute("update ingest_settings set value = '1' where key in ('data_rules_from_enrichment_id', 'auto_promote_enrichment')")
    c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps({"slug": slug, "sections": {
        "Legal & regulatory": [{"title": "Roe v. Edit Capital, 1:20-cv-00001 (D. Del.)", "source": DOCKET},
                               {"title": "Poe v. Edit Capital, 1:21-cv-00002 (D. Del.)", "source": DOCKET + "2/"}],
        "People": [{"name": "Jane Roe", "role": "Partner", "source": ADV}]}}),))
    lid = c.execute("select id from firm_legal_items where firm_id = %s and title like 'Roe%%'", (fid,)).fetchone()[0]
    # make it a long, rule-breaking row (as found in the live data)
    c.execute("update firm_legal_items set title = %s where id = %s", (LONG, lid))
    return fid, lid


def _err(c, sql, args):
    c.execute("savepoint s")
    with pytest.raises(Exception) as e:
        c.execute(sql, args)
    c.execute("rollback to savepoint s")
    return str(e.value)


def test_edit_in_place_fixes_legal_row_without_new_or_hidden_rows():
    with _db() as c:
        fid, lid = _setup(c)
        before = c.execute("select count(*), max(sort_order) filter (where id = %s) from firm_legal_items where firm_id = %s", (lid, fid)).fetchone()
        assert c.execute("select count(*) from data_rules_report() where row_id = %s", (lid,)).fetchone()[0] == 1
        rem = c.execute("select count(*) from removed_items where firm_id = %s", (fid,)).fetchone()[0]
        bid = c.execute("select edit_in_place('firm_legal_items', %s, %s, %s::jsonb, 'test-batch', 'pytest')", (lid, fid, json.dumps({
            "title": "Doe v. Edit Capital, Inc., N.D. California 5:13-cv-02054", "year_label": "2013-05-06",
            "status_label": "Defendant; dismissed for lack of personal jurisdiction, judgment for defendants 2014-03-24"}))).fetchone()[0]
        assert c.execute("select count(*), max(sort_order) filter (where id = %s) from firm_legal_items where firm_id = %s", (lid, fid)).fetchone() == before
        assert c.execute("select count(*) from firm_legal_items where firm_id = %s and hidden", (fid,)).fetchone()[0] == 0
        assert c.execute("select count(*) from removed_items where firm_id = %s", (fid,)).fetchone()[0] == rem
        assert c.execute("select count(*) from data_rules_report() where row_id = %s", (lid,)).fetchone()[0] == 0
        b = c.execute("select batch, table_name, row_id, row_data->>'title' from cleanup_backup where id = %s", (bid,)).fetchone()
        assert b == ("test-batch", "firm_legal_items", lid, LONG)
        assert c.execute("select undo_edit_in_place(%s)", (bid,)).fetchone()[0] is True
        assert c.execute("select title from firm_legal_items where id = %s", (lid,)).fetchone()[0] == LONG
        c.rollback()


def test_edit_in_place_refuses_bad_edits_and_rolls_back():
    with _db() as c:
        fid, lid = _setup(c)
        q = "select edit_in_place(%s, %s, %s, %s::jsonb, %s)"
        nb = lambda: c.execute("select count(*) from cleanup_backup where row_id = %s", (lid,)).fetchone()[0]
        assert "still breaks a rule" in _err(c, q, ("firm_legal_items", lid, fid, json.dumps({"title": LONG + " more"}), "b"))
        assert "stable key" in _err(c, q, ("firm_legal_items", lid, fid, json.dumps({"title": "Poe v. Edit Capital, 1:21-cv-00002"}), "b"))
        assert "not editable" in _err(c, q, ("firm_legal_items", lid, fid, json.dumps({"hidden": "true"}), "b"))
        assert "not editable" in _err(c, q, ("firm_legal_items", lid, fid, json.dumps({"sort_order": "1"}), "b"))
        assert "batch id" in _err(c, q, ("firm_legal_items", lid, fid, json.dumps({"title": "X v. Y"}), ""))
        assert "not on firm" in _err(c, q, ("firm_legal_items", lid, uuid.uuid4(), json.dumps({"title": "X v. Y"}), "b"))
        assert nb() == 0
        assert c.execute("select title from firm_legal_items where id = %s", (lid,)).fetchone()[0] == LONG
        c.execute("insert into locked_rows(table_name, row_id, firm_id, reason) values ('firm_legal_items', %s, %s, 'test')", (lid, fid))
        assert "locked" in _err(c, q, ("firm_legal_items", lid, fid, json.dumps({"title": "X v. Y, 1:22-cv-00003"}), "b"))
        c.rollback()


def test_edit_in_place_people_row_and_no_count_alert():
    with _db() as c:
        fid, _ = _setup(c)
        pid = c.execute("select id from firm_people_roles where firm_id = %s", (fid,)).fetchone()[0]
        c.execute("update firm_people_roles set person_name = 'Jane Roe — Partner, since 03/2015 (ADV Schedule A)', role = '' where id = %s", (pid,))
        c.execute("select edit_in_place('firm_people_roles', %s, %s, %s::jsonb, 'b')", (pid, fid, json.dumps({"person_name": "Jane Roe", "role": "Partner (since 2015-03)"})))
        assert c.execute("select person_name, role, hidden from firm_people_roles where id = %s", (pid,)).fetchone() == ("Jane Roe", "Partner (since 2015-03)", False)
        c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps({"slug": c.execute("select slug from firms where id = %s", (fid,)).fetchone()[0],
                  "sections": {"Overview": [{"label": "Founded", "value": "1999", "source": ADV}]}}),))
        assert c.execute("select count(*) from section_count_alerts where firm_id = %s", (fid,)).fetchone()[0] == 0
        c.rollback()


def test_edit_in_place_batch_keeps_good_edits_when_one_is_refused():
    with _db() as c:
        fid, lid = _setup(c)
        pid = c.execute("select id from firm_people_roles where firm_id = %s", (fid,)).fetchone()[0]
        items = [{"table": "firm_legal_items", "row": str(lid), "firm": str(fid), "fields": {"title": LONG + " x"}},
                 {"table": "firm_people_roles", "row": str(pid), "firm": str(fid), "fields": {"role": "General Partner"}}]
        got = c.execute("select row_id, backup_id is not null, error from edit_in_place_batch(%s::jsonb, 'b')", (json.dumps(items),)).fetchall()
        assert got[0][0] == lid and got[0][1] is False and "still breaks a rule" in got[0][2]
        assert got[1] == (pid, True, None)
        assert c.execute("select role from firm_people_roles where id = %s", (pid,)).fetchone()[0] == "General Partner"
        assert c.execute("select title from firm_legal_items where id = %s", (lid,)).fetchone()[0] == LONG
        c.rollback()
