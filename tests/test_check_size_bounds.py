"""Check size pill is the stored US dollar bounds. The source sentence stays off the page."""
import os
import re
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261109000100_v2_check_size_bounds.sql"
UNDO = ROOT / "supabase/rollbacks/20261109000100_v2_check_size_bounds.sql"
GUIDE = ROOT / "docs/PAGE_DATA_GUIDE.md"
BRIEF = ROOT / "tools/ingest/external-bot-night-run.md"
SENTENCE = "Initial investments generally range from $25 million to $75 million"
WHOLE = re.compile(r"^[1-9][0-9]*$")


def money_display(amount):
    """Same abbreviation as public._money_display for a positive USD amount."""
    if amount is None:
        return None
    amount = Decimal(str(amount))
    if amount <= 0:
        return None
    for div, suffix in ((Decimal(10**9), "B"), (Decimal(10**6), "M"), (Decimal(10**3), "K")):
        if amount >= div:
            q = amount / div
            places = Decimal("1") if q >= 100 else Decimal("0.01")
            q = q.quantize(places, rounding=ROUND_HALF_UP)
            text = format(q, "f")
            if "." in text:
                text = text.rstrip("0").rstrip(".")
            return "$" + text + suffix
    return "$" + format(amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP), "f")


def whole(value):
    if value is None:
        return False
    return WHOLE.fullmatch(str(value).strip()) is not None


def check_size_label(min_usd, max_usd):
    """Page label. A missing side stays missing. A single number is not copied across."""
    if whole(min_usd) and whole(max_usd) and int(str(min_usd).strip()) == int(str(max_usd).strip()):
        return money_display(min_usd)
    if whole(min_usd) and whole(max_usd) and int(str(min_usd).strip()) < int(str(max_usd).strip()):
        return money_display(min_usd) + "\u2013" + money_display(max_usd)
    if min_usd is None and whole(max_usd):
        return "Up to " + money_display(max_usd)
    if max_usd is None and whole(min_usd):
        return money_display(min_usd) + "+"
    return None


def check_size_reason(fact):
    """One item. None means the numbers can be stored. The sentence is not parsed."""
    fact = dict(fact)
    if "currency" in fact and str(fact.get("currency") or "").strip().upper() != "USD":
        return "check size currency must be USD"
    fact.pop("currency", None)
    if not str(fact.get("amount_text") or "").strip():
        return "check size amount_text is required (source excerpt, not shown)"
    if "min_usd" in fact and fact["min_usd"] is not None and not whole(fact["min_usd"]):
        return "check size min_usd must be a positive whole number of US dollars"
    if "max_usd" in fact and fact["max_usd"] is not None and not whole(fact["max_usd"]):
        return "check size max_usd must be a positive whole number of US dollars"
    has_min = whole(fact.get("min_usd"))
    has_max = whole(fact.get("max_usd"))
    if not has_min and not has_max:
        return "check size needs min_usd or max_usd"
    if has_min and has_max and int(str(fact["min_usd"]).strip()) > int(str(fact["max_usd"]).strip()):
        return "check size min_usd is greater than max_usd"
    return None


def test_labels_follow_the_four_shapes_and_do_not_invent_a_bound():
    assert check_size_label(25000000, 25000000) == "$25M"
    assert check_size_label(25000000, 75000000) == "$25M\u2013$75M"
    assert check_size_label(None, 25000000) == "Up to $25M"
    assert check_size_label(25000000, None) == "$25M+"
    assert check_size_label(500000, 2000000) == "$500K\u2013$2M"
    assert check_size_label(25000, 500000) == "$25K\u2013$500K"
    assert check_size_label(None, 1000000) == "Up to $1M"
    assert check_size_label(None, 250000) == "Up to $250K"
    assert check_size_label(None, None) is None
    assert check_size_label(75000000, 25000000) is None
    assert check_size_label(0, 25000000) is None
    assert check_size_label("25.5", 75000000) is None
    assert SENTENCE not in (check_size_label(25000000, 75000000) or "")


