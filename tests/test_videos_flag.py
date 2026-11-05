"""Videos section and HQ country flag on the firm page."""
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261105220000_v2_firm_page_videos_flag.sql"
UNDO = ROOT / "supabase/rollbacks/20261105220000_v2_firm_page_videos_flag.sql"


def test_migration_patches_v2_firm_page_and_skips_when_missing():
    s = MIG.read_text()
    assert "to_regprocedure('public.v2_firm_page(text)') is null" in s
    assert "raise notice 'v2 schema missing, skipped'" in s
    assert "v2_interviews" in s
    assert "view_count desc nulls last" in s
    assert "limit 3" in s
    assert "'key','videos'" in s
    assert "hq_country" in s
    assert "not v.link_dead" in s
    assert UNDO.exists()
    undo = UNDO.read_text()
    assert "videos block not found" in undo
    assert "'hq',hq,'website'" in undo


@pytest.mark.skipif(not shutil.which("node"), reason="node not installed")
def test_videos_and_flag_render():
    r = subprocess.run(["node", "--test", "tests/videos_flag.test.mjs"], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-2000:]
