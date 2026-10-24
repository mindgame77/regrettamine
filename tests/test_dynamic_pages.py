"""Dynamic firm pages: firm_meta / firm_sitemap (public, read-only, published firms only) and the edge renderer."""
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not shutil.which("node"), reason="node not installed")
def test_edge_renderer_matches_static_build():
    subprocess.run(["python3", "launch/build.py"], cwd=ROOT, check=True, capture_output=True)
    r = subprocess.run(["node", "--test", "launch/edge/firm.test.mjs"], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-2000:]


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_firm_meta_and_sitemap_only_public_published():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        for fn in ("firm_meta(text)", "firm_sitemap(integer,integer)"):
            cur.execute("select prosecdef, provolatile, proconfig from pg_proc where oid = %s::regprocedure", ("public." + fn,))
            secdef, vol, cfg = cur.fetchone()
            assert secdef and vol == "s", fn
            assert any(c.startswith("search_path=") for c in cfg or []), fn
            cur.execute("select has_function_privilege('anon', %s, 'execute')", ("public." + fn,))
            assert cur.fetchone()[0], fn
        cur.execute(
            "select slug from firms where published and not coalesce(is_test,false) and deleted_at is null and data_status='real' order by slug limit 1"
        )
        row = cur.fetchone()
        if row:
            cur.execute("select slug, name from firm_meta(%s)", (row[0].upper(),))
            assert cur.fetchone()[0] == row[0]
        cur.execute("select count(*) from firm_meta('definitely-not-a-firm')")
        assert cur.fetchone()[0] == 0
        cur.execute("select count(*) from firm_sitemap(1, 10000) s join firms f using (slug) where not f.published or f.is_test or f.deleted_at is not null or f.data_status <> 'real'")
        assert cur.fetchone()[0] == 0
        cur.execute("select count(*) from firm_sitemap(1, 100000)")
        assert cur.fetchone()[0] <= 10000
        conn.rollback()
