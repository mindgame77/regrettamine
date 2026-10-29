"""Fix 3: a newer Checker-approved count for the same firm + platform replaces the shown count; the old count goes
to social_count_history (count, date read, source, submission id). A missing count never shows."""
import copy
import os
from pathlib import Path

import pytest

from test_checker_social_path import FIX, cur, run  # noqa: F401  (cur is a fixture)

MIG = Path("supabase/migrations/20261029230000_social_count_history.sql")
RB = Path("supabase/rollbacks/20261029230000_social_count_history.sql")
YC = next(s for s in FIX if s["id"] == 5354)


def test_files():
    sql = MIG.read_text(encoding="utf-8")
    assert "create table if not exists public.social_count_history" in sql
    assert "it.f || jsonb_build_object('submission_id', p_id)" in sql
    assert "enable row level security" in sql
    assert "drop table if exists public.social_count_history" in RB.read_text(encoding="utf-8")


def yc(followers, read_at):
    sub = copy.deepcopy(YC)
    v = sub["payload"]["records"][0]["value"]
    if followers is None:
        v.pop("followers")
    else:
        v["followers"] = followers
    v["followers_read_at"] = read_at
    return sub


def shown(c, fid):
    return [(a["platform"], int(a["followers"])) for a in c.execute("select public._firm_social(%s)", (fid,)).fetchone()[0]]


def history(c, fid):
    return c.execute("select platform, followers::bigint, read_at::text, source, submission_id is not null, replaced_by is not null "
                     "from social_count_history where firm_id = %s order by replaced_at", (fid,)).fetchall()



def test_newer_count_replaces_and_old_goes_to_history(cur):
    fid, rep, reg = run(cur, yc(1662038, "2026-10-12"))
    assert rep["failure"] == 0, rep
    assert shown(cur, fid) == [("x", 1662038)]
    _, rep2, _ = run(cur, yc(1700000, "2026-10-29"), reg)
    assert rep2["failure"] == 0, rep2
    assert shown(cur, fid) == [("x", 1700000)]
    assert history(cur, fid) == [("x", 1662038, "2026-10-12", "Checker", True, True)]
    cur_rows = cur.execute("select count(*) from vc_source_facts where firm_id = %s and status = 'current' and fact_type = 'media_reach'", (fid,)).fetchone()[0]
    assert cur_rows == 1


def test_same_day_or_older_count_does_not_replace(cur):
    fid, _, reg = run(cur, yc(1662038, "2026-10-29"))
    run(cur, yc(1500000, "2026-10-20"), reg)
    run(cur, yc(1600000, "2026-10-29"), reg)
    assert shown(cur, fid) == [("x", 1662038)]
    assert history(cur, fid) == []


def test_missing_count_stays_hidden(cur):
    fid, rep, _ = run(cur, yc(None, "2026-10-29"))
    assert any(r.get("reason") == "social followers must be a number" for r in rep["reasons"]), rep
    assert shown(cur, fid) == []
    fid2, _, reg2 = run(cur, yc(1662038, "2026-10-12"))
    run(cur, yc(None, "2026-10-29"), reg2)
    assert shown(cur, fid2) == [("x", 1662038)]
    assert history(cur, fid2) == []


def test_old_row_without_submission_keeps_null(cur):
    """Older non-Checker rows (like GC's 2026-10-12 X row) move to history with submission_id null, never invented."""
    fid, _, reg = run(cur, yc(1662038, "2026-10-29"))
    cur.execute("update vc_source_facts set value = value - 'submission_id', checked_by = null, source_system = 'x', "
                "retrieved_at = '2026-10-01' where firm_id = %s and fact_type = 'media_reach'", (fid,))
    run(cur, yc(1700000, "2026-10-29"), reg)
    assert history(cur, fid) == [("x", 1662038, "2026-10-01", "x", False, True)]
    assert shown(cur, fid) == [("x", 1700000)]
