"""Real, sourced facts from the research tables, shaped for the report tabs.

Input is the raw export of rows with data_status = 'real' from vc_source_facts,
vc_entity_identifiers, vc_partner_history, vc_political_activity and
vc_context_notes (see scripts/export_real_facts.py). needs_proof and test rows
never reach this module. Text is the stored fact value, never a generated judgement.
"""
from __future__ import annotations

import datetime as dt
import re

# Rows whose section is named after a tab mirror the report tables (legal_matters,
# press_items, funds, ...) that the page already renders, so they are not repeated.
ALREADY_ON_PAGE = {"legal", "public", "fund", "overview", "portfolio"}

FIRM_WORDS = {
    "a16z": ("Andreessen", "a16z", "AH Capital"),
    "generalcatalyst": ("General Catalyst",),
    "sequoia": ("Sequoia",),
    "lightspeed": ("Lightspeed", "LSVP"),
    "plugandplay": ("Plug and Play", "Plug & Play", "Amidi"),
}

DOCKET = re.compile(r"\b\d:\d{2}-[a-z]{2}-\d{3,5}\b|\b\d{4}-\d{4}-[A-Z]{3}\b|\b\d{2}-\d{4}\b|\bMDL(?: No\.)? \d{3,4}\b")
URL_KEYS = (
    re.compile(r"gov\.uscourts\.([a-z0-9]+\.\d+)"),
    re.compile(r"USCOURTS-([a-z0-9]+-[0-9_]+)"),
    re.compile(r"docket_id%3A(\d+)"),
)
FIELD_LABEL = {
    "matter_status": "Status",
    "matter_class": "Type",
    "matter_role": "Role",
    "matter_outcome": "Outcome",
    "crd": "SEC CRD",
    "legal_entity": "Legal entity",
    "registration_status": "SEC registration",
    "files_13f": "13F filer",
    "regulatory_aum": "Regulatory AUM",
    "private_fund_count": "Private funds",
    "employees": "Employees",
    "investment_staff": "Investment staff",
    "latest_raise": "Latest Form D",
    "fundraise": "Fundraise",
    "partner_start_date": "Joined",
    "role_change": "Role change",
    "tenure_start": "Tenure start",
    "partner_departure_press": "Departure",
    "public_board_seat": "Outside board seat",
    "sec_disciplinary": "SEC disclosures",
    "regulatory_action_amount": "Penalty amount",
    "regulatory_action_type": "Action type",
    "sanctions_check": "Sanctions screen",
    "negative_alias": "Not the same firm",
    "context": "Team page change",
}
IDENTITY_FIELDS = {"crd", "legal_entity", "registration_status", "files_13f"}
PEOPLE_FIELDS = {"partner_start_date", "role_change", "tenure_start", "partner_departure_press"}


def day(value):
    if not value:
        return ""
    text = str(value)[:10]
    try:
        return dt.date.fromisoformat(text).strftime("%b %-d, %Y")
    except ValueError:
        return text


def _val(row):
    value = row.get("value")
    return value if isinstance(value, dict) else {"value": value}


def _who(entity):
    entity = entity or ""
    return entity.split(":", 1)[1].strip() if entity.startswith("partner:") else ""


SITE_TZ = "America/Los_Angeles"


def local_day(value):
    """Calendar day of a timestamp in the site's time zone (Pacific), as YYYY-MM-DD."""
    text = str(value or "")
    if len(text) <= 10:
        return text
    try:
        from zoneinfo import ZoneInfo

        stamp = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
        if stamp.tzinfo is None:
            return text[:10]
        return stamp.astimezone(ZoneInfo(SITE_TZ)).date().isoformat()
    except ValueError:
        return text[:10]


def _src(row):
    return {
        "url": row.get("source_url") or "",
        "source": row.get("source_label") or "",
        "retrieved": local_day(row.get("retrieved_at")),
        "published": (_val(row).get("published_date") or row.get("published_date") or "") or "",
    }


def _norm_key(key):
    return re.sub(r"[^0-9A-Za-z:-]", "", key.replace("No.", "")) if key.startswith("MDL") else key


def _keys(row):
    found = {_norm_key(k) for k in DOCKET.findall(str(_val(row).get("value") or ""))}
    for pat in URL_KEYS:
        match = pat.search(row.get("source_url") or "")
        if match:
            found.add("url:" + match.group(1))
    return found


def _role(slug, caption, attrs, people):
    text = (caption + " " + " ".join(attrs.get("matter_role", []))).lower()
    if "non-party" in text or "subpoena" in text:
        return "Non-party", "gray"
    if people and not any(w.lower() in caption.lower() for w in FIRM_WORDS.get(slug, ())):
        return "Partner as company director; firm not a party", "gray"
    if any(w.lower() in caption.lower() for w in FIRM_WORDS.get(slug, ())):
        return "Firm is a party", "amber"
    return "Firm not in the case caption", "gray"


