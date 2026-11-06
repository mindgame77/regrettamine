"""v2_investor_principles: table, RLS, and the five verified a16z quotes."""
import os
import pathlib
import re

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261106010000_v2_investor_principles.sql"
UNDO = ROOT / "supabase/rollbacks/20261106010000_v2_investor_principles.sql"

# Approved one-line summaries for the five report quotes that are both EXACT and in the mockup.
SUMMARIES = {
    "15": "Attract people, capital and customers; know the space\u2019s history; show personal drive.",
    "16": "Build strong customer retention and get distribution before incumbents copy your innovation.",
    "2": "We prefer founding CEOs who keep\u2014and ideally created\u2014the product vision.",
    "8": "Invest in distinctive strength that stands out\u2014not merely a lack of weakness across team, product, and market.",
    "10": "Look for founder-market fit: the person born to do that idea.",
}
QUOTE_START = {
    "15": "I gotta say, like the best entrepreneurs",
    "16": "there\u2019s a quote that I use a lot, the best companies have hostages, not customers.",
    "2": "We prefer founding CEOs. In particular, we think the keeper of the product vision",
    "8": "We talk a lot in our firm about",
    "10": "There\u2019s another concept we call founder-market fit",
}


def _seed():
    text = MIG.read_text(encoding="utf-8")
    return text.split("execute $seed$", 1)[1].split("$seed$;", 1)[0]


def test_migration_matches_v2_sibling_rules():
    s = MIG.read_text(encoding="utf-8")
    assert "to_regclass('public.v2_firms') is null" in s
    assert "raise notice 'v2 schema missing, skipped'" in s
    assert "create table if not exists public.v2_investor_principles" in s
    assert "references public.v2_firms(firm_id) on delete cascade" in s
    assert "id bigint generated always as identity primary key" in s
    assert "created_at timestamptz not null default now()" in s
    assert "published_at date not null" in s
    assert "char_length(btrim(summary)) between 1 and 200" in s
    assert "btrim(quote) <> btrim(summary)" in s
    assert "btrim(source_url) ~* '^https://'" in s
    assert "role_source_url is null or btrim(role_source_url) ~* '^https://'" in s
    assert "unique (firm_id, display_order)" in s
    assert "enable row level security" in s
    assert "revoke all on table public.v2_investor_principles from public, anon, authenticated" in s
    assert "grant select, insert, update, delete on table public.v2_investor_principles to service_role" in s
    assert "create policy" not in s.lower()
    assert "'key','investors'" in s
    assert "role_source_url" not in s.split("'key','investors'", 1)[1].split("end if;", 1)[0]
    assert UNDO.exists()
    undo = UNDO.read_text(encoding="utf-8")
    assert "drop table public.v2_investor_principles" in undo
    assert "investors block not found" in undo


def test_seed_is_the_five_verified_quotes_only():
    seed = _seed()
    summaries = dict(re.findall(r"\$qQ(\d+)s\$(.*?)\$qQ\1s\$", seed, re.S))
    quotes = dict(re.findall(r"\$qQ(\d+)\$(.*?)\$qQ\1\$", seed, re.S))
    assert set(summaries) == set(SUMMARIES)
    assert summaries == SUMMARIES
    assert set(quotes) == set(SUMMARIES)
    for n, start in QUOTE_START.items():
        assert quotes[n].startswith(start)
        assert quotes[n] != summaries[n]
        assert len(summaries[n]) <= 200
    assert re.findall(r"date '(\d{4}-\d{2}-\d{2})'", seed) == [
        "2026-01-14", "2026-01-14", "2010-06-29", "2016-05-30", "2016-05-30",
    ]
    assert seed.count("null::text") == 3
    assert seed.count("https://a16z.com/podcast/alex-rampell-on-tbpn-revenge-redemption-and-founder-drive/") == 2
    assert "https://podscripts.co/podcasts/the-a16z-show/alex-rampell-on-tbpn-revenge-redemption-and-founder-drive" in seed
    assert "https://a16z.com/announcement/why-andreessen-horowitz-invested-in-foursquare/" in seed
    for banned in ("cdixon.org", "pmarchive.com", "Andrew Chen", "Sarah Wang", "Jeff Jordan", "Anish Acharya", "Martin Casado", "Seema Amble"):
        assert banned not in seed
    assert "where f.slug = 'a16z'" in seed


DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_rls_constraints_and_a16z_seed():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute("select to_regclass('public.v2_investor_principles')")
        already = cur.fetchone()[0] is not None
        if not already:
            cur.execute(
                """
                do $$ begin
                  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
                  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
                  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
                end $$
                """
            )
            cur.execute("select to_regclass('public.v2_firms')")
            if cur.fetchone()[0] is None:
                cur.execute(
                    """
                    create table public.v2_firms (
                      firm_id bigint generated always as identity primary key,
                      slug text not null unique
                    )
                    """
                )
                cur.execute("insert into public.v2_firms (slug) values ('a16z'), ('empty-firm')")
            cur.execute(MIG.read_text(encoding="utf-8"))
        cur.execute("select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname='v2_investor_principles'")
        assert cur.fetchone()[0] is True
        cur.execute("select count(*) from pg_policy p join pg_class c on c.oid=p.polrelid where c.relname='v2_investor_principles'")
        assert cur.fetchone()[0] == 0
        cur.execute("select has_table_privilege('anon', 'public.v2_investor_principles', 'select')")
        assert cur.fetchone()[0] is False
        cur.execute("select has_table_privilege('service_role', 'public.v2_investor_principles', 'select')")
        assert cur.fetchone()[0] is True
        cur.execute("select has_table_privilege('service_role', 'public.v2_investor_principles', 'insert')")
        assert cur.fetchone()[0] is True
        cur.execute("set role anon")
        cur.execute("savepoint anon_read")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            cur.execute("select investor_name from public.v2_investor_principles")
        cur.execute("rollback to savepoint anon_read")
        cur.execute("reset role")
        cur.execute(
            """
            select investor_name, display_order, published_at::text, role_source_url is not null
              from public.v2_investor_principles p
              join public.v2_firms f on f.firm_id = p.firm_id
             where f.slug = 'a16z'
             order by display_order
            """
        )
        seeded = cur.fetchall()
        assert [r[1] for r in seeded] == [1, 2, 3, 4, 5]
        assert [r[0] for r in seeded] == ["Alex Rampell", "Alex Rampell", "Ben Horowitz", "Marc Andreessen", "Marc Andreessen"]
        assert [r[2] for r in seeded] == ["2026-01-14", "2026-01-14", "2010-06-29", "2016-05-30", "2016-05-30"]
        assert [r[3] for r in seeded] == [True, True, False, False, False]
        cur.execute(
            """
            select count(*) from public.v2_investor_principles p
              join public.v2_firms f on f.firm_id = p.firm_id
             where f.slug = 'empty-firm'
            """
        )
        if not already:
            assert cur.fetchone()[0] == 0
        else:
            cur.fetchone()
        cur.execute("select firm_id from public.v2_firms where slug = 'a16z'")
        firm_id = cur.fetchone()[0]
        cur.execute("savepoint bad")
        with pytest.raises(psycopg.Error):
            cur.execute(
                """
                insert into public.v2_investor_principles
                  (firm_id, investor_name, investor_title, summary, quote, published_at, source_url, display_order)
                values (%s, 'A', 'Partner', 'Same text', 'Same text', '2020-01-01', 'https://a16z.com/x', 90)
                """,
                (firm_id,),
            )
        cur.execute("rollback to savepoint bad")
        cur.execute("savepoint badurl")
        with pytest.raises(psycopg.Error):
            cur.execute(
                """
                insert into public.v2_investor_principles
                  (firm_id, investor_name, investor_title, summary, quote, published_at, source_url, display_order)
                values (%s, 'A', 'Partner', 'Short summary.', 'A different quote.', '2020-01-01', 'http://a16z.com/x', 91)
                """,
                (firm_id,),
            )
        cur.execute("rollback to savepoint badurl")
        cur.execute("savepoint dup")
        with pytest.raises(psycopg.Error):
            cur.execute(
                """
                insert into public.v2_investor_principles
                  (firm_id, investor_name, investor_title, summary, quote, published_at, source_url, display_order)
                values (%s, 'A', 'Partner', 'Short summary.', 'A different quote.', '2020-01-02', 'https://a16z.com/y', 1)
                """,
                (firm_id,),
            )
        cur.execute("rollback to savepoint dup")
        cur.execute("select rolbypassrls from pg_roles where rolname = 'service_role'")
        bypass = cur.fetchone()[0]
        cur.execute("set role service_role")
        cur.execute("select count(*) from public.v2_investor_principles")
        visible = cur.fetchone()[0]
        cur.execute("reset role")
        if bypass:
            assert visible >= 5
        else:
            assert visible == 0
        conn.rollback()
