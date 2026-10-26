"""firm_page_cache stores firm_details. A fresh row matches the live build. A fact or legal edit drops the row."""
import os
import uuid

import pytest

pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _db():
    import psycopg
    return psycopg.connect(DATABASE_URL)


def _gold(c, slug, name):
    row = c.execute("select id from firms where slug = %s and deleted_at is null", (slug,)).fetchone()
    if row:
        return row[0]
    return c.execute(
        "insert into firms(slug, name, short_name, published, data_status) values (%s, %s, %s, true, 'real') returning id",
        (slug, name, slug[:8]),
    ).fetchone()[0]


def test_cached_details_match_live_for_yc_and_a16z_and_edits_drop_the_row():
    with _db() as c:
        for slug, name in (("y-combinator", "Y Combinator"), ("a16z", "Andreessen Horowitz")):
            anon = str(uuid.uuid4())
            other = str(uuid.uuid4())
            fid = _gold(c, slug, name)
            c.execute("delete from firm_page_cache where firm_id = %s", (fid,))
            assert c.execute(
                "select _firm_details_cached(%s)::jsonb = firm_details(%s)::jsonb", (fid, fid)
            ).fetchone()[0]
            assert c.execute(
                "select payload = firm_details(%s)::jsonb from firm_page_cache where firm_id = %s", (fid, fid)
            ).fetchone()[0]
            built = c.execute("select built_at from firm_page_cache where firm_id = %s", (fid,)).fetchone()[0]
            opened = c.execute(
                """select (page->>'open')::boolean as open,
                          (page->'details')::jsonb = firm_details(%s)::jsonb as same
                     from (select firm_page(%s, %s, true) as page) s""",
                (fid, slug, anon),
            ).fetchone()
            assert opened == (True, True)
            again = c.execute("select built_at from firm_page_cache where firm_id = %s", (fid,)).fetchone()[0]
            c.execute("select firm_page(%s, %s, false)", (slug, anon))
            assert c.execute("select built_at from firm_page_cache where firm_id = %s", (fid,)).fetchone()[0] == again == built
            locked = c.execute(
                """select (page->>'open')::boolean, page->>'details' is null
                     from (select firm_page(%s, %s, false) as page) s""",
                (slug, other),
            ).fetchone()
            assert locked == (False, True)
            c.execute("savepoint edit")
            c.execute(
                "insert into firm_profile_facts (firm_id, section, label, value, sort_order) values (%s, 'overview', 'Overview', 'cache drop', 1)",
                (fid,),
            )
            assert c.execute("select count(*) from firm_page_cache where firm_id = %s", (fid,)).fetchone()[0] == 0
            c.execute("rollback to savepoint edit")
            assert c.execute("select count(*) from firm_page_cache where firm_id = %s", (fid,)).fetchone()[0] == 1
            c.execute(
                "insert into firm_legal_items (firm_id, grp, title) values (%s, 'case', 'Cache drop v. Example')",
                (fid,),
            )
            assert c.execute("select count(*) from firm_page_cache where firm_id = %s", (fid,)).fetchone()[0] == 0
            assert c.execute(
                "select _firm_details_cached(%s)::jsonb = firm_details(%s)::jsonb", (fid, fid)
            ).fetchone()[0]
        for role in ("anon", "authenticated"):
            if c.execute("select 1 from pg_roles where rolname = %s", (role,)).fetchone():
                assert not c.execute(
                    "select has_table_privilege(%s, 'public.firm_page_cache', 'select')", (role,)
                ).fetchone()[0]
                assert not c.execute(
                    "select has_function_privilege(%s, 'public._firm_details_cached(uuid)', 'execute')", (role,)
                ).fetchone()[0]
        c.rollback()
