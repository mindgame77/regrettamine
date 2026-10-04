"""Toxy Score v2.

Pure function. Section scores come from score_inputs rows. The rules are
docs/toxy-score-v2-rules.md (agreed Oct 2, 2026). Higher is better. The
total is capped to 0–100.

Inputs are a list of dicts:

    {"section_code", "name", "value_numeric", "value_text", "max_numeric"}

Missing numbers count as 0. The a16z worksheet below is the published
worked example, not a special case inside the formula.
"""
from decimal import Decimal, ROUND_HALF_UP

SECTIONS = ("s1", "s2", "s3", "s4", "bonus", "pen")

# Age-default points, as published in the rules (95% of 17.5 is 16.6).
_AGE_POINTS = (
    (lambda age, n: age >= 10 and n > 500, Decimal("16.6")),
    (lambda age, n: age >= 10, Decimal("14.9")),
    (lambda age, n: age >= 5, Decimal("12.25")),
    (lambda age, n: age >= 2, Decimal("8.75")),
    (lambda age, n: True, Decimal("7")),
)

_TONE_POINTS = {
    "mostly_positive": Decimal("15.75"),
    "mixed": Decimal("9.6"),
    "mostly_negative": Decimal("3.5"),
    "serious_harm": Decimal("0"),
}

# Published a16z drivers. Names and figures are the score file / rules example.
A16Z_SCORE_INPUTS = [
    {"section_code": "s1", "name": "portfolio_companies", "value_numeric": 1456},
    {"section_code": "s1", "name": "own_founder_lawsuits", "value_numeric": 1},
    {"section_code": "s1", "name": "founder_ceo_removals", "value_numeric": 1},
    {"section_code": "s1", "name": "downround_events", "value_numeric": 0},
    {"section_code": "s1", "name": "blocking_events", "value_numeric": 0},
    {"section_code": "s1", "name": "losses_or_fraud", "value_numeric": 0},
    {"section_code": "s2", "name": "money_fund_size", "value_numeric": 2, "max_numeric": 2},
    {"section_code": "s2", "name": "money_reserves", "value_numeric": Decimal("1.5"), "max_numeric": 2},
    {"section_code": "s2", "name": "money_hit_target", "value_numeric": Decimal("1.5"), "max_numeric": 2},
    {"section_code": "s2", "name": "media_points", "value_numeric": 6, "max_numeric": 6},
    {"section_code": "s2", "name": "help_platform", "value_numeric": 1, "max_numeric": 2},
    {"section_code": "s2", "name": "help_intros", "value_numeric": Decimal("0.75"), "max_numeric": Decimal("1.5")},
    {"section_code": "s2", "name": "help_stability", "value_numeric": 2, "max_numeric": 2},
    {"section_code": "s2", "name": "partner_departures", "value_numeric": 1},
    {"section_code": "s3", "name": "portfolio_companies", "value_numeric": 1456},
    {"section_code": "s3", "name": "fund_age_years", "value_numeric": 16},
    {"section_code": "s3", "name": "negative_first_hand", "value_numeric": 2},
    {"section_code": "s3", "name": "first_hand_accounts", "value_numeric": 3},
    {"section_code": "s4", "name": "investing_partners", "value_numeric": 88},
    {"section_code": "s4", "name": "conflict_count", "value_numeric": 3},
    {"section_code": "s4", "name": "scaled_deduction", "value_numeric": 1},
    {"section_code": "bonus", "name": "years_investing", "value_numeric": 16},
    {"section_code": "bonus", "name": "significant_harm", "value_numeric": 0},
    {"section_code": "pen", "name": "doj_probe", "value_numeric": Decimal("-2"), "value_text": "open_investigation"},
    {"section_code": "pen", "name": "coinbase_director_suit", "value_numeric": Decimal("-0.5"), "value_text": "director_suit"},
    {"section_code": "pen", "name": "sec_record", "value_numeric": 0, "value_text": "sec"},
    {"section_code": "pen", "name": "sanctions", "value_numeric": 0, "value_text": "sanctions_clear"},
]


def _d(value):
    if value is None or value == "":
        return Decimal("0")
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


def _by_name(inputs, section):
    out = {}
    for row in inputs:
        if row.get("section_code") == section:
            out[row["name"]] = row
    return out


def _num(rows, name):
    row = rows.get(name)
    if not row:
        return Decimal("0")
    return _d(row.get("value_numeric"))


def rate_fraction(count, portfolio):
    """Share of the portfolio, mapped to the v2 penalty fraction.

    Under 1% costs nothing. 1–3% is a small penalty (10% of the subsection).
    3–10% is medium (35%). Over 10% is large (70%).
    """
    count = _d(count)
    portfolio = _d(portfolio)
    if count <= 0:
        return Decimal("0")
    if portfolio <= 0:
        return Decimal("0.70")
    rate = count / portfolio
    if rate < Decimal("0.01"):
        return Decimal("0")
    if rate < Decimal("0.03"):
        return Decimal("0.10")
    if rate <= Decimal("0.10"):
        return Decimal("0.35")
    return Decimal("0.70")


