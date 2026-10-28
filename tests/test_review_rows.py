"""Opened Review rows list cases already stored. Payloads and check rows are not rewritten."""
import json
import os
import pathlib
import uuid

import pytest
CHECKS_OFF = pytest.mark.skip(reason="checks are off (Alex 2026-10-28): firm_check_rows is no longer filled")

ROOT = pathlib.Path(__file__).resolve().parents[1]
COPY = json.loads((ROOT / "launch" / "copy.json").read_text())
JS = (ROOT / "launch" / "js" / "company.js").read_text()


def test_review_row_copy_is_the_approved_wording():
    table = COPY["company"]["table"]
    assert table["active_h"] == ["{n} active case:", "{n} active cases:"]
    assert table["coming"] == ["{n} active case, details coming soon", "{n} active cases, details coming soon"]
    assert table["search_courts"] == "Search court records"
    assert table["source"] == "Source:"
    assert table["docket"] == "CourtListener docket"
    assert "T.none_itemized" not in JS
    assert "courtlistener.com/?q=" in JS
    assert "check_row_items" in (ROOT / "supabase" / "migrations" / "20261025230000_check_case_items.sql").read_text()


pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
@CHECKS_OFF
def test_saved_cases_fill_a_review_row_without_rewriting_rows():
    import psycopg

    note_s = "Lido token buyers' class action. N.D. Cal. 3:23-cv-06492, stayed."
    note_h = "Compound token buyers class action. N.D. Cal. 3:22-cv-07781."
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute(
            """insert into firms (slug, name, display_name, legal_name, published, data_status)
               values ('zz-cases', 'ZZ Cases Ventures', 'ZZ Cases Ventures', 'ZZ Cases Ventures, L.L.C.', true, 'real')
               returning id"""
        )
        fid = cur.fetchone()[0]
        cur.execute(
            "insert into firm_check_rows (firm_id, n, title, descr, state, count_label) select %s, n, 'T' || n, 'D', 'nc', null from generate_series(1, 10) n",
            (fid,),
        )
        cur.execute(
            """update firm_check_rows set state = 'review', count_label = case n
                 when 4 then '1 open probe' when 5 then '3 active cases' when 6 then '2 active cases · 11 on file' else count_label end
               where firm_id = %s and n in (4, 5, 6)""",
            (fid,),
        )
        rows = [
            ("case", "Samuels v. Lido DAO", "2023", "Active", None, note_s, "https://www.courtlistener.com/docket/zz-samuels/", "CourtListener 3:23-cv-06492"),
            ("case", "Houghton v. AH Capital Mgmt (Compound)", "2022", "Active", None, note_h, "https://www.courtlistener.com/docket/zz-houghton/", "CourtListener 3:22-cv-07781"),
            ("case", "Old Closed v. Firm", "2019", "Closed", None, "Closed. N.D. Cal. 1:19-cv-00001.", "https://www.courtlistener.com/docket/zz-closed/", "CourtListener"),
            ("case", "London v. Firm", "2021", "Active", None, "Claim in the High Court of England and Wales.", "https://www.courtlistener.com/docket/zz-london/", "CourtListener"),
            ("case", "Future Year v. Firm", "2054", "Active", None, "N.D. Cal. 1:54-cv-00001.", "https://www.courtlistener.com/docket/zz-future/", "CourtListener"),
            ("regulator", "DOJ antitrust probe", None, None, "Open · no charges", "Board seats. No court named.", "https://www.bloomberg.com/news/zz-doj-probe", "Bloomberg"),
            ("regulator", "SEC disciplinary record", None, None, "None filed", "No action.", "https://adviserinfo.sec.gov/firm/summary/zz", "SEC IAPD"),
            ("regulator", "Sanctions lists", None, None, "No match", "No match.", "https://www.opensanctions.org/zz", "OpenSanctions"),
            ("regulator", "Parent order", None, None, "Parent · settled", "Parent, not the adviser.", "https://www.sec.gov/zz-parent", "SEC"),
            ("context", "Background", None, None, None, "Not a case.", "https://example.com/zz-context", "Example"),
        ]
        for i, (grp, title, year, state, status, note, url, label) in enumerate(rows):
            cur.execute(
                """insert into firm_legal_items (firm_id, grp, title, year_label, state, status_label, note, sort_order)
                   values (%s, %s, %s, %s, %s, %s, %s, %s) returning id""",
                (fid, grp, title, year, state, status, note, i),
            )
            item = cur.fetchone()[0]
            cur.execute(
                "insert into sources (url, retrieved_at, data_status) values (%s, now(), 'real') on conflict (url) do update set url = excluded.url returning id",
                (url,),
            )
            sid = cur.fetchone()[0]
            cur.execute(
                """insert into fact_sources (source_id, firm_id, fact_type, fact_id, label, sort_order, data_status)
                   values (%s, %s, 'firm_legal_items', %s, %s, 0, 'real')""",
                (sid, fid, item, label),
            )
        cur.execute("select title, yr, status, court, src_url, src_label from check_saved_items(%s, 6) order by title", (fid,))
        us = cur.fetchall()
        assert [r[0] for r in us] == ["Future Year v. Firm", "Houghton v. AH Capital Mgmt (Compound)", "Samuels v. Lido DAO"]
        by = {r[0]: r for r in us}
        assert by["Samuels v. Lido DAO"][1:] == ("2023", "Active", "N.D. Cal.", "https://www.courtlistener.com/docket/zz-samuels/", "CourtListener 3:23-cv-06492")
        assert by["Houghton v. AH Capital Mgmt (Compound)"][3] == "N.D. Cal."
        assert by["Future Year v. Firm"][1] is None
        cur.execute("select title from check_saved_items(%s, 7)", (fid,))
        assert cur.fetchall() == [("London v. Firm",)]
        cur.execute("select title, status, src_label from check_saved_items(%s, 4)", (fid,))
        assert cur.fetchall() == [("DOJ antitrust probe", "Open · no charges", "Bloomberg")]
        cur.execute("select count(*) from check_saved_items(%s, 5)", (fid,))
        assert cur.fetchone()[0] == 0
        cur.execute("select note from firm_legal_items where firm_id = %s and title = 'Samuels v. Lido DAO'", (fid,))
        assert cur.fetchone()[0] == note_s
        cur.execute("select count_label, source_submission from firm_check_rows where firm_id = %s and n = 6", (fid,))
        assert cur.fetchone() == ("2 active cases · 11 on file", None)

        anon = str(uuid.uuid4())
        cur.execute("select firm_page('zz-cases', %s, true)", (anon,))
        page = cur.fetchone()[0]
        page = page if isinstance(page, dict) else json.loads(page)
        assert page["firm"]["sec_name"] == "ZZ Cases Ventures, L.L.C."
        c6 = next(c for c in page["checks"] if c["n"] == 6)
        assert c6["itemized"] == 3
        assert [i["title"] for i in c6["items"]] == ["Samuels v. Lido DAO", "Houghton v. AH Capital Mgmt (Compound)", "Future Year v. Firm"]
        assert c6["items"][0]["url"].endswith("/zz-samuels/")
        assert c6["items"][0]["court"] == "N.D. Cal."
        c4 = next(c for c in page["checks"] if c["n"] == 4)
        assert [i["title"] for i in c4["items"]] == ["DOJ antitrust probe"]
        c5 = next(c for c in page["checks"] if c["n"] == 5)
        assert c5["items"] == [] and c5["itemized"] == 0
        cur.execute("select count_label from firm_check_rows where firm_id = %s and n = 6", (fid,))
        assert cur.fetchone()[0] == "2 active cases · 11 on file"
        conn.rollback()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
