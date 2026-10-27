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
            "Press coverage": [{"outlet": "TechCrunch", "date": "2026-08-11", "headline": "Enr raises", "url": "https://techcrunch.com/enr", "snippet": "s"},
                               {"outlet": "Enr Pod", "date": "2026-08-12", "headline": "Episode 1", "url": "https://enrpod.fm/ep/2", "snippet": "s"}],
            "What founders say": [{"who": "A founder, X, 2026-10-20", "quote": "great", "source": "https://x.com/someone/status/1"},
                                  {"who": "Enr, X", "quote": "we are great", "source": "https://x.com/enrtest/status/2"},
                                  {"who": "B founder, Enr Pod", "quote": "on our pod", "source": "https://www.enrpod.fm/ep/1"}],
            "Timeline": [{"date": "1983", "event": "Founded", "source": "https://www.reuters.com/a"}],
            "Legal & regulatory": [{"title": "Doe v. Enr, terminated 2025", "source": "https://www.courtlistener.com/docket/1/"},
                                   {"title": "Embassy bio", "source": "https://us.embassy.gov/bio"}],
            "Funds": [{"name": "Fund I", "source": "https://reports.adviserinfo.sec.gov/x.pdf"}]},
            "fix": [{"field": "people[Jane Roe].current", "bot_value": "Partner", "correct_value": "former partner (left 2020)", "source_url": "https://www.sec.gov/x"},
                    {"field": "aum", "correct_value": "no figure", "source_url": "https://www.sec.gov/y"}],
            "owned_media": [{"url": "https://enrpod.fm", "label": "Enr Pod"}],
            "leads": [{"field": "lawsuits", "value": {"title": "Founder alleges breach"}, "source_url": "https://www.axios.com/z"}],
            "add": [{"field": "people", "value": "No source here"}],
            "searches": [{"section": "board_seats", "site": "sec.gov", "query": "Enr board", "searched_at": "2026-10-24", "result": "none", "item_count": 0}]}
        r = c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps(p),)).fetchone()[0]
        assert r["valid"] and r["on_page"]
        reasons = {x["reason"] for x in r["rejected"]}
        # source tiers (docs/SOURCE_TIERS.md): any real page is accepted (the embassy .gov bio is tier 'other'); no URL stays unshown
        assert not any("not allowed" in x for x in reasons) and "no source URL" in reasons and "AUM needs a numeric figure" in reasons
        n = lambda k: len(c.execute("select _sec_items(%s, %s)", (k, fid)).fetchone()[0])
        # A new press link is not_checked, so it stays off the page until someone marks it.
        assert c.execute("select check_mark from press_item_firms where firm_id = %s order by sort_order", (fid,)).fetchall() == [("not_checked",), ("not_checked",)]
        assert n("press") == 0 and n("founders") == 0 and n("timeline") == 1 and n("legal") == 2 and n("funds") == 1
        assert dict(c.execute("select item, status from firm_section_status where slug = %s", (slug,)).fetchall())["press"] == "missing"
        c.execute("update press_item_firms set check_mark = 'checked_correct' where firm_id = %s", (fid,))
        assert n("press") == 2
        # founder quotes go to reviews (Activity), not founder_accounts; firm-owned sources are firm_voice, not public
        assert c.execute("select count(*) from founder_accounts where firm_id = %s", (fid,)).fetchone()[0] == 0
        rv = c.execute("select review_type, is_public, independent from reviews where firm_id = %s order by review_type", (fid,)).fetchall()
        assert rv == [("firm_voice", False, False), ("firm_voice", False, False), ("founder", True, True)]
        # owned media from the payload (a podcast the firm runs) also marks press as own media
        press = c.execute("select _sec_items('press', %s)", (fid,)).fetchone()[0]
        assert [x["independent"] for x in press if "enrpod" in x["url"]] == [False]
        # leads are never public (step 4): they stay in the holding area, logged as rejected
        assert c.execute("select count(*) from firm_legal_items where firm_id = %s and title like 'Lead%%'", (fid,)).fetchone()[0] == 0
        assert any(x.startswith("lead:") for x in reasons)
        # fixes are held for a person (publish step): the displayed role and the friend's row stay unchanged
        people = c.execute("select _sec_items('people', %s)", (fid,)).fetchone()[0]
        jane = [x for x in people if x["head"] == "Jane Roe"][0]
        assert not jane["role"].startswith("former partner") and jane.get("badge") != "Corrected"
        assert c.execute("select count(*) from publish_checks where firm_id = %s and kind = 'fix' and outcome = 'held'", (fid,)).fetchone()[0] >= 1
        assert c.execute("select count(*) from firm_corrections where firm_id = %s", (fid,)).fetchone()[0] == 0
        # a second enrichment for the same firm: its fixes are held too, its new person is added
        p["sections"]["People & board seats"] = [{"name": "Max Doe", "role": "Partner", "since": "2019", "source": "https://www.sec.gov/p"}]
        p["fix"] += [{"field": "people[Max Doe].current", "bot_value": "Partner", "correct_value": "former partner (left 2026)", "source_url": "https://tech.eu/m"}]
        c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps(p),))
        people = c.execute("select _sec_items('people', %s)", (fid,)).fetchone()[0]
        mx = [x for x in people if x["head"].startswith("Max Doe")][0]
        assert mx["role"].startswith("Partner")
        assert c.execute("select role from firm_people_roles where id = %s", (pid,)).fetchone()[0] == "Partner"
        # re-promotion is idempotent and leaves the friend's rows alone
        before = c.execute("select count(*) from enrichment_rows where firm_id = %s", (fid,)).fetchone()[0]
        c.execute("select promote_enrichment(%s)", (fid,))
        assert c.execute("select count(*) from enrichment_rows where firm_id = %s", (fid,)).fetchone()[0] == before
        assert c.execute("select count(*) from firm_people_roles where id = %s", (pid,)).fetchone()[0] == 1
        # search log + section status: board_seats searched with no result counts as done
        st = dict(c.execute("select item, status from firm_section_status where slug = %s", (slug,)).fetchall())
        assert st["press"] == "filled" and st["board_seats"] == "searched_none" and st["checks"] == "missing"
        assert c.execute("select check_mark from press_item_firms where firm_id = %s", (fid,)).fetchall() == [("checked_correct",), ("checked_correct",)]
        assert c.execute("select count(*) from next_firms_to_enrich(500) where slug = %s", (slug,)).fetchone()[0] == 1
        assert c.execute("select count(*) from site_search_stats where source_site = 'sec.gov'").fetchone()[0] == 1
        c.rollback()


