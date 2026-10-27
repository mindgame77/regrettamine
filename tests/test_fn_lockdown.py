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
    "unlock_firm(text,uuid,boolean,text)",
    "handle_new_user()",
    "record_fact_event()",
    "record_published_review()",
    "sync_watch_alerts_from_view()",
    "checks_from_upload_trg()",
    "promote_bot_facts(uuid)",
    "promote_bot_facts_trg()",
    "check_saved_items(uuid,integer)",
    "check_row_items(uuid,bigint,integer)",
    "_firm_details_cached(uuid)",
    "_firm_page_cache_invalidate()",
    "warm_firm_page_cache(integer)",
    "lock_enabled()",
]
USER_ONLY = ["watch_fund(text)", "unwatch_fund(text)", "delete_my_account()"]
PUBLIC = ["firm_page(text,uuid,boolean,text)", "firm_meta(text)", "firm_sitemap(integer,integer)", "public_site_bundle()", "bump_firm_check(text,uuid)"]
# Old site RPCs. The functions stay. anon and authenticated cannot call them.
REVOKED = [
    "carry_anon_views(text)",
    "fact_record_count()",
    "firm_id_for_slug(text)",
    "landing_funds()",
    "my_alert_funds()",
    "my_report_slugs()",
    "my_watch_alerts()",
    "my_watch_slugs()",
    "public_firm_id(text)",
    "search_funds(text)",
    "set_fund_alert(text,boolean)",
    "open_report(text,text)",
]
# Still callable. Do not revoke these with the old site.
KEPT = [
    "my_billing()",
    "access_tier()",
    "set_fund_alert_kind(text,text,boolean)",
    "set_watch_alert_kind(text,boolean)",
    "watch_fund(text)",
    "unwatch_fund(text)",
    "is_admin()",
]


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
        for fn in REVOKED:
            for role in ("anon", "authenticated"):
                assert _can(cur, role, fn) is False, (role, fn)
            assert _can(cur, "service_role", fn) is True, fn
        for fn in KEPT:
            assert _can(cur, "authenticated", fn) is True, fn
            assert _can(cur, "service_role", fn) is True, fn
