"""Publish step: toxy-enricher publishes on insert; other rows can still use a batch (dry run -> Alex approves -> run -> undo);
per-firm page check; leads and fixes held; item-by-item merge; check history kept."""
import json
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
ADV = "https://adviserinfo.sec.gov/firm/summary/777001"
DOCKET = "https://www.courtlistener.com/docket/777001/pub-capital/"
PRESS = "https://techcrunch.com/2020/01/01/pub-capital-raises/"


def _db():
    import psycopg
    return psycopg.connect(DATABASE_URL)


def _firm(c, auto="0"):
    slug = "pub-" + uuid.uuid4().hex[:8]
    fid = c.execute("insert into firms(slug, name, short_name, published, data_status, primary_domain) "
                    "values (%s, 'Pub Capital', 'Pc', true, 'real', 'pc.test') returning id", (slug,)).fetchone()[0]
    c.execute("update ingest_settings set value = '1' where key = 'data_rules_from_enrichment_id'")
    c.execute("update ingest_settings set value = %s where key = 'auto_promote_enrichment'", (auto,))
    return slug, fid


def _enrich(c, slug, sections, **extra):
    c.execute("select research_enrich('toxy-enricher', %s::jsonb)", (json.dumps({"slug": slug, "sections": sections, **extra}),))


def _n(c, table, fid, hidden=False):
    return c.execute(f"select count(*) from {table} where firm_id = %s and hidden = %s", (fid, hidden)).fetchone()[0]


def test_enricher_publishes_even_when_the_batch_switch_is_off():
    with _db() as c:
        slug, fid = _firm(c, auto="0")
        c.execute("set local app.test_auto_publish = ''")
        assert c.execute("select _auto_publish_on()").fetchone()[0] is False
        _enrich(c, slug, {"Timeline": [{"date": "2010", "event": "Opened office", "source": ADV}]})
        assert _n(c, "timeline_events", fid) == 1
        c.rollback()


def test_leads_and_fixes_are_held_never_published():
    with _db() as c:
        slug, fid = _firm(c)
        _enrich(c, slug, {"People": [{"name": "Jane Roe", "role": "Partner", "source": ADV}]})
        c.execute("select promote_enrichment(%s)", (fid,))
        _enrich(c, slug, {"Legal & regulatory": [{"title": "Roe v. Pub Capital, 1:20-cv-00001 (D. Del.)", "source": DOCKET, "allegation": True}]},
                fix=[{"field": "people[Jane Roe].current", "bot_value": "Partner", "correct_value": "former partner (left 2020)", "source_url": ADV}],
                leads=[{"field": "legal", "value": {"title": "Rumoured probe of Pub Capital", "source": PRESS}, "source_url": PRESS}])
        c.execute("select promote_enrichment(%s)", (fid,))
        assert _n(c, "firm_legal_items", fid) == 0
        assert c.execute("select count(*) from firm_corrections where firm_id = %s", (fid,)).fetchone()[0] == 0
        assert c.execute("select count(*) from publish_checks where firm_id = %s and kind = 'fix' and outcome = 'held'", (fid,)).fetchone()[0] == 1
        assert c.execute("select count(*) from publish_checks where firm_id = %s and kind = 'lead' and outcome = 'published'", (fid,)).fetchone()[0] == 0
        sql = open(os.path.join(os.path.dirname(__file__), "..", "supabase", "migrations", "20261026210000_publish_step.sql")).read()
        assert "Lead (unverified)" not in sql and "Lead (allegation" not in sql
        c.rollback()


def test_merge_across_rows_newer_wins_older_adds_source():
    with _db() as c:
        slug, fid = _firm(c)
        _enrich(c, slug, {"Timeline": [{"date": "2010", "event": "Opened office", "source": ADV}]})
        _enrich(c, slug, {"Timeline": [{"date": "2010", "event": "Opened office", "source": PRESS}]})
        c.execute("select promote_enrichment(%s)", (fid,))
        assert _n(c, "timeline_events", fid) == 1
        tid = c.execute("select id from timeline_events where firm_id = %s", (fid,)).fetchone()[0]
        urls = {r[0] for r in c.execute("select s.url from fact_sources x join sources s on s.id = x.source_id where x.fact_id = %s", (tid,))}
        assert urls == {ADV, PRESS}
        # the first row publishes on insert; the later row adds its source to that item
        outs = c.execute("select e.id, p.outcome from publish_checks p join research_enrichments e on e.id = p.origin_id "
                         "where p.firm_id = %s and p.section = 'timeline' order by e.id", (fid,)).fetchall()
        assert [o for _, o in outs] == ["published", "merged"]
        c.rollback()


def _hold_for_batch(c):
    """Ingest publishes toxy-enricher immediately. These tests still cover the batch path, so they hold that trigger."""
    c.execute("alter table bots.research_enrichments disable trigger enrichment_promote")