def _section_fund_vs_founders(inputs):
    rows = _by_name(inputs, "s1")
    portfolio = _num(rows, "portfolio_companies")
    parts = (
        ("own_founder_lawsuits", Decimal("30")),
        ("founder_ceo_removals", Decimal("12")),
        ("downround_events", Decimal("10")),
        ("blocking_events", Decimal("8")),
    )
    total = Decimal("0")
    for name, maximum in parts:
        kept = Decimal("1") - rate_fraction(_num(rows, name), portfolio)
        total += maximum * kept
    total -= Decimal("3") * _num(rows, "losses_or_fraud")
    return max(Decimal("0"), total)


def _section_support(inputs):
    rows = _by_name(inputs, "s2")
    money = _num(rows, "money_fund_size") + _num(rows, "money_reserves") + _num(rows, "money_hit_target")
    money = min(Decimal("6"), max(Decimal("0"), money))
    media = min(Decimal("6"), max(Decimal("0"), _num(rows, "media_points")))
    # help_platform and help_intros are already at half when the only source is the fund.
    deduction = min(Decimal("2"), Decimal("0.5") * _num(rows, "partner_departures"))
    stability = max(Decimal("0"), _num(rows, "help_stability") - deduction)
    help_score = _num(rows, "help_platform") + _num(rows, "help_intros") + stability
    help_score = min(Decimal("5.5"), max(Decimal("0"), help_score))
    return money + media + help_score


def age_default(age_years, portfolio_companies):
    age = _d(age_years)
    count = _d(portfolio_companies)
    for predicate, points in _AGE_POINTS:
        if predicate(age, count):
            return points
    return Decimal("7")


def _section_founder_experience(inputs):
    rows = _by_name(inputs, "s3")
    portfolio = _num(rows, "portfolio_companies")
    negatives = _num(rows, "negative_first_hand")
    accounts = _num(rows, "first_hand_accounts")
    age = _num(rows, "fund_age_years")
    default = age_default(age, portfolio)
    share = (negatives / portfolio) if portfolio > 0 else (Decimal("1") if negatives > 0 else Decimal("0"))
    if share < Decimal("0.01"):
        return default
    tone = (rows.get("tone") or {}).get("value_text") or "mixed"
    content = _TONE_POINTS.get(tone, _TONE_POINTS["mixed"])
    if accounts < 5:
        blended = (content + default) / 2
        return blended.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return content


def _section_conflicts(inputs):
    """−1 per conflict, scaled by partner count, floored at 0.

    When the worksheet records a scaled deduction (a16z: 3 conflicts across
    88 partners, scaled cost 1), that figure is the deduction. Otherwise each
    conflict costs (partners involved / investing partners), and a one-partner
    firm pays the full point.
    """
    rows = _by_name(inputs, "s4")
    if "scaled_deduction" in rows:
        deduction = _num(rows, "scaled_deduction")
    else:
        partners = _num(rows, "investing_partners")
        weighted = Decimal("0")
        saw_conflict = False
        for row in inputs:
            if row.get("section_code") == "s4" and row.get("name") == "conflict":
                saw_conflict = True
                involved = _d(row.get("value_numeric")) or Decimal("1")
                weighted += involved
        if not saw_conflict:
            weighted = _num(rows, "conflict_count")
        if partners > 0:
            deduction = weighted / partners
        else:
            deduction = weighted
    deduction = min(Decimal("5"), max(Decimal("0"), deduction))
    return Decimal("5") - deduction


def _section_bonus(inputs):
    rows = _by_name(inputs, "bonus")
    if _num(rows, "significant_harm") > 0:
        return Decimal("0")
    years = _num(rows, "years_investing")
    steps = int(years // 5)
    return Decimal(min(3, max(0, steps)))


def _section_penalty(inputs):
    total = Decimal("0")
    for row in inputs:
        if row.get("section_code") != "pen":
            continue
        total += _d(row.get("value_numeric"))
    if total < Decimal("-50"):
        total = Decimal("-50")
    if total > 0:
        total = Decimal("0")
    return total


def sanctions_banner(inputs):
    for row in inputs:
        if row.get("section_code") != "pen":
            continue
        kind = (row.get("value_text") or "")
        points = _d(row.get("value_numeric"))
        if kind in {"sanction", "sanctions"} and points <= Decimal("-50"):
            return True
    return False


def band_for(total):
    score = _d(total)
    if score >= 90:
        return "Very low risk"
    if score >= 75:
        return "Low risk"
    if score >= 50:
        return "Moderate"
    if score >= 25:
        return "Elevated"
    return "High"


def score_v2(inputs):
    """Return section scores and the capped total for one firm or vehicle."""
    sections = {
        "s1": _section_fund_vs_founders(inputs),
        "s2": _section_support(inputs),
        "s3": _section_founder_experience(inputs),
        "s4": _section_conflicts(inputs),
        "bonus": _section_bonus(inputs),
        "pen": _section_penalty(inputs),
    }
    raw = sections["s1"] + sections["s2"] + sections["s3"] + sections["s4"] + sections["bonus"] + sections["pen"]
    if raw < 0:
        raw = Decimal("0")
    if raw > 100:
        raw = Decimal("100")
    shown = raw.quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)
    return {
        "sections": sections,
        "exact": raw,
        "total": shown,
        "band": band_for(shown),
        "sanctions_banner": sanctions_banner(inputs),
    }
