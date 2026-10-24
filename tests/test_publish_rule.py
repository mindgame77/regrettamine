"""Publish rule: published + real + non-test + non-deleted firms are served by content RPCs; launch_page is irrelevant."""
import os
import uuid

import psycopg
import pytest

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")

CASES = [  # slug, published, launch_page, data_status, is_test, deleted, served
    ("zz-pr-ok", True, False, "real", False, False, True),
    ("zz-pr-lp", True, True, "real", False, False, True),
    ("zz-pr-unpub", False, True, "real", False, False, False),
    ("zz-pr-status", True, True, "test", False, False, False),
    ("zz-pr-del", True, True, "real", False, True, False),
]


def test_publish_rule_drives_content_rpcs():
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        for slug, pub, lp, st, t, d, _ in CASES:
            cur.execute(
                "insert into firms (slug, name, published, launch_page, data_status, is_test, deleted_at)"
                " values (%s, %s, %s, %s, %s, %s, case when %s then now() end)",
                (slug, slug, pub, lp, st, t, d))
        cur.execute("select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace"
                    " where n.nspname = 'public' and p.prosrc ilike '%launch_page%'")
        assert cur.fetchall() == []
        for slug, *_, served in CASES:
            cur.execute("select firm_page(%s, %s, false)", (slug, str(uuid.uuid4())))
            r = cur.fetchone()[0]
            assert (r.get("status") != "not_found") == served, (slug, r)
            cur.execute("select firm_check_status(%s)", (slug,))
            c = cur.fetchone()[0]
            assert (c is not None and c.get("status") != "not_found") == served, (slug, c)
        conn.rollback()