def test_batch_dry_run_approve_run_undo():
    with _db() as c:
        slug, fid = _firm(c)
        _hold_for_batch(c)
        _enrich(c, slug, {"Timeline": [{"date": "2010", "event": "Opened office", "source": ADV}],
                          "People": [{"name": "Jane Roe", "role": "Partner", "source": ADV}]})
        b = "t-" + uuid.uuid4().hex[:6]
        c.execute("select create_publish_batch(%s, 'enricher', null, %s::uuid[])", (b, [str(fid)]))
        c.execute("select dry_run_publish_batch(%s)", (b,))
        assert _n(c, "timeline_events", fid) == 0  # dry run rolled back
        d = c.execute("select decision, items from publish_batch_firms where batch_id = %s and phase = 'dry'", (b,)).fetchone()
        assert d[0] == "live" and d[1]["items"]["published"]["timeline"] == 1
        c.execute("savepoint s")
        with pytest.raises(Exception):
            c.execute("select run_publish_batch(%s)", (b,))  # not approved
        c.execute("rollback to savepoint s")
        c.execute("select approve_publish_batch(%s, 'Alex')", (b,))
        c.execute("select run_publish_batch(%s)", (b,))
        assert _n(c, "timeline_events", fid) == 1 and _n(c, "firm_people_roles", fid) == 1
        assert c.execute("select count(*) from enrichment_rows where firm_id = %s and batch_id = %s", (fid, b)).fetchone()[0] >= 2
        assert c.execute("select count(*) from publish_checks where firm_id = %s and batch_id = %s", (fid, b)).fetchone()[0] >= 2
        checks = c.execute("select count(*) from publish_checks where firm_id = %s", (fid,)).fetchone()[0]
        c.execute("select undo_publish_batch(%s)", (b,))
        assert _n(c, "timeline_events", fid) == 0 and _n(c, "timeline_events", fid, hidden=True) == 1
        assert _n(c, "firm_people_roles", fid) == 0 and _n(c, "firm_people_roles", fid, hidden=True) == 1
        assert c.execute("select count(*) from publish_checks where firm_id = %s", (fid,)).fetchone()[0] == checks  # history kept
        assert c.execute("select status from publish_batches where id = %s", (b,)).fetchone()[0] == "undone"
        c.rollback()


def test_undo_removes_added_sources_but_keeps_a_copy():
    with _db() as c:
        slug, fid = _firm(c)
        _hold_for_batch(c)
        _enrich(c, slug, {"Timeline": [{"date": "2010", "event": "Opened office", "source": ADV}]})
        c.execute("select promote_enrichment(%s)", (fid,))  # already live from an earlier publish
        _enrich(c, slug, {"Timeline": [{"date": "2010", "event": "Opened office", "source": PRESS}]})
        b = "t-" + uuid.uuid4().hex[:6]
        c.execute("select create_publish_batch(%s, 'enricher', null, %s::uuid[])", (b, [str(fid)]))
        c.execute("select dry_run_publish_batch(%s)", (b,))
        c.execute("select approve_publish_batch(%s, 'Alex')", (b,))
        c.execute("select run_publish_batch(%s)", (b,))
        tid = c.execute("select id from timeline_events where firm_id = %s", (fid,)).fetchone()[0]
        n = lambda: c.execute("select count(*) from fact_sources where fact_id = %s", (tid,)).fetchone()[0]
        assert n() == 2
        c.execute("select undo_publish_batch(%s)", (b,))
        assert n() == 1 and _n(c, "timeline_events", fid) == 1  # the older item stays live
        assert c.execute("select count(*) from cleanup_backup where batch = %s and table_name = 'fact_sources'", ("undo:" + b,)).fetchone()[0] == 1
        c.rollback()