def test_superseded_enrichment_search_log_is_not_counted():
    slug = "enrs-" + uuid.uuid4().hex[:8]
    with _db() as c:
        fid = c.execute("insert into firms(slug, name, short_name, published, data_status, primary_domain) values (%s, 'Enrs Test', 'Enrs', true, 'real', 'enrs.com') returning id", (slug,)).fetchone()[0]
        old = {"slug": slug, "sections": {"Timeline": [{"date": "1990", "event": "Founded", "source": "https://www.reuters.com/enrs"}]},
               "searches": [{"section": "board_seats", "site": "sec.gov", "query": "Enrs board", "searched_at": "2026-10-23", "result": "none", "item_count": 0}]}
        new = dict(old, searches=[{"section": "board_seats", "site": "sec.gov", "query": "Enrs board v2", "searched_at": "2026-10-24", "result": "error", "item_count": 0}])
        c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps(old),))
        c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps(new),))
        # nothing is deleted: both versions stay in search_log
        assert c.execute("select count(*) from search_log where firm_id = %s and section = 'board_seats'", (fid,)).fetchone()[0] == 2
        # only the latest enrichment counts
        assert c.execute("select count(*) from search_log_current where firm_id = %s and section = 'board_seats'", (fid,)).fetchone()[0] == 1
        assert c.execute("select searches, none from firm_site_coverage where firm_id = %s and section = 'board_seats' and source_site = 'sec.gov'", (fid,)).fetchone() == (1, 0)
        st = dict(c.execute("select item, status from firm_section_status where slug = %s", (slug,)).fetchall())
        assert st["board_seats"] == "missing"


UPFRONT_NOTE = (
    "Sanctions search log: result recorded as 'none' (the spec's closest neutral value; "
    "the searches field allows only found/none/blocked/error) — name-only near match, unconfirmed; "
    "not a hit and not an identification of anyone.\n"
    "Kan Chen ITAR name-only match: the public identifiers differ; kept as a name-only lead.\n"
    "[Legal & regulatory] Sanctions screen: name-only match: \"Kevin Zhang\" matches the name in "
    "Consolidated Screening List entry \"Kevin Zhang\" (ITAR Debarred (DTC) - State Department, 78 FR 66984); "
    "no shared identifiers, across OFAC SDN (+ALT), OFAC non-SDN consolidated, Consolidated Screening List, "
    "UN, UK (FCDO) and EU lists for 35 names.\n"
    "Surname-only match for Tucker, not this person."
)


def _checks(slug):
    return {"slug": slug, "sections": {"Timeline": [{"date": "1983", "event": "Founded", "source": "https://www.reuters.com/a"}]}}


