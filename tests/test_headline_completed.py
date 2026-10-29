import os
import pytest

DATABASE_URL = os.environ.get("DATABASE_URL")
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="needs DATABASE_URL")


@pytest.mark.parametrize("pub,new,ok", [
    ("Hold Lab raises a fund", "Hold Lab raises a fund for AI", True),
    ("Hold Lab raises a…", "Hold Lab raises a new fund", True),
    ("Hold Lab raises a...", "Hold Lab raises a new fund", True),
    ("Hold Lab raises a fund", "Hold Lab raises a fund", False),
    ("Hold Lab raises a fund", "Other lab raises a bigger fund", False),
    ("Hold Lab raises a fund for AI", "Hold Lab raises a fund", False),
    (None, "x", False),
])
def test_headline_completes(pub, new, ok):
    import psycopg
    with psycopg.connect(DATABASE_URL) as conn:
        assert conn.execute("select public._entry_headline_completes(%s, %s)", (pub, new)).fetchone()[0] is ok


def test_rulebook_has_headline_completed():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    guide = open(os.path.join(root, "docs", "PAGE_DATA_GUIDE.md"), encoding="utf-8").read()
    assert "'headline completed'" in guide


def test_headline_update_waits_for_links_to_open():
    import pathlib
    m = (pathlib.Path(__file__).resolve().parents[1] / "supabase" / "migrations" / "20261029075000_headline_after_link_opens.sql").read_text()
    trg = m[m.index("function bots.entry_check_trg()"):m.index("function public._checker_entry_gate(")]
    gate = m[m.index("function public._checker_entry_gate("):]
    assert "_entry_complete_headlines" not in trg
    assert "_entry_complete_headlines" in gate