def test_firm_that_breaks_its_page_is_held_rest_go_live():
    with _db() as c:
        s1, f1 = _firm(c)
        s2, f2 = _firm(c)
        _hold_for_batch(c)
        for s in (s1, s2):
            _enrich(c, s, {"Legal & regulatory": [{"title": "Roe v. Pub Capital, 1:20-cv-00001 (D. Del.)", "source": DOCKET}]})
        c.execute("select promote_enrichment(%s)", (f1,))
        c.execute("select promote_enrichment(%s)", (f2,))
        for s in (s1, s2):
            _enrich(c, s, {"Timeline": [{"date": "2011", "event": "Second office", "source": ADV}]})
        # simulate a bad side effect for firm 1 only: adding a timeline row makes its legal section disappear
        c.execute("""create function pg_temp.breaker() returns trigger language plpgsql as $$
                     begin update firm_legal_items set hidden = true, hidden_reason = 't', hidden_by = 't' where firm_id = new.firm_id and new.firm_id = '%s'; return null; end $$""" % f1)
        c.execute("create trigger zz_breaker after insert on timeline_events for each row execute function pg_temp.breaker()")
        b = "t-" + uuid.uuid4().hex[:6]
        c.execute("select create_publish_batch(%s, 'enricher', null, %s::uuid[])", (b, [str(f1), str(f2)]))
        c.execute("select dry_run_publish_batch(%s)", (b,))
        c.execute("select approve_publish_batch(%s, 'Alex')", (b,))
        c.execute("select run_publish_batch(%s)", (b,))
        rows = dict(c.execute("select firm_id, decision from publish_batch_firms where batch_id = %s and phase = 'run'", (b,)).fetchall())
        assert rows[f1] == "held" and rows[f2] == "live"
        assert _n(c, "timeline_events", f1) == 0 and _n(c, "firm_legal_items", f1) == 1  # rolled back
        assert _n(c, "timeline_events", f2) == 1
        reasons = c.execute("select reasons from publish_batch_firms where batch_id = %s and firm_id = %s and phase = 'run'", (b, f1)).fetchone()[0]
        assert any("legal" in r for r in reasons)
        c.rollback()


def test_approval_functions_are_not_callable_by_the_site():
    with _db() as c:
        for fn in ("approve_publish_batch(text, text)", "run_publish_batch(text)", "undo_publish_batch(text)",
                   "dry_run_publish_firm(text, uuid)", "dry_run_publish_batch(text, integer, integer)"):
            for role in ("anon", "authenticated"):
                if c.execute("select 1 from pg_roles where rolname = %s", (role,)).fetchone():
                    assert not c.execute("select has_function_privilege(%s, %s, 'execute')", (role, "public." + fn)).fetchone()[0]


def _gold(c, slug, name):
    row = c.execute("select id from firms where slug = %s and deleted_at is null", (slug,)).fetchone()
    if row:
        return row[0]
    return c.execute("insert into firms(slug, name, short_name, published, data_status) "
                     "values (%s, %s, %s, true, 'real') returning id", (slug, name, slug[:8])).fetchone()[0]


def _legacy_dry(c, batch, fid):
    """The old per-firm dry body: _publish_firm inside the same rollback, with the same held handling."""
    c.execute("""
      create or replace function pg_temp.legacy_dry(p_id text, p_firm uuid) returns jsonb
      language plpgsql set search_path = public as $fn$
      declare b publish_batches; r jsonb;
      begin
        select * into b from publish_batches where id = p_id;
        begin
          r := _publish_firm(p_id, b.source, p_firm);
          raise exception using errcode = 'P0001', message = 'dryrun-rollback';
        exception when others then
          if sqlerrm <> 'dryrun-rollback' then r := jsonb_build_object('decision', 'held', 'reasons', jsonb_build_array('error: ' || sqlerrm)); end if;
        end;
        return r;
      end $fn$
    """)
    return c.execute("select pg_temp.legacy_dry(%s, %s)", (batch, fid)).fetchone()[0]


def test_per_firm_dry_run_matches_legacy_for_yc_and_a16z():
    with _db() as c:
        firms = [("y-combinator", _gold(c, "y-combinator", "Y Combinator")),
                 ("a16z", _gold(c, "a16z", "Andreessen Horowitz"))]
        b = "t-" + uuid.uuid4().hex[:6]
        c.execute("select create_publish_batch(%s, 'enricher', null, %s::uuid[])", (b, [str(fid) for _, fid in firms]))
        before = {fid: _n(c, "timeline_events", fid) for _, fid in firms}
        legacy = {slug: _legacy_dry(c, b, fid) for slug, fid in firms}
        for slug, fid in firms:
            c.execute("select dry_run_publish_firm(%s, %s)", (b, fid))
            decision, reasons, items = c.execute(
                "select decision, reasons, items from publish_batch_firms where batch_id = %s and firm_id = %s and phase = 'dry'",
                (b, fid)).fetchone()
            old = legacy[slug]
            assert decision == old["decision"], slug
            assert list(reasons) == list(old["reasons"]), slug
            for key in ("items", "counts_before", "counts_after", "alerts", "blocked"):
                assert items.get(key) == old.get(key), (slug, key)
            assert _n(c, "timeline_events", fid) == before[fid]
        c.rollback()


