"""Enricher ingest: promotion on top of the friend's data, source rules, correction overrides, search log, section status."""
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


def test_enrichment_promotes_without_touching_friend_rows():
    slug = "enr-" + uuid.uuid4().hex[:8]
    with _db() as c:
        fid = c.execute("insert into firms(slug, name, short_name, published, data_status, primary_domain) values (%s, 'Enr Test', 'Enrtest', true, 'real', 'enrtest.com') returning id", (slug,)).fetchone()[0]
        pid = c.execute("insert into firm_people_roles(firm_id, kind, person_name, role, sort_order) values (%s, 'officer', 'Jane Roe', 'Partner', 1) returning id", (fid,)).fetchone()[0]
        c.execute("insert into sources(url, retrieved_at, data_status) values ('https://example.com/team', now(), 'real') on conflict (url) do nothing")
        c.execute("insert into fact_sources(id, source_id, firm_id, fact_type, fact_id, data_status) select gen_random_uuid(), id, %s, 'firm_people_roles', %s, 'real' from sources where url = 'https://example.com/team'", (fid, pid))
        p = {"slug": slug, "sections": {
            "Press coverage": [{"outlet": "TechCrunch", "date": "2026-08-11", "headline": "Enr raises", "url": "https://techcrunch.com/enr", "snippet": "s"}],
            "What founders say": [{"who": "A founder, X, 2026-10-20", "quote": "great", "source": "https://x.com/someone/status/1"},
                                  {"who": "Enr, X", "quote": "we are great", "source": "https://x.com/enrtest/status/2"}],
            "Timeline": [{"date": "1983", "item": "Founded", "source": "https://www.reuters.com/a"}],
            "Legal & regulatory": [{"item": "Doe v. Enr, terminated 2025", "source": "https://www.courtlistener.com/docket/1/"},
                                   {"item": "Embassy bio", "source": "https://us.embassy.gov/bio"}],
            "Funds": [{"item": "Fund I", "source": "https://reports.adviserinfo.sec.gov/x.pdf"}]},
            "fix": [{"field": "people[Jane Roe].current", "bot_value": "Partner", "correct_value": "former partner (left 2020)", "source_url": "https://www.sec.gov/x"},
                    {"field": "aum", "correct_value": "no figure", "source_url": "https://www.sec.gov/y"}],
            "leads": [{"field": "lawsuits", "value": "Founder alleges breach", "source_url": "https://www.axios.com/z"}],
            "add": [{"field": "people", "value": "No source here"}],
            "searches": [{"section": "board_seats", "site": "sec.gov", "query": "Enr board", "searched_at": "2026-10-24", "result": "none", "item_count": 0}]}
        r = c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps(p),)).fetchone()[0]
        assert r["valid"] and r["on_page"]
        reasons = {x["reason"] for x in r["rejected"]}
        assert any("not allowed" in x for x in reasons) and "no source URL" in reasons and "AUM needs a numeric figure" in reasons
        n = lambda k: len(c.execute("select _sec_items(%s, %s)", (k, fid)).fetchone()[0])
        assert n("press") == 1 and n("founders") == 2 and n("timeline") == 1 and n("legal") == 2 and n("funds") == 1
        # firm-owned founder source is labelled as not independent
        assert c.execute("select count(*) from founder_accounts where firm_id = %s and not independent and outlet like '%%not independent%%'", (fid,)).fetchone()[0] == 1
        # leads are marked unverified
        assert c.execute("select state from firm_legal_items where firm_id = %s and title like 'Lead%%'", (fid,)).fetchone()[0] == "Unverified"
        # the fix overrides the displayed role; the friend's row itself is unchanged
        people = c.execute("select _sec_items('people', %s)", (fid,)).fetchone()[0]
        jane = [x for x in people if x["head"] == "Jane Roe"][0]
        assert jane["role"].startswith("former partner") and jane["badge"] == "Corrected"
        assert c.execute("select role from firm_people_roles where id = %s", (pid,)).fetchone()[0] == "Partner"
        # re-promotion is idempotent and leaves the friend's rows alone
        before = c.execute("select count(*) from enrichment_rows where firm_id = %s", (fid,)).fetchone()[0]
        c.execute("select promote_enrichment(%s)", (fid,))
        assert c.execute("select count(*) from enrichment_rows where firm_id = %s", (fid,)).fetchone()[0] == before
        assert c.execute("select count(*) from firm_people_roles where id = %s", (pid,)).fetchone()[0] == 1
        # search log + section status: board_seats searched with no result counts as done
        st = dict(c.execute("select item, status from firm_section_status where slug = %s", (slug,)).fetchall())
        assert st["press"] == "filled" and st["board_seats"] == "searched_none" and st["checks"] == "missing"
        assert c.execute("select count(*) from next_firms_to_enrich(500) where slug = %s", (slug,)).fetchone()[0] == 1
        assert c.execute("select count(*) from site_search_stats where source_site = 'sec.gov'").fetchone()[0] == 1
        c.rollback()