def legal_cases(slug, rows):
    cases = []
    attrs_rows = []
    for row in rows:
        field = _val(row).get("field") or row.get("fact_type")
        if field == "legal_matter":
            cases.append({"rows": [row], "keys": _keys(row), "attrs": {}, "people": set()})
        else:
            attrs_rows.append(row)
    merged = []
    for case in cases:
        for other in merged:
            if case["keys"] & other["keys"]:
                other["rows"] += case["rows"]
                other["keys"] |= case["keys"]
                break
        else:
            merged.append(case)
    loose = list(attrs_rows)
    changed = True
    while changed:
        changed = False
        for row in list(loose):
            keys = _keys(row)
            target = next((c for c in merged if keys & c["keys"]), None)
            if target is None:
                continue
            target["attrs"].setdefault(_val(row).get("field"), []).append(str(_val(row).get("value")))
            target["rows"].append(row)
            target["keys"] |= keys
            loose.remove(row)
            changed = True
    out = []
    for case in merged:
        first = case["rows"][0]
        value = str(_val(first).get("value") or "")
        caption, _, rest = value.partition(" | ")
        people = sorted({_who(_val(r).get("entity")) for r in case["rows"] if _who(_val(r).get("entity"))})
        badge, tone = _role(slug, caption, case["attrs"], people)
        details = [rest.replace(" | ", " · ")] if rest else []
        for field in ("matter_role", "matter_class", "matter_status", "matter_outcome"):
            for item in dict.fromkeys(case["attrs"].get(field, [])):
                details.append(f"{FIELD_LABEL[field]}: {item}")
        if people:
            details.append("Named: " + ", ".join(people))
        sources = []
        for r in case["rows"]:
            s = _src(r)
            if s["url"] and s["url"] not in [x["url"] for x in sources]:
                sources.append(s)
        year = ""
        filed = re.search(r"filed (\d{4})", rest)
        docket = re.search(r"\b\d:(\d{2})-[a-z]{2}-", rest) or re.search(r"\b(\d{2})-\d{4}\b", rest)
        if filed:
            year = filed.group(1)
        elif docket:
            year = "20" + docket.group(1) if int(docket.group(1)) < 50 else "19" + docket.group(1)
        else:
            m = re.search(r"\b(?:19|20)\d{2}\b", rest)
            year = m.group(0) if m else ""
        out.append({
            "kind": "case", "title": caption, "detail": " · ".join(details), "badge": badge, "tone": tone,
            "year": year, "keys": sorted(case["keys"]), "sources": sources,
        })
    for row in loose:
        v = _val(row)
        out.append({
            "kind": "case_note", "title": "Court record " + FIELD_LABEL.get(v.get("field"), "note").lower(), "detail": str(v.get("value") or ""),
            "badge": "Court record", "tone": "gray", "year": "", "keys": sorted(_keys(row)), "sources": [_src(row)],
        })
    return out


def _item(row, title=None, detail=None, badge="", group=""):
    v = _val(row)
    who = _who(v.get("entity") or row.get("entity"))
    return {
        "title": title if title is not None else (FIELD_LABEL.get(v.get("field") or row.get("field"), (v.get("field") or "Fact").replace("_", " ").capitalize())),
        "detail": detail if detail is not None else str(v.get("value") or row.get("value") or ""),
        "who": who, "badge": badge, "group": group, "sources": [_src(row)],
    }