def test_door_rejects_one_bad_item_and_keeps_the_sentence_with_numbers():
    good = {"amount_text": SENTENCE, "min_usd": 25000000, "max_usd": 75000000}
    assert check_size_reason(good) is None
    assert check_size_reason({"amount_text": SENTENCE}) == "check size needs min_usd or max_usd"
    assert check_size_reason({"amount_text": SENTENCE, "min_usd": None, "max_usd": None}) == "check size needs min_usd or max_usd"
    assert check_size_reason({"amount_text": SENTENCE, "min_usd": 0, "max_usd": 75000000}).startswith("check size min_usd")
    assert check_size_reason({"amount_text": SENTENCE, "min_usd": -1, "max_usd": 5}).startswith("check size min_usd")
    assert check_size_reason({"amount_text": SENTENCE, "min_usd": "25.5", "max_usd": 75}).startswith("check size min_usd")
    assert check_size_reason({"amount_text": SENTENCE, "min_usd": "25 million", "max_usd": 75000000}).startswith("check size min_usd")
    assert check_size_reason({"amount_text": SENTENCE, "max_usd": "75 million"}).startswith("check size max_usd")
    assert check_size_reason({"amount_text": SENTENCE, "min_usd": 75000000, "max_usd": 25000000}) == "check size min_usd is greater than max_usd"
    assert check_size_reason({"amount_text": "  ", "min_usd": 25000000, "max_usd": 25000000}).startswith("check size amount_text")
    assert check_size_reason({"min_usd": 25000000, "max_usd": 25000000}).startswith("check size amount_text")
    assert check_size_reason({"amount_text": SENTENCE, "max_usd": 25000000}) is None
    assert check_size_reason({"amount_text": SENTENCE, "min_usd": 25000000}) is None
    assert check_size_reason({"amount_text": SENTENCE, "min_usd": 25000000, "max_usd": 25000000}) is None
    assert check_size_reason({"amount_text": SENTENCE, "min_usd": 25000000, "max_usd": 75000000, "currency": "EUR"}) == "check size currency must be USD"
    assert check_size_reason({"amount_text": SENTENCE, "min_usd": 25000000, "max_usd": 75000000, "currency": "usd"}) is None
    assert check_size_reason({"amount_text": SENTENCE, "min_usd": 25000000, "max_usd": 75000000, "currency": " USD "}) is None
    assert check_size_reason({"amount_text": SENTENCE, "min_usd": 25000000, "max_usd": 75000000, "currency": ""}) == "check size currency must be USD"
    sibling_bad = check_size_reason({"amount_text": SENTENCE})
    sibling_good = check_size_reason(good)
    assert sibling_bad and sibling_good is None


def test_migration_formats_from_numbers_and_rejects_per_item():
    text = MIG.read_text(encoding="utf-8")
    undo = UNDO.read_text(encoding="utf-8")
    guide = GUIDE.read_text(encoding="utf-8")
    brief = BRIEF.read_text(encoding="utf-8")
    select = text.split("(select case when c.min_usd", 1)[1].split(" end from v2_firm_check_sizes", 1)[0]
    assert "public._money_display(c.min_usd,'USD')" in select
    assert "public._money_display(c.max_usd,'USD')" in select
    assert "\u2013" in select
    assert "'Up to '" in select
    assert "|| '+'" in select
    assert "else null" in select
    assert "amount_text" not in select
    assert "source_level" not in text
    assert "create table" not in text.lower()
    assert "add column" not in text.lower()
    assert "check size currency must be USD" in text
    assert "check size amount_text is required (source excerpt, not shown)" in text
    assert "check size min_usd must be a positive whole number of US dollars" in text
    assert "check size max_usd must be a positive whole number of US dollars" in text
    assert "check size needs min_usd or max_usd" in text
    assert "check size min_usd is greater than max_usd" in text
    assert "fact := fact - 'currency'" in text
    assert "v2 schema missing, skipped page" in text
    assert "v2_research_submit missing, skipped" in text
    door = text.split("IF reason IS NULL AND tbl = 'v2_firm_check_sizes' THEN", 1)[1].split("check size min_usd is greater than max_usd", 1)[0]
    assert "RAISE" not in door
    assert "nullif(btrim(c.amount_text)" in undo
    assert "check size needs min_usd or max_usd" in undo
    assert "$25M–$75M" in guide
    assert "Up to $25M" in guide
    assert "$25M+" in guide
    assert "amount_text` is the source excerpt and is not shown" in guide
    assert "Which source levels are shown is unchanged." in guide
    assert "Seed checks run from $500,000 to $2 million" in brief
    assert "$500K–$2M" in brief


def _page_case(text):
    body = text.split("(select case when c.min_usd", 1)[1].split(" end from v2_firm_check_sizes", 1)[0]
    return "select case when c.min_usd" + body + " end"


@pytest.mark.skipif(not os.environ.get("DATABASE_URL", "").strip(), reason="DATABASE_URL is not set")
def test_page_sql_matches_money_display_for_every_shape():
    import psycopg

    case = _page_case(MIG.read_text(encoding="utf-8"))
    cases = [
        (25000000, 25000000, "$25M"),
        (25000000, 75000000, "$25M\u2013$75M"),
        (None, 25000000, "Up to $25M"),
        (25000000, None, "$25M+"),
        (500000, 2000000, "$500K\u2013$2M"),
        (25000, 500000, "$25K\u2013$500K"),
        (None, 1000000, "Up to $1M"),
        (None, 250000, "Up to $250K"),
        (None, None, None),
        (75000000, 25000000, None),
        (0, 25000000, None),
    ]
    with psycopg.connect(os.environ["DATABASE_URL"]) as conn, conn.cursor() as cur:
        cur.execute("select to_regprocedure('public._money_display(numeric,text)')")
        if cur.fetchone()[0] is None:
            pytest.skip("_money_display is not installed")
        for lo, hi, expected in cases:
            cur.execute(
                f"{case} from (values (%s::numeric, %s::numeric)) as c(min_usd, max_usd)",
                (lo, hi),
            )
            assert cur.fetchone()[0] == expected
