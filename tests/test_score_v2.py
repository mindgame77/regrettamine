"""Toxy Score v2. The a16z worksheet is the published worked example."""
import json
from decimal import Decimal
from pathlib import Path

from regrettamine.score_v2 import A16Z_SCORE_INPUTS, score_v2

ROOT = Path(__file__).resolve().parents[1]


def test_a16z_published_worksheet():
    result = score_v2(A16Z_SCORE_INPUTS)
    sections = result["sections"]
    assert sections["s1"] == Decimal("60")
    assert sections["s2"] == Decimal("14.25")
    assert sections["s3"] == Decimal("16.6")
    assert sections["s4"] == Decimal("4")
    assert sections["bonus"] == Decimal("3")
    assert sections["pen"] == Decimal("-2.5")
    assert result["total"] == Decimal("95.4")
    assert result["band"] == "Very low risk"
    assert result["sanctions_banner"] is False


def test_rate_scale_and_loss_deduction():
    inputs = [
        {"section_code": "s1", "name": "portfolio_companies", "value_numeric": 100},
        {"section_code": "s1", "name": "own_founder_lawsuits", "value_numeric": 2},  # 2% → 10% off 30
        {"section_code": "s1", "name": "founder_ceo_removals", "value_numeric": 0},
        {"section_code": "s1", "name": "downround_events", "value_numeric": 0},
        {"section_code": "s1", "name": "blocking_events", "value_numeric": 0},
        {"section_code": "s1", "name": "losses_or_fraud", "value_numeric": 1},  # −3 even under 1%
    ]
    # 30 * 0.9 + 12 + 10 + 8 - 3 = 27 + 12 + 10 + 8 - 3 = 54
    assert score_v2(inputs)["sections"]["s1"] == Decimal("54")


def test_conflict_scales_with_partner_count():
    solo = score_v2([
        {"section_code": "s4", "name": "investing_partners", "value_numeric": 1},
        {"section_code": "s4", "name": "conflict", "value_numeric": 1},
    ])
    wide = score_v2([
        {"section_code": "s4", "name": "investing_partners", "value_numeric": 88},
        {"section_code": "s4", "name": "conflict", "value_numeric": 1},
    ])
    assert solo["sections"]["s4"] == Decimal("4")
    assert wide["sections"]["s4"] > solo["sections"]["s4"]
    assert wide["sections"]["s4"] == Decimal("5") - (Decimal("1") / Decimal("88"))


def test_young_fund_age_default_and_cap():
    young = score_v2([
        {"section_code": "s3", "name": "portfolio_companies", "value_numeric": 4},
        {"section_code": "s3", "name": "fund_age_years", "value_numeric": 1},
        {"section_code": "s3", "name": "negative_first_hand", "value_numeric": 0},
        {"section_code": "s3", "name": "first_hand_accounts", "value_numeric": 0},
    ])
    assert young["sections"]["s3"] == Decimal("7")

    sanctioned = A16Z_SCORE_INPUTS + [
        {"section_code": "pen", "name": "listed", "value_numeric": -50, "value_text": "sanction"},
    ]
    banned = score_v2(sanctioned)
    assert banned["sections"]["pen"] == Decimal("-50")
    assert banned["total"] == Decimal("47.9")
    assert banned["sanctions_banner"] is True


def test_partner_departures_count_per_year_capped():
    import copy
    from regrettamine.score_v2 import A16Z_SCORE_INPUTS, score_v2

    def with_years(n):
        rows = copy.deepcopy(A16Z_SCORE_INPUTS)
        for r in rows:
            if r["name"] == "partner_departure_years":
                r["value_numeric"] = n
        return score_v2(rows)["total"]

    assert with_years(1) == Decimal("95.4")
    assert with_years(0) - with_years(1) == Decimal("0.5")
    assert with_years(4) == with_years(9)


def test_published_fund_scores_match_inputs():
    inputs = json.loads((ROOT / "data" / "score_inputs.json").read_text(encoding="utf-8"))
    assert set(inputs) == {
        "lux", "accel", "bessemer", "battery", "insightpartners",
        "baincapitalventures", "generalcatalyst", "sequoia", "khosla", "lightspeed",
    }
    for slug, rows in inputs.items():
        fund = json.loads((ROOT / "data" / "funds" / f"{slug}.json").read_text(encoding="utf-8"))
        result = score_v2(rows)
        assert result["total"] == Decimal(str(fund["scoreExact"])), slug
        assert result["band"] == fund["band"], slug
        by_id = {part["id"]: part["got"] for part in fund["parts"]}
        assert by_id["s1"] == _got(result["sections"]["s1"])
        assert by_id["s3"] == _got(result["sections"]["s3"])
        assert by_id["s4"] == _got(result["sections"]["s4"])
        assert by_id["bonus"] == "+" + _got(result["sections"]["bonus"])
        pen = result["sections"]["pen"]
        assert by_id["pen"] == ("0" if pen == 0 else "−" + _got(abs(pen)))


def _got(value):
    text = format(value, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text or "0"
