#!/usr/bin/env python3
"""Build the Regretamin static site into ./site.

Source of truth:
  Supabase published_site_bundle()  every firm, report and fact (no repo data files)

No third-party dependencies. Internal links are relative, so the same
output works at a GitHub project URL (/regrettamine/) and at regretamin.com.
"""
import html
import json
import math
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "data"
SRC = ROOT / "src"
SITE = ROOT / "site"

EXT_SVG = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M6 3H3.5A.5.5 0 0 0 3 3.5v9a.5.5 0 0 0 .5.5h9a.5.5 0 0 0 .5-.5V10M9 3h4v4M13 3 7.5 8.5"/></svg>'
OPEN_SVG = '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 3h4v4M13 3 7.5 8.5"/></svg>'
SAVE_SVG = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M6 6a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v14l-6-4.2L6 20z"/></svg>'
CORRECT_LINE = '<a class="lnk" id="correctLink" hidden>@@s:page.scoring.request_a_correction@@</a>'
def load_strings():
    raw = (SRC / "js" / "strings.js").read_text(encoding="utf-8")
    body = raw.split("/*BEGIN_STRINGS*/", 1)[1].split("/*END_STRINGS*/", 1)[0]
    return json.loads(body)


STRINGS = load_strings()


def S(key, variant="default"):
    variants = STRINGS[key]["variants"]
    if variant not in variants:
        raise SystemExit(f"strings.js: {key} has no variant {variant!r}")
    return variants[variant]["text"]


_TOKEN = re.compile(r"\{\{(s|sjs):([a-z0-9_.]+)(?:\|([a-z0-9_]+))?\}\}|@@(s):([a-z0-9_.]+)@@")


def apply_strings(text):
    """Replace {{s:key|variant}} (HTML) and {{sjs:key|variant}} (inside a single-quoted JS string)."""
    def sub(match):
        if match.group(4):  # @@s:key@@ is the brace-free form used inside build.py f-strings
            kind, key, variant = "s", match.group(5), "default"
        else:
            kind, key, variant = match.group(1), match.group(2), match.group(3) or "default"
        if key not in STRINGS:
            raise SystemExit(f"strings.js: unknown key {key}")
        value = S(key, variant)
        if kind == "sjs":
            value = value.replace("\\", "\\\\").replace("'", "\\'")
        return value
    for _ in range(3):  # a string may itself contain {{s:brand.name}}
        if "{{s" not in text and "@@s:" not in text:
            break
        text = _TOKEN.sub(sub, text)
    return text


