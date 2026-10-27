"""Load the test database from tests/fixtures/db_snapshot.json.

The snapshot is an export of the live content tables (no user or billing data).
It exists only to give tests a realistic database; the site never reads it.
Never run this against live: it truncates the content tables first.
"""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
SNAPSHOT = ROOT / "tests" / "fixtures" / "db_snapshot.json"

# Parents before children.
ORDER = [
    "import_runs", "score_versions", "score_sections", "firms", "funds", "fund_entities", "people", "fund_people",
    "portfolio_companies", "company_founders", "investments", "reviews", "review_ratings",
    "legal_matters", "legal_matter_firms", "legal_matter_parties", "filings", "docket_entries",
    "legal_groups", "legal_group_items", "regulatory_records", "sanctions_checks",
    "press_items", "press_item_firms", "sources", "fact_sources", "takeaways", "ask_questions",
    "copy_blocks", "page_chips", "firm_meta_items", "list_items", "portfolio_metrics", "firm_ranks",
    "evidence_cards", "evidence_lines", "score_results", "score_result_parts", "score_lines", "score_inputs",
    "site_stats", "site_updates", "fact_events",
    "vc_aliases", "vc_fact_conflicts", "vc_source_facts", "vc_ai_summaries", "vc_ai_summary_facts",
    "vc_scores", "vc_score_parts", "vc_score_inputs", "vc_entity_identifiers", "vc_partner_history",
    "vc_political_activity", "vc_firm_claims", "vc_context_notes",
]


def reset(cur):
    cur.execute(
        """
        truncate table
          public.firms, public.people, public.portfolio_companies, public.sources,
          public.legal_matters, public.press_items, public.site_stats, public.site_updates,
          public.fact_events, public.import_runs, public.score_versions, public.vc_ai_summaries,
          public.vc_scores, public.site_fragments
        restart identity cascade
        """
    )


def insert_rows(cur, table, rows):
    if not rows:
        return
    cur.execute(
        "select column_name from information_schema.columns where table_schema = 'public' and table_name = %s "
        "and is_generated = 'NEVER' order by ordinal_position",
        (table,),
    )
    # Only columns present in the seed rows, so newer columns keep their defaults.
    present = set().union(*(r.keys() for r in rows))
    cols = [row[0] for row in cur.fetchall() if row[0] in present]
    col_list = ", ".join(f'"{c}"' for c in cols)
    cur.execute(
        f'insert into public."{table}" ({col_list}) overriding system value '
        f'select {col_list} from json_populate_recordset(null::public."{table}", %s::json)',
        (json.dumps(rows),),
    )


def load_db():
    """(home, funds) from DATABASE_URL. The loader lives in regrettamine, not the old site build."""
    from regrettamine.load_db import load_db as load
    return load()


def seed_report_bundles(cur):
    """Render each report from the database, the same way the build does, for open_report."""
    from build import render_report_payload
    from regrettamine.assemble import assemble_site

    cur.execute("select published_site_bundle()")
    bundle = cur.fetchone()[0]
    _home, funds = assemble_site(bundle)
    import build
    funds = build.apply_strings_to_data(funds)
    build.assign_list_ranks(funds)
    for slug, fund in funds.items():
        html = render_report_payload(fund, "../../")
        cur.execute(
            """
            insert into report_bundles (firm_id, payload)
            select id, jsonb_build_object('html', %s::text) from firms where slug = %s
            on conflict (firm_id) do update set payload = excluded.payload, updated_at = now()
            """,
            (html, slug),
        )


def main():
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        sys.exit("DATABASE_URL is required, for example postgresql:///regrettamine")
    import psycopg

    snapshot = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    with psycopg.connect(url) as conn:
        with conn.cursor() as cur:
            reset(cur)
            cur.execute("set local session_replication_role = replica")
            for table in ORDER:
                insert_rows(cur, table, snapshot.get(table) or [])
            cur.execute("set local session_replication_role = origin")
            seed_report_bundles(cur)
        conn.commit()
    firms = snapshot.get("firms") or []
    print(f"seeded {len(firms)} firms, {sum(1 for f in firms if f.get('report_slug'))} reports, {len(snapshot.get('site_updates') or [])} updates")


if __name__ == "__main__":
    main()
