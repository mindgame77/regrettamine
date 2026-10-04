#!/usr/bin/env python3
"""Insert one unpublished test firm. Never used by the live site.

1 firm, 3 vehicles, 20 people, 1,000 portfolio companies, 100 reviews,
150 sources. is_test is true and published is false. The schema rejects
publishing a test row.

    DATABASE_URL=postgresql:///regrettamine python3 scripts/stress_fixture.py
"""
import os
import sys
import uuid
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

SLUG = "stress-fixture"
COMPANIES = 1000
REVIEWS = 100
PEOPLE = 20
FUNDS = 3
SOURCES = 150


def _ids(n):
    return [str(uuid.uuid4()) for _ in range(n)]


def build_page_extras():
    """In-memory collections for the fund-page renderer. Marked as test data."""
    companies = [
        {
            "name": f"Stress Co {i:04d}",
            "domain": f"stress-{i:04d}.test",
            "round": "Seed" if i % 2 == 0 else "Series A",
            "outcome": ("operating", "exited", "shut down")[i % 3],
            "lead": i % 2 == 0,
            "board": i % 10 == 0,
        }
        for i in range(1, COMPANIES + 1)
    ]
    reviews = [
        {
            "founder": f"Stress Founder {i % PEOPLE + 1}",
            "company": f"Stress Co {i:04d}",
            "partner": f"Stress Partner {(i % PEOPLE) + 1}",
            "body": f"TEST DATA review {i}",
            "firstHand": i % 2 == 0,
            "verification": "verified" if i % 2 == 0 else "unverified",
            "moderation": "approved",
            "date": "2024-01-01",
            "ratings": [
                {"dimension": "treatment", "score": (i % 5) + 1},
                {"dimension": "support", "score": (i % 4) + 1},
            ],
        }
        for i in range(1, REVIEWS + 1)
    ]
    vehicles = [
        {"name": f"Stress Fund {n}", "vintage": 2020 + n, "size": 100000000 * n, "status": "investing", "kind": "flagship"}
        for n in range(1, FUNDS + 1)
    ]
    return companies, reviews, vehicles


def insert_stress(conn):
    """Replace any previous stress-fixture row and load the small fixture."""
    companies, reviews, vehicles = build_page_extras()
    firm_id = str(uuid.uuid4())
    people_ids = _ids(PEOPLE)
    fund_ids = _ids(FUNDS)
    company_ids = _ids(COMPANIES)
    review_ids = _ids(REVIEWS)
    source_ids = _ids(SOURCES)
    with conn.cursor() as cur:
        cur.execute("delete from firms where slug = %s", (SLUG,))
        cur.execute(
            """
            insert into firms (
              id, slug, name, initials, hq, founded_year, firm_type,
              list_score, list_band, list_v2, list_legal_active, list_sort,
              published, is_test, legal_note
            ) values (
              %s, %s, %s, 'TD', 'Test City', 2020, 'VC',
              50, 'Moderate', false, 0, 999,
              false, true, 'TEST DATA — not a real firm'
            )
            """,
            (firm_id, SLUG, "TEST DATA — do not publish"),
        )
        cur.executemany(
            """
            insert into funds (id, firm_id, name, vintage, size_usd, status, vehicle_kind, sort_order)
            values (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            [
                (fund_ids[i], firm_id, vehicle["name"], vehicle["vintage"], vehicle["size"], vehicle["status"], vehicle["kind"], i)
                for i, vehicle in enumerate(vehicles)
            ],
        )
        cur.executemany(
            "insert into people (id, full_name) values (%s, %s)",
            [(people_ids[i], f"Stress Partner {i + 1}") for i in range(PEOPLE)],
        )
        cur.executemany(
            """
            insert into fund_people (id, person_id, firm_id, fund_id, role, start_date, sort_order)
            values (%s, %s, %s, %s, 'General partner', %s, %s)
            """,
            [
                (str(uuid.uuid4()), people_ids[i], firm_id, fund_ids[i % FUNDS], date(2020, 1, 1), i)
                for i in range(PEOPLE)
            ],
        )
        cur.executemany(
            "insert into portfolio_companies (id, name, domain, sector) values (%s, %s, %s, 'test')",
            [(company_ids[i], companies[i]["name"], companies[i]["domain"]) for i in range(COMPANIES)],
        )
        cur.executemany(
            """
            insert into company_founders (id, company_id, person_id, title)
            values (%s, %s, %s, 'Founder')
            """,
            [
                (str(uuid.uuid4()), company_ids[i], people_ids[i])
                for i in range(PEOPLE)
            ],
        )
        investment_ids = _ids(COMPANIES)
        cur.executemany(
            """
            insert into investments (
              id, firm_id, fund_id, company_id, round_name, invested_on, is_lead, board_seat, outcome
            ) values (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            [
                (
                    investment_ids[i],
                    firm_id,
                    fund_ids[i % FUNDS],
                    company_ids[i],
                    companies[i]["round"],
                    date(2021, 1, 1),
                    companies[i]["lead"],
                    companies[i]["board"],
                    companies[i]["outcome"],
                )
                for i in range(COMPANIES)
            ],
        )
        cur.executemany(
            """
            insert into reviews (
              id, firm_id, fund_id, company_id, founder_person_id, partner_person_id,
              body, first_hand, verification_status, moderation_status, reviewed_on
            ) values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            [
                (
                    review_ids[i],
                    firm_id,
                    fund_ids[i % FUNDS],
                    company_ids[i],
                    people_ids[i % PEOPLE],
                    people_ids[(i + 1) % PEOPLE],
                    reviews[i]["body"],
                    reviews[i]["firstHand"],
                    reviews[i]["verification"],
                    reviews[i]["moderation"],
                    date(2024, 1, 1),
                )
                for i in range(REVIEWS)
            ],
        )
        rating_rows = []
        for i in range(REVIEWS):
            for rating in reviews[i]["ratings"]:
                rating_rows.append((str(uuid.uuid4()), review_ids[i], rating["dimension"], rating["score"]))
        cur.executemany(
            "insert into review_ratings (id, review_id, dimension, score) values (%s, %s, %s, %s)",
            rating_rows,
        )
        cur.executemany(
            """
            insert into sources (id, url, publisher, domain, verified, junk)
            values (%s, %s, 'TEST DATA', 'example.test', true, false)
            """,
            [(source_ids[i], f"https://example.test/stress/{i + 1}") for i in range(SOURCES)],
        )
        cur.executemany(
            """
            insert into fact_sources (id, source_id, firm_id, fact_type, fact_id, label, sort_order)
            values (%s, %s, %s, %s, %s, %s, %s)
            """,
            [
                (
                    str(uuid.uuid4()),
                    source_ids[i],
                    firm_id,
                    "review" if i < REVIEWS else "investment",
                    review_ids[i] if i < REVIEWS else investment_ids[i % COMPANIES],
                    f"TEST DATA source {i + 1}",
                    i,
                )
                for i in range(SOURCES)
            ],
        )
    return {
        "firm_id": firm_id,
        "companies": COMPANIES,
        "reviews": REVIEWS,
        "people": PEOPLE,
        "funds": FUNDS,
        "sources": SOURCES,
    }


def main():
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        sys.exit("DATABASE_URL is required")
    import psycopg

    with psycopg.connect(url) as conn:
        counts = insert_stress(conn)
        conn.commit()
    print(
        "inserted unpublished test firm "
        f"{SLUG}: {counts['funds']} funds, {counts['people']} people, "
        f"{counts['companies']} companies, {counts['reviews']} reviews, {counts['sources']} sources"
    )


if __name__ == "__main__":
    main()