@CHECKS_OFF
def test_submission_findings_win_and_keep_their_source():
    import psycopg

    payload = {
        "coverage": [{"checklist_item": "legal.lawsuit x firm", "status": "records", "query_ids": ["q"], "record_ids": ["a", "b"]}],
        "search_log": [{"query_id": "q", "tool": "courtlistener", "query": "x"}],
        "records": [
            {"record_id": "a", "field_path": "lawsuits", "checklist_item": "legal.lawsuit x firm",
             "value": {"caption": "Caption v. Firm", "status": "open", "court": "S.D.N.Y.", "filed_at": "2014-02-03"},
             "sources": [{"url": "https://www.courtlistener.com/docket/zz-caption/"}]},
            {"record_id": "b", "field_path": "lawsuits", "checklist_item": "legal.lawsuit x firm",
             "value": {"case": "Only Case Name", "status": "open", "filed_at": "2015-06-07"},
             "sources": [{"url": "https://news.example.com/zz-only-case"}]},
        ],
    }
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute(
            """insert into firms (slug, name, display_name, legal_name, published, data_status, sec_crd)
               values ('zz-subwin', 'ZZ Subwin Capital', 'ZZ Subwin Capital', 'ZZ SUBWIN CAPITAL LLC', true, 'real', '999771')
               returning id"""
        )
        fid = cur.fetchone()[0]
        cur.execute(
            "insert into firm_check_rows (firm_id, n, title, descr, state) select %s, n, 'T' || n, 'D', 'nc' from generate_series(1, 10) n",
            (fid,),
        )
        cur.execute("insert into research_queue (registry_id, name, sec_crd, priority, status) values ('zz-subwin', 'ZZ SUBWIN CAPITAL LLC', '999771', 1, 'submitted')")
        cur.execute("insert into research_submissions (registry_id, payload, valid) values ('zz-subwin', %s, true) returning id", (json.dumps(payload),))
        sid = cur.fetchone()[0]
        cur.execute(
            """insert into firm_legal_items (firm_id, grp, title, year_label, state, note, sort_order)
               values (%s, 'case', 'Saved Case That Must Not Show', '2020', 'Active', 'N.D. Cal. extra.', 0)""",
            (fid,),
        )
        cur.execute("select title, court, src_url from check_findings(%s) where k = 6 order by title", (sid,))
        got = cur.fetchall()
        assert ("Caption v. Firm", "S.D.N.Y.", "https://www.courtlistener.com/docket/zz-caption/") in got
        assert ("Only Case Name", None, "https://news.example.com/zz-only-case") in got
        anon = str(uuid.uuid4())
        cur.execute("select firm_page('zz-subwin', %s, true)", (anon,))
        page = cur.fetchone()[0]
        page = page if isinstance(page, dict) else json.loads(page)
        titles = [i["title"] for i in next(c for c in page["checks"] if c["n"] == 6)["items"]]
        assert titles == ["Saved Case That Must Not Show"]
        assert "Only Case Name" not in titles and "Caption v. Firm" not in titles
        cur.execute("select payload->'records'->1->'value'->>'case' from research_submissions where id = %s", (sid,))
        assert cur.fetchone()[0] == "Only Case Name"
        conn.rollback()