def apply_strings_to_data(obj):
    """Resolve {{s:key}} inside loaded JSON/Supabase records (shared site text lives in strings.js)."""
    if isinstance(obj, dict):
        return {k: apply_strings_to_data(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [apply_strings_to_data(v) for v in obj]
    if isinstance(obj, str) and "{{s" in obj:
        return apply_strings(obj)
    return obj


def apply_strings_to_site():
    for path in SITE.rglob("*"):
        if path.suffix in (".html", ".js", ".json", ".css") and path.is_file():
            raw = path.read_text(encoding="utf-8")
            if "{{s" in raw or "@@s:" in raw:
                path.write_text(apply_strings(raw), encoding="utf-8")


BRAND = S("brand.name")
SENT_LABEL = {k: S("report.sentiment.label", k) for k in ("pos", "neu", "neg")}
PAGE_SIZE = 24
LIST_CAP = 8


def esc(value):
    return html.escape(str(value), quote=True)


def embed(obj):
    # Keep the JSON out of a closing script tag.
    return json.dumps(obj, ensure_ascii=False).replace("<", "\\u003c")


def load_json(path):
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def ring_svg(score_exact, size=240, stroke=20):
    r = (size - stroke) / 2
    circ = round(2 * math.pi * r, 1)
    offset = round(circ * (1 - float(score_exact) / 100), 1)
    half = size / 2
    return (
        f'<svg width="{size}" height="{size}" viewBox="0 0 {size} {size}">'
        f'<defs><linearGradient id="rg" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="#19C37D"/>'
        f'<stop offset=".5" stop-color="#3FA9F5"/>'
        f'<stop offset="1" stop-color="#6C3BFF"/></linearGradient></defs>'
        f'<circle cx="{half:.1f}" cy="{half:.1f}" r="{r:.1f}" stroke="#F1EFF7" stroke-width="{stroke}" fill="none"/>'
        f'<circle cx="{half:.1f}" cy="{half:.1f}" r="{r:.1f}" stroke="url(#rg)" stroke-width="{stroke}" fill="none" '
        f'stroke-linecap="round" stroke-dasharray="{circ:.1f}" stroke-dashoffset="{offset:.1f}"/></svg>'
    )


def leg_row(m):
    return (
        f'<button class="lrow" data-ev="{esc(m["id"])}">'
        f'<span class="ly">{esc(m["year"])}</span>'
        f'<span class="ls">{esc(m["text"])}<small>{esc(m["sub"])}</small></span>'
        f'<span class="lr"><span class="rt {esc(m["tone"])}">{esc(m["badge"])}</span>'
        f'<span class="chev">›</span></span></button>'
    )


def legend_value(part):
    got = esc(part["got"])
    if part.get("legendOf"):
        return f'<b>{got}<small>{esc(part["legendOf"])}</small></b>'
    return f"<b>{got}</b>"


def score_inputs(part):
    rows = []
    for item in part["inputs"]:
        neg = " neg" if str(item["points"]).startswith("−") else ""
        rows.append(
            f'<div class="wi"><span class="wn">{esc(item["name"])}</span>'
            f'<b class="wp{neg}">{esc(item["points"])}</b>'
            f'<span class="ww">{esc(item["why"])}</span></div>'
        )
    return "".join(rows)


def source_line(fund, ev_id):
    sources = fund["evidence"][ev_id].get("sources") or []
    return " · ".join(pair[0] for pair in sources[:2])


def join_capped(items, render_item, limit=LIST_CAP):
    """Show the first rows, then a disclosure. Short lists stay one block."""
    if len(items) <= limit:
        return "".join(render_item(item) for item in items)
    head = "".join(render_item(item) for item in items[:limit])
    tail = "".join(render_item(item) for item in items[limit:])
    return (
        head
        + f'<details class="more"><summary>@@s:build.show_more@@ <span>{len(items) - limit} more</span></summary>'
        + f'<div class="lst">{tail}</div></details>'
    )



# ---- Real, sourced facts from the research tables (data/facts/<slug>.json) ----

def fact_day(value):
    from regrettamine.real_facts import day
    return day(value)


def sources_html(sources):
    links = []
    for src in sources or []:
        url = src.get("url") or ""
        label = esc(src.get("source") or url)
        when = f' · retrieved {esc(fact_day(src.get("retrieved")))}' if src.get("retrieved") else ""
        pub = f' · published {esc(fact_day(src.get("published")))}' if src.get("published") else ""
        if url.startswith("http"):
            links.append(f'<a href="{esc(url)}" target="_blank" rel="noopener">{label}</a>{pub}{when}')
        else:
            links.append(f"{label}{pub}{when}")
    return f'<span class="fsrc">{"; ".join(links)}</span>' if links else ""


def fact_row(item):
    who = f' <span class="sm">{esc(item["who"])}</span>' if item.get("who") and item.get("who") != item.get("title") else ""
    badge = f'<span class="rt {esc(item.get("tone") or "gray")}">{esc(item["badge"])}</span>' if item.get("badge") else ""
    year = f'<span class="ly">{esc(item["year"])}</span>' if item.get("year") else ""
    return (
        f'<div class="it fact">{year}<div><b>{esc(item["title"])}</b>{who}'
        f'<div class="sm">{esc(item.get("detail") or "")}</div>{sources_html(item.get("sources"))}</div>{badge}</div>'
    )


def fact_card(title, items, note=""):
    if not items:
        return ""
    srcs = {s.get("url") for item in items for s in item.get("sources") or [] if s.get("url")}
    small = f'{len(items)} item{"" if len(items) == 1 else "s"} · {len(srcs)} source{"" if len(srcs) == 1 else "s"}'
    foot = f'<p class="note">{esc(note)}</p>' if note else ""
    return (
        f'<div class="pc list facts"><div class="ph3"><h3>{esc(title)}</h3><small>{small}</small></div>'
        f'{join_capped(items, fact_row)}{foot}</div>'
    )


def real_facts(fund):
    return (fund.get("realFacts") or {}).get("tabs") or {}


def _matter_text(fund):
    return " ".join(f'{m.get("text", "")} {m.get("sub", "")}' for m in fund.get("matters") or [])


def legal_fact_items(fund):
    """Court cases and regulator actions from the research tables, minus ones the page already lists."""
    legal = real_facts(fund).get("legal") or {}
    known = _matter_text(fund)
    reg_text = " ".join(f'{r.get("title", "")} {r.get("detail", "")}' for r in (fund.get("regulatory") or {}).get("records") or [])
    cases, dup_cases = [], []
    for case in legal.get("cases") or []:
        dockets = [k for k in case.get("keys") or [] if not k.startswith("url:")]
        party = (case.get("title") or "").split(" v. ")[0].split(",")[0].strip()
        if any(k in known for k in dockets) or (case.get("kind") == "case" and len(party) > 4 and party in known):
            dup_cases.append(dict(case, badge="Same matter as listed above", tone="gray"))
        else:
            cases.append(case)
    actions, dup_actions = [], []
    for act in legal.get("actions") or []:
        amount = re.sub(r"[^0-9,]", "", act.get("title") or "").strip(",")
        if amount and amount in reg_text:
            dup_actions.append(act)
        else:
            actions.append(act)
    return cases, dup_cases, actions, dup_actions


def penalty_records(fund, matters):
    """Regulatory records that carry points and are not already a listed matter."""
    out = []
    for rec in (fund.get("regulatory") or {}).get("records") or []:
        if str(rec.get("points") or "").startswith("−") and rec.get("ev") not in matters:
            out.append(rec)
    return out


def legal_count(fund, matters):
    cases, _dup, actions, _dupa = legal_fact_items(fund)
    real_cases = [c for c in cases if c.get("kind") == "case"]
    return len(matters) + len(real_cases) + len(actions) + len(penalty_records(fund, matters))


def legal_checked(fund):
    from regrettamine.real_facts import iter_sources
    dates = [s.get("retrieved") for s in iter_sources(real_facts(fund).get("legal") or {}) if s.get("retrieved")]
    return fact_day(max(dates)) if dates else ""


def latest_checked(fund):
    from regrettamine.real_facts import iter_sources
    dates = [s.get("retrieved") for s in iter_sources(real_facts(fund)) if s.get("retrieved")]
    return fact_day(max(dates)) if dates else ""


def tab_fact_stats(fund):
    """Items and distinct source links per tab, for the overview and the tests."""
    from regrettamine.real_facts import iter_sources
    out = {}
    for tab, body in real_facts(fund).items():
        items = sum(len(v) for v in body.values()) if isinstance(body, dict) else 0
        urls = {s.get("url") for s in iter_sources(body) if s.get("url")}
        out[tab] = (items, len(urls))
    return out

def render_takeaways(fund):
    cards = []
    for i, tk in enumerate(fund["takeaways"]):
        cards.append(
            f'<button class="tkc t{i % 5}" data-ev="{esc(tk["ev"])}">'
            f'<span class="ix">{i + 1:02d}</span><h4>{esc(tk["title"])}</h4><p>{esc(tk["text"])}</p>'
            f'<span class="src"><span>{esc(source_line(fund, tk["ev"]))}</span>'
            f'<span class="open">@@s:build.evidence@@</span></span></button>'
        )
    return "".join(cards)


def grouped_matter_ids(fund):
    ids = set()
    for group in fund.get("legalGroups") or []:
        ids.update(group.get("ids") or [])
        ids.update((group.get("more") or {}).get("ids") or [])
    return ids


def strip_toxy(value):
    """User-facing pages do not name the old score brand."""
    if isinstance(value, str):
        text = value.replace("Toxy Score v2", BRAND + " score")
        text = text.replace("Toxy sources", "sources")
        text = text.replace("Toxy's ", "")
        text = text.replace("Toxy ", "")
        return text.replace("Toxy", "")
    if isinstance(value, list):
        return [strip_toxy(item) for item in value]
    if isinstance(value, dict):
        return {key: strip_toxy(item) for key, item in value.items()}
    return value


_CAP_CLAUSE = re.compile(r"\s*\d+ ÷ 5 is capped at \+3\.")
_RANK_V2 = re.compile(r"^All 11 funds are (?:scored )?on v2\.\s*")


def dedupe_founded_sentence(fund):
    """The age row and the bonus row stored the same founded sentence. Keep it once, on the bonus."""
    parts = {part.get("id"): part for part in fund.get("parts") or []}
    bonus_why = ""
    for item in (parts.get("bonus") or {}).get("inputs") or []:
        if item.get("name") == "Years investing":
            bonus_why = item.get("why") or ""
    if "capped at +3" not in bonus_why:
        return fund
    for item in (parts.get("s3") or {}).get("inputs") or []:
        if item.get("name") != "Age default":
            continue
        why = item.get("why") or ""
        if "capped at +3" not in why:
            continue
        trimmed = _CAP_CLAUSE.sub("", why).strip()
        if why == bonus_why or (trimmed and trimmed in bonus_why):
            item["why"] = ""
        else:
            item["why"] = trimmed
    return fund


def fund_heading(fund):
    name = (fund.get("name") or "").strip()
    short = (fund.get("short") or "").strip()
    initials = "".join(part[0] for part in name.split() if part)
    redundant = (
        not short
        or short.lower() == name.lower()
        or (len(short) > 1 and short.lower() in name.lower())
        or short.lower() == initials.lower()
    )
    if redundant:
        return esc(name)
    return f"{esc(name)} <span>{esc(short)}</span>"


def empty_card(sentence, checked):
    when = f'<p class="checked">@@s:build.last_checked@@ {esc(checked)}</p>' if checked else ""
    return f'<div class="pc emptycard"><p>{esc(sentence)}</p>{when}</div>'


def render_overview(fund, matters):
    grouped = grouped_matter_ids(fund)
    top = "".join(leg_row(matters[i]) for i in fund["topLegal"] if i not in grouped)
    n = legal_count(fund, matters)
    if not top:
        cases, _d, actions, _da = legal_fact_items(fund)
        top = "".join(fact_row(item) for item in (actions + [c for c in cases if c.get("kind") == "case"])[:3])
    if fund["takeaways"]:
        take_block = (
            f'<div class="sech"><h2 class="h2">@@s:js.gate.takeaways@@</h2><small>@@s:build.click_any_card_to_see@@</small></div>'
            f'<div class="tkg tk6">{render_takeaways(fund)}</div>'
        )
    else:
        take_block = (
            '<div class="sech"><h2 class="h2">@@s:js.gate.takeaways@@</h2></div>'
            '<p class="empty-state">@@s:build.no_takeaways_yet@@</p>'
        )
    if n:
        rows = f'<div class="pc lstc"><div class="lst">{top}</div></div>' if top else ''
        legal_block = (
            f'<div class="sech"><h2 class="h2">@@s:js.gate.top_legal_matters@@</h2>'
            f'<button class="lnk" data-go="legal">@@s:build.see_all@@ {n} →</button></div>'
            f'{rows}'
        )
    else:
        legal_block = (
            '<div class="sech"><h2 class="h2">@@s:js.gate.top_legal_matters@@</h2></div>'
            '<p class="empty-state">@@s:build.no_legal_matters_on_file@@</p>'
        )
    summary = fund.get("summary") or ""
    if summary:
        summary_block = f'<div class="blk sumb"><div class="lab">@@s:js.gate.summary@@</div><div><p class="big clamp5">{esc(summary)}</p></div></div>'
    else:
        summary_block = '<p class="empty-state">@@s:build.no_summary_yet@@</p>'
    return summary_block + take_block + legal_block + render_fact_totals(fund)


TAB_LABELS = (("legal", "Legal"), ("fund", "Fund & people"), ("public", "Public"), ("portfolio", "Portfolio"))


def render_fact_totals(fund):
    """Counts of sourced facts per tab, each with its latest retrieval date."""
    from regrettamine.real_facts import iter_sources

    rows = []
    for key, label in TAB_LABELS:
        body = real_facts(fund).get(key) or {}
        items = sum(len(v) for v in body.values()) if isinstance(body, dict) else 0
        if not items:
            continue
        srcs = list(iter_sources(body))
        urls = {x.get("url") for x in srcs if x.get("url")}
        latest = max((x.get("retrieved") for x in srcs if x.get("retrieved")), default="")
        when = f" · latest retrieved {esc(fact_day(latest))}" if latest else ""
        rows.append(
            f'<div class="it"><b>{esc(label)}</b><span>{items} fact{"s" if items != 1 else ""} · '
            f'{len(urls)} source{"s" if len(urls) != 1 else ""}{when}</span>'
            f'<button class="lnk" data-go="{key}">@@s:build.see_all@@ →</button></div>'
        )
    if not rows:
        return ""
    return (
        '<div class="sech"><h2 class="h2">Sourced facts on file</h2><small>Each fact links to its source.</small></div>'
        f'<div class="pc lstc"><div class="lst">{"".join(rows)}</div></div>'
    )


def render_score_facts(fund):
    """The legal and sanctions facts the score's core (SEC, sanctions, legal) is read from."""
    legal = real_facts(fund).get("legal") or {}
    cases, dup_cases, actions, dup_actions = legal_fact_items(fund)
    return "".join([
        fact_card("Facts behind the penalty: regulator actions", actions + dup_actions,
                  "Regulator penalties count under the penalty rules."),
        fact_card("Facts behind the penalty: sanctions screens", legal.get("sanctions") or [],
                  "A sanctions match needs an exact identity match. No match takes no points."),
        fact_card("Facts behind the penalty: regulatory checks", legal.get("checks") or []),
    ])


def render_score(fund):
    blocks = []
    for part in fund["parts"]:
        sid = part["id"]
        nsrc = len(fund["evidence"].get(sid, {}).get("sources") or [])
        srcl = f"Sources ({nsrc}) →" if nsrc else "Sources →"
        blocks.append(
            f'<div class="scb {esc(part["cardClass"])}" id="sc-{esc(sid)}" data-ws="{esc(sid)}">'
            f'<div class="scbh"><span class="wl"><i></i>{esc(part["name"])}</span>'
            f'<span class="scbar"><b style="width:{esc(part["scoreBar"])}"></b></span>'
            f'<span class="wv"><b>{esc(part["got"])}</b><small>{esc(part["maxLabel"])}</small></span></div>'
            f'<p class="wr"><span>@@s:build.rule@@</span>{esc(part["rule"])}</p>'
            f'<div class="wih"><span>@@s:build.input@@</span><span style="text-align:right">@@s:page.scoring.points@@</span><span>@@s:build.why@@</span></div>'
            f'<div class="wt">{score_inputs(part)}</div>'
            f'<button class="lnk sm2" data-ev="{esc(sid)}">{srcl}</button></div>'
        )
    return f'<div class="scbs">{"".join(blocks)}</div><p class="note">{esc(fund["scoreFooter"])}</p>'


def render_regulatory(reg, matters=None):
    icons = {"ok": "✓", "am": "!", "gy": "i", "red": "!"}
    known = set(matters or {})
    buttons = []
    for rec in reg["records"]:
        detail = "@@s:report.regulatory.see_matter@@" if rec.get("ev") in known else rec["detail"]
        buttons.append(
            f'<button class="rr" data-ev="{esc(rec["ev"])}">'
            f'<i class="ri {esc(rec["icon"])}">{icons[rec["icon"]]}</i>'
            f'<span><b>{esc(rec["title"])}</b><small>{esc(detail)}</small></span>'
            f'<span class="lr"><span class="rt {esc(rec["tone"])}">{esc(rec["points"])}</span>'
            f'<span class="chev">›</span></span></button>'
        )
    sanc = reg["sanctions"]
    if sanc.get("ok", True):
        sanc_html = (
            f'<div class="sanc ok"><i class="ri ok big">✓</i><div><b>{esc(sanc["title"])}</b>'
            f'<span>{esc(sanc["text"])}</span></div>'
            f'<button class="lnk" data-ev="{esc(sanc["ev"])}">{esc(sanc["link"])}</button></div>'
        )
        if sanc.get("note"):
            sanc_html += f'<p class="note">{esc(sanc["note"])}</p>'
    else:
        sanc_html = (
            f'<div class="sanc bad"><i class="ri red">!</i><div><b>{esc(sanc["title"])}</b>'
            f'<span>{esc(sanc.get("text", ""))}</span></div></div>'
        )
    return (
        f'<div class="pc regc"><div class="ph3"><h3>{esc(reg["title"])}</h3><small>{esc(reg["note"])}</small></div>'
        f'<div class="gg two" style="margin:0"><div><div class="sub">{esc(reg["recordsTitle"])}</div>{"".join(buttons)}</div>'
        f'<div><div class="sub">{esc(reg["sanctionsTitle"])}</div>{sanc_html}</div></div></div>'
    )


def render_legal(fund, matters):
    legal = real_facts(fund).get("legal") or {}
    cases, dup_cases, actions, dup_actions = legal_fact_items(fund)
    checks = legal.get("checks") or []
    screens = legal.get("sanctions") or []
    has_records = bool(matters or cases or actions or penalty_records(fund, matters))
    if not has_records and not checks and not screens and not dup_cases:
        checked = fund.get("updated") or ""
        # Nothing on file. Say so once; no "found nothing" sentence without a recorded check.
        return '<div class="pc emptycard"><p>{{s:report.legal.empty|no_data}}</p></div>'
    parts = [render_regulatory(fund["regulatory"], matters)]
    if not has_records:
        when = legal_checked(fund) or fund.get("updated") or ""
        parts.insert(0, empty_card("@@s:report.legal.empty@@", when))
    for group in fund.get("legalGroups") or []:
        if not matters:
            break
        rows = "".join(leg_row(matters[i]) for i in group["ids"])
        more = ""
        if group.get("more"):
            m = group["more"]
            more_rows = "".join(leg_row(matters[i]) for i in m["ids"])
            more = (
                f'<details class="more"><summary>{esc(m["summary"])} <span>{esc(m["hint"])}</span></summary>'
                f'<div class="lst">{more_rows}</div></details>'
            )
        parts.append(
            f'<div class="pc"><div class="ph3"><h3>{esc(group["title"])}</h3><small>{esc(group["note"])}</small></div>'
            f'<div class="lst">{rows}</div>{more}</div>'
        )
    parts.append(fact_card(
        "Regulator actions", actions + dup_actions,
        "Regulator penalties and settlements found in official releases.",
    ))
    parts.append(fact_card(
        "Court records", cases + dup_cases,
        "Each row says how the fund or its people are named. Our score counts only cases in which the fund sued its own founders; none of these is classed that way, so they are listed, not scored.",
    ))
    parts.append(fact_card("Regulatory checks", checks, "Form ADV disclosure reads and similar checks. A clean read is listed, not scored."))
    parts.append(fact_card(
        f"Sanctions screens ({len(screens)} names)", screens,
        "Each name was checked against the list named in the source. A match needs an exact identity match.",
    ))
    if fund.get("notCounted"):
        bullets = "".join(f"<li>{esc(item)}</li>" for item in fund["notCounted"])
        parts.append(
            f'<div class="pc"><div class="ph3"><h3>{esc(fund["notCountedTitle"])}</h3></div><ul class="mini">{bullets}</ul></div>'
        )
    when = legal_checked(fund)
    if when:
        parts.append(f'<p class="note checked">@@s:build.last_checked@@ {esc(when)}</p>')
    return "".join(parts)


def render_fact_tile(tile):
    return f'<div><div class="k">{esc(tile["k"])}</div><div class="v">{esc(tile["v"])}</div><div class="s">{esc(tile["s"])}</div></div>'


def render_board_item(item):
    badge = ""
    if item.get("badge"):
        badge = f' <span class="rt {esc(item.get("tone", "amber"))}">{esc(item["badge"])}</span>'
    return f'<div class="it"><b>{esc(item["name"])}</b><span>{esc(item["value"])}{badge}</span></div>'


def render_move_item(item):
    return (
        f'<div class="it"><div><b>{esc(item["name"])}</b><div class="sm">{esc(item["role"])}</div></div>'
        f'<span class="rt {esc(item.get("tone", "gray"))}">{esc(item["badge"])}</span></div>'
    )


def render_pair_item(item):
    return f'<div class="it"><b>{esc(item["name"])}</b><span>{esc(item["value"])}</span></div>'


def render_vehicles(vehicles):
    if not vehicles:
        return ""
    def one(item):
        bits = [bit for bit in (str(item.get("vintage") or ""), item.get("kind") or "", item.get("status") or "") if bit]
        size = item.get("size")
        if size not in (None, ""):
            bits.append(str(size))
        return f'<div class="it"><b>{esc(item["name"])}</b><span>{esc(" · ".join(bits))}</span></div>'
    body = join_capped(vehicles, one)
    return (
        f'<div class="pc list" id="vehicles"><div class="ph3"><h3>@@s:build.funds@@</h3>'
        f'<small>{len(vehicles)} vehicle{"" if len(vehicles) == 1 else "s"}</small></div>{body}</div>'
    )


def render_reviews(reviews, checked="", accounts=0):
    if not reviews:
        if accounts:
            return ""
        return '<div class="pc emptycard"><p>{{s:report.founders.empty|no_data}}</p></div>'
    def one(item):
        who = " · ".join(bit for bit in (item.get("founder"), item.get("company"), item.get("partner")) if bit)
        flags = []
        if item.get("firstHand"):
            flags.append("first-hand")
        if item.get("verification"):
            flags.append(item["verification"])
        dims = " ".join(f'{esc(r["dimension"])} {esc(r["score"])}' for r in item.get("ratings") or [])
        return (
            f'<div class="it review"><div><b>{esc(who or "@@s:js.auth.founder@@")}</b>'
            f'<div class="sm">{esc(item.get("body") or "")}</div></div>'
            f'<span class="rt gray">{esc(" · ".join(flags))}</span>'
            f'<span class="sm">{dims}</span></div>'
        )
    visible = reviews[:PAGE_SIZE]
    more = ""
    if len(reviews) > PAGE_SIZE:
        more = (
            f'<button type="button" class="lnk" id="moreReviews" data-page-size="{PAGE_SIZE}">@@s:build.show_more@@</button>'
            f'<p class="note" id="reviewCount">@@s:build.showing@@ {PAGE_SIZE} of {len(reviews)}</p>'
        )
    noun = "review" if len(reviews) == 1 else "reviews"
    return (
        f'<div class="pc list" id="reviews"><div class="ph3"><h3>@@s:common.founder_reviews@@</h3>'
        f'<small>{len(reviews)} {noun}</small></div>'
        f'<div class="lst" id="reviewList">{"".join(one(item) for item in visible)}</div>{more}</div>'
    )


def render_fund_tab(tab, extras=None):
    extras = extras or {}
    facts = "".join(render_fact_tile(t) for t in tab["facts"]) if tab["facts"] else '<p class="empty-state">@@s:build.no_fund_facts_yet@@</p>'
    boards = tab["boards"]
    moves = tab["moves"]
    media = tab["media"]
    board_body = join_capped(boards["items"], render_board_item) if boards["items"] else '<p class="empty-state">@@s:build.no_board_seats_on_file@@</p>'
    move_body = join_capped(moves["items"], render_move_item) if moves["items"] else '<p class="empty-state">@@s:build.no_partner_moves_on_file@@</p>'
    media_body = join_capped(media["items"], render_pair_item) if media["items"] else '<p class="empty-state">@@s:build.no_media_reach_on_file@@</p>'
    return (
        f'<div class="pc"><div class="ph3"><h3>{esc(tab["factsTitle"])}</h3><small>{esc(tab["factsNote"])}</small></div>'
        f'<div class="kv">{facts}</div></div>'
        f'<div class="gg three">'
        f'<div class="pc list"><div class="ph3"><h3>{esc(boards["title"])}</h3></div>'
        f'{board_body}<p class="note">{esc(boards["note"])}</p></div>'
        f'<div class="pc list"><div class="ph3"><h3>{esc(moves["title"])}</h3><small>{esc(moves["note"])}</small></div>'
        f'{move_body}<p class="note">{esc(moves["foot"])}</p></div>'
        f'<div class="pc list"><div class="ph3"><h3>{esc(media["title"])}</h3><small>{esc(media["note"])}</small></div>'
        f'{media_body}<p class="note">{esc(media["foot"])}</p></div>'
        f'</div>'
        f'{render_vehicles(extras.get("vehicles") or [])}'
        f'{render_reviews(extras.get("reviews") or [], (extras or {}).get("checked") or "", len((extras.get("facts") or {}).get("accounts") or []))}'
        f'{render_fund_facts(extras.get("facts") or {})}'
    )


def render_fund_facts(fund_facts):
    return "".join([
        fact_card("Firm identity", fund_facts.get("identity") or [], "From SEC filings."),
        fact_card("Fund facts", fund_facts.get("facts") or []),
        fact_card("People and partner history", fund_facts.get("people") or []),
        fact_card("Partners' outside board seats", fund_facts.get("boards") or []),
        fact_card("Founder accounts on record", fund_facts.get("accounts") or [], "Listed as found. Our score counts founder accounts under its own rules."),
        fact_card("Political activity", fund_facts.get("political") or []),
        fact_card("Registered entities", fund_facts.get("entities") or [], "Fund vehicles and affiliates in SEC EDGAR, GLEIF and company registers."),
        fact_card("Context notes", fund_facts.get("notes") or []),
    ])


def favicon(publisher, domain, prefix):
    initial = esc(publisher[:1])
    icon = ROOT / "assets" / "fav" / f"{domain}.png"
    if icon.exists():
        return (
            f'<span class="fav"><img src="{prefix}assets/fav/{esc(domain)}.png" alt="" '
            f'onerror="this.parentNode.classList.add(\'nofav\');this.remove()"><em>{initial}</em></span>'
        )
    return f'<span class="fav nofav"><em>{initial}</em></span>'


def render_companies(companies):
    if not companies:
        return ""
    def one(item):
        bits = [bit for bit in (item.get("round"), item.get("outcome")) if bit]
        if item.get("lead"):
            bits.append("lead")
        if item.get("board"):
            bits.append("board seat")
        return f'<div class="it"><b>{esc(item["name"])}</b><span>{esc(" · ".join(bits))}</span></div>'
    visible = companies[:PAGE_SIZE]
    more = ""
    if len(companies) > PAGE_SIZE:
        more = (
            f'<button type="button" class="lnk" id="moreCos" data-page-size="{PAGE_SIZE}">@@s:build.show_more@@</button>'
            f'<p class="note" id="coCount">@@s:build.showing@@ {min(PAGE_SIZE, len(companies))} of {len(companies)}</p>'
        )
    noun = "company" if len(companies) == 1 else "companies"
    return (
        f'<div class="pc" id="companies"><div class="ph3"><h3>@@s:build.portfolio_companies@@</h3>'
        f'<small>{len(companies)} {noun}</small></div>'
        f'<div class="lst" id="coList">{"".join(one(item) for item in visible)}</div>{more}</div>'
    )


def render_public(fund, prefix):
    pub = fund["public"]
    items = pub["items"]
    press = (real_facts(fund).get("public") or {}).get("press") or []
    press_card = fact_card("Press found in research", press, "Listed as found, with no sentiment rating.")
    if not items:
        if press:
            return press_card
        return '<div class="pc emptycard"><p>{{s:report.public.empty_all|no_data}}</p></div>'
    visible = items if len(items) <= PAGE_SIZE else items[:PAGE_SIZE]
    cards = []
    for item in visible:
        se = item["sentiment"]
        cards.append(
            f'<a class="pubc" data-sent="{esc(se)}" href="{esc(item["url"])}" target="_blank" rel="noopener" '
            f'title="@@s:report.public.open_source@@ {esc(item["domain"])} @@s:report.public.new_tab@@">'
            f'<span class="pt">{favicon(item["publisher"], item["domain"], prefix)}'
            f'<span class="pn"><b>{esc(item["publisher"])}</b><small>{esc(item["domain"])} · {esc(item["date"])}</small></span>'
            f'<span class="ext" aria-hidden="true">{EXT_SVG}</span></span>'
            f'<span class="ph4">{esc(item["headline"])}</span>'
            f'<span class="sw2"><span class="snt {esc(se)}">{SENT_LABEL[se]}</span><span class="swy">{esc(item["why"])}</span></span>'
            f'<span class="pf"><span class="gt">{esc(item["group"])}</span><span class="open2">{OPEN_SVG}</span></span></a>'
        )
    counts = {k: sum(1 for item in items if item["sentiment"] == k) for k in SENT_LABEL}
    bar = "".join(
        f'<i class="{k}" style="flex:{counts[k]} 0 0" title="{SENT_LABEL[k]}: {counts[k]}"></i>'
        for k in ("pos", "neu", "neg") if counts[k]
    )
    filters = f'<button class="sf on" data-sf="all">@@s:build.all@@ <b>{len(items)}</b></button>' + "".join(
        f'<button class="sf {k}" data-sf="{k}"><i></i>{SENT_LABEL[k]} <b>{counts[k]}</b></button>'
        for k in ("pos", "neu", "neg")
    )
    publishers = len({item["domain"] for item in items})
    pager = ""
    if len(items) > PAGE_SIZE:
        pager = (
            f'<button type="button" class="lnk" id="morePress" data-page-size="{PAGE_SIZE}" data-prefix="{esc(prefix)}">@@s:build.show_more@@</button>'
            f'<p class="note" id="pressCount">@@s:build.showing@@ {PAGE_SIZE} of {len(items)}</p>'
        )
    return (
        f'<div class="pubh"><div><h2 class="h2">{esc(pub["title"])}</h2>'
        f'<p class="note" style="margin-top:4px">{esc(pub["intro"])}</p></div>'
        f'<span class="mi">{len(items)} @@s:build.sources@@ {publishers} publishers</span></div>'
        f'<div class="pc sentc"><div class="sentt"><b>{esc(pub["sentimentTitle"])}</b>'
        f'<span class="note">{esc(pub["sentimentNote"])}</span></div>'
        f'<div class="sbar">{bar}</div><div class="sfl" role="group" aria-label="@@s:build.filter_by_sentiment@@">{filters}</div></div>'
        f'<div class="pubg"{"" if len(items) <= PAGE_SIZE else " id=\"pressList\""}>{"".join(cards)}</div>{pager}<p class="note sempty" hidden>{esc(pub["empty"])}</p>'
        f'{press_card}'
    )


def render_portfolio(port):
    rows = []
    for row in port["events"]:
        rows.append(
            f'<div class="r"><div class="t">{esc(row["label"])}<small>{esc(row["examples"])}</small></div>'
            f'<div class="track"><b style="width:{esc(row["width"])}"></b></div><div class="c">{esc(row["count"])}</div></div>'
        )
    bars = "".join(
        f'<i style="width:{esc(h["pct"])};background:{h["color"]}"></i>' for h in port["health"]
    )
    health_rows = "".join(
        f'<div class="it"><b><span class="sw" style="background:{h["color"]}"></span>{esc(h["label"])}</b><span>{esc(h["pct"])}</span></div>'
        for h in port["health"]
    )
    size = port["size"]
    lit = port["litigation"]
    return (
        f'<div class="gg port"><div class="pc ev"><div class="ph3"><h3>{esc(port["title"])}</h3><small>{esc(port["note"])}</small></div>'
        f'{"".join(rows)}<p class="note">{esc(port["foot"])}</p></div>'
        f'<div class="gg"><div class="pc list"><div class="ph3"><h3>{esc(size["title"])}</h3></div>'
        f'<div class="kpi"><div class="v">{esc(size["value"])}</div><div class="s">{esc(size["text"])}</div></div>'
        f'<div class="ph3" style="margin-top:18px"><h3>{esc(port["healthTitle"])}</h3><small>{esc(port["healthNote"])}</small></div>'
        f'<div class="hstack">{bars}</div>{health_rows}</div>'
        f'<div class="pc"><div class="ph3"><h3>{esc(lit["title"])}</h3></div>'
        f'<div class="kpi"><div class="v">{esc(lit["value"])}</div><div class="s">{esc(lit["text"])}</div></div></div></div></div>'
    )


def render_ask(ask):
    cards = []
    for q in ask["questions"]:
        cards.append(
            f'<div class="askc"><span class="q">{esc(q["n"])}</span><div><h4>{esc(q["title"])}</h4>'
            f'<p>“{esc(q["q"])}”</p></div></div>'
        )
    return (
        f'<div class="askbar"><div><h2 class="h2">{esc(ask["title"])}</h2>'
        f'<p class="note" style="margin-top:4px">{esc(ask["note"])}</p></div>'
        f'<div class="btns"><button class="b w" id="copyq">@@s:build.copy_questions@@</button>'
        f'<button class="b c" id="pdf">@@s:build.download_pdf@@</button></div></div>'
        f'<div class="print-head">{esc(ask["printHead"])}</div>'
        f'<div class="askg">{"".join(cards)}</div>'
    )


def render_score_bars(fund):
    bars = []
    legends = []
    for part in fund["parts"]:
        bars.append(
            f'<button class="sb {esc(part["barClass"])}" data-ev="{esc(part["id"])}" '
            f'style="flex:{esc(part["heroFlex"])} 0 0" aria-label="{esc(part["aria"])}">'
            f'<span class="fill" style="width:{esc(part["heroFill"])}"></span></button>'
        )
        legends.append(
            f'<button data-ev="{esc(part["id"])}" class="{esc(part["legendClass"])}">'
            f'<span><i></i>{esc(part["legend"])}</span>{legend_value(part)}</button>'
        )
    return f'<div class="stk">{"".join(bars)}</div><div class="sleg">{"".join(legends)}</div>'


def render_worked_example(fund):
    return (
        f'<div class="ex"><div class="exh"><div class="big">{esc(fund["scoreExact"])}'
        f'<small>{esc(fund["band"])} @@s:build.coverage_39@@</small></div>'
        f'<div style="flex:1">{render_score_bars(fund)}</div></div>'
        f'{render_score(fund)}</div>'
    )


def header_meta(fund):
    """Location, founded year, and the SEC adviser line. Legal names and token chips stay off this row."""
    chips = [fund["hq"], f'@@s:report.since@@ {fund["since"]}']
    for item in fund.get("meta") or []:
        text = str(item)
        if text.startswith("SEC adviser") or "CRD" in text:
            chips.append(text)
    return chips


def overview_badges(fund):
    """Top pills that stay. Coverage, sanctions, and source badges are not part of the score block."""
    hidden = {"cov", "pen", "rel"}
    kept = []
    for badge in fund.get("badges") or []:
        if badge.get("ev") in hidden:
            continue
        text = badge.get("text") or ""
        if text.startswith(("Coverage ", "Sanctions:", "Sources ")):
            continue
        kept.append(badge)
    return kept


def render_hero(fund):
    lo, hi = fund["range"]
    rank = fund["rank"]
    example = '<span class="ph">example</span>' if rank.get("example") else ""
    badges = []
    for badge in overview_badges(fund):
        badges.append(
            f'<button class="bdg" data-ev="{esc(badge["ev"])}"><i class="dt {esc(badge["icon"])}"></i>{esc(badge["text"])}</button>'
        )
    badge_row = f'<div class="bdgs">{"".join(badges)}</div>' if badges else ""
    shown = esc(fund["scoreShown"])
    return (
        f'<div class="heroW">'
        f'<button class="rankb" data-ev="rank"><i>#{esc(rank["place"])}</i> of {esc(rank["of"])} funds{example}</button>'
        f'<div class="hero"><div>'
        f'<button class="ringBtn" id="ringBtn" aria-label="Score {shown}. See why on the Score tab">'
        f'<div class="ringBox">{ring_svg(fund["scoreExact"])}'
        f'<div class="num"><div><b>{shown}</b><span>@@s:js.gate.out_of_100@@</span></div></div></div></button>'
        f'<span class="bandPill">{esc(fund["band"])}</span>'
        f'<button class="rng" data-ev="range">likely {esc(lo)}–{esc(hi)} ⓘ</button></div>'
        f'<div><div class="q">{esc(fund["question"])}</div><div class="dv">{esc(fund["verdict"])}</div>'
        f'<div class="vsub">{esc(fund["verdictSub"])}</div>'
        f'{badge_row}'
        f'<div class="ovx"><div class="bart"><span>{esc(fund["scoreBarNote"])}</span>'
        f'<button class="lnk" data-ev="rules">@@s:build.how_scoring_works@@</button></div>'
        f'{render_score_bars(fund)}</div>'
        f'</div></div></div>'
    )


def render_fund_page(fund, prefix):
    return apply_strings(_render_fund_page(fund, prefix))


def _render_fund_page(fund, prefix):
    fund = dedupe_founded_sentence(strip_toxy(fund))
    matters = {m["id"]: m for m in fund["matters"]}
    meta = [f'<span class="mi">{esc(item)}</span>' for item in header_meta(fund)]
    n_legal = legal_count(fund, matters)
    n_public = len(fund["public"]["items"]) + len((real_facts(fund).get("public") or {}).get("press") or [])

    def tab_button(key, label, count=None):
        zero = ' class="zero"' if count == 0 else ""
        badge = f" <i>{count}</i>" if count is not None else ""
        return f'<button data-tab="{key}"{zero} role="tab">{label}{badge}</button>'

    tab_html = "".join([
        tab_button("overview", "@@s:js.gate.overview@@"),
        tab_button("score", "@@s:page.scoring.score@@"),
        tab_button("legal", "@@s:common.legal@@", n_legal),
        tab_button("fund", "@@s:report.tab.fund@@"),
        tab_button("public", "@@s:js.gate.public@@", n_public),
        tab_button("portfolio", "@@s:js.gate.portfolio@@"),
        tab_button("ask", "@@s:js.gate.ask_the_fund@@"),
    ])
    panels = {
        "overview": render_overview(fund, matters),
        "score": render_score(fund) + render_score_facts(fund),
        "legal": render_legal(fund, matters),
        "fund": render_fund_tab(fund["fundTab"], {"vehicles": fund.get("vehicles"), "reviews": fund.get("reviews"), "checked": fund.get("updated") or "", "facts": real_facts(fund).get("fund") or {}}),
        "public": render_public(fund, prefix),
        "portfolio": render_portfolio(fund["portfolio"]) + render_companies(fund.get("companies") or []),
        "ask": render_ask(fund["ask"]),
    }
    sections = "".join(f'<section data-panel="{k}">{panels[k]}</section>' for k in panels)
    home = prefix
    body = f'''<div class="blobs np" style="height:900px"><div class="blob" style="width:520px;height:520px;background:#CDBBFF;left:-180px;top:-120px"></div><div class="blob" style="width:460px;height:460px;background:#FFC7B8;right:-140px;top:-40px"></div><div class="blob" style="width:380px;height:380px;background:#FFEBA0;left:42%;top:420px;opacity:.35"></div></div>
<nav class="pillnav np"><a class="logo" href="{home}"><img class="lockup" src="{prefix}assets/logo/lockup-light.svg" alt="{BRAND}" width="143" height="36"></a>
 <div class="links"><a class="on" href="{home}">@@s:common.vcs@@</a><a href="{home}scoring/">@@s:common.scoring@@</a><a href="{home}plans/">@@s:common.pricing@@</a><!-- Our Story --></div>
 <div class="r" id="navSlot"><a class="b w" href="{home}login/">@@s:common.log_in@@</a><a class="b v" href="{home}account/#watchlist">@@s:common.get_alerts@@</a></div></nav>
<div class="ftop"><div class="wrap">
 <div class="crumb np"><a href="{home}">@@s:common.all_vcs@@</a></div>
 <div class="fh np"><div><h1>{fund_heading(fund)}<button type="button" class="save" id="save" data-tip="@@s:page.settings.save@@" aria-label="@@s:build.save_to_watchlist@@" aria-pressed="false">{SAVE_SVG}</button></h1>
  {CORRECT_LINE}
  <div class="meta">{"".join(meta)}</div></div>
  <div class="upd">@@s:build.updated@@ {esc(fund["updated"])}<br>{esc(fund["method"])}</div></div>
 <div class="np">{render_hero(fund)}</div>
 <div class="tabsW np"><div class="tabs" role="tablist">{tab_html}</div></div>
 {sections}
 <p class="fnote np">{esc(fund["footnote"])}</p>
</div></div>
<footer class="np"><div class="wrap"><span class="logo"><img class="lockup sm" src="{prefix}assets/logo/lockup-light.svg" alt="{BRAND}" width="111" height="28"></span><span>regretamin.com</span><span style="margin-left:auto"><a href="{home}scoring/">@@s:common.scoring@@</a> · <a href="{home}privacy/">@@s:common.privacy@@</a> · <a href="{home}terms/">@@s:common.terms@@</a></span></div></footer>
<div class="scrim"></div><aside class="drawer" role="dialog" aria-modal="true" aria-label="@@s:build.details@@"><div class="dh"><div><div class="dk" id="dk"></div><div class="dtt" id="dt"></div></div><button class="dx" id="dx" aria-label="@@s:page.settings.close@@">×</button></div><div class="db" id="db"></div></aside><div class="toast"></div>'''
    title = fund.get("title") or f'{fund["name"]} · {BRAND}'
    extra = ""
    companies = fund.get("companies") or []
    reviews = fund.get("reviews") or []
    press = fund.get("public", {}).get("items") or []
    if len(companies) > PAGE_SIZE:
        extra += f'<script id="portfolio-data" type="application/json">{embed(companies)}</script>\n'
    if len(reviews) > PAGE_SIZE:
        extra += f'<script id="review-data" type="application/json">{embed(reviews)}</script>\n'
    if len(press) > PAGE_SIZE:
        extra += f'<script id="press-data" type="application/json">{embed(press)}</script>\n'
    scripts = (
        f'<script id="evidence" type="application/json">{embed(fund["evidence"])}</script>\n'
        f'<script id="ask-copy" type="application/json">{embed(fund["ask"]["clipboard"])}</script>\n'
        f'{extra}'
        f'<script src="{prefix}js/supabase-config.js"></script>'
        f'<script src="{prefix}js/stripe-config.js"></script>'
        f'<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>'
        f'<script src="{prefix}js/auth.js"></script>'
        f'<script src="{prefix}js/gate.js"></script>'
        f'<script src="{prefix}js/fund.js"></script>'
    )
    page = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(title)}</title>
<link rel="icon" href="{prefix}assets/favicon.ico" sizes="any">
<link rel="icon" href="{prefix}assets/favicon.svg" type="image/svg+xml">
<link rel="icon" href="{prefix}assets/logo/favicon-32.png" type="image/png" sizes="32x32">
<link rel="apple-touch-icon" href="{prefix}assets/logo/apple-touch-icon.png">
<link rel="stylesheet" href="{prefix}css/common.css">
<link rel="stylesheet" href="{prefix}css/fund.css">
<link rel="stylesheet" href="{prefix}css/auth.css">
<meta name="regret-root" content="{prefix}">
</head><body data-firm="{esc(fund["slug"])}" data-report="1">
{body}{scripts}</body></html>
'''
    referenced = set()
    # data-ev values are written with esc(), which does not change these ids.
    for token in page.split('data-ev="')[1:]:
        referenced.add(token.split('"', 1)[0])
    missing = sorted(referenced - set(fund["evidence"]))
    if missing:
        raise SystemExit(f'{fund["slug"]}: evidence popup missing for {", ".join(missing)}')
    return page


def build_home(home):
    raw = (SRC / "home.html").read_text(encoding="utf-8")
    if "__HOME_JSON__" not in raw:
        raise SystemExit("src/home.html is missing the __HOME_JSON__ placeholder")
    return raw.replace("__HOME_JSON__", embed(home))


PUBLIC_LIST = 3
DROPPED_UPDATE = "rescored on Toxy Score v2. Empty blocks stay empty."


def public_home(home):
    """What a signed-out visitor is allowed to download.

    The fund table shows the top three by score. The rest are fetched after
    login. The deleted "Ten funds rescored" update stays out, and exact
    duplicate feed rows are dropped.
    """
    ranked = sorted(home["funds"], key=lambda fund: (-float(fund.get("exact") if fund.get("exact") is not None else fund["score"]), fund["name"]))
    seen = set()
    updates = []
    for upd in home["updates"]:
        if DROPPED_UPDATE in (upd.get("t") or ""):
            continue
        key = (upd.get("no"), upd.get("t"), upd.get("u"))
        if key in seen:
            continue
        seen.add(key)
        updates.append(upd)
    return {
        "funds": ranked[:PUBLIC_LIST],
        "fundTotal": len(home["funds"]),
        "stats": home["stats"],
        "updates": updates,
    }


def write_config():
    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_ANON_KEY", "").strip()
    payload = {"url": url, "key": key}
    (SITE / "js" / "supabase-config.js").write_text(
        "window.REGRET_CONFIG=" + json.dumps(payload) + ";\n",
        encoding="utf-8",
    )


def legal_html(value, label, email=False):
    """Empty config stays a yellow placeholder. A real email becomes a mailto link."""
    text = str(value or "").strip()
    if not text:
        return f'<span class="ph">{esc(label)}</span>'
    if email and "@" in text:
        return f'<a href="mailto:{esc(text)}">{esc(text)}</a>'
    return esc(text)


def apply_legal(raw):
    path = DATA / "site.json"
    legal = {}
    if path.exists():
        legal = load_json(path).get("legal") or {}
    company = legal_html(legal.get("company"), "company")
    email = legal_html(legal.get("contact_email"), "contact email", email=True)
    place = legal_html(legal.get("jurisdiction"), "jurisdiction")
    return (
        raw.replace("__COMPANY__", company)
        .replace("__CONTACT_EMAIL__", email)
        .replace("__JURISDICTION__", place)
    )


SCORING_EXAMPLE = "scoring_example"


def scoring_example_html(funds):
    fund = funds.get("a16z")
    if not fund:
        raise SystemExit("scoring page needs the a16z fund report")
    return apply_strings(render_worked_example(fund))


def build_scoring(example_html):
    if not example_html:
        raise SystemExit("scoring page needs the stored scoring example (site_fragments)")
    raw = (SRC / "scoring.html").read_text(encoding="utf-8").replace("__SCORE_EXAMPLE__", example_html)
    dest = SITE / "scoring" / "index.html"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(raw, encoding="utf-8")


def build_shell(name, dest):
    raw = (SRC / name).read_text(encoding="utf-8")
    if "__HOME_JSON__" in raw:
        raise SystemExit(f"{name} should not carry fund data")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(raw, encoding="utf-8")


def build_legal(name, dest):
    raw = apply_legal((SRC / name).read_text(encoding="utf-8"))
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(raw, encoding="utf-8")


def copy_static():
    for folder in ("css", "js"):
        dest = SITE / folder
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(SRC / folder, dest)
    assets = SITE / "assets"
    if assets.exists():
        shutil.rmtree(assets)
    shutil.copytree(ROOT / "assets", assets)
    data_dest = SITE / "data"
    if data_dest.exists():
        shutil.rmtree(data_dest)
    data_dest.mkdir(parents=True)
    # Fund report JSON is not part of the public site. Reports load through open_report.
    for item in DATA.iterdir():
        if item.name == "funds":
            continue
        dest = data_dest / item.name
        if item.is_dir():
            shutil.copytree(item, dest)
        else:
            shutil.copy2(item, dest)
    (SITE / ".nojekyll").write_text("")
    cname = ROOT / "CNAME"
    if cname.exists():
        shutil.copy(cname, SITE / "CNAME")


def load_site():
    """Every page renders from the database. Sources, in order:

    1. SUPABASE_SERVICE_ROLE_KEY: the full published bundle (server-side only).
    2. DATABASE_URL: the same bundle straight from Postgres (tests, local publishing).
    3. SITE_BUNDLE: a published_site_bundle() document saved to a file (deploy stopgap).
    4. SUPABASE_ANON_KEY: the visitor-safe public bundle. Shells and the list only;
       report bodies stay in report_pages.

    Returns (home, funds, fragments, full). There is no hand-written fallback.
    """
    from regrettamine.assemble import assemble_public, assemble_site

    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    db = os.environ.get("DATABASE_URL", "").strip()
    saved = os.environ.get("SITE_BUNDLE", "").strip()
    anon = os.environ.get("SUPABASE_ANON_KEY", "").strip()
    if url and key:
        from regrettamine.supabase_load import fetch_bundle
        print("source: supabase (service role, server-side)")
        bundle = fetch_bundle(url, key)
    elif db:
        from regrettamine.supabase_load import fetch_db_bundle
        print("source: database (DATABASE_URL)")
        bundle = fetch_db_bundle(db)
    elif saved:
        print(f"source: saved database bundle {saved}")
        bundle = load_json(Path(saved))
    elif url and anon:
        from regrettamine.supabase_load import fetch_public_bundle
        print("source: supabase public bundle (anon key)")
        home, funds, fragments = assemble_public(fetch_public_bundle(url, anon))
        return apply_strings_to_data(home), apply_strings_to_data(funds), fragments, False
    else:
        raise SystemExit("No database source: set SUPABASE_URL with a key, DATABASE_URL or SITE_BUNDLE")
    home, funds = assemble_site(bundle)
    return apply_strings_to_data(home), apply_strings_to_data(funds), {}, True


def load_db():
    """Full site data from the database, for tests and tools. Same path as the build."""
    home, funds, _fragments, full = load_site()
    if not full:
        raise SystemExit("load_db needs the full bundle (service key, DATABASE_URL or SITE_BUNDLE)")
    return home, funds


def render_report_payload(fund, prefix):
    """Report body stored in report_pages. Not written into the public HTML."""
    page = render_fund_page(fund, prefix)
    start = page.split('<div class="ftop"><div class="wrap">', 1)[1]
    inner = start.split("<footer", 1)[0]
    inner = inner.rsplit("</div></div>", 1)[0]
    scripts = []
    for marker in ("evidence", "ask-copy", "portfolio-data", "review-data", "press-data"):
        token = f'<script id="{marker}"'
        if token not in page:
            continue
        chunk = page.split(token, 1)[1].split("</script>", 1)[0]
        scripts.append(token + chunk + "</script>")
    return inner + "\n" + "\n".join(scripts)


def render_fund_shell(fund, prefix):
    """Public fund URL. The score line is static. The record stays on the server."""
    fund = strip_toxy(fund)
    home = prefix
    title = f'{fund["name"]} · {BRAND}'
    body = f'''<div class="blobs np" style="height:420px"><div class="blob" style="width:520px;height:520px;background:#CDBBFF;left:-180px;top:-120px"></div><div class="blob" style="width:460px;height:460px;background:#FFC7B8;right:-140px;top:-40px"></div></div>
<nav class="pillnav np"><a class="logo" href="{home}"><img class="lockup" src="{prefix}assets/logo/lockup-light.svg" alt="{BRAND}" width="143" height="36"></a>
 <div class="links"><a class="on" href="{home}">@@s:common.vcs@@</a><a href="{home}scoring/">@@s:common.scoring@@</a><a href="{home}plans/">@@s:common.pricing@@</a><!-- Our Story --></div>
 <div class="r" id="navSlot"><a class="b w" href="{home}login/">@@s:common.log_in@@</a><a class="b v" href="{home}account/#watchlist">@@s:common.get_alerts@@</a></div></nav>
<div class="ftop"><div class="wrap" id="report">
 <div class="crumb np"><a href="{home}">@@s:common.all_vcs@@</a></div>
 <div class="fh np"><div><h1>{fund_heading(fund)}<button type="button" class="save" id="save" data-tip="@@s:page.settings.save@@" aria-label="@@s:build.save_to_watchlist@@" aria-pressed="false">{SAVE_SVG}</button></h1>
  {CORRECT_LINE}</div></div>
 <p class="report-wait">@@s:build.loading_the_report@@</p>
</div></div>
<footer class="np"><div class="wrap"><span class="logo"><img class="lockup sm" src="{prefix}assets/logo/lockup-light.svg" alt="{BRAND}" width="111" height="28"></span><span>regretamin.com</span><span style="margin-left:auto"><a href="{home}scoring/">@@s:common.scoring@@</a> · <a href="{home}privacy/">@@s:common.privacy@@</a> · <a href="{home}terms/">@@s:common.terms@@</a></span></div></footer>
<div class="scrim"></div><aside class="drawer" role="dialog" aria-modal="true" aria-label="@@s:build.details@@"><div class="dh"><div><div class="dk" id="dk"></div><div class="dtt" id="dt"></div></div><button class="dx" id="dx" aria-label="@@s:page.settings.close@@">×</button></div><div class="db" id="db"></div></aside><div class="toast"></div>'''
    scripts = (
        f'<script src="{prefix}js/supabase-config.js"></script>'
        f'<script src="{prefix}js/stripe-config.js"></script>'
        f'<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>'
        f'<script src="{prefix}js/auth.js"></script>'
        f'<script src="{prefix}js/gate.js"></script>'
        f'<script src="{prefix}js/fund.js"></script>'
    )
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(title)}</title>
<link rel="icon" href="{prefix}assets/favicon.ico" sizes="any">
<link rel="icon" href="{prefix}assets/favicon.svg" type="image/svg+xml">
<link rel="icon" href="{prefix}assets/logo/favicon-32.png" type="image/png" sizes="32x32">
<link rel="apple-touch-icon" href="{prefix}assets/logo/apple-touch-icon.png">
<link rel="stylesheet" href="{prefix}css/common.css">
<link rel="stylesheet" href="{prefix}css/fund.css">
<link rel="stylesheet" href="{prefix}css/auth.css">
<meta name="regret-root" content="{prefix}">
</head><body data-firm="{esc(fund["slug"])}" data-report="1">
{body}{scripts}</body></html>
'''


def publish_report_pages(funds, fragments=None):
    """Rewrite every stored report. Pull requests skip this so they cannot replace production."""
    if os.environ.get("REPORT_PUBLISH", "").strip() != "1":
        print("report pages: not uploaded (REPORT_PUBLISH is not 1)")
        return
    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not (url and key):
        print("report pages: not uploaded (service role key is not set)")
        return
    from regrettamine.supabase_load import store_report
    errors = []
    for slug, fund in funds.items():
        html = apply_strings(render_report_payload(fund, "../../"))
        try:
            store_report(url, key, slug, html)
        except Exception as exc:
            errors.append(f"{slug}: {exc}")
            continue
        print(f"stored report {slug}")
    from regrettamine.supabase_load import store_fragment
    for frag_key, html in (fragments or {}).items():
        try:
            store_fragment(url, key, frag_key, html)
        except Exception as exc:
            errors.append(f"fragment {frag_key}: {exc}")
    if errors:
        raise SystemExit("report upload failed: " + "; ".join(errors))


def assign_list_ranks(funds):
    """Same order as the landing list: higher shown score first, then name."""
    ranked = sorted(
        funds.values(),
        # Exact (unrounded) score first; the name only breaks true ties.
        key=lambda fund: (-float(fund.get("scoreExact") if fund.get("scoreExact") is not None else fund.get("scoreShown") or 0), fund.get("name") or ""),
    )
    total = len(ranked)
    rows = []
    for fund in ranked:
        exact = fund.get("scoreExact")
        label = f"{float(exact):.1f}" if isinstance(exact, (int, float)) else str(exact or "")
        rows.append([fund.get("name") or "", label])
    for place, fund in enumerate(ranked, start=1):
        rank = dict(fund.get("rank") or {})
        rank["place"] = place
        rank["of"] = total
        fund["rank"] = rank
        card = (fund.get("evidence") or {}).get("rank")
        if not isinstance(card, dict):
            continue
        card["title"] = f"#{place} of {total}"
        card["body"] = _RANK_V2.sub("", card.get("body") or "")
        card["rows"] = [list(row) for row in rows]


def main():
    if SITE.exists():
        shutil.rmtree(SITE)
    SITE.mkdir(parents=True)
    home, funds, fragments, full = load_site()
    home = strip_toxy(home)
    if full:
        assign_list_ranks(funds)
        fragments = dict(fragments, **{SCORING_EXAMPLE: scoring_example_html(funds)})
    linked = [f.get("report") for f in home["funds"] if f.get("report")]
    missing = [slug for slug in linked if slug not in funds]
    if missing:
        raise SystemExit("the list links reports the database does not have: " + ", ".join(missing))
    public = public_home(home)
    (SITE / "index.html").write_text(build_home(public), encoding="utf-8")
    account = (SRC / "account.html").read_text(encoding="utf-8").replace("__HOME_JSON__", embed(public))
    (SITE / "account").mkdir(parents=True, exist_ok=True)
    (SITE / "account" / "index.html").write_text(account, encoding="utf-8")
    alerts = SITE / "account" / "alerts" / "index.html"
    alerts.parent.mkdir(parents=True, exist_ok=True)
    alerts.write_text(
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta http-equiv="refresh" content="0;url=../#watchlist">'
        '<link rel="canonical" href="../#watchlist">'
        '<title>@@s:build.watchlist@@ ' + BRAND + '</title>'
        '<script>location.replace("../#watchlist")</script></head>'
        '<body><p><a href="../#watchlist">@@s:common.watchlist@@</a></p></body></html>\n',
        encoding="utf-8",
    )
    build_shell("login.html", SITE / "login" / "index.html")
    build_shell("reset.html", SITE / "login" / "reset" / "index.html")
    build_legal("privacy.html", SITE / "privacy" / "index.html")
    build_legal("terms.html", SITE / "terms" / "index.html")
    build_shell("how.html", SITE / "how" / "index.html")
    build_shell("reset-redirect.html", SITE / "reset" / "index.html")
    build_shell("plans.html", SITE / "plans" / "index.html")
    build_shell("settings.html", SITE / "settings" / "index.html")
    build_shell("admin.html", SITE / "admin" / "index.html")
    build_shell("deleted.html", SITE / "deleted" / "index.html")
    not_found = SITE / "404.html"
    not_found.write_text((SRC / "404.html").read_text(encoding="utf-8"), encoding="utf-8")
    build_scoring(fragments.get(SCORING_EXAMPLE))
    for slug, fund in funds.items():
        dest = SITE / "vc" / slug / "index.html"
        dest.parent.mkdir(parents=True, exist_ok=True)
        # Two levels under the site root: /vc/<slug>/. Body comes from open_report.
        dest.write_text(render_fund_shell(fund, "../../"), encoding="utf-8")
        print(f"built /vc/{slug}/")
    if full:
        publish_report_pages(funds, fragments)
    copy_static()
    (SITE / "data" / "home.json").write_text(
        json.dumps(public, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    write_config()
    apply_strings_to_site()
    print(f"built {SITE} ({len(list(SITE.rglob('*')))} files)")


if __name__ == "__main__":
    sys.exit(main() or 0)
