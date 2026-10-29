"""Security guard (Alex 2026-10-28, A14.6): owner-run (SECURITY DEFINER) functions in public need a fixed
search_path, and only allowlisted ones may be run by anon (logged-out users). Add a function here only if the
public site or app calls it as anon."""
import os

import pytest

DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()

# Called by the public site/app as anon, or used inside RLS policies. Keep this list short.
ANON_ALLOWED = {
    "_own_media",
    "access_tier",
    "bump_firm_check",
    "can_alert_fund",
    "check_balance",
    "claim_anon_checks",
    "firm_activity_list",
    "firm_check_status",
    "firm_is_public",
    "firm_meta",
    "firm_page",
    "firm_page_speed",
    "firm_redirect",
    "firm_sitemap",
    "firm_suggest",
    "is_admin",
    "is_paid",
    "my_billing",
    "notify_when_checked",
    "public_site_bundle",
    "request_check",
    "request_firm",
}

SQL = """
select p.proname,
       p.oid::regprocedure::text as sig,
       not coalesce(exists(select 1 from unnest(p.proconfig) c where c like 'search_path=%'), false) as no_path,
       has_function_privilege('anon', p.oid, 'execute') as anon_exec
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
left join pg_depend d on d.objid = p.oid and d.deptype = 'e'
where n.nspname = 'public' and p.prosecdef and d.objid is null
"""


def _rows():
    if not DATABASE_URL:
        pytest.skip("DATABASE_URL is not set")
    import psycopg
    with psycopg.connect(DATABASE_URL) as c:
        return c.execute(SQL).fetchall()


def test_definer_functions_have_fixed_search_path():
    bad = sorted(sig for _, sig, no_path, _ in _rows() if no_path)
    assert not bad, f"SECURITY DEFINER without fixed search_path: {bad}"


def test_only_allowlisted_definer_functions_open_to_anon():
    bad = sorted(sig for name, sig, _, anon in _rows() if anon and name not in ANON_ALLOWED)
    assert not bad, f"SECURITY DEFINER callable by anon but not on ANON_ALLOWED: {bad}"
