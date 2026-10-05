#!/usr/bin/env python3
"""Write the ten v2 fund reports and the score-input sidecar.

Every number below is taken from a Form ADV PDF read for this report,
a page that was opened, or a docket/press URL cited on the card.
Missing blocks stay empty. The script does not invent portfolio totals.
"""
import json
import math
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
import sys

sys.path.insert(0, str(ROOT))

from regrettamine.score_v2 import score_v2  # noqa: E402

UPDATED = "Oct 4, 2026"
SHORTS = {
    "lux": "Lux",
    "accel": "I",
    "bessemer": "BVP",
    "battery": "Battery",
    "insightpartners": "Insight",
    "baincapitalventures": "BCV",
    "generalcatalyst": "GC",
    "sequoia": "Sequoia",
    "khosla": "Khosla",
    "lightspeed": "Lightspeed",
}
ADV = "https://reports.adviserinfo.sec.gov/reports/ADV/{crd}/PDF/{crd}.pdf"
IAPD = "https://adviserinfo.sec.gov/firm/summary/{crd}"

QUESTIONS = [
    ("01", "Down rounds, bridges, pay-to-play", "In your last 3 down or flat rounds, did you lead, follow or walk?"),
    ("02", "Follow-on and pro rata", "What share of your seed/A companies did you reinvest in at the next round, including the strugglers?"),
    ("03", "Replacing founder-CEOs", "When did you last back replacing a founder-CEO, and how did it happen?"),
    ("04", "Board seat & consent rights", "Will you take a seat at my stage? Which consent rights do you require?"),
    ("05", "Competitor overlap", "Does any partner sit on the board of a company that competes with me?"),
    ("06", "Reserves for this check", "Which fund is this check from, and how much is reserved for follow-ons?"),
    ("07", "Foreign or sovereign LPs", "Are there sovereign or foreign-state LPs in this fund?"),
    ("08", "References from failures", "Give me 2 founders whose companies failed with you on the board."),
]


def pdf(crd):
    return ADV.format(crd=crd)


def iapd(crd):
    return IAPD.format(crd=crd)


def D(value):
    return Decimal(str(value))


def base_inputs(portfolio, age, departures, pen_rows, help_platform=0, help_intros=0, lawsuits=0):
    rows = [
        {"section_code": "s1", "name": "portfolio_companies", "value_numeric": portfolio},
        {"section_code": "s1", "name": "own_founder_lawsuits", "value_numeric": lawsuits},
        {"section_code": "s1", "name": "founder_ceo_removals", "value_numeric": 0},
        {"section_code": "s1", "name": "downround_events", "value_numeric": 0},
        {"section_code": "s1", "name": "blocking_events", "value_numeric": 0},
        {"section_code": "s1", "name": "losses_or_fraud", "value_numeric": 0},
        {"section_code": "s2", "name": "money_fund_size", "value_numeric": 2, "max_numeric": 2},
        {"section_code": "s2", "name": "money_reserves", "value_numeric": 1.5, "max_numeric": 2},
        {"section_code": "s2", "name": "money_hit_target", "value_numeric": 1.5, "max_numeric": 2},
        {"section_code": "s2", "name": "media_points", "value_numeric": 0, "max_numeric": 6},
        {"section_code": "s2", "name": "help_platform", "value_numeric": help_platform, "max_numeric": 2},
        {"section_code": "s2", "name": "help_intros", "value_numeric": help_intros, "max_numeric": 1.5},
        {"section_code": "s2", "name": "help_stability", "value_numeric": 2, "max_numeric": 2},
        {"section_code": "s2", "name": "partner_departure_years", "value_numeric": departures},
        {"section_code": "s3", "name": "portfolio_companies", "value_numeric": portfolio},
        {"section_code": "s3", "name": "fund_age_years", "value_numeric": age},
        {"section_code": "s3", "name": "negative_first_hand", "value_numeric": 0},
        {"section_code": "s3", "name": "first_hand_accounts", "value_numeric": 0},
        {"section_code": "s4", "name": "conflict_count", "value_numeric": 0},
        {"section_code": "s4", "name": "scaled_deduction", "value_numeric": 0},
        {"section_code": "bonus", "name": "years_investing", "value_numeric": age},
        {"section_code": "bonus", "name": "significant_harm", "value_numeric": 0},
    ]
    rows.extend(pen_rows)
    return rows


CLEAN_PEN = [
    {"section_code": "pen", "name": "sec_record", "value_numeric": 0, "value_text": "sec"},
    {"section_code": "pen", "name": "sanctions", "value_numeric": 0, "value_text": "sanctions_clear"},
]
INSIGHT_PEN = [
    {"section_code": "pen", "name": "sec_fee_order", "value_numeric": -10, "value_text": "fine"},
    {"section_code": "pen", "name": "sanctions", "value_numeric": 0, "value_text": "sanctions_clear"},
]


def fmt_num(value):
    text = format(value, "f")
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return text or "0"


def shown_int(total):
    return int(total.to_integral_value(rounding=ROUND_HALF_UP)) if False else int(total)


def floor_shown(total):
    return int(total.to_integral_value(rounding="ROUND_FLOOR"))


def pct(part, whole):
    if whole == 0:
        return "0%"
    return f"{(D(part) / D(whole) * 100):.1f}%"


def rss(values):
    return math.sqrt(sum(float(v) * float(v) for v in values))


def card(kicker, title, body, sources, rows=None, tone=""):
    return {
        "kicker": kicker,
        "title": title,
        "body": body,
        "rows": rows or [],
        "sources": sources,
        "tone": tone,
    }


def ask_block(name):
    lines = [f"Questions to ask {name}, from Regretamine", ""]
    for index, (_, title, question) in enumerate(QUESTIONS, start=1):
        lines.append(f"{index}. {title}: {question}")
    return {
        "title": "Not public: ask the fund",
        "note": "These can't be checked from public records. Bring them to your partner meeting.",
        "printHead": f"{name} · Questions to ask · Regretamine · {UPDATED}",
        "questions": [{"n": n, "title": title, "q": q} for n, title, q in QUESTIONS],
        "clipboard": "\n".join(lines),
    }


def part(section, got, maximum, rule, inputs, penalty=False):
    got_text = fmt_num(got)
    if section == "bonus":
        got_text = f"+{fmt_num(got)}"
        fill = "100.0%" if got else "0%"
        flex = "3"
        bar = fill
        legend_of = None
        max_label = "max +3"
        aria = f"Track record bonus +{fmt_num(got)}"
    elif section == "pen":
        if got == 0:
            got_text = "0"
        else:
            got_text = "−" + fmt_num(abs(got))
        flex = fmt_num(abs(got)) if got else "0"
        fill = "100%" if got else "0%"
        bar = f"{(abs(got) / D(50) * 100):.1f}%"
        legend_of = None
        max_label = "range 0 to −50"
        aria = f"Regulatory penalty minus {fmt_num(abs(got))}" if got else "Regulatory penalty 0"
    else:
        fill = pct(got, maximum)
        flex = fmt_num(maximum)
        bar = fill
        legend_of = f"/{fmt_num(maximum)}"
        max_label = f"of {fmt_num(maximum)}"
        aria = f"{NAMES[section]}: {got_text} of {fmt_num(maximum)}"
    meta = PART_META[section]
    return {
        "id": section,
        "cardClass": meta[0],
        "barClass": meta[1],
        "legendClass": meta[2],
        "name": NAMES[section],
        "legend": LEGENDS[section],
        "got": got_text,
        "maxLabel": max_label,
        "legendOf": legend_of,
        "heroFlex": flex,
        "heroFill": fill,
        "scoreBar": bar,
        "aria": aria,
        "rule": rule,
        "inputs": inputs,
    }


NAMES = {
    "s1": "Fund vs. founders",
    "s2": "Ability to support you",
    "s3": "Founder experience",
    "s4": "Conflicts of interest",
    "bonus": "Track record bonus",
    "pen": "Regulatory penalty",
}
LEGENDS = {
    "s1": "Fund vs. founders",
    "s2": "Support",
    "s3": "Founder exp.",
    "s4": "Conflicts",
    "bonus": "Bonus",
    "pen": "Regulatory",
}
PART_META = {
    "s1": ("k1", "sb1", "k1"),
    "s2": ("k2", "sb2", "k2"),
    "s3": ("k3", "sb3", "k3"),
    "s4": ("k4", "sb4", "k4"),
    "bonus": ("kb", "bonus", "kb"),
    "pen": ("kp", "pen", "kp"),
}

S1_RULE = "Bad events are measured as a share of companies backed. Under 1% costs nothing. A missing portfolio count is not scored as a 70% rate. −3 per case the fund lost or where fraud was found."
S2_RULE = "Money 6 + media 6 (capped) + help after the check 5.5. Claims the fund makes about itself count at half until founders confirm them. Partner departures cost −0.5 for each calendar year with a departure, up to −2."
S3_RULE = "Only first-hand accounts count. If negative accounts are under 1% of the portfolio, or there are none, the fund gets its age default."
S4_RULE = "−1 per documented conflict, scaled by partner count. No documented conflict was scored here."
BONUS_RULE = "+1 for every 5 years of investing with no significant pattern of harm, up to +3."
PEN_RULE = "Penalty only. A fine is −10 to −20. A clean Form ADV disclosure page is 0. Sanctions need an exact identity match."


def money_why(spec):
    return (
        f"Fund size 2/2: {spec['size_why']} "
        "Money left 1.5/2: reserves are not in the filing. Hit target 1.5/2: no published target for the current fund."
    )


