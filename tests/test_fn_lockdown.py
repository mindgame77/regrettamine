"""Internal SECURITY DEFINER functions are not callable by anon/authenticated."""
import os

import pytest

pytest.importorskip("psycopg")
import psycopg  # noqa: E402

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")

LOCKED = [
    "apply_stripe_event(jsonb)",
    "apply_subscription(uuid,text,text,timestamp with time zone)",
    "stripe_note_card(jsonb)",
    "store_report_page(text,text)",
    "sync_watch_alerts(uuid)",
    "unlock_firm(text,uuid,boolean)",
    "handle_new_user()",
    "record_fact_event()",
    "record_published_review()",
    "sync_watch_alerts_from_view()",
    "checks_from_upload_trg()",
]
USER_ONLY = ["watch_fund(text)", "unwatch_fund(text)", "set_fund_alert(text,boolean)", "delete_my_account()"]
PUBLIC = ["firm_page(text,uuid,boolean)", "firm_meta(text)", "firm_sitemap(integer,integer)", "search_funds(text)", "public_site_bundle()", "bump_firm_check(text,uuid)"]


def _can(cur, role, fn):
    cur.execute("select to_regprocedure(%s) is not null", ("public." + fn,))
    if not cur.fetchone()[0]:
        return None
    cur.execute("select has_function_privilege(%s, %s, 'execute')", (role, "public." + fn))
    return cur.fetchone()[0]


def test_internal_functions_locked():
    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        for fn in LOCKED:
            for role in ("anon", "authenticated"):
                assert _can(cur, role, fn) in (False, None), (role, fn)
            assert _can(cur, "service_role", fn) in (True, None), fn
        for fn in USER_ONLY:
            assert _can(cur, "anon", fn) in (False, None), fn
            assert _can(cur, "authenticated", fn) in (True, None), fn
        for fn in PUBLIC:
            assert _can(cur, "anon", fn) in (True, None), fn
