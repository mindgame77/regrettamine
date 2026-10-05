"""One render of a small synthetic firm: 0, 1, and many rows.

The fixture is test data. It is not a published fund and it is not seeded
with the real firms.
"""
import json
from pathlib import Path

from build import render_fund_page
from scripts.stress_fixture import build_page_extras

ROOT = Path(__file__).resolve().parents[1]


def _a16z():
    return json.loads((ROOT / "data" / "funds" / "a16z.json").read_text(encoding="utf-8"))


def _slice(html, start, end):
    return html.split(start, 1)[1].split(end, 1)[0]


def test_template_zero_one_and_many():
    companies, reviews, vehicles = build_page_extras()
    assert len(companies) == 1000
    assert len(reviews) == 100
    assert len(vehicles) == 3

    empty = _a16z()
    empty["summary"] = ""
    empty["takeaways"] = []
    empty["topLegal"] = []
    empty["matters"] = []
    empty["legalGroups"] = []
    empty["public"]["items"] = []
    empty_html = render_fund_page(empty, "../../")
    assert "No summary yet." in empty_html
    assert "No takeaways yet." in empty_html
    assert "No legal matters on file." in empty_html
    assert "No data yet. We found no press for this fund." in empty_html
    assert "No data yet. We found no court cases, regulator actions or sanctions for this fund." in empty_html
    assert "moreCos" not in empty_html

    one = _a16z()
    one["companies"] = companies[:1]
    one["reviews"] = reviews[:1]
    one_html = render_fund_page(one, "../../")
    assert "Stress Co 0001" in one_html
    assert "1 company" in one_html
    assert "moreCos" not in one_html
    assert "1 review" in one_html
    assert "moreReviews" not in one_html

    many = _a16z()
    many["name"] = "TEST DATA"
    many["companies"] = companies
    many["reviews"] = reviews
    many["vehicles"] = vehicles
    many["fundTab"]["boards"]["items"] = [
        {"name": f"Stress Partner {i}", "value": "Board"} for i in range(1, 21)
    ]
    sample = dict(many["public"]["items"][0])
    extra = []
    for i in range(1, 13):
        item = dict(sample)
        item["headline"] = f"TEST DATA press {i}"
        item["url"] = f"https://example.test/press/{i}"
        extra.append(item)
    many["public"]["items"] = many["public"]["items"] + extra
    html = render_fund_page(many, "../../")
    co_list = _slice(html, 'id="coList">', 'id="moreCos"')
    assert "Stress Co 0001" in co_list
    assert "Stress Co 1000" not in co_list
    assert "Stress Co 1000" in html
    assert 'id="moreCos"' in html
    review_list = _slice(html, 'id="reviewList">', 'id="moreReviews"')
    assert "TEST DATA review 1" in review_list
    assert "TEST DATA review 100" not in review_list
    assert "Stress Fund 1" in html
    assert "Show more" in html
    assert "Stress Partner 20" in html
    press_list = _slice(html, 'id="pressList">', 'id="morePress"')
    assert "TEST DATA press 12" not in press_list
    assert "TEST DATA press 12" in html