def shape_firm(slug, export):
    facts = [r for r in export.get("facts") or [] if r.get("slug") == slug and r.get("section") not in ALREADY_ON_PAGE]
    by = lambda *sections: [r for r in facts if r.get("section") in sections]
    legal_rows = by("legal_matter")
    reg_rows = by("regulatory_record")
    sanc_rows = by("sanctions_check")
    cases = legal_cases(slug, legal_rows)

    # Regulatory: actions with an amount or type are one action; disclosure reads are checks.
    actions, checks = [], []
    action_rows = [r for r in reg_rows if (_val(r).get("field") or "").startswith("regulatory_action")]
    if action_rows:
        amount = next((str(_val(r).get("value")) for r in action_rows if _val(r).get("field") == "regulatory_action_amount"), "")
        kind = next((str(_val(r).get("value")) for r in action_rows if _val(r).get("field") == "regulatory_action_type"), "")
        srcs = []
        for r in action_rows:
            s = _src(r)
            if s["url"] not in [x["url"] for x in srcs]:
                srcs.append(s)
        actions.append({
            "title": f"Regulator penalty: {amount}" if amount else "Regulator action",
            "detail": kind, "badge": "Regulator action", "tone": "amber",
            "year": (srcs[0]["published"] or "")[:4], "sources": srcs,
        })
    for r in reg_rows:
        if r in action_rows:
            continue
        checks.append(_item(r, badge="Checked"))
    screened = []
    for r in sanc_rows:
        v = _val(r)
        who = _who(v.get("entity")) or ("the firm" if (v.get("entity") or "firm") == "firm" else v.get("entity"))
        screened.append({"title": who, "detail": str(v.get("value") or ""), "sources": [_src(r)]})

    identity = [_item(r) for r in by("sec_crd", "legal_entity") + [r for r in by("fund_fact") if _val(r).get("field") in IDENTITY_FIELDS]]
    fund_facts = [_item(r) for r in by("fund_fact") if _val(r).get("field") not in IDENTITY_FIELDS]
    people = [_item(r) for r in by("partner_move")]
    for r in export.get("partners") or []:
        if r.get("slug") == slug:
            people.append({
                "title": r.get("person_name") or "Partner", "detail": " · ".join(b for b in (r.get("kind"), r.get("organization") or r.get("value")) if b),
                "who": r.get("person_name") or "", "badge": "", "group": "", "sources": [_src(r)],
            })
    boards = [_item(r, title=_who(_val(r).get("entity")) or "Partner") for r in by("board_seat")]
    accounts = []
    acc_rows = by("founder_experience")
    if acc_rows:
        fields = {(_val(r).get("field")): str(_val(r).get("value")) for r in acc_rows}
        bits = [fields.get("founder_account", "")]
        if fields.get("account_author_role"):
            bits.append("Author: " + fields["account_author_role"])
        if fields.get("account_first_hand") == "true":
            bits.append("First-hand")
        if fields.get("account_verification"):
            bits.append("Verification: " + fields["account_verification"])
        if fields.get("account_tone"):
            bits.append("Tone: " + fields["account_tone"])
        src = []
        for r in acc_rows:
            s = _src(r)
            if s["url"] not in [x["url"] for x in src]:
                src.append(s)
        accounts.append({"title": "Founder account", "detail": " · ".join(b for b in bits if b), "who": "", "badge": "", "group": "", "sources": src})
    entities = []
    for r in export.get("ids") or []:
        if r.get("slug") != slug:
            continue
        name = str(r.get("value") or "").split(" | ")[0]
        label = {"cik": "SEC CIK", "lei": "LEI", "company_number": "Company no."}.get(r.get("id_type"), r.get("id_type") or "ID")
        entities.append({"title": name, "detail": f"{label} {r.get('id_value') or ''}".strip() + (f" · {r['jurisdiction']}" if r.get("jurisdiction") else ""),
                         "who": "", "badge": "", "group": r.get("id_type") or "", "sources": [_src(r)]})
    notes = []
    for r in export.get("notes") or []:
        if r.get("slug") == slug:
            notes.append({"title": FIELD_LABEL.get(r.get("kind") or r.get("field"), "Note"), "detail": str(r.get("value") or ""),
                          "who": "", "badge": "", "group": r.get("kind") or "", "sources": [_src(r)]})
    political = []
    for r in export.get("political") or []:
        if r.get("slug") == slug:
            political.append({"title": r.get("person_name") or "Political activity", "detail": str(r.get("value") or ""),
                              "who": r.get("person_name") or "", "badge": r.get("kind") or "", "group": "", "sources": [_src(r)]})
    press = []
    for r in by("press_item"):
        v = _val(r)
        press.append({"title": str(v.get("value") or ""), "detail": v.get("publisher") or r.get("source_label") or "",
                      "who": _who(v.get("entity")), "badge": "", "group": "", "sources": [_src(r)]})
    tabs = {
        "legal": {"cases": cases, "actions": actions, "checks": checks, "sanctions": screened},
        "fund": {"identity": identity, "facts": fund_facts, "people": people, "boards": boards,
                 "accounts": accounts, "entities": entities, "notes": notes, "political": political},
        "public": {"press": press},
        "portfolio": {},
    }
    return {"slug": slug, "tabs": tabs}


def iter_sources(node):
    if isinstance(node, dict):
        for s in node.get("sources") or []:
            yield s
        for key, value in node.items():
            if key != "sources":
                yield from iter_sources(value)
    elif isinstance(node, list):
        for value in node:
            yield from iter_sources(value)


def summarize(shaped):
    out = {}
    for tab, body in shaped["tabs"].items():
        srcs = list(iter_sources(body))
        items = sum(len(v) for v in body.values()) if isinstance(body, dict) else 0
        out[tab] = {
            "items": items,
            "sources": len({s["url"] for s in srcs if s.get("url")}),
            "latest": max((s["retrieved"] for s in srcs if s.get("retrieved")), default=""),
        }
    return out