def help_why(spec, departures):
    bits = []
    if spec.get("help_platform"):
        bits.append(f"Platform {fmt_num(spec['help_platform'])}/2: the firm's own claim, scored at half.")
    else:
        bits.append("Platform 0/2: no founder-confirmed platform team.")
    if spec.get("help_intros"):
        bits.append(f"Intros {fmt_num(spec['help_intros'])}/1.5: the firm's own claim, scored at half.")
    else:
        bits.append("Intros 0/1.5: no independent intro record.")
    deduction = min(2, departures) * D("0.5")
    stability = D(2) - deduction
    if departures:
        bits.append(
            f"Partner stability {fmt_num(stability)}/2: −{fmt_num(deduction)} for {departures} calendar year"
            f"{'s' if departures != 1 else ''} with a departure."
        )
    else:
        bits.append("Partner stability 2/2: no departure year was verified for this adviser.")
    return " ".join(bits)


def coverage_percent(lawsuit_cov):
    # Weights are the section maximums and sum to 100.
    # Lawsuits use the fund's own coverage. Removals, down rounds, blocking,
    # media, and founder accounts were not measured (0). Money is the 2 known
    # points of 6. Help is the stability slice only (2/5.5). Conflicts are the
    # ADV read, not a board census (15%).
    weighted = (
        D(30) * D(str(lawsuit_cov))
        + D(6) * D("0.33")
        + D("5.5") * D("0.36")
        + D(5) * D("0.15")
    )
    return int((weighted).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def range_pair(total, lawsuit_cov, reg_down):
    unchecked_law = D(1) - D(str(lawsuit_cov))
    downs = [
        D(30) * D("0.10") * unchecked_law,
        D(12) * D("0.10"),
        D(10) * D("0.50"),
        D(8) * D("0.50"),
        D("0.5"),
        D(1),
        D(6),
        D(1),
        D(str(reg_down)),
    ]
    ups = [D(1), D(3), D(2)]
    low = int((D(total) - D(str(round(rss(downs), 2)))).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    high = int((D(total) + D(str(round(rss(ups), 2)))).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    return max(0, low), min(100, high), downs, ups


def swing_rows(downs, ups):
    labels = [
        "1a Lawsuits with own founders",
        "1b Pushing out founder-CEOs",
        "1c Down-round / pay-to-play",
        "1d Blocking deals / rounds",
        "2a Money",
        "2c Help after the check",
        "3 Founder experience",
        "4 Conflicts",
        "6 Regulatory",
    ]
    # ups align to money, media, help — media has no downside row of its own.
    up_for = {
        "2a Money": ups[0],
        "2b Media reach": ups[1],
        "2c Help after the check": ups[2],
    }
    rows = []
    down_map = dict(zip(labels, downs))
    ordered = labels[:5] + ["2b Media reach"] + labels[5:]
    for label in ordered:
        down = down_map.get(label, D(0))
        up = up_for.get(label, D(0))
        rows.append([label, f"-{float(down):.1f} / +{float(up):.1f}"])
    return rows


# Specs. portfolio 0 means unpublished: lawsuit counts in the formula stay 0
# when we cannot form a rate. A sourced floor is an upper bound on the rate.
FUNDS = [
    {
        "slug": "lux",
        "name": "Lux Capital",
        "hq": "New York, NY",
        "since": "2000",
        "age": 26,
        "age_why": "Lux Capital's Wikipedia entry says the firm was founded in 2000. 26 ÷ 5 is capped at +3.",
        "age_source": ["Wikipedia, Lux Capital", "https://en.wikipedia.org/wiki/Lux_Capital"],
        "crd": "163026",
        "legal_name": "LUX CAPITAL MANAGEMENT, LLC",
        "sec_file": "802-75425",
        "status": "Exempt reporting adviser since 2012, not a full Item 5 RIA.",
        "filing": "March 31, 2026",
        "size_label": "Private-fund GAV",
        "size_value": "$11.24B",
        "size_note": "Sum of current gross asset value for 17 private funds on Schedule D. Not Item 5 regulatory AUM.",
        "size_why": "Schedule D gross asset value sums to $11,237,733,247 across 17 private funds.",
        "staff_value": "Not in Item 5",
        "staff_note": "ERA filing. An office-location question is not a firmwide headcount, so it is not used.",
        "accounts_value": "17 funds",
        "accounts_note": "Private funds listed on Schedule D of the March 31, 2026 ADV.",
        "portfolio": 0,
        "lawsuits": 0,
        "lawsuit_cov": "0.10",
        "departures": 0,
        "pen": CLEAN_PEN,
        "reg_down": "1",
        "aum": 11.24,
        "aum_as_of": "Mar 2026",
        "aum_src": "SEC Form ADV Schedule D GAV",
        "old": 83,
        "legal_n": 0,
        "legal_note": "No verified open matter with the adviser as a party.",
        "verdict": "No founder lawsuit was verified. Most of the conduct score is still unchecked.",
        "verdict_sub": "Private-fund gross asset value is $11.24B. Reserves, media reach, and founder accounts were not found.",
        "summary": "Lux's March 31, 2026 Form ADV has no filed disclosure page. Founder-side lawsuits, down rounds, and first-hand accounts were not established from the sources read.",
        "portfolio_value": "Not published",
        "portfolio_text": "The companies page shows a short featured set, not a full historical list. No rate uses that set.",
        "lit_value": "Not measured",
        "lit_text": "No founder-company lawsuit was verified, and there is no portfolio denominator.",
        "matters": [],
        "moves": [],
        "press": [],
        "not_counted": [
            "Name lookalikes (other entities with “Lux” in the name) are not this adviser.",
            "A full person-by-person sanctions screen was not run.",
        ],
        "takeaways": [
            ("tk0", "The asset figure is gross asset value, not regulatory AUM.", "Item 5 regulatory AUM is blank because Lux files as an exempt reporting adviser."),
            ("tk1", "Support is the thin part of the score.", "Reserves, a published fund target, and measured media reach were not found."),
            ("tk2", "Founder experience is the age default.", "No first-hand founder account was collected, so the score uses years investing, not reviews."),
        ],
    },
    {
        "slug": "accel",
        "name": "Accel",
        "hq": "Palo Alto, CA",
        "since": "1983",
        "age": 43,
        "age_why": "Accel's own note says its principles have been constant since 1983. 43 ÷ 5 is capped at +3.",
        "age_source": ["Accel, “What comes next”", "https://www.accel.com/news/what-comes-next.md"],
        "crd": "331435",
        "legal_name": "ACCEL MANAGEMENT CO. L.L.C.",
        "sec_file": "801-131163",
        "status": "SEC-registered adviser. Registration effective September 24, 2024.",
        "filing": "March 30, 2026",
        "size_label": "Regulatory AUM",
        "size_value": "$38.03B",
        "size_note": "Discretionary regulatory AUM $38,031,743,340. 83 accounts. Non-discretionary $0.",
        "size_why": "Form ADV Item 5.F discretionary regulatory AUM is $38,031,743,340.",
        "staff_value": "91",
        "staff_note": "Item 5.A. 50 of those employees perform investment advisory functions (Item 5.B.1).",
        "accounts_value": "83",
        "accounts_note": "Discretionary accounts on the March 30, 2026 ADV.",
        "portfolio": 152,
        "lawsuits": 1,
        "lawsuit_cov": "0.25",
        "departures": 0,
        "pen": CLEAN_PEN,
        "reg_down": "1",
        "aum": 38.03,
        "aum_as_of": "Mar 2026",
        "aum_src": "SEC Form ADV",
        "old": 78,
        "legal_n": 0,
        "legal_note": "Rapt settled in 2006. No open matter was verified.",
        "verdict": "One settled founder suit is under 1% of the companies named on Accel's site.",
        "verdict_sub": "The companies page is a partial list, so that rate is an upper bound. Down rounds and founder accounts were not checked.",
        "summary": "Accel's March 30, 2026 Form ADV reports $38.03 billion of discretionary regulatory AUM and no filed disclosure page. One 2006 founder settlement is the lawsuit on this record.",
        "portfolio_value": "152",
        "portfolio_text": "Company links on accel.com/companies on Oct 4, 2026. A partial public list, used only as a floor.",
        "lit_value": "≤0.7%",
        "lit_text": "1 settled suit ÷ 152 named companies. If the full history is larger, the rate is lower.",
        "matters": [
            {
                "id": "L1",
                "year": "2006",
                "text": "Venture Capital Journal reported that Rapt founders settled a suit against Accel and Levensohn. The article body is paywalled, so the claims are not restated here.",
                "sub": "Rapt founders v. Accel and Levensohn",
                "badge": "0 pts",
                "tone": "gray",
                "role": "Defendant",
                "other": "Rapt founders",
                "status": "Settled · Nov 1, 2006",
                "relevance": "High",
                "effect": "0 (under 1% of the named list)",
                "kicker": "Legal · 2006",
                "title": "Rapt founders settle suit against Accel",
                "body": "The only founder-company suit verified for this report. Scored as one lawsuit. No loss or fraud finding against Accel was in the headline that could be read.",
                "sources": [
                    ["Venture Capital Journal, Nov 1, 2006", "https://www.venturecapitaljournal.com/rapt-founders-settle-suit-against-accel-levensohn/"],
                ],
                "group": "founder",
                "featured": True,
            }
        ],
        "moves": [],
        "press": [
            {
                "publisher": "Venture Capital Journal",
                "domain": "venturecapitaljournal.com",
                "date": "Nov 1, 2006",
                "headline": "Rapt founders settle suit against Accel, Levensohn",
                "url": "https://www.venturecapitaljournal.com/rapt-founders-settle-suit-against-accel-levensohn/",
                "group": "Legal",
                "sentiment": "neg",
                "why": "Cited on the Legal tab. The body is paywalled.",
            }
        ],
        "not_counted": [
            "Accel Entertainment, Accel-KKR, Accel Schools, and Accel Logistics are different companies and are not scored.",
            "A full person-by-person sanctions screen was not run.",
        ],
        "takeaways": [
            ("tk0", "The lawsuit rate uses a partial company list.", "152 is a count of links on the public companies page, not a full history."),
            ("tk1", "Support is the thin part of the score.", "Reserves, a published target, and measured media reach were not found."),
            ("tk2", "Founder experience is the age default.", "No first-hand founder account was collected."),
        ],
        "extra_sources": {
            "portfolio": ["Accel companies page", "https://www.accel.com/companies"],
        },
    },
    {
        "slug": "bessemer",
        "name": "Bessemer Venture Partners",
        "hq": "Larchmont, NY",
        "since": "1975",
        "age": 51,
        "age_why": "Bessemer's own history says the venture firm dates to 1975. The 1911 date is the Phipps family office, not this adviser. 51 ÷ 5 is capped at +3.",
        "age_source": ["Bessemer, operating model", "https://www.bvp.com/atlas/inside-bessemers-operating-model"],
        "crd": "159279",
        "legal_name": "BESSEMER VENTURE PARTNERS",
        "sec_file": "801-125875",
        "status": "SEC-registered adviser. Registration effective June 14, 2022.",
        "filing": "May 13, 2026",
        "size_label": "Regulatory AUM",
        "size_value": "$20.24B",
        "size_note": "Discretionary regulatory AUM $20,239,213,324. 36 accounts. Non-discretionary $0.",
        "size_why": "Form ADV Item 5.F discretionary regulatory AUM is $20,239,213,324.",
        "staff_value": "191",
        "staff_note": "Item 5.A. 83 perform investment advisory functions (Item 5.B.1).",
        "accounts_value": "36",
        "accounts_note": "Discretionary accounts on the May 13, 2026 ADV.",
        "portfolio": 450,
        "lawsuits": 1,
        "lawsuit_cov": "0.25",
        "departures": 0,
        "help_platform": 1,
        "help_intros": 0.75,
        "pen": CLEAN_PEN,
        "reg_down": "1",
        "aum": 20.24,
        "aum_as_of": "May 2026",
        "aum_src": "SEC Form ADV",
        "old": 71,
        "legal_n": 0,
        "legal_note": "Transeo was a 2011 case. No open matter was verified.",
        "verdict": "One founder-company suit is under 1% of the active companies Bessemer publishes.",
        "verdict_sub": "Platform and intro points are the firm's own claims, at half. A later judgment in Transeo was not found.",
        "summary": "Bessemer publishes 450+ active portfolio companies and, on its homepage, claims a talent team and a large intro practice. Those claims are scored at half. One 2011 founder-company suit is on the legal record.",
        "portfolio_value": "450+",
        "portfolio_text": "Active portfolio companies stated on bvp.com. Used as a floor. Total history is not published, so a rate against 450 is an upper bound.",
        "lit_value": "≤0.3%",
        "lit_text": "1 case ÷ 450 active companies. Exited companies would make the historical rate lower.",
        "matters": [
            {
                "id": "L1",
                "year": "2013",
                "text": "Transeo, owned by founder Laurent Marteau, sued Bessemer entities after Bessemer took control of Neutral Holdings. The March 29, 2013 opinion dismissed the CEO-removal fiduciary claim and let a refusal-to-consider-an-offer claim proceed. A final judgment was not found.",
                "sub": "Transeo S.A.R.L. v. Bessemer Venture Partners VI L.P.",
                "badge": "0 pts",
                "tone": "gray",
                "role": "Defendant",
                "other": "Transeo S.A.R.L. / Laurent Marteau",
                "status": "Motion decided Mar 29, 2013 · later judgment not found",
                "relevance": "High",
                "effect": "0 (under 1% of the active list). Not also scored as a removal or a block.",
                "kicker": "Legal · 2013",
                "title": "Transeo v. Bessemer Venture Partners VI",
                "body": "S.D.N.Y. 11-cv-05331, opinion at 936 F. Supp. 2d 376. One episode. The removal allegation and the alleged refusal to consider an AVG offer stay inside this lawsuit. They are not second and third score events.",
                "sources": [
                    ["Justia opinion", "https://law.justia.com/cases/federal/district-courts/new-york/nysdce/7:2011cv05331/382774/31/"],
                    ["Opinion PDF", "https://cases.justia.com/federal/district-courts/new-york/nysdce/7:2011cv05331/382774/31/0.pdf"],
                ],
                "group": "founder",
                "featured": True,
            }
        ],
        "moves": [],
        "press": [],
        "not_counted": [
            "1911 is the Phipps family office (Bessemer Securities), not the year this venture firm started.",
            "A full person-by-person sanctions screen was not run.",
        ],
        "takeaways": [
            ("tk0", "The homepage support claims are scored at half.", "Talent advisors, operating advisors, and “1,000+ introductions a year” are Bessemer’s own words."),
            ("tk1", "The company count is active companies, not full history.", "450+ is the floor used for the lawsuit rate."),
            ("tk2", "Founder accounts were not collected.", "The founder-experience points are the age default."),
        ],
        "extra_sources": {
            "help": ["Bessemer homepage", "https://www.bvp.com/"],
        },
    },
    {
        "slug": "battery",
        "name": "Battery Ventures",
        "hq": "Boston, MA",
        "since": "1983",
        "age": 43,
        "age_why": "Wikipedia, citing the firm's history, says Battery was founded in 1983. 43 ÷ 5 is capped at +3.",
        "age_source": ["Wikipedia, Battery Ventures", "https://en.wikipedia.org/wiki/Battery_Ventures"],
        "crd": "160921",
        "legal_name": "BATTERY MANAGEMENT CORP.",
        "sec_file": "801-79475",
        "status": "SEC-registered adviser. Registration effective April 18, 2014.",
        "filing": "March 30, 2026",
        "size_label": "Regulatory AUM",
        "size_value": "$15.61B",
        "size_note": "Discretionary regulatory AUM $15,609,095,762. 60 accounts. Non-discretionary $0.",
        "size_why": "Form ADV Item 5.F discretionary regulatory AUM is $15,609,095,762.",
        "staff_value": "113",
        "staff_note": "Item 5.A. 70 perform investment advisory functions (Item 5.B.1).",
        "accounts_value": "60",
        "accounts_note": "Discretionary accounts on the March 30, 2026 ADV.",
        "portfolio": 530,
        "lawsuits": 0,
        "lawsuit_cov": "0.15",
        "departures": 0,
        "pen": CLEAN_PEN,
        "reg_down": "1",
        "aum": 15.61,
        "aum_as_of": "Mar 2026",
        "aum_src": "SEC Form ADV",
        "old": 67,
        "legal_n": 0,
        "legal_note": "No verified open matter with the adviser as a party.",
        "verdict": "No founder lawsuit was verified. The age default uses a 530-company floor.",
        "verdict_sub": "That company count is Wikipedia's “more than 530,” so founder experience is the large-portfolio default. Down rounds were not checked.",
        "summary": "Battery's March 30, 2026 Form ADV reports $15.61 billion of discretionary regulatory AUM and no filed disclosure page. Wikipedia says the firm has invested in more than 530 companies.",
        "portfolio_value": "530+",
        "portfolio_text": "Wikipedia says Battery has invested in more than 530 companies. Used as a floor, not a full list.",
        "lit_value": "Not measured",
        "lit_text": "No founder-company lawsuit was verified against this floor.",
        "matters": [],
        "moves": [],
        "press": [],
        "not_counted": [
            "Wikipedia's asset and employee figures are not used. The Form ADV figures are.",
            "A full person-by-person sanctions screen was not run.",
        ],
        "takeaways": [
            ("tk0", "The company floor is what lifts founder experience.", "More than 530 companies puts the fund in the 500+ age default. It is not a company-by-company list."),
            ("tk1", "Support is the thin part of the score.", "Reserves, a published target, and measured media reach were not found."),
            ("tk2", "No first-hand founder account was collected.", "Negative accounts were not found either, so the default stands."),
        ],
    },
    {
        "slug": "insightpartners",
        "name": "Insight Partners",
        "hq": "New York, NY",
        "since": "1995",
        "age": 31,
        "age_why": "Wikipedia says Insight Partners was founded in 1995. 31 ÷ 5 is capped at +3. The SEC fine is a penalty, not the bonus's “significant harm” test, which is about a pattern against founders.",
        "age_source": ["Wikipedia, Insight Partners", "https://en.wikipedia.org/wiki/Insight_Partners"],
        "crd": "142994",
        "legal_name": "INSIGHT VENTURE PARTNERS",
        "sec_file": "801-67560",
        "status": "SEC-registered adviser.",
        "filing": "September 9, 2026",
        "size_label": "Regulatory AUM",
        "size_value": "$92.18B",
        "size_note": "Discretionary regulatory AUM $92,178,934,483. 181 accounts. Non-discretionary $0.",
        "size_why": "Form ADV Item 5.F discretionary regulatory AUM is $92,178,934,483.",
        "staff_value": "438",
        "staff_note": "Item 5.A. 147 perform investment advisory functions (Item 5.B.1).",
        "accounts_value": "181",
        "accounts_note": "Discretionary accounts on the September 9, 2026 ADV.",
        "portfolio": 875,
        "lawsuits": 0,
        "lawsuit_cov": "0.15",
        "departures": 0,
        "pen": INSIGHT_PEN,
        "reg_down": "5",
        "penalty": True,
        "aum": 92.18,
        "aum_as_of": "Sep 2026",
        "aum_src": "SEC Form ADV",
        "old": 67,
        "legal_n": 1,
        "legal_note": "Kate Lowry sued on Dec 30, 2025. No dismissal was found.",
        "verdict": "The SEC fined the adviser in 2023 for excess management fees. That is the score.",
        "verdict_sub": "The fees were repaid and there was no fraud finding, so the fine is −10, the bottom of the fine band. A former VP's suit is listed and is not a founder case.",
        "summary": "Insight's September 9, 2026 Form ADV reports $92.18 billion of discretionary regulatory AUM and a filed regulatory disclosure for the SEC's June 20, 2023 order.",
        "portfolio_value": "875+",
        "portfolio_text": "Wikipedia, citing Insight's about page, says the firm had invested in over 875 companies as of June 30, 2025. Used as a floor.",
        "lit_value": "Not measured",
        "lit_text": "No fund-versus-founder lawsuit was verified against this floor.",
        "matters": [
            {
                "id": "L1",
                "year": "2025",
                "text": "Former vice president Kate Lowry sued Insight for disability discrimination, gender discrimination, and wrongful termination. TechCrunch saw a suit filed December 30 in San Mateo County. This is an employee suit, not a suit by a portfolio founder.",
                "sub": "Lowry v. Insight Partners",
                "badge": "0 pts",
                "tone": "open",
                "role": "Defendant",
                "other": "Kate Lowry",
                "status": "Filed Dec 30, 2025 · no dismissal found",
                "relevance": "Low · employee, not a founder",
                "effect": "0",
                "kicker": "Legal · 2025",
                "title": "Kate Lowry v. Insight Partners",
                "body": "Employment case. It does not enter the fund-versus-founders rate. No later dismissal was found in the sources read, so the list counts it as active.",
                "sources": [
                    ["TechCrunch, Jan 5, 2026", "https://techcrunch.com/2026/01/05/insight-partners-sued-by-former-vice-president-kate-lowry/"],
                ],
                "group": "other",
                "featured": True,
            }
        ],
        "moves": [],
        "press": [
            {
                "publisher": "TechCrunch",
                "domain": "techcrunch.com",
                "date": "Jan 5, 2026",
                "headline": "Insight Partners sued by former vice president Kate Lowry",
                "url": "https://techcrunch.com/2026/01/05/insight-partners-sued-by-former-vice-president-kate-lowry/",
                "group": "Legal",
                "sentiment": "neg",
                "why": "Cited on the Legal tab. Employee suit, 0 points.",
            },
            {
                "publisher": "U.S. Securities and Exchange Commission",
                "domain": "sec.gov",
                "date": "Jun 20, 2023",
                "headline": "SEC charges Insight Venture Management for overcharging fees",
                "url": "https://www.sec.gov/newsroom/press-releases/2023-112",
                "group": "Regulator",
                "sentiment": "neg",
                "why": "Cited on the regulatory record. The dollar figures live there.",
            },
        ],
        "not_counted": [
            "IPI Partners is a different firm. Its sanctions news is not scored here.",
            "Wikipedia describes a 2024 ransomware incident. It is not a founder suit and not an SEC order, so it is not scored.",
            "A full person-by-person sanctions screen was not run.",
        ],
        "takeaways": [
            ("tk0", "Read the 2023 SEC order before treating the founder record as the whole record.", "The points come off the regulatory penalty, not off fund-versus-founders."),
            ("tk1", "The employee suit is not a founder suit.", "It is on the Legal tab and costs 0 under the founder section."),
            ("tk2", "The company floor is the firm's reported total.", "Over 875 companies is what puts founder experience on the large-portfolio default."),
        ],
    },
    {
        "slug": "baincapitalventures",
        "name": "Bain Capital Ventures",
        "hq": "Boston, MA",
        "since": "2001",
        "age": 25,
        "age_why": "Wikipedia says Bain Capital Ventures was founded in 2001, not 1984 (that year belongs to Bain Capital). 25 ÷ 5 is capped at +3.",
        "age_source": ["Wikipedia, Bain Capital Ventures", "https://en.wikipedia.org/wiki/Bain_Capital_Ventures"],
        "crd": "145652",
        "legal_name": "BAIN CAPITAL VENTURES, LP",
        "sec_file": "801-69071",
        "status": "SEC-registered adviser. Registration effective April 10, 2008.",
        "filing": "March 31, 2026",
        "size_label": "Regulatory AUM",
        "size_value": "$9.84B",
        "size_note": "Discretionary regulatory AUM $9,837,931,000. 20 accounts. Non-discretionary $0.",
        "size_why": "Form ADV Item 5.F discretionary regulatory AUM is $9,837,931,000.",
        "staff_value": "97",
        "staff_note": "Item 5.A. 47 perform investment advisory functions (Item 5.B.1).",
        "accounts_value": "20",
        "accounts_note": "Discretionary accounts on the March 31, 2026 ADV.",
        "portfolio": 400,
        "lawsuits": 0,
        "lawsuit_cov": "0.15",
        "departures": 0,
        "pen": CLEAN_PEN,
        "reg_down": "1",
        "aum": 9.84,
        "aum_as_of": "Mar 2026",
        "aum_src": "SEC Form ADV",
        "old": 66,
        "legal_n": 0,
        "legal_note": "No verified open matter with this adviser as a party. Bain Capital private-equity cases are not this firm.",
        "verdict": "No founder lawsuit was verified for the venture adviser.",
        "verdict_sub": "Regulatory AUM is $9.84 billion as of the March 31, 2026 ADV, replacing the stale $10 billion figure. Bain Capital's private-equity cases are not counted.",
        "summary": "Bain Capital Ventures' March 31, 2026 Form ADV reports $9.84 billion of discretionary regulatory AUM and no filed disclosure page. The venture firm dates to 2001.",
        "portfolio_value": "400+ active",
        "portfolio_text": "Wikipedia says BCV has over 400 active portfolio companies. Active is not a full history, and it is under 500, so the age default stays at the 10-year tier.",
        "lit_value": "Not measured",
        "lit_text": "No founder-company lawsuit against this adviser was verified.",
        "matters": [],
        "moves": [],
        "press": [],
        "not_counted": [
            "Bain Capital LLC and Bain Capital Partners private-equity matters are a different adviser and are not scored.",
            "A full person-by-person sanctions screen was not run.",
        ],
        "takeaways": [
            ("tk0", "Use the 2026 ADV, not the old $10 billion figure.", "Discretionary regulatory AUM on the March 31, 2026 filing is $9,837,931,000."),
            ("tk1", "Do not import Bain Capital's private-equity docket.", "This page is the venture adviser, CRD 145652."),
            ("tk2", "Support and founder accounts are thin.", "Reserves, media reach, and first-hand reviews were not found."),
        ],
    },
    {
        "slug": "generalcatalyst",
        "name": "General Catalyst",
        "hq": "Cambridge, MA",
        "since": "2000",
        "age": 25,
        "age_why": "General Catalyst's capital page says 25 years in its Creation strategy. That is the sourced floor. 25 ÷ 5 is capped at +3. The list year 2000 was already on this site and is one year apart, which does not change the points.",
        "age_source": ["General Catalyst, Capital", "https://www.generalcatalyst.com/capital"],
        "crd": "162548",
        "legal_name": "GENERAL CATALYST",
        "sec_file": "801-115155",
        "status": "SEC-registered adviser. Registration effective April 26, 2019.",
        "filing": "July 21, 2026",
        "size_label": "Regulatory AUM",
        "size_value": "$45.50B",
        "size_note": "Discretionary regulatory AUM $45,502,659,880. 49 accounts. Non-discretionary $0.",
        "size_why": "Form ADV Item 5.F discretionary regulatory AUM is $45,502,659,880.",
        "staff_value": "211",
        "staff_note": "Item 5.A. 68 perform investment advisory functions (Item 5.B.1).",
        "accounts_value": "49",
        "accounts_note": "Discretionary accounts on the July 21, 2026 ADV.",
        "portfolio": 0,
        "lawsuits": 0,
        "lawsuit_cov": "0.10",
        "departures": 1,
        "pen": CLEAN_PEN,
        "reg_down": "1",
        "aum": 45.5,
        "aum_as_of": "Jul 2026",
        "aum_src": "SEC Form ADV",
        "old": 66,
        "legal_n": 0,
        "legal_note": "Palantir's suit did not name the firm as a defendant in the report we have.",
        "verdict": "Three managing directors left in 2025. That is the deduction.",
        "verdict_sub": "Palantir's case is a subpoena report, not a suit against the firm. No founder lawsuit was verified, and the portfolio count is unpublished.",
        "summary": "General Catalyst's July 21, 2026 Form ADV reports $45.50 billion of discretionary regulatory AUM and no filed disclosure page. TechCrunch reported three managing-director departures in 2025.",
        "portfolio_value": "Not published",
        "portfolio_text": "No complete company count was found. A missing count is coverage, not a penalty.",
        "lit_value": "Not measured",
        "lit_text": "No fund-versus-founder lawsuit was verified.",
        "matters": [
            {
                "id": "L1",
                "year": "2026",
                "text": "Bloomberg reported that a judge partly blocked former Palantir employees at Percepta from poaching. General Catalyst was subpoenaed, not sued.",
                "sub": "Palantir matter · Percepta",
                "badge": "0 pts",
                "tone": "gray",
                "role": "Non-party · subpoena",
                "other": "Palantir",
                "status": "Firm subpoenaed, not sued",
                "relevance": "Low",
                "effect": "0",
                "kicker": "Legal · 2026",
                "title": "Palantir / Percepta subpoena",
                "body": "Same treatment as a non-party subpoena: listed, not scored. The departure deduction is separate and lives on the Fund tab.",
                "sources": [
                    ["Bloomberg, Mar 6, 2026", "https://www.bloomberg.com/news/articles/2026-03-06/ex-palantir-ai-workers-blocked-from-poaching-using-secrets"],
                ],
                "group": "other",
                "featured": True,
            }
        ],
        "moves": [
            {"name": "Deep Nishar", "role": "Managing director", "badge": "Left 2025"},
            {"name": "Kyle Doherty", "role": "Managing director", "badge": "Left 2025"},
            {"name": "Adam Valkin", "role": "Managing director", "badge": "Left 2025"},
        ],
        "press": [
            {
                "publisher": "TechCrunch",
                "domain": "techcrunch.com",
                "date": "Mar 3, 2025",
                "headline": "General Catalyst loses three top investors as the firm expands beyond venture",
                "url": "https://techcrunch.com/2025/03/03/general-catalyst-loses-three-top-investors-as-the-firm-expands-beyond-venture-contemplates-ipo/",
                "group": "People",
                "sentiment": "neg",
                "why": "Cited on the Fund tab for the 2025 departures.",
            }
        ],
        "not_counted": [
            "TechCrunch's IPO comments are attributed to people close to the firm. They are not scored as a plan.",
            "A full person-by-person sanctions screen was not run.",
        ],
        "takeaways": [
            ("tk0", "2025 is one departure year, not three deductions.", "Nishar, Doherty, and Valkin left in the same calendar year. The cap is −0.5 per year."),
            ("tk1", "The Palantir matter is a subpoena.", "It is on the Legal tab and costs 0."),
            ("tk2", "Portfolio size is unpublished.", "No lawsuit rate is computed, and founder experience stays on the age default."),
        ],
    },
    {
        "slug": "sequoia",
        "name": "Sequoia Capital",
        "hq": "Menlo Park, CA",
        "since": "1972",
        "age": 54,
        "age_why": "Sequoia's history page says Don Valentine founded the firm in 1972. 54 ÷ 5 is capped at +3.",
        "age_source": ["Sequoia, Our History", "https://sequoiacap.com/our-history/"],
        "crd": "157373",
        "legal_name": "SEQUOIA CAPITAL OPERATIONS, LLC",
        "sec_file": "801-122957",
        "status": "SEC-registered adviser. Registration effective January 3, 2022. Brochure submitted March 31, 2026; this amendment was filed July 17, 2026.",
        "filing": "July 17, 2026",
        "size_label": "Regulatory AUM",
        "size_value": "$82.17B",
        "size_note": "Discretionary regulatory AUM $82,165,771,068. 60 accounts. Non-discretionary $0.",
        "size_why": "Form ADV Item 5.F discretionary regulatory AUM is $82,165,771,068.",
        "staff_value": "168",
        "staff_note": "Item 5.A. 32 perform investment advisory functions (Item 5.B.1).",
        "accounts_value": "60",
        "accounts_note": "Discretionary accounts on the July 17, 2026 ADV.",
        "portfolio": 0,
        "lawsuits": 0,
        "lawsuit_cov": "0.10",
        "departures": 0,
        "pen": CLEAN_PEN,
        "reg_down": "1",
        "aum": 82.17,
        "aum_as_of": "Jul 2026",
        "aum_src": "SEC Form ADV",
        "old": 52,
        "legal_n": 0,
        "legal_note": "Doe v. Sequoia was not re-read for this report, so it is not counted as active.",
        "verdict": "No verified founder lawsuit, and no published portfolio count.",
        "verdict_sub": "Regulatory AUM is $82.17 billion. A self-represented Doe case is on the update feed and was not re-read, so it is not scored.",
        "summary": "Sequoia Capital Operations' July 17, 2026 Form ADV reports $82.17 billion of discretionary regulatory AUM and no filed disclosure page. The firm dates its founding to 1972.",
        "portfolio_value": "Not published",
        "portfolio_text": "sequoiacap.com/our-companies/ did not return a countable list. No rate uses a guessed total.",
        "lit_value": "Not measured",
        "lit_text": "No fund-versus-founder lawsuit was verified.",
        "matters": [],
        "moves": [],
        "press": [],
        "not_counted": [
            "Doe v. Sequoia (PacerMonitor, Aug 2026) was not re-read. It is not scored and not marked active.",
            "Token-buyer and customer suits, partner-personal matters, and probes of Sequoia Capital India were not charged to this adviser.",
            "A full person-by-person sanctions screen was not run.",
        ],
        "takeaways": [
            ("tk0", "The high AUM is not a conduct score.", "Money is 5 of 6 because reserves and a target are not in the filing."),
            ("tk1", "There is no portfolio denominator.", "A lawsuit rate was not invented from a partial page."),
            ("tk2", "Founder experience is the age default.", "No first-hand account was collected. The 500-company tier was not reached."),
        ],
    },
    {
        "slug": "khosla",
        "name": "Khosla Ventures",
        "hq": "Menlo Park, CA",
        "since": "2004",
        "age": 22,
        "age_why": "Vinod Khosla's Wikipedia entry says he founded Khosla Ventures in 2004. 22 ÷ 5 is capped at +3.",
        "age_source": ["Wikipedia, Vinod Khosla", "https://en.wikipedia.org/wiki/Vinod_Khosla"],
        "crd": "162910",
        "legal_name": "KHOSLA VENTURES, LLC",
        "sec_file": "802-76280",
        "status": "Exempt reporting adviser since 2012, not a full Item 5 RIA.",
        "filing": "May 20, 2026",
        "size_label": "Private-fund GAV",
        "size_value": "$21.73B",
        "size_note": "Sum of current gross asset value for 31 private funds on Schedule D. Not Item 5 regulatory AUM. A separate “total firm assets” figure is not mixed in.",
        "size_why": "Schedule D gross asset value sums to $21,727,199,655 across 31 private funds.",
        "staff_value": "Not in Item 5",
        "staff_note": "ERA filing. An office-location question is not a firmwide headcount, so it is not used.",
        "accounts_value": "31 funds",
        "accounts_note": "Private funds listed on Schedule D of the May 20, 2026 ADV.",
        "portfolio": 115,
        "lawsuits": 1,
        "lawsuit_cov": "0.25",
        "departures": 0,
        "pen": CLEAN_PEN,
        "reg_down": "1",
        "aum": 21.73,
        "aum_as_of": "May 2026",
        "aum_src": "SEC Form ADV Schedule D GAV",
        "old": 63,
        "legal_n": 0,
        "legal_note": "The Avogy suit was the fund's own case. No open matter was verified.",
        "verdict": "Khosla sued a former portfolio CEO. That one case is under 1% of the names on its portfolio page.",
        "verdict_sub": "The page is a partial list, so the rate is an upper bound. A later dismissal was not confirmed in a source we could read. No fraud finding against the fund was verified.",
        "summary": "Khosla Ventures' May 20, 2026 Form ADV is an exempt-reporting-adviser filing. Private-fund gross asset value sums to $21.73 billion. The verified lawsuit is the firm's own case against Avogy's former CEO.",
        "portfolio_value": "115",
        "portfolio_text": "Company names on khoslaventures.com/portfolio on Oct 4, 2026. A partial public list, used only as a floor.",
        "lit_value": "≤0.9%",
        "lit_text": "1 suit brought by the firm ÷ 115 named companies. If the full history is larger, the rate is lower.",
        "matters": [
            {
                "id": "L1",
                "year": "2017",
                "text": "Axios reported that Khosla Ventures sued former Avogy CEO Dinesh Ramanathan in Santa Clara Superior Court, alleging self-dealing on a $200,000 IP sale to his new company. A later dismissal was not confirmed in a source we could read.",
                "sub": "Khosla Ventures v. Ramanathan (Avogy)",
                "badge": "0 pts",
                "tone": "gray",
                "role": "Plaintiff",
                "other": "Dinesh Ramanathan",
                "status": "Filed 2017 · later disposition not verified",
                "relevance": "High",
                "effect": "0 (under 1% of the named list). No −3: no loss or fraud finding against the fund was verified.",
                "kicker": "Legal · 2017",
                "title": "Khosla Ventures v. former Avogy CEO",
                "body": "Fund-brought suit. Counted once, as a lawsuit with a portfolio founder. Not also scored as a removal.",
                "sources": [
                    ["Axios, Sep 11, 2017", "https://www.axios.com/2017/12/15/khosla-sues-entrepreneur-for-fraud-1513305375"],
                ],
                "group": "founder",
                "featured": True,
            }
        ],
        "moves": [],
        "press": [
            {
                "publisher": "Axios",
                "domain": "axios.com",
                "date": "Sep 11, 2017",
                "headline": "Khosla sues entrepreneur for fraud",
                "url": "https://www.axios.com/2017/12/15/khosla-sues-entrepreneur-for-fraud-1513305375",
                "group": "Legal",
                "sentiment": "neg",
                "why": "Cited on the Legal tab.",
            }
        ],
        "not_counted": [
            "Martins Beach litigation is about Vinod Khosla's property, not Khosla Ventures, LLC. It is not scored as a fund case.",
            "A Nextdoor shareholder case that once named Khosla-related defendants was not re-read and is not scored.",
            "A full person-by-person sanctions screen was not run.",
        ],
        "takeaways": [
            ("tk0", "The asset figure is gross asset value.", "31 private funds sum to $21.73 billion. That is not Item 5 regulatory AUM."),
            ("tk1", "The firm sued a former portfolio CEO.", "The case is on the Legal tab. The rate against the public name list is under 1%."),
            ("tk2", "The portfolio page is a floor, not a census.", "115 names. A larger true history would make the rate smaller."),
        ],
        "extra_sources": {
            "portfolio": ["Khosla Ventures portfolio", "https://www.khoslaventures.com/portfolio"],
        },
    },
    {
        "slug": "lightspeed",
        "name": "Lightspeed Venture Partners",
        "hq": "Menlo Park, CA",
        "since": "2000",
        "age": 26,
        "age_why": "Lightspeed's own story says “Since 2000.” 26 ÷ 5 is capped at +3.",
        "age_source": ["Lightspeed, Supabase story", "https://lsvp.com/stories/our-investment-in-supabase/"],
        "crd": "160187",
        "legal_name": "LIGHTSPEED VENTURE PARTNERS",
        "sec_file": "801-132552",
        "status": "SEC-registered adviser. Registration effective April 28, 2025.",
        "filing": "May 6, 2026",
        "size_label": "Regulatory AUM",
        "size_value": "$50.01B",
        "size_note": "Discretionary $47,322,785,837 (50 accounts) plus non-discretionary $2,682,626,884 (1 account). Total $50,005,412,721.",
        "size_why": "Form ADV total regulatory AUM is $50,005,412,721.",
        "staff_value": "132",
        "staff_note": "Item 5.A. 125 perform investment advisory functions (Item 5.B.1), as the form states it.",
        "accounts_value": "51",
        "accounts_note": "50 discretionary accounts and 1 non-discretionary account.",
        "portfolio": 0,
        "lawsuits": 0,
        "lawsuit_cov": "0.10",
        "departures": 2,
        "pen": CLEAN_PEN,
        "reg_down": "1",
        "aum": 50.01,
        "aum_as_of": "May 2026",
        "aum_src": "SEC Form ADV",
        "old": 58,
        "legal_n": 0,
        "legal_note": "No verified open matter with this adviser as a party.",
        "verdict": "Partner departures in 2024 and 2026 are the deduction.",
        "verdict_sub": "No founder lawsuit was verified. A global “500 companies” claim covers separate advisers and is not used as this adviser's denominator.",
        "summary": "Lightspeed Management's May 6, 2026 Form ADV reports $50.01 billion of regulatory AUM and no filed disclosure page. Two calendar years have a verified partner departure.",
        "portfolio_value": "Not published",
        "portfolio_text": "Lightspeed's India and Southeast Asia adviser is a separate firm. A global company count was not used for this adviser.",
        "lit_value": "Not measured",
        "lit_text": "No fund-versus-founder lawsuit was verified.",
        "matters": [],
        "moves": [
            {"name": "Abhishek Nag", "role": "Partner", "badge": "Left 2024"},
            {"name": "Vaibhav Agrawal", "role": "Partner", "badge": "Reported 2024"},
            {"name": "Michael Mignano", "role": "Partner", "badge": "Left 2026"},
        ],
        "press": [
            {
                "publisher": "The Economic Times",
                "domain": "economictimes.indiatimes.com",
                "date": "Apr 13, 2024",
                "headline": "Lightspeed partners Abhishek Nag, Vaibhav Agrawal quit",
                "url": "https://economictimes.indiatimes.com/tech/technology/lightspeed-partners-vaibhav-agrawal-abhishek-nag-quit/articleshow/109248901.cms",
                "group": "People",
                "sentiment": "neg",
                "why": "Cited on the Fund tab. 2024 is one departure year.",
            },
            {
                "publisher": "Union Square Ventures",
                "domain": "usv.com",
                "date": "Apr 2026",
                "headline": "Welcoming Mike Mignano to the USV partnership",
                "url": "https://www.usv.com/writing/2026/04/welcoming-mike-mignano-to-the-usv-partnership/",
                "group": "People",
                "sentiment": "neg",
                "why": "Cited on the Fund tab. He had been a Lightspeed partner.",
            },
        ],
        "not_counted": [
            "A single-source line in the Economic Times piece puts Agrawal's exit in 2023. That year is not added on top of 2024.",
            "Lightspeed India Partners is a distinct adviser. Its portfolio is not this page's denominator.",
            "A full person-by-person sanctions screen was not run.",
        ],
        "takeaways": [
            ("tk0", "Two departure years, not three people.", "2024 and 2026 each cost −0.5. The 2023 line was one unnamed source and is not a third year."),
            ("tk1", "Do not use the global 500-company line.", "Lightspeed says its India adviser is a separate firm."),
            ("tk2", "Support otherwise rests on the ADV.", "Reserves, a target, and measured media reach were not found."),
        ],
        "extra_sources": {
            "mignano": ["USV, Michael Mignano", "https://www.usv.com/people/michael-mignano/"],
        },
    },
]


def lawsuit_why(spec):
    count = spec["lawsuits"]
    portfolio = spec["portfolio"]
    if count and portfolio:
        rate = D(count) / D(portfolio) * 100
        return (
            f"{count} case ÷ {portfolio} = {rate:.2f}%. "
            "The denominator is a published floor, so this rate is an upper bound. Under 1%, no penalty."
        )
    if count and not portfolio:
        return "A case is on the Legal tab. The portfolio count is unpublished, so no rate is scored."
    return "No fund-versus-founder lawsuit was verified. No rate is scored."


def removal_why():
    return "No removal was verified as its own event. Where a lawsuit alleged one, it stays inside that lawsuit."


def build_evidence(spec, cov, lo, hi, downs, ups, sections, rank_rows, place):
    adv_src = ["Form ADV PDF", pdf(spec["crd"])]
    iapd_src = ["SEC IAPD summary", iapd(spec["crd"])]
    evidence = {}
    for key, title, text in spec["takeaways"]:
        sources = [adv_src]
        if key == "tk0" and spec.get("extra_sources", {}).get("help"):
            sources = [spec["extra_sources"]["help"], adv_src]
        if "company" in text.lower() or "floor" in text.lower() or "875" in text or "530" in text or "152" in text or "450" in text or "115" in text:
            if spec.get("extra_sources", {}).get("portfolio"):
                sources = [spec["extra_sources"]["portfolio"]]
            elif spec["slug"] in {"battery", "insightpartners", "baincapitalventures"}:
                sources = [spec["age_source"]]
        evidence[key] = card(f"Takeaway", title, text, sources)
    s1_sources = [adv_src]
    for matter in spec["matters"]:
        if matter["group"] == "founder":
            s1_sources = matter["sources"]
    evidence["s1"] = card(
        f"Score · {fmt_num(sections['s1'])} of 60",
        "Fund vs. founders",
        spec["summary"],
        s1_sources,
    )
    s2_sources = [adv_src, spec["age_source"]]
    if spec.get("extra_sources", {}).get("help"):
        s2_sources.append(spec["extra_sources"]["help"])
    for item in spec["press"]:
        if item["group"] == "People":
            s2_sources.append([item["publisher"], item["url"]])
    evidence["s2"] = card(
        f"Score · {fmt_num(sections['s2'])} of 17.5",
        "Ability to support you",
        "Money is the filing. Media reach was not measured. Help is empty unless the firm itself claimed a platform, and then only at half.",
        s2_sources,
    )
    evidence["s3"] = card(
        f"Score · {fmt_num(sections['s3'])} of 17.5",
        "Founder experience",
        "No first-hand account was collected, so the age default applies.",
        [spec["age_source"]],
        rows=[["First-hand accounts", "0"], ["Age default", fmt_num(sections["s3"])]],
    )
    evidence["s4"] = card(
        "Score · 5 of 5",
        "Conflicts of interest",
        "No competitor-board or incubation conflict was verified. A partner-by-partner board list was not built.",
        [adv_src],
    )
    evidence["bonus"] = card(
        f"Bonus · +{fmt_num(sections['bonus'])}",
        "Track record bonus",
        spec["age_why"],
        [spec["age_source"]],
    )
    pen_sources = [adv_src, iapd_src]
    if spec.get("penalty"):
        pen_sources = [
            ["SEC press release, Jun 20, 2023", "https://www.sec.gov/newsroom/press-releases/2023-112"],
            ["SEC order IA-6332", "https://www.sec.gov/files/litigation/admin/2023/ia-6332.pdf"],
            adv_src,
        ]
    pen_body = (
        "The Form ADV regulatory disclosure page has no information filed."
        if not spec.get("penalty")
        else "SEC order of June 20, 2023: excess management fees of $773,754.41, a $1.5 million civil penalty, and disgorgement plus interest of $864,958.17 that the SEC said had already been paid back. No fraud finding. Scored at −10, the bottom of the fine band. The same fee conflict is not also deducted under conflicts."
    )
    evidence["pen"] = card(
        f"Penalty · {fmt_num(sections['pen']) if sections['pen'] else '0'}",
        "Regulatory penalty",
        pen_body,
        pen_sources,
        tone="penalty" if spec.get("penalty") else "",
    )
    evidence["sec"] = card(
        "Regulatory record",
        "SEC disclosure page" if not spec.get("penalty") else "SEC fee order, 2023",
        pen_body,
        pen_sources,
        tone="open" if spec.get("penalty") else "",
    )
    evidence["range"] = card(
        "How sure are we",
        f"Likely range {lo}–{hi}",
        "For each unchecked part we took a small plausible downside (10% of lawsuits and removals, half of down-rounds and blocking, and the unpublished reserve and founder-experience gaps) and combined them as independent swings. Upside is unpublished reserves, unmeasured media, and unconfirmed help.",
        [],
        rows=swing_rows(downs, ups),
    )
    evidence["cov"] = card(
        f"Coverage · {cov}%",
        "How much we could check",
        "Weighted by section points. Down rounds, blocking, media reach, and founder accounts are 0% because they were not measured. A thin record is not a clean record. The percent does not change the 0–100 score.",
        [],
        rows=[
            ["1a Lawsuits", f"{int(float(spec['lawsuit_cov']) * 100)}%"],
            ["1b Founder removals", "0%"],
            ["1c Down rounds", "0%"],
            ["1d Blocking", "0%"],
            ["2a Money", "33%"],
            ["2b Media", "0%"],
            ["2c Help", "36%"],
            ["3 Founder experience", "0%"],
            ["4 Conflicts", "15%"],
        ],
    )
    evidence["rel"] = card(
        "Sources",
        "Sourced rows only",
        "Each scored figure links to a filing or an article that was read. Older research files were used as leads, not as facts. Empty blocks were left empty.",
        [adv_src],
    )
    evidence["rank"] = card(
        "Ranking",
        f"#{place} of 11",
        "Ties are broken A–Z. The list shows the whole number below the one-decimal score.",
        [],
        rows=rank_rows,
    )
    evidence["rules"] = card(
        "Methodology",
        "How the Regretamine score works",
        "Every fund starts with full points and loses them only for verified evidence about its own behavior. Bad events are a share of the portfolio: under 1% costs nothing. A missing portfolio count is not treated as a 70% rate. Regulatory is penalty-only.",
        [],
        rows=[
            ["Fund vs. founders", "60"],
            ["Ability to support you", "17.5"],
            ["Founder experience", "17.5"],
            ["Conflicts", "5"],
            ["Track record bonus", "up to +3"],
            ["Regulatory penalty", "0 to −50"],
        ],
    )
    evidence["sanc"] = card(
        "Sanctions · no ADV designation",
        "No adviser designation in the filing",
        "The Form ADV disclosure pages were read. No sanctions designation for this adviser was in them. People were not screened one by one. A designation would need an exact identity match, not a shared word in a name.",
        [adv_src, iapd_src],
        rows=[
            ["Form ADV DRP", "No sanctions designation filed"],
            ["People screened", "Not run"],
            ["Adviser", spec["legal_name"]],
        ],
    )
    for matter in spec["matters"]:
        evidence[matter["id"]] = card(
            matter["kicker"],
            matter["title"],
            matter["body"],
            matter["sources"],
            rows=[
                ["Firm role", matter["role"]],
                ["Other party", matter["other"]],
                ["Status", matter["status"]],
                ["Founder relevance", matter["relevance"]],
                ["Score effect", matter["effect"]],
            ],
            tone=matter["tone"],
        )
    return evidence


def build_fund(spec, result, cov, lo, hi, downs, ups, rank_rows, place):
    sections = result["sections"]
    total = result["total"]
    shown = floor_shown(total)
    band = result["band"]
    s2_inputs = [
        {"name": "Money", "points": "5 / 6", "why": money_why(spec)},
        {"name": "Media reach (capped)", "points": "0 / 6", "why": "No measured audience. Owned channels were not scored."},
        {"name": "Help after the check", "points": f"{fmt_num(sections['s2'] - 5)} / 5.5", "why": help_why(spec, spec["departures"])},
    ]
    # s2 = money 5 + media 0 + help. Help points label is s2 - 5.
    parts = [
        part("s1", sections["s1"], 60, S1_RULE, [
            {"name": "Lawsuits with its own startups or founders", "points": "30 / 30", "why": lawsuit_why(spec)},
            {"name": "Pushing out founder CEOs", "points": "12 / 12", "why": removal_why()},
            {"name": "Down-round or pay-to-play behavior", "points": "10 / 10", "why": "No evidence found. Terms were not checked, so coverage is 0% and there is no deduction."},
            {"name": "Blocking acquisitions or rounds", "points": "8 / 8", "why": "No documented veto was verified on its own. Coverage is 0%."},
            {"name": "Lost case or fraud finding (−3 each)", "points": "0", "why": "None verified against the fund."},
        ]),
        part("s2", sections["s2"], D("17.5"), S2_RULE, s2_inputs),
        part("s3", sections["s3"], D("17.5"), S3_RULE, [
            {"name": "First-hand accounts", "points": "0", "why": "None collected. Anonymous and second-hand posts were not used."},
            {"name": "Negative share", "points": "0", "why": "No negative first-hand account, so the share is under 1%."},
            {"name": "Age default", "points": fmt_num(sections["s3"]), "why": ""},
        ]),
        part("s4", sections["s4"], 5, S4_RULE, [
            {"name": "Documented conflicts", "points": "0", "why": "None verified. Board seats were not censused."},
            {"name": "Scaled deduction", "points": "0", "why": "No conflict to scale."},
        ]),
        part("bonus", sections["bonus"], 3, BONUS_RULE, [
            {"name": "Years investing", "points": str(spec["age"]), "why": spec["age_why"]},
        ]),
        part("pen", sections["pen"], 50, PEN_RULE, pen_lines(spec, sections["pen"])),
    ]
    founder = [m["id"] for m in spec["matters"] if m["group"] == "founder"]
    other = [m["id"] for m in spec["matters"] if m["group"] != "founder"]
    groups = []
    if founder or not other:
        groups.append({
            "title": "Founder-relevant",
            "note": f"{len(founder)} matter{'s' if len(founder) != 1 else ''}",
            "ids": founder,
        })
    if other:
        groups.append({
            "title": "Other matters",
            "note": "Not scored as fund versus founders",
            "ids": other,
        })
    matters = []
    for matter in spec["matters"]:
        matters.append({
            "id": matter["id"],
            "year": matter["year"],
            "text": matter["text"],
            "sub": matter["sub"],
            "badge": matter["badge"],
            "tone": matter["tone"],
        })
    sec_points = "−10 pts" if spec.get("penalty") else "0 pts"
    sec_tone = "amber" if spec.get("penalty") else "gray"
    sec_title = "SEC fee order, 2023" if spec.get("penalty") else "SEC disciplinary record"
    sec_detail = (
        "June 20, 2023 order. Excess fees repaid. $1.5 million penalty. No fraud finding."
        if spec.get("penalty")
        else f"No information filed on the disclosure pages of the {spec['filing']} Form ADV."
    )
    page = {
        "slug": spec["slug"],
        "name": spec["name"],
        "short": SHORTS[spec["slug"]],
        "title": f"{spec['name']} · Regretamine",
        "hq": spec["hq"],
        "since": spec["since"],
        "meta": [
            f"SEC adviser · CRD {spec['crd']}",
            spec["legal_name"],
        ],
        "notToken": "",
        "updated": UPDATED,
        "method": "Regretamine score",
        "scoreShown": shown,
        "scoreExact": float(total),
        "band": band,
        "range": [lo, hi],
        "rank": {"place": place, "tier": "Top 1" if place == 1 else "v2", "of": 11, "example": False},
        "question": "Should I take this money?",
        "verdict": spec["verdict"],
        "verdictSub": spec["verdict_sub"],
        "floats": [
            {"class": "f1", "ev": "pen", "iconBg": "var(--mint)" if not spec.get("penalty") else "var(--peach)", "icon": "✓" if not spec.get("penalty") else "!", "text": "Sanctions: no ADV hit", "small": "people not screened"},
            {"class": "f2", "ev": "cov", "iconBg": "var(--sky)", "icon": "%", "text": f"Coverage {cov}%", "small": "what we could check"},
        ],
        "badges": [
            {"ev": "cov", "icon": "am", "text": f"Coverage {cov}%"},
            {"ev": "rel", "icon": "ok", "text": "Sources linked"},
            {"ev": "pen", "icon": "ok" if not spec.get("penalty") else "am", "text": "Sanctions: no ADV hit"},
        ],
        "scoreBarNote": f"Where the {shown} comes from · tap a block for the Score tab",
        "parts": parts,
        "summary": spec["summary"],
        "takeaways": [{"ev": key, "title": title, "text": text} for key, title, text in spec["takeaways"]],
        "topLegal": [m["id"] for m in spec["matters"] if m.get("featured")],
        "matters": matters,
        "regulatory": {
            "title": "Regulatory records & sanctions",
            "note": "Form ADV read · Oct 4, 2026",
            "recordsTitle": "Regulatory records",
            "sanctionsTitle": "Sanctions",
            "records": [
                {"icon": "am" if spec.get("penalty") else "ok", "title": sec_title, "detail": sec_detail, "points": sec_points, "tone": sec_tone, "ev": "sec"},
            ],
            "sanctions": {
                "ok": True,
                "title": "No adviser designation in the filing",
                "text": f"The {spec['filing']} Form ADV for {spec['legal_name']} has no sanctions disclosure. People at the firm were not screened one by one.",
                "ev": "sanc",
                "link": "Details →",
                "note": "A shared word in another entity's name is not a match.",
            },
        },
        "legalGroups": groups,
        "notCountedTitle": "Not counted",
        "notCounted": spec["not_counted"],
        "fundTab": {
            "factsTitle": "Fund facts",
            "factsNote": f"Form ADV, {spec['filing']}",
            "facts": [
                {"k": spec["size_label"], "v": spec["size_value"], "s": spec["size_note"]},
                {"k": "Accounts", "v": spec["accounts_value"], "s": spec["accounts_note"]},
                {"k": "Staff", "v": spec["staff_value"], "s": spec["staff_note"]},
                {"k": "Latest ADV", "v": spec["filing"], "s": spec["status"]},
                {"k": "SEC file", "v": spec["sec_file"], "s": f"CRD {spec['crd']}"},
                {"k": "Performance", "v": "Not public", "s": "IRR / TVPI / DPI were not in the filing"},
            ],
            "boards": {
                "title": "Partner board seats",
                "items": [],
                "note": "No partner-board list was verified. Empty is missing data, not a clean conflict record.",
            },
            "moves": {
                "title": "Partner moves",
                "note": "Verified departures only",
                "items": spec["moves"],
                "foot": "One calendar year costs −0.5, however many people left that year.",
            },
            "media": {
                "title": "Media reach",
                "note": "Not measured",
                "items": [],
                "foot": "No subscriber or audience figure was verified, so media points are 0.",
            },
        },
        "public": {
            "title": "Public record",
            "intro": "Articles cited on this page. The fact itself lives on the tab named in the note.",
            "sentimentTitle": "What these sources are",
            "sentimentNote": "A link is not a second copy of the fact.",
            "empty": "No press was needed beyond the filings.",
            "items": spec["press"],
        },
        "portfolio": {
            "title": "What we did not classify",
            "note": "No event histogram",
            "events": [],
            "foot": "Portfolio-company trouble is not charged to the firm unless the firm's own role is documented. No event list was classified.",
            "size": {"title": "Portfolio size", "value": spec["portfolio_value"], "text": spec["portfolio_text"]},
            "healthTitle": "Health",
            "healthNote": "Not classified",
            "health": [],
            "litigation": {"title": "Portfolio litigation rate", "value": spec["lit_value"], "text": spec["lit_text"]},
        },
        "ask": ask_block(spec["name"]),
        "footnote": "Every scored fact links to a dated source. Empty blocks were left empty. Founder sentiment stays empty until it rests on a first-hand account.",
        "scoreFooter": "Rules: Regretamine score (Oct 2, 2026). Inputs: this report, Oct 4, 2026.",
    }
    page["evidence"] = build_evidence(spec, cov, lo, hi, downs, ups, sections, rank_rows, place)
    # s1 lawsuit points label is always 30/30 for these inputs because every scored rate is under 1% or the count is 0.
    return page


def pen_lines(spec, pen):
    if spec.get("penalty"):
        return [
            {"name": "SEC fee order, 2023", "points": "−10", "why": "Fine band is −10 to −20. Fees were repaid and there was no fraud finding, so −10. Not also scored as a conflict."},
            {"name": "Sanctions", "points": "0", "why": "No sanctions designation in the Form ADV. People were not screened one by one."},
        ]
    return [
        {"name": "SEC record", "points": "0", "why": f"No information filed on the disclosure pages of the {spec['filing']} Form ADV."},
        {"name": "Sanctions", "points": "0", "why": "No sanctions designation in the Form ADV. People were not screened one by one."},
    ]


def dump(path, payload):
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main():
    scored = []
    for spec in FUNDS:
        inputs = base_inputs(
            spec["portfolio"],
            spec["age"],
            spec["departures"],
            spec["pen"],
            help_platform=spec.get("help_platform", 0),
            help_intros=spec.get("help_intros", 0),
            lawsuits=spec["lawsuits"],
        )
        result = score_v2(inputs)
        cov = coverage_percent(spec["lawsuit_cov"])
        lo, hi, downs, ups = range_pair(result["total"], spec["lawsuit_cov"], spec["reg_down"])
        scored.append((spec, inputs, result, cov, lo, hi, downs, ups))

    a16z = json.loads((ROOT / "data" / "funds" / "a16z.json").read_text(encoding="utf-8"))
    ranking = [{
        "slug": "a16z",
        "name": "Andreessen Horowitz",
        "total": D("95.4"),
        "shown": 95,
        "band": "Very low risk",
    }]
    for spec, inputs, result, cov, lo, hi, downs, ups in scored:
        ranking.append({
            "slug": spec["slug"],
            "name": spec["name"],
            "total": result["total"],
            "shown": floor_shown(result["total"]),
            "band": result["band"],
        })
    ranking.sort(key=lambda row: (-row["total"], row["name"]))
    place_of = {}
    rank_rows = []
    for index, row in enumerate(ranking, start=1):
        place_of[row["slug"]] = index
        rank_rows.append([row["name"], f"{fmt_num(row['total'])}"])

    out_dir = ROOT / "data" / "funds"
    inputs_out = {}
    reports = {}
    for spec, inputs, result, cov, lo, hi, downs, ups in scored:
        page = build_fund(spec, result, cov, lo, hi, downs, ups, rank_rows, place_of[spec["slug"]])
        reports[spec["slug"]] = page
        dump(out_dir / f"{spec['slug']}.json", page)
        inputs_out[spec["slug"]] = inputs
        print(
            f"{spec['slug']:22} {result['total']} shown {floor_shown(result['total'])} "
            f"{result['band']} cov {cov} range {lo}-{hi} place {place_of[spec['slug']]}"
        )
    dump(ROOT / "data" / "score_inputs.json", inputs_out)

    a16z["rank"] = {"place": place_of["a16z"], "tier": "Top 1", "of": 11, "example": False}
    a16z["evidence"]["rank"] = {
        "kicker": "Ranking",
        "title": f"#{place_of['a16z']} of 11",
        "body": "Ties are broken A–Z. The list shows the whole number below the one-decimal score.",
        "rows": rank_rows,
        "sources": [],
        "tone": "",
    }
    dump(out_dir / "a16z.json", a16z)

    home = json.loads((ROOT / "data" / "home.json").read_text(encoding="utf-8"))
    by_slug = {spec["slug"]: (spec, result, cov, lo, hi) for spec, inputs, result, cov, lo, hi, downs, ups in scored}
    for row in home["funds"]:
        if row["id"] == "a16z":
            continue
        spec, result, cov, lo, hi = by_slug[row["id"]]
        row["since"] = int(spec["since"])
        row["aum"] = spec["aum"]
        row["aumAsOf"] = spec["aum_as_of"]
        row["aumStale"] = False
        row["aumSrc"] = spec["aum_src"]
        row["score"] = floor_shown(result["total"])
        row["v2"] = True
        row["band"] = result["band"]
        row["legal"] = spec["legal_n"]
        row["legalNote"] = spec["legal_note"]
        row["updated"] = "2026-10-04"
        row["updatedTs"] = "2026-10-04T00:00:00-07:00"
        row["updatedS"] = "Oct 4, 2026"
        row["old"] = spec["old"]
        row["lo"] = lo
        row["hi"] = hi
        row["cov"] = cov
        row["short"] = SHORTS[spec["slug"]]
        row["verdict"] = spec["verdict"]
        row["report"] = spec["slug"]
    # Key order must match assemble_home: optional fields then report last.
    ordered = []
    for row in home["funds"]:
        item = {
            "id": row["id"], "name": row["name"], "ini": row["ini"], "hq": row["hq"],
            "metro": row["metro"], "since": row["since"], "type": row["type"],
            "aum": row["aum"], "aumAsOf": row["aumAsOf"], "aumStale": row["aumStale"],
            "aumSrc": row["aumSrc"], "score": row["score"], "v2": row["v2"],
            "band": row["band"], "legal": row["legal"], "legalNote": row["legalNote"],
            "updated": row["updated"], "updatedTs": row["updatedTs"], "updatedS": row["updatedS"],
        }
        if row.get("short"):
            item["short"] = row["short"]
        if row.get("old") is not None:
            item["old"] = row["old"]
        if row.get("lo") is not None:
            item["lo"] = row["lo"]
        if row.get("hi") is not None:
            item["hi"] = row["hi"]
        if row.get("cov") is not None:
            item["cov"] = row["cov"]
        if row.get("verdict"):
            item["verdict"] = row["verdict"]
        item["report"] = row.get("report")
        ordered.append(item)
    home["funds"] = ordered

    urls = set()
    for slug in ["a16z", *reports]:
        payload = a16z if slug == "a16z" else reports[slug]
        for card_body in payload["evidence"].values():
            for _label, url in card_body.get("sources") or []:
                urls.add(url)
        for item in payload["public"]["items"]:
            urls.add(item["url"])
    for upd in home["updates"]:
        if upd.get("u", "").startswith("http"):
            urls.add(upd["u"])
    active = sum(row["legal"] for row in home["funds"])
    home["stats"] = [
        {"n": 11, "l": "funds", "s": "All 11 have a v2 report", "v": True},
        {"n": len(urls), "l": "sources cited", "s": "Distinct URLs in the 11 reports and the update feed", "v": True},
        {"n": active, "l": "active legal matters", "s": "Open matters on the v2 reports. Insight 1, a16z 4", "v": True},
        {"n": 0, "l": "funds sanctioned", "s": "No adviser-name designation in the Form ADVs read. Person screen only for a16z", "v": False},
    ]
    dump(ROOT / "data" / "home.json", home)
    print("sources", len(urls), "active", active)


if __name__ == "__main__":
    main()
