"""Regulator actions, legal source labels, and fund asset amounts."""
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261108230000_v2_legal_labels_fund_assets.sql"


def test_migration_skips_without_v2_and_publishes_only_the_approved_rows():
    s = MIG.read_text()
    assert "to_regprocedure('public.v2_firm_page(text)') is null" in s
    assert "raise notice 'v2 schema missing, skipped'" in s
    assert "M3.8 fund assets" in s
    assert "when l.item_group = 'regulator'" in s
    assert "U.S. Treasury" in s
    assert "courtlistener\\.com" in s or "courtlistener\\.com$" in s
    assert "l.person_id" not in s
    assert "v2_people" not in s
    assert "v2_fund_assets" in s
    assert "between 2021 and 2026" in s
    assert "is_current" in s
    allowed = [943, 945, 967, 1033, 1035, 1037, 1039, 1041, 1043, 1045, 1047, 1049, 1051, 1053, 1055]
    queue_list = s.split("allowed_q bigint[] := array[", 1)[1].split("]", 1)[0]
    row_list = s.split("allowed_rows bigint[] := array[", 1)[1].split("]", 1)[0]
    assert [int(x) for x in queue_list.split(",")] == allowed
    assert 304 not in [int(x) for x in row_list.split(",")]
    assert 947 not in [int(x) for x in queue_list.split(",")]
    assert "queue_id = 947" in s
    assert "feeder fund 304 must stay unpublished" in s
    assert "delete from" not in s.lower()
    assert "drop table" not in s.lower()


@pytest.mark.skipif(not shutil.which("node"), reason="node not installed")
def test_legal_and_fund_asset_display():
    r = subprocess.run(
        ["node", "--test", "tests/legal_order.test.mjs", "tests/fund_assets.test.mjs"],
        cwd=ROOT, capture_output=True, text=True,
    )
    assert r.returncode == 0, r.stdout[-4000:] + r.stderr[-2000:]