def test_name_only_flag_is_clear_and_leaves_the_payload_alone():
    slug = "nmon-" + uuid.uuid4().hex[:8]
    with _db() as c:
        fid = c.execute(
            "insert into firms(slug, name, short_name, published, data_status, primary_domain) "
            "values (%s, 'Name Only Test', 'Nmon', true, 'real', 'nmon.test') returning id",
            (slug,),
        ).fetchone()[0]
        c.execute(
            "insert into firm_check_rows (firm_id, n, title, descr, state) "
            "select %s, n, 'T' || n, 'D', 'nc' from generate_series(1, 10) n",
            (fid,),
        )
        c.execute("update firm_check_rows set state = 'review' where firm_id = %s and n = 4", (fid,))
        def parsed(txt):
            return c.execute("select n, list_name from _name_only_from_text(%s) order by 1, 2", (txt,)).fetchall()
        # the log line names the file that was screened; the list after the phrase is the one that counts
        assert parsed('Screened against UK Sanctions List, report date 2026-10-16: name-only match: "James Kim" appears as an alias string in the EU consolidated list, across OFAC SDN and EU lists. — https://sanctionslist.fcdo.gov.uk/docs/UK-Sanctions-List.csv') == [(1, "EU consolidated list")]
        assert parsed('Screened against UK Sanctions List: name-only match: "John Lee" matches a Consolidated Screening List Non-SDN Menu-Based Sanctions (NS-MBS) entry, across OFAC SDN and UK lists.') == [(1, "Non-SDN Menu-Based Sanctions (NS-MBS)")]
        assert parsed('name-only near match, unconfirmed. Surname-only match for Tucker. recorded as name-only text matches, not a hit.') == []
        p = _checks(slug)
        p["notes"] = UPFRONT_NOTE
        p["searches"] = [{"section": "checks", "site": "trade.gov", "query": "35 names", "searched_at": "2026-10-24", "result": "none", "item_count": 0}]
        raw = json.dumps(p)
        c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (raw,))
        stored = c.execute("select payload from research_enrichments where firm_id = %s", (fid,)).fetchone()[0]
        if isinstance(stored, str):
            stored = json.loads(stored)
        assert stored == p
        # the screened-list trailer is not a hit; the shorter ITAR label collapses into the specific one
        rows = dict(c.execute("select n, name_only from firm_check_rows where firm_id = %s and name_only is not null", (fid,)).fetchall())
        assert rows == {3: ["ITAR Debarred (DTC)"]}
        assert c.execute("select state from firm_check_rows where firm_id = %s and n = 3", (fid,)).fetchone()[0] == "nc"
        anon = str(uuid.uuid4())
        def page(spend):
            v = c.execute("select firm_page(%s, %s, %s)", (slug, anon, spend)).fetchone()[0]
            return v if isinstance(v, dict) else json.loads(v)
        locked = page(False)
        assert not locked["open"]
        assert all(ch["state"] is None and ch["name_only"] is None for ch in locked["checks"])
        opened = page(True)
        by_n = {ch["n"]: ch for ch in opened["checks"]}
        assert opened["open"] and by_n[3]["state"] == "clear" and by_n[3]["name_only"] == ["ITAR Debarred (DTC)"]
        assert by_n[1]["name_only"] is None and by_n[1]["state"] == "nc"
        # a real review is not turned into a name-only Clear
        c.execute("update firm_check_rows set name_only = array['OFAC SDN'], state = 'review' where firm_id = %s and n = 1", (fid,))
        opened = page(False)
        by_n = {ch["n"]: ch for ch in opened["checks"]}
        assert by_n[1]["state"] == "review" and by_n[1]["name_only"] is None
        # re-promotion from a structured flag replaces the derived row; the first payload is untouched
        before = c.execute("select id, md5(payload::text) from research_enrichments where firm_id = %s", (fid,)).fetchone()
        p2 = _checks(slug)
        p2["searches"] = [{"section": "checks", "site": "fcdo.gov.uk", "query": "James Kim", "searched_at": "2026-10-25", "result": "none", "item_count": 0,
                           "name_only": True, "list": "EU consolidated list", "check": 1}]
        c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps(p2),))
        assert c.execute("select md5(payload::text) from research_enrichments where id = %s", (before[0],)).fetchone()[0] == before[1]
        rows = dict(c.execute("select n, name_only from firm_check_rows where firm_id = %s and name_only is not null order by n", (fid,)).fetchall())
        assert rows[1] == ["EU consolidated list"] and 3 not in rows
        assert c.execute("select result, name_only from search_log_current where firm_id = %s and section = 'checks' and query = 'James Kim'", (fid,)).fetchone() == ("none", True)
        # near-match boilerplate and a surname-only line do not invent a list
        p3 = _checks(slug)
        p3["notes"] = "result recorded as 'none' — name-only near match, unconfirmed (2 name-only near match(es)). Surname-only match for Tucker, not this person."
        c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps(p3),))
        assert c.execute("select count(*) from firm_check_rows where firm_id = %s and name_only is not null", (fid,)).fetchone()[0] == 0
        c.rollback()
