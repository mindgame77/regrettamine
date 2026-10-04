#!/usr/bin/env python3
"""Import a worksheet CSV. Skips rows with example=yes.

    DATABASE_URL=postgresql:///regrettamine python3 scripts/import_csv.py funds templates/csv/funds.csv
    DATABASE_URL=… python3 scripts/import_csv.py legal templates/csv/legal_matters.csv
    DATABASE_URL=… python3 scripts/import_csv.py people templates/csv/people.csv
    DATABASE_URL=… python3 scripts/import_csv.py press templates/csv/press_items.csv

firm_slug must already exist in firms. fund_name, when set, must match a vehicle of that firm.
"""
import csv
import os
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def connect():
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        sys.exit("DATABASE_URL is required")
    import psycopg
    return psycopg.connect(url)


def rows(path):
    with open(path, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if (row.get("example") or "").strip().lower() == "yes":
                continue
            if not any((value or "").strip() for value in row.values()):
                continue
            yield row


def firm_id(cur, slug):
    cur.execute("select id from firms where slug = %s", (slug,))
    found = cur.fetchone()
    if not found:
        sys.exit(f"no firm with slug {slug!r}. Add the firm in the Table Editor first.")
    return found[0]


def fund_id(cur, firm, name):
    if not (name or "").strip():
        return None
    cur.execute("select id from funds where firm_id = %s and name = %s", (firm, name))
    found = cur.fetchone()
    if not found:
        sys.exit(f"no vehicle named {name!r} for that firm")
    return found[0]


def import_funds(cur, path):
    count = 0
    for row in rows(path):
        cur.execute(
            """
            insert into funds (id, firm_id, name, vintage, size_usd, status, vehicle_kind, notes)
            values (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                str(uuid.uuid4()),
                firm_id(cur, row["firm_slug"]),
                row["name"],
                row.get("vintage") or None,
                row.get("size_usd") or None,
                row.get("status") or None,
                row.get("vehicle_kind") or None,
                row.get("notes") or None,
            ),
        )
        count += 1
    return count


def import_legal(cur, path):
    count = 0
    for row in rows(path):
        matter = str(uuid.uuid4())
        fid = firm_id(cur, row["firm_slug"])
        counted = (row.get("counted") or "").strip().lower() in {"1", "true", "yes", "y"}
        cur.execute(
            "insert into legal_matters (id, source_key, title) values (%s, %s, %s)",
            (matter, row.get("source_key") or None, row.get("detail") or row.get("summary")),
        )
        cur.execute(
            """
            insert into legal_matter_firms (
              id, matter_id, firm_id, party_role, status, counted, relevance, points,
              year_label, summary, detail, badge, evidence_key
            ) values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                str(uuid.uuid4()),
                matter,
                fid,
                row.get("party_role") or None,
                row.get("status") or None,
                counted,
                row.get("relevance") or None,
                row.get("points") or None,
                row.get("year") or None,
                row.get("summary") or None,
                row.get("detail") or None,
                row.get("badge") or None,
                row.get("source_key") or None,
            ),
        )
        count += 1
    return count


def import_people(cur, path):
    count = 0
    for row in rows(path):
        fid = firm_id(cur, row["firm_slug"])
        cur.execute("select id from people where full_name = %s", (row["full_name"],))
        found = cur.fetchone()
        if found:
            person = found[0]
        else:
            person = str(uuid.uuid4())
            cur.execute("insert into people (id, full_name) values (%s, %s)", (person, row["full_name"]))
        cur.execute(
            """
            insert into fund_people (id, person_id, firm_id, fund_id, role, start_date, end_date, notes)
            values (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                str(uuid.uuid4()),
                person,
                fid,
                fund_id(cur, fid, row.get("fund_name")),
                row.get("role") or "Partner",
                row.get("start_date") or None,
                row.get("end_date") or None,
                row.get("notes") or None,
            ),
        )
        count += 1
    return count


def import_press(cur, path):
    count = 0
    for row in rows(path):
        fid = firm_id(cur, row["firm_slug"])
        press = str(uuid.uuid4())
        cur.execute(
            """
            insert into press_items (id, publisher, url, published_on, headline, sentiment, why, group_label)
            values (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                press,
                row.get("publisher") or None,
                row.get("url") or None,
                row.get("published_on") or None,
                row.get("headline") or None,
                row.get("sentiment") or None,
                row.get("why") or None,
                row.get("group_label") or None,
            ),
        )
        cur.execute(
            "insert into press_item_firms (press_item_id, firm_id) values (%s, %s)",
            (press, fid),
        )
        count += 1
    return count


IMPORTERS = {
    "funds": import_funds,
    "legal": import_legal,
    "people": import_people,
    "press": import_press,
}


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in IMPORTERS:
        sys.exit("usage: import_csv.py funds|legal|people|press FILE.csv")
    kind, path = sys.argv[1], sys.argv[2]
    with connect() as conn:
        with conn.cursor() as cur:
            count = IMPORTERS[kind](cur, path)
        conn.commit()
    print(f"imported {count} {kind} row(s) from {path}")


if __name__ == "__main__":
    main()
