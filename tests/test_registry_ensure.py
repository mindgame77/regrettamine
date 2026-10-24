"""Registry link: a valid report creates/links the firm page by CRD or registry_id, never by a fuzzy name."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")

PAYLOAD = {
    "coverage": [{"checklist_item": "registration x firm", "status": "records", "query_ids": ["q1"], "record_ids": ["r1"]}],
    "search_log": [{"query_id": "q1", "tool": "form_adv", "query": "x", "executed_at": "2026-10-20T15:00:00Z"}],
    "records": [{"record_id": "r1", "field_path": "legal_entities",
                 "value": {"crd": "998101", "kind": "adviser", "registration_status": "SEC registered, Approved"}}],
}


def _j(v):
    return v if isinstance(v, (dict, list)) else json.loads(v)


def test_display_name_cleaning():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        for raw, want in [("ACCEL MANAGEMENT CO. L.L.C", "Accel"), ("THRIVE CAPITAL MANAGEMENT, LLC", "Thrive Capital"),
                          ("EJF CAPITAL LP", "EJF Capital"), ("BOXGROUP VENTURES LLC", "BoxGroup Ventures"),
                          ("LIGHTSPEED MANAGEMENT COMPANY, L.L.C.", "Lightspeed"), ("a16z crypto", "a16z Crypto"),
                          ("GILDE HEALTHCARE PARTNERS B.V.", "Gilde Healthcare Partners"),
                          ("AT ONE VENTURES OPCO, LLC", "At One Ventures"), ("MERCATO MANAGEMENT LEGACY, LLC", "Mercato"),
                          ("PEARL ENERGY INVESTMENT MANAGEMENT III, LLC", "Pearl Energy Investment"),
                          ("ALPHA SQUARE GROUP S", "Alpha Square Group"), ("1sharpe Capital", "1Sharpe Capital"),
                          ("A.capital Ventures", "A.Capital Ventures"), ("776 MANAGEMENT, LLC", "776"),
                          ("CREANDUM V ADVISOR AB", "Creandum"), ("83NORTH 2017", "83North"), ("5Y CAPITAL", "5Y Capital")]:
            cur.execute("select firm_display_name(%s)", (raw,))
            assert cur.fetchone()[0] == want, raw
        for args, want in [(("NEW YORK", "New York", "United States"), "New York, NY"), (("Austin", "TX", "US"), "Austin, TX"),
                           (("London", None, "United Kingdom"), "London, United Kingdom"),
                           (("St. Louis", "MO", "US-SMALL"), "St. Louis, MO"), (("Denver", "CO", "US-CUR"), "Denver, CO"),
                           (("Mumbai", "Maharashtra", "IN"), "Mumbai, India"),
                           (("Hong Kong", None, "Hong Kong SAR"), "Hong Kong, Hong Kong SAR")]:
            cur.execute("select firm_hq_format(%s, %s, %s)", args)
            assert cur.fetchone()[0] == want, args


def test_report_creates_published_page_and_queue_dedupes():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        # an older page whose fuzzy name matches the name-only duplicate must not steal the report
        cur.execute("insert into research_queue (registry_id, name, sec_crd, priority, status, website, hq_city, state, country) values "
                    "('zz-r1', 'ZZ ROCKET VENTURES MANAGEMENT, LLC', '998101', 5, 'submitted', 'HTTPS://WWW.ZZROCKET.VC/team', 'PALO ALTO', 'CA', 'United States')")
        cur.execute("insert into research_queue (registry_id, name, priority, status) values ('zz-r2', 'Zz Rocket Ventures', 1, 'queued') returning status, duplicate_of")
        assert cur.fetchone() == ("skipped", "zz-r1")          # name-only twin of a CRD entry
        cur.execute("insert into research_queue (registry_id, name, sec_crd, priority, status) values ('zz-r3', 'OTHER', '998101', 1, 'queued') returning 1")
        assert cur.fetchone() is None                           # second row for the same CRD is dropped
        cur.execute("insert into research_enrichments (bot_id, registry_id, payload, valid, accepted, rejected) values ('b', 'zz-r1', '{}', false, 0, 0) returning id")
        eid = cur.fetchone()[0]
        cur.execute("insert into research_submissions (registry_id, payload, valid) values ('zz-r1', %s, false)", (json.dumps({"coverage": []}),))
        cur.execute("select published, indexable from firms where registry_id = 'zz-r1'")
        assert cur.fetchall() == [(True, False)]                # queued / invalid report: only the 'Not checked yet' page (noindex)
        assert cur.execute("select count(*) from firms where registry_id = 'zz-r2'").fetchone()[0] == 0   # flagged duplicate: no page
        cur.execute("insert into research_submissions (registry_id, payload, valid) values ('zz-r1', %s, true)", (json.dumps(PAYLOAD),))
        cur.execute("select id, slug, name, display_name, legal_name, sec_crd, primary_domain, hq, published, data_status, source_system "
                    "from firms where registry_id = 'zz-r1'")
        fid, slug, name, dn, legal, crd, dom, hq, pub, ds, src = cur.fetchone()
        assert (slug, name, dn, legal) == ("zz-rocket-ventures", "ZZ Rocket Ventures", "ZZ Rocket Ventures", "ZZ ROCKET VENTURES MANAGEMENT, LLC")
        assert (crd, dom, hq, pub, ds, src) == ("998101", "zzrocket.vc", "Palo Alto, CA", True, "real", "research")
        assert cur.execute("select indexable from firms where id = %s", (fid,)).fetchone()[0] is True   # upgraded in place
        cur.execute("select firm_id from research_enrichments where id = %s", (eid,))
        assert cur.fetchone()[0] == fid                         # orphan enrichment linked
        cur.execute("select n, state from firm_check_rows where firm_id = %s order by n", (fid,))
        rows = cur.fetchall()
        assert len(rows) == 10 and rows[7] == (8, "clear") and rows[0] == (1, "nc")   # partial: rest stays 'Not checked yet'
        P = _j(cur.execute("select firm_page(%s, %s, false)", (slug, str(uuid.uuid4()))).fetchone()[0])
        assert P["status"] == "ok" and P["firm"]["name"] == "ZZ Rocket Ventures" and P["firm"]["sec_name"] == "ZZ ROCKET VENTURES MANAGEMENT, LLC"
        assert cur.execute("select name, legal_name from firm_meta(%s)", (slug,)).fetchone() == ("ZZ Rocket Ventures", "ZZ ROCKET VENTURES MANAGEMENT, LLC")
        assert any(r["slug"] == slug for r in _j(cur.execute("select firm_suggest('zz rocket')").fetchone()[0]))
        # second report and an enrichment by registry_id reuse the same page (no duplicate firm), slug sent is kept
        cur.execute("insert into research_submissions (registry_id, payload, valid) values ('zz-r2', %s, true)", (json.dumps(PAYLOAD),))
        r = _j(cur.execute("select research_enrich('b', %s)", (json.dumps({"registry_id": "zz-r1", "slug": "zz-rocket-old"}),)).fetchone()[0])
        assert r["firm"] == slug and r["on_page"] is True
        assert cur.execute("select slug, firm_id from research_enrichments where id = %s", (r["enrichment_id"],)).fetchone() == ("zz-rocket-old", fid)
        assert cur.execute("select count(*) from firms where sec_crd = '998101' or registry_id in ('zz-r1', 'zz-r2')").fetchone()[0] == 1
        conn.rollback()


def test_slug_clash_gets_suffix_and_crd_link_wins():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("insert into firms (slug, name, published, data_status) values ('zz-clash', 'Zz Clash', true, 'real')")
        cur.execute("insert into firms (slug, name, published, data_status, sec_crd) values ('zz-crd', 'Zz Curated Name', true, 'real', '998202') returning id")
        crd_fid = cur.fetchone()[0]
        cur.execute("insert into research_queue (registry_id, name, sec_crd, priority, status) values "
                    "('zz-c1', 'ZZ CLASH LLC', '998201', 1, 'submitted'), ('zz-c2', 'ZZ CURATED LEGAL NAME LP', '998202', 1, 'submitted')")
        new_id = cur.execute("select ensure_firm_for_registry('zz-c1')").fetchone()[0]
        assert cur.execute("select slug from firms where id = %s", (new_id,)).fetchone()[0] == "zz-clash-2"
        assert cur.execute("select ensure_firm_for_registry('zz-c2')").fetchone()[0] == crd_fid
        assert cur.execute("select registry_id, name from firms where id = %s", (crd_fid,)).fetchone() == ("zz-c2", "Zz Curated Name")
        conn.rollback()