def test_dry_run_batch_is_changed_only_and_keeps_other_rows():
    with _db() as c:
        s1, f1 = _firm(c)
        s2, f2 = _firm(c)
        _hold_for_batch(c)
        for s in (s1, s2):
            _enrich(c, s, {"Timeline": [{"date": "2012", "event": "Opened a desk", "source": ADV}]})
        b = "t-" + uuid.uuid4().hex[:6]
        c.execute("select create_publish_batch(%s, 'enricher', null, %s::uuid[])", (b, [str(f1), str(f2)]))
        assert list(c.execute("select _publish_changed_firms(%s)", (b,)).fetchone()[0]) == [f1, f2]
        rep = c.execute("select dry_run_publish_batch(%s)", (b,)).fetchone()[0]
        assert rep["firms_checked"] == 1 and rep["remaining"] == 1 and rep["next"] == str(f2)
        kept = c.execute("select id, checked_at from publish_batch_firms where batch_id = %s and firm_id = %s and phase = 'dry'", (b, f1)).fetchone()
        rep2 = c.execute("select dry_run_publish_batch(%s)", (b,)).fetchone()[0]
        assert rep2["firms_checked"] == 1 and rep2["remaining"] == 0 and rep2["next"] is None
        assert c.execute("select id, checked_at from publish_batch_firms where batch_id = %s and firm_id = %s and phase = 'dry'", (b, f1)).fetchone() == kept
        assert list(c.execute("select _publish_changed_firms(%s)", (b,)).fetchone()[0]) == []
        # a later firm edit, enrichment, or submission puts only that firm back on the list
        c.execute("insert into cleanup_backup(batch, firm_id, table_name, row_data, saved_at) "
                  "values ('edit-test', %s, 'firm_legal_items', '{}'::jsonb, now() + interval '1 second')", (f1,))
        assert list(c.execute("select _publish_changed_firms(%s)", (b,)).fetchone()[0]) == [f1]
        c.execute("delete from cleanup_backup where firm_id = %s and batch = 'edit-test'", (f1,))
        c.execute("insert into research_enrichments(bot_id, firm_id, payload, valid, received_at) "
                  "values ('toxy-enricher', %s, '{}'::jsonb, true, now() + interval '1 second')", (f1,))
        assert list(c.execute("select _publish_changed_firms(%s)", (b,)).fetchone()[0]) == [f1]
        c.execute("delete from research_enrichments where firm_id = %s", (f1,))
        reg = "zz-chg-" + uuid.uuid4().hex[:8]
        c.execute("insert into research_queue (registry_id, name, priority, status) values (%s, 'Zz Change', 900000, 'queued')", (reg,))
        c.execute("update firms set registry_id = null where registry_id = %s and id <> %s", (reg, f1))
        c.execute("update firms set registry_id = %s where id = %s", (reg, f1))
        c.execute("insert into research_submissions(registry_id, bot_id, payload, record_count, valid, received_at) "
                  "values (%s, 'zz-bot', '{}'::jsonb, 1, true, now() + interval '1 second')", (reg,))
        assert list(c.execute("select _publish_changed_firms(%s)", (b,)).fetchone()[0]) == [f1]
        c.rollback()


def test_submit_rate_limit_rejects_the_21st_without_inserting():
    with _db() as c:
        bot = "zz-rate-" + uuid.uuid4().hex[:8]
        other = bot + "-b"
        reg = "zz-rate-" + uuid.uuid4().hex[:8]
        payload = json.dumps({"schema_version": "dump-1.2"})
        c.execute("insert into research_queue (registry_id, name, priority, status, claimed_by, claimed_at) "
                  "values (%s, 'Zz Rate Partners', 900000, 'claimed', %s, now())", (reg, bot))
        for _ in range(20):
            c.execute("update research_queue set status = 'claimed', claimed_by = %s, attempts = 0, claimed_at = now() where registry_id = %s", (bot, reg))
            got = c.execute("select research_submit(%s, %s, %s::jsonb, 1, true, '[]'::jsonb)", (reg, bot, payload)).fetchone()[0]
            assert got["ok"] is True
        assert c.execute("select count(*) from research_submissions where bot_id = %s", (bot,)).fetchone()[0] == 20
        assert c.execute("select 1 from pg_indexes where indexname = 'research_submissions_bot_received_idx'").fetchone()
        c.execute("savepoint rate")
        with pytest.raises(Exception) as ei:
            c.execute("update research_queue set status = 'claimed', claimed_by = %s, attempts = 0 where registry_id = %s", (bot, reg))
            c.execute("select research_submit(%s, %s, %s::jsonb, 1, true, '[]'::jsonb)", (reg, bot, payload))
        assert "rate_limited: max 20 uploads per minute per bot, retry shortly" in str(ei.value)
        c.execute("rollback to savepoint rate")
        assert c.execute("select count(*) from research_submissions where bot_id = %s", (bot,)).fetchone()[0] == 20
        c.execute("update research_queue set status = 'claimed', claimed_by = %s, attempts = 0, claimed_at = now() where registry_id = %s", (other, reg))
        other_ok = c.execute("select research_submit(%s, %s, %s::jsonb, 1, true, '[]'::jsonb)", (reg, other, payload)).fetchone()[0]
        assert other_ok["ok"] is True
        c.rollback()
