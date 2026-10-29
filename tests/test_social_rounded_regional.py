"""A15.6 rounded counts and A15.7 regional accounts (Alex 2026-10-29).
rounded: shown like any count, an exact count replaces it, it never replaces an exact one.
regional + region: its own pill per region, never replaces (or is replaced by) the main account."""
import copy
from pathlib import Path

from test_checker_social_path import FIX, cur, run  # noqa: F401  (cur is a fixture)

MIG = Path("supabase/migrations/20261029250000_social_rounded_regional.sql")
RB = Path("supabase/rollbacks/20261029250000_social_rounded_regional.sql")
YC = next(s for s in FIX if s["id"] == 5354)


def test_files():
    sql = MIG.read_text(encoding="utf-8")
    assert "add column if not exists rounded boolean" in sql and "add column if not exists region text" in sql
    assert "delete from public.firm_page_cache" in sql
    rb = RB.read_text(encoding="utf-8")
    assert "create or replace function public._checker_social" in rb and "CREATE OR REPLACE FUNCTION public._firm_social" in rb


def sub(followers, read_at, url=None, **marks):
    s = copy.deepcopy(YC)
    v = s["payload"]["records"][0]["value"]
    v["followers"], v["followers_read_at"] = followers, read_at
    if url:
        v["url"] = url
    v.update(marks)
    return s


def shown(c, fid):
    return [(a["platform"], int(a["followers"]), a.get("region")) for a in c.execute("select public._firm_social(%s)", (fid,)).fetchone()[0]]


def facts(c, fid):
    return c.execute("select value->>'rounded', value->>'regional', value->>'region' from vc_source_facts "
                     "where firm_id = %s and status = 'current' and fact_type = 'media_reach' order by value->>'region' nulls first", (fid,)).fetchall()


def test_rounded_shown_and_marker_stored(cur):
    fid, rep, _ = run(cur, sub(20100, "2026-10-29", rounded=True))
    assert rep["failure"] == 0, rep
    assert shown(cur, fid) == [("x", 20100, None)]
    assert facts(cur, fid) == [("true", None, None)]


def test_exact_replaces_rounded_same_day_and_rounded_never_replaces_exact(cur):
    fid, _, reg = run(cur, sub(20100, "2026-10-29", rounded=True))
    _, rep, _ = run(cur, sub(20143, "2026-10-29"), reg)
    assert rep["failure"] == 0, rep
    assert shown(cur, fid) == [("x", 20143, None)]
    assert cur.execute("select followers::bigint, rounded from social_count_history where firm_id = %s", (fid,)).fetchall() == [(20100, True)]
    _, rep2, _ = run(cur, sub(20200, "2026-10-30", rounded=True), reg)
    assert any(r["reason"] == "skipped, the page already has an exact count" for r in rep2["reasons"]), rep2
    assert shown(cur, fid) == [("x", 20143, None)]


def test_regional_is_separate_pill_and_never_replaces_main(cur):
    fid, _, reg = run(cur, sub(1662038, "2026-10-12"))
    _, rep, _ = run(cur, sub(25873, "2026-10-29", url="https://twitter.com/LightspeedIndia", regional=True, region="India"), reg)
    assert rep["failure"] == 0, rep
    assert shown(cur, fid) == [("x", 1662038, None), ("x", 25873, "India")]
    assert facts(cur, fid) == [(None, None, None), (None, "true", "India")]
    assert cur.execute("select count(*) from social_count_history where firm_id = %s", (fid,)).fetchone()[0] == 0
    # a newer main count replaces only the main pill
    run(cur, sub(1700000, "2026-10-30"), reg)
    assert shown(cur, fid) == [("x", 1700000, None), ("x", 25873, "India")]
    # a newer regional count replaces only the regional pill
    run(cur, sub(26000, "2026-10-31", url="https://twitter.com/LightspeedIndia", regional=True, region="India"), reg)
    assert shown(cur, fid) == [("x", 1700000, None), ("x", 26000, "India")]
    assert cur.execute("select region from social_count_history where firm_id = %s order by replaced_at, region nulls first",
                       (fid,)).fetchall() == [(None,), ("India",)]


def test_regional_without_region_fails(cur):
    fid, rep, _ = run(cur, sub(25873, "2026-10-29", regional=True))
    assert any(r["reason"] == "regional social account needs a region" for r in rep["reasons"]), rep
    assert shown(cur, fid) == []


def test_main_pills_unchanged_shape(cur):
    """Accounts without markers keep the exact output keys they had (no region key)."""
    fid, _, _ = run(cur, sub(1662038, "2026-10-29"))
    out = cur.execute("select public._firm_social(%s)", (fid,)).fetchone()[0]
    assert [sorted(a) for a in out] == [["followers", "platform", "url"]]
