"""Team social pills reuse the company social pill: icon and count only."""
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]


@pytest.mark.skipif(not shutil.which("node"), reason="node not installed")
def test_team_pills_match_company_pills():
    r = subprocess.run(
        ["node", "--test", "tests/team_no_source_pills.test.mjs", "tests/social_pills.test.mjs"],
        cwd=ROOT, capture_output=True, text=True,
    )
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-2000:]
