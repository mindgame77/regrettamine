"""Checker confirm can drop unsupported optional details (drop_fields) instead of rejecting the whole row."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = "20261109060000_v2_checker_drop_fields.sql"
SQL = (ROOT / "supabase/migrations" / NAME).read_text()
UNDO = (ROOT / "supabase/rollbacks" / NAME).read_text()
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()


def test_migration_only_replaces_checker_action():
    low = SQL.lower()
    assert low.count("create or replace function") == 1
    assert "create or replace function public.v2_checker_action(" in low
    assert "to_regprocedure('public.v2_checker_action(uuid,text,jsonb,boolean)') is null" in low
    assert "p_args->'drop_fields'" not in UNDO


def test_strict_allowlist_and_errors():
    assert "ARRAY['x_url','x_followers','linkedin_url','linkedin_followers','photo_url']" in SQL
    assert "q.table_name = 'v2_people'" in SQL
    for msg in ("drop_fields only works with verdict confirm",
                "drop_fields must be a non-empty list of field names",
                "drop_fields: cannot drop %s from %s (allowed: %s)"):
        assert msg in SQL
    for never in ("'person_name'", "'source_url'", "'person_id'", "'firm_id'", "'submission_id'"):
        assert never not in SQL.split("drop_ok :=", 1)[1].split(";", 1)[0]


def test_dropped_fields_are_logged():
    assert "'dropped',dropped" in SQL
    assert "(dropped: '" in SQL


def test_door_passes_drop_fields_to_checker():
    assert "drop_fields: body.drop_fields" in FN
