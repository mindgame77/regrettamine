"""New startups match on website domain. A missing or hosted-platform site does not freeze the key."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261110040000_v2_startup_website_identity.sql").read_text(encoding="utf-8")
UNDO = (ROOT / "supabase/rollbacks/20261110040000_v2_startup_website_identity.sql").read_text(encoding="utf-8")
TEST = (ROOT / "supabase/tests/v2_startup_website_identity.sql").read_text(encoding="utf-8")
REASON = "website_url required: find this startup''s website or skip the startup and its deal"
HOSTS = (
    "linktr.ee", "medium.com", "github.com", "notion.site", "wixsite.com", "carrd.co",
    "substack.com", "linkedin.com", "facebook.com", "x.com", "twitter.com", "instagram.com",
)


def _function(text):
    start = text.index("CREATE OR REPLACE FUNCTION public.v2_research_submit")
    end = text.index("END $function$") + len("END $function$")
    return text[start:end]


def test_migration_replaces_the_function_and_skips_when_v2_is_missing():
    assert "to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null" in MIG
    assert "raise notice 'v2 schema missing, skipped'" in MIG
    assert "create table" not in MIG.lower()
    assert "add column" not in MIG.lower()
    body = _function(MIG)
    assert "IF reason IS NULL AND tbl = 'v2_startups' AND NOT (p ? 'startup_id') THEN" in body
    assert "IF reason IS NULL AND tbl = 'v2_startups' AND p ? 'startup_id' THEN" in body
    assert "existing startup: only website_url can be filled" in body
    assert "Held: empty startup website waits for the Checker" in body
    assert REASON in body
    assert "v_platform_hosts text[] := ARRAY[" in body
    for host in HOSTS:
        assert f"'{host}'" in body
    assert "lower(split_part(regexp_replace(regexp_replace(v_st_web, '^https?://', '', 'i'), '^www\\.', '', 'i'), '/', 1))" in body
    assert "v2_startups_domain_uq" in body
    assert "WHEN unique_violation THEN" in body
    assert "'matched_startup_id',v_st_id" in body
    assert "matched existing startup %s by website" in body
    assert "status IS DISTINCT FROM ('Rejected: ' || v_site_reason)" in body
    assert "lower(s.startup_name)" not in body
    assert "A matching name does not matter" in body


def test_undo_restores_the_live_function():
    assert "to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null" in UNDO
    old = _function(UNDO)
    assert "matched_startup_id" not in old
    assert "v_site_reason" not in old
    assert "v_platform_hosts" not in old
    assert "v2_startups_domain_uq" not in old
    assert "status LIKE 'Rejected:%'" in old
    assert "status IS DISTINCT FROM" not in old
    assert "IF reason IS NULL AND tbl = 'v2_startups' AND p ? 'startup_id' THEN" in old
    assert "NOT (p ? 'startup_id')" not in old
    assert "rejections today for one firm" in old
    assert old != _function(MIG)


def test_sql_script_covers_the_dry_run_cases():
    for label in (
        "No website",
        "Hosted-platform domain",
        "Exact domain",
        "Subdomain stays distinct",
        "Same name, new domain",
        "Matched ref is used by a later v2_deals item",
        "Website fill",
        "does not count toward the freeze",
        "normal rejection still does",
        "Unique-violation race",
    ):
        assert label in TEST
    assert "v2_run_startup_race_test" not in TEST
    assert "v2.run_startup_race_test" in TEST
    assert "raise exception 'v2_startup_website_identity_ok'" in TEST
