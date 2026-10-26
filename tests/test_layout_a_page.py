"""Layout A is one page builder for every firm: rows, one News section, and a client-side tab switch."""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
COPY = json.loads((ROOT / "launch" / "copy.json").read_text())
JS = (ROOT / "launch" / "js" / "company.js").read_text()
APP = (ROOT / "launch" / "js" / "app.js").read_text()
BUILD = (ROOT / "launch" / "build.py").read_text()
CSS = (ROOT / "launch" / "style.css").read_text()
RULES = (ROOT / "docs" / "DATA_RULES.md").read_text()


def test_sections_are_layout_a():
    keys = [s["key"] for s in COPY["sections"]["list"]]
    assert keys == ["overview", "legal", "news", "founders", "people", "funds", "lps"]
    news = COPY["sections"]["list"][2]
    assert news["title"] == "News" and news["renderer"] == "news"
    assert "checks" not in keys and "press" not in keys and "timeline" not in keys
    assert COPY["company"]["legal"]["case"] == "Cases"
    assert COPY["company"]["legal"]["regulator"] == "Regulators"
    assert COPY["company"]["legal"]["context"] == "Context"
    assert COPY["company"]["people"]["officer"] == "Officers"
    assert COPY["company"]["commitments"] == "{n} commitments"
    assert COPY["company"]["outlets"] == ["{n} outlet", "{n} outlets"]
    assert COPY["company"]["summary"] == "Check summary"
    assert "data-tab" in COPY["company"]["full_check"] or "full_check" in COPY["company"]


def test_page_renders_rows_news_and_a_client_side_toggle():
    assert "function row(" in JS and "function groupLps(" in JS and "news:" in JS
    assert "function buildNews(" in JS and "buildNews(" in JS.split("function pageSecs")[1]
    assert 'data-tab="checks"' in JS and "function applyTab(" in JS and "function paint(" in JS
    assert "The 10 checks" not in JS.split("function pageSecs")[1].split("function checkSummaryHtml")[0]
    assert 'data-tab="{k}"' in BUILD and 'id="panel-checks"' in BUILD and 'id="panel-full"' in BUILD
    assert "function goTab(" in APP and "history.pushState" in APP
    assert "scrollTo(0, 0)" not in APP
    assert "#panel-checks[hidden]" in CSS and ".rw{" in CSS and ".nout{" in CSS
    assert "display only" in RULES and "only when News is drawn" in RULES
    assert "news_items" not in RULES and "story_key" not in RULES


def test_news_is_combined_when_the_page_draws():
    r = subprocess.run(["node", "--test", "tests/news_display.test.mjs"], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-2000:]


def test_legal_rows_put_active_first():
    r = subprocess.run(["node", "--test", "tests/legal_order.test.mjs"], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-2000:]
