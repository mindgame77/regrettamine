#!/usr/bin/env python3
"""Build the Regretamine static site into ./site.

Source of truth:
  data/home.json          fund list, stats, updates
  data/funds/<slug>.json  a full report

No third-party dependencies. Internal links are relative, so the same
output works at a GitHub project URL (/regrettamine/) and at regretamine.com.
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
ALERT_LINE = '<div class="alert-line"><div class="tog" id="alertTog" role="switch" aria-checked="false"><span>Alerts</span><span class="sw2"></span></div><p class="fnote" id="alertNote" hidden>Open this report to get alerts</p><a class="lnk" id="correctLink" hidden>Request a correction</a></div>'
SENT_LABEL = {"pos": "Positive", "neu": "Neutral", "neg": "Negative"}
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
        + f'<details class="more"><summary>Show more <span>{len(items) - limit} more</span></summary>'
        + f'<div class="lst">{tail}</div></details>'
    )


def render_takeaways(fund):
    cards = []
    for i, tk in enumerate(fund["takeaways"]):
        cards.append(
            f'<button class="tkc t{i % 5}" data-ev="{esc(tk["ev"])}">'
            f'<span class="ix">{i + 1:02d}</span><h4>{esc(tk["title"])}</h4><p>{esc(tk["text"])}</p>'
            f'<span class="src"><span>{esc(source_line(fund, tk["ev"]))}</span>'
            f'<span class="open">Evidence →</span></span></button>'
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
        text = value.replace("Toxy Score v2", "Regretamine score")
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
    when = f'<p class="checked">Last checked {esc(checked)}</p>' if checked else ""
    return f'<div class="pc emptycard"><p>{esc(sentence)}</p>{when}</div>'


def render_overview(fund, matters):
    grouped = grouped_matter_ids(fund)
    top = "".join(leg_row(matters[i]) for i in fund["topLegal"] if i not in grouped)
    n = len(matters)
    if fund["takeaways"]:
        take_block = (
            f'<div class="sech"><h2 class="h2">Takeaways</h2><small>Click any card to see the evidence</small></div>'
            f'<div class="tkg tk6">{render_takeaways(fund)}</div>'
        )
    else:
        take_block = (
            '<div class="sech"><h2 class="h2">Takeaways</h2></div>'
            '<p class="empty-state">No takeaways yet.</p>'
        )
    if n:
        rows = f'<div class="pc lstc"><div class="lst">{top}</div></div>' if top else ''
        legal_block = (
            f'<div class="sech"><h2 class="h2">Top legal matters</h2>'
            f'<button class="lnk" data-go="legal">See all {n} →</button></div>'
            f'{rows}'
        )
    else:
        legal_block = (
            '<div class="sech"><h2 class="h2">Top legal matters</h2></div>'
            '<p class="empty-state">No legal matters on file.</p>'
        )
    summary = fund.get("summary") or ""
    if summary:
        summary_block = f'<div class="blk sumb"><div class="lab">Summary</div><div><p class="big clamp5">{esc(summary)}</p></div></div>'
    else:
        summary_block = '<p class="empty-state">No summary yet.</p>'
    return summary_block + take_block + legal_block


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
            f'<p class="wr"><span>Rule</span>{esc(part["rule"])}</p>'
            f'<div class="wih"><span>Input</span><span style="text-align:right">Points</span><span>Why</span></div>'
            f'<div class="wt">{score_inputs(part)}</div>'
            f'<button class="lnk sm2" data-ev="{esc(sid)}">{srcl}</button></div>'
        )
    return f'<div class="scbs">{"".join(blocks)}</div><p class="note">{esc(fund["scoreFooter"])}</p>'


def render_regulatory(reg, matters=None):
    icons = {"ok": "✓", "am": "!", "gy": "i", "red": "!"}
    known = set(matters or {})
    buttons = []
    for rec in reg["records"]:
        detail = "See the matter on this tab." if rec.get("ev") in known else rec["detail"]
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
    if not matters:
        return empty_card(
            "No data yet. We found no court cases, regulator actions or sanctions for this fund.",
            fund.get("updated") or "",
        )
    parts = [render_regulatory(fund["regulatory"], matters)]
    for group in fund["legalGroups"]:
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
    bullets = "".join(f"<li>{esc(item)}</li>" for item in fund["notCounted"])
    parts.append(
        f'<div class="pc"><div class="ph3"><h3>{esc(fund["notCountedTitle"])}</h3></div><ul class="mini">{bullets}</ul></div>'
    )
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
        f'<div class="pc list" id="vehicles"><div class="ph3"><h3>Funds</h3>'
        f'<small>{len(vehicles)} vehicle{"" if len(vehicles) == 1 else "s"}</small></div>{body}</div>'
    )


def render_reviews(reviews, checked=""):
    if not reviews:
        return empty_card("No data yet. We found no founder accounts for this fund.", checked)
    def one(item):
        who = " · ".join(bit for bit in (item.get("founder"), item.get("company"), item.get("partner")) if bit)
        flags = []
        if item.get("firstHand"):
            flags.append("first-hand")
        if item.get("verification"):
            flags.append(item["verification"])
        dims = " ".join(f'{esc(r["dimension"])} {esc(r["score"])}' for r in item.get("ratings") or [])
        return (
            f'<div class="it review"><div><b>{esc(who or "Founder")}</b>'
            f'<div class="sm">{esc(item.get("body") or "")}</div></div>'
            f'<span class="rt gray">{esc(" · ".join(flags))}</span>'
            f'<span class="sm">{dims}</span></div>'
        )
    visible = reviews[:PAGE_SIZE]
    more = ""
    if len(reviews) > PAGE_SIZE:
        more = (
            f'<button type="button" class="lnk" id="moreReviews" data-page-size="{PAGE_SIZE}">Show more</button>'
            f'<p class="note" id="reviewCount">Showing {PAGE_SIZE} of {len(reviews)}</p>'
        )
    noun = "review" if len(reviews) == 1 else "reviews"
    return (
        f'<div class="pc list" id="reviews"><div class="ph3"><h3>Founder reviews</h3>'
        f'<small>{len(reviews)} {noun}</small></div>'
        f'<div class="lst" id="reviewList">{"".join(one(item) for item in visible)}</div>{more}</div>'
    )


def render_fund_tab(tab, extras=None):
    extras = extras or {}
    facts = "".join(render_fact_tile(t) for t in tab["facts"]) if tab["facts"] else '<p class="empty-state">No fund facts yet.</p>'
    boards = tab["boards"]
    moves = tab["moves"]
    media = tab["media"]
    board_body = join_capped(boards["items"], render_board_item) if boards["items"] else '<p class="empty-state">No board seats on file.</p>'
    move_body = join_capped(moves["items"], render_move_item) if moves["items"] else '<p class="empty-state">No partner moves on file.</p>'
    media_body = join_capped(media["items"], render_pair_item) if media["items"] else '<p class="empty-state">No media reach on file.</p>'
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
        f'{render_reviews(extras.get("reviews") or [], (extras or {}).get("checked") or "")}'
    )


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
            f'<button type="button" class="lnk" id="moreCos" data-page-size="{PAGE_SIZE}">Show more</button>'
            f'<p class="note" id="coCount">Showing {min(PAGE_SIZE, len(companies))} of {len(companies)}</p>'
        )
    noun = "company" if len(companies) == 1 else "companies"
    return (
        f'<div class="pc" id="companies"><div class="ph3"><h3>Portfolio companies</h3>'
        f'<small>{len(companies)} {noun}</small></div>'
        f'<div class="lst" id="coList">{"".join(one(item) for item in visible)}</div>{more}</div>'
    )


def render_public(fund, prefix):
    pub = fund["public"]
    items = pub["items"]
    if not items:
        return empty_card(
            "No data yet. We found no press for this fund.",
            fund.get("updated") or "",
        )
    visible = items if len(items) <= PAGE_SIZE else items[:PAGE_SIZE]
    cards = []
    for item in visible:
        se = item["sentiment"]
        cards.append(
            f'<a class="pubc" data-sent="{esc(se)}" href="{esc(item["url"])}" target="_blank" rel="noopener" '
            f'title="Open source on {esc(item["domain"])} (new tab)">'
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
    filters = f'<button class="sf on" data-sf="all">All <b>{len(items)}</b></button>' + "".join(
        f'<button class="sf {k}" data-sf="{k}"><i></i>{SENT_LABEL[k]} <b>{counts[k]}</b></button>'
        for k in ("pos", "neu", "neg")
    )
    publishers = len({item["domain"] for item in items})
    pager = ""
    if len(items) > PAGE_SIZE:
        pager = (
            f'<button type="button" class="lnk" id="morePress" data-page-size="{PAGE_SIZE}" data-prefix="{esc(prefix)}">Show more</button>'
            f'<p class="note" id="pressCount">Showing {PAGE_SIZE} of {len(items)}</p>'
        )
    return (
        f'<div class="pubh"><div><h2 class="h2">{esc(pub["title"])}</h2>'
        f'<p class="note" style="margin-top:4px">{esc(pub["intro"])}</p></div>'
        f'<span class="mi">{len(items)} sources · {publishers} publishers</span></div>'
        f'<div class="pc sentc"><div class="sentt"><b>{esc(pub["sentimentTitle"])}</b>'
        f'<span class="note">{esc(pub["sentimentNote"])}</span></div>'
        f'<div class="sbar">{bar}</div><div class="sfl" role="group" aria-label="Filter by sentiment">{filters}</div></div>'
        f'<div class="pubg"{"" if len(items) <= PAGE_SIZE else " id=\"pressList\""}>{"".join(cards)}</div>{pager}<p class="note sempty" hidden>{esc(pub["empty"])}</p>'
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
        f'<div class="btns"><button class="b w" id="copyq">Copy questions</button>'
        f'<button class="b c" id="pdf">Download PDF</button></div></div>'
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
        f'<small>{esc(fund["band"])} · coverage 39%</small></div>'
        f'<div style="flex:1">{render_score_bars(fund)}</div></div>'
        f'{render_score(fund)}</div>'
    )


def render_hero(fund):
    lo, hi = fund["range"]
    rank = fund["rank"]
    example = '<span class="ph">example</span>' if rank.get("example") else ""
    floats = []
    for fl in fund["floats"]:
        floats.append(
            f'<button class="float {esc(fl["class"])} ovx" data-ev="{esc(fl["ev"])}">'
            f'<i style="background:{fl["iconBg"]}">{fl["icon"]}</i>{esc(fl["text"])} <small>{esc(fl["small"])}</small></button>'
        )
    badges = []
    for b in fund["badges"]:
        badges.append(
            f'<button class="bdg" data-ev="{esc(b["ev"])}"><i class="dt {esc(b["icon"])}"></i>{esc(b["text"])}</button>'
        )
    shown = esc(fund["scoreShown"])
    return (
        f'<div class="heroW">'
        f'<button class="rankb" data-ev="rank"><i>#{esc(rank["place"])}</i> of {esc(rank["of"])} funds{example}</button>'
        f'{"".join(floats)}'
        f'<div class="hero"><div>'
        f'<button class="ringBtn" id="ringBtn" aria-label="Score {shown}. See why on the Score tab">'
        f'<div class="ringBox">{ring_svg(fund["scoreExact"])}'
        f'<div class="num"><div><b>{shown}</b><span>out of 100</span></div></div></div></button>'
        f'<span class="bandPill">{esc(fund["band"])}</span>'
        f'<button class="rng" data-ev="range">likely {esc(lo)}–{esc(hi)} ⓘ</button></div>'
        f'<div><div class="q">{esc(fund["question"])}</div><div class="dv">{esc(fund["verdict"])}</div>'
        f'<div class="vsub">{esc(fund["verdictSub"])}</div>'
        f'<div class="bdgs">{"".join(badges)}</div>'
        f'<div class="ovx"><div class="bart"><span>{esc(fund["scoreBarNote"])}</span>'
        f'<button class="lnk" data-ev="rules">How scoring works</button></div>'
        f'{render_score_bars(fund)}</div>'
        f'</div></div></div>'
    )


def render_fund_page(fund, prefix):
    fund = dedupe_founded_sentence(strip_toxy(fund))
    matters = {m["id"]: m for m in fund["matters"]}
    meta = [f'<span class="mi">{esc(fund["hq"])}</span>', f'<span class="mi">Since {esc(fund["since"])}</span>']
    meta += [f'<span class="mi">{esc(item)}</span>' for item in fund["meta"]]
    if fund.get("notToken"):
        meta.append(f'<span class="mi y">{esc(fund["notToken"])}</span>')
    n_legal = len(matters)
    n_public = len(fund["public"]["items"])

    def tab_button(key, label, count=None):
        zero = ' class="zero"' if count == 0 else ""
        badge = f" <i>{count}</i>" if count is not None else ""
        return f'<button data-tab="{key}"{zero} role="tab">{label}{badge}</button>'

    tab_html = "".join([
        tab_button("overview", "Overview"),
        tab_button("score", "Score"),
        tab_button("legal", "Legal", n_legal),
        tab_button("fund", "Fund &amp; people"),
        tab_button("public", "Public", n_public),
        tab_button("portfolio", "Portfolio"),
        tab_button("ask", "Ask the fund"),
    ])
    panels = {
        "overview": render_overview(fund, matters),
        "score": render_score(fund),
        "legal": render_legal(fund, matters),
        "fund": render_fund_tab(fund["fundTab"], {"vehicles": fund.get("vehicles"), "reviews": fund.get("reviews"), "checked": fund.get("updated") or ""}),
        "public": render_public(fund, prefix),
        "portfolio": render_portfolio(fund["portfolio"]) + render_companies(fund.get("companies") or []),
        "ask": render_ask(fund["ask"]),
    }
    sections = "".join(f'<section data-panel="{k}">{panels[k]}</section>' for k in panels)
    home = prefix
    body = f'''<div class="blobs np" style="height:900px"><div class="blob" style="width:520px;height:520px;background:#CDBBFF;left:-180px;top:-120px"></div><div class="blob" style="width:460px;height:460px;background:#FFC7B8;right:-140px;top:-40px"></div><div class="blob" style="width:380px;height:380px;background:#FFEBA0;left:42%;top:420px;opacity:.35"></div></div>
<nav class="pillnav np"><a class="logo" href="{home}"><i></i><span class="wm">regret<em>amine</em></span></a>
 <div class="links"><a class="on" href="{home}">VCs</a><a href="{home}scoring/">Scoring</a><a href="{home}plans/">Pricing</a><!-- Our Story --></div>
 <div class="r" id="navSlot"><a class="b w" href="{home}login/">Log in</a><a class="b v" href="{home}account/#watchlist">Get alerts</a></div></nav>
<div class="ftop"><div class="wrap">
 <div class="crumb np"><a href="{home}">← All VCs</a></div>
 <div class="fh np"><div><h1>{fund_heading(fund)}<button type="button" class="save" id="save" data-tip="Save" aria-label="Save to watchlist" aria-pressed="false">{SAVE_SVG}</button></h1>
  {ALERT_LINE}
  <div class="meta">{"".join(meta)}</div></div>
  <div class="upd">Updated {esc(fund["updated"])}<br>{esc(fund["method"])}</div></div>
 <div class="np">{render_hero(fund)}</div>
 <div class="tabsW np"><div class="tabs" role="tablist">{tab_html}</div></div>
 {sections}
 <p class="fnote np">{esc(fund["footnote"])}</p>
</div></div>
<footer class="np"><div class="wrap"><span class="logo" style="font-size:17px;color:var(--ink)"><i style="width:22px;height:22px;border-radius:7px"></i><span class="wm">regret<em>amine</em></span></span><span>regretamine.com</span><span style="margin-left:auto"><a href="{home}scoring/">Scoring</a> · <a href="{home}privacy/">Privacy</a> · <a href="{home}terms/">Terms</a></span></div></footer>
<div class="scrim"></div><aside class="drawer" role="dialog" aria-modal="true" aria-label="Details"><div class="dh"><div><div class="dk" id="dk"></div><div class="dtt" id="dt"></div></div><button class="dx" id="dx" aria-label="Close">×</button></div><div class="db" id="db"></div></aside><div class="toast"></div>'''
    title = fund.get("title") or f'{fund["name"]} · Regretamine'
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
<link rel="icon" href="{prefix}assets/favicon.svg">
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
    ranked = sorted(home["funds"], key=lambda fund: (-fund["score"], fund["name"]))
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


def build_scoring(funds):
    fund = funds.get("a16z")
    if not fund:
        raise SystemExit("scoring page needs the a16z fund report")
    raw = (SRC / "scoring.html").read_text(encoding="utf-8").replace("__SCORE_EXAMPLE__", render_worked_example(fund))
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


def load_local():
    home = load_json(DATA / "home.json")
    funds = {}
    for path in sorted((DATA / "funds").glob("*.json")):
        fund = load_json(path)
        slug = fund.get("slug")
        if slug != path.stem:
            raise SystemExit(f"{path.name}: slug {slug!r} must match the filename")
        funds[slug] = fund
    return home, funds


def load_site():
    """Full catalog for the build. The service role key never goes into the site."""
    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if url and key:
        from regrettamine.supabase_load import load_site as load_remote
        print("source: supabase (service role, server-side)")
        return load_remote(url, key)
    if os.environ.get("SUPABASE_ANON_KEY", "").strip():
        print("source: json (SUPABASE_SERVICE_ROLE_KEY is not set; the anon key cannot read the full bundle)")
    else:
        print("source: json")
    return load_local()


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
    title = f'{fund["name"]} · Regretamine'
    body = f'''<div class="blobs np" style="height:420px"><div class="blob" style="width:520px;height:520px;background:#CDBBFF;left:-180px;top:-120px"></div><div class="blob" style="width:460px;height:460px;background:#FFC7B8;right:-140px;top:-40px"></div></div>
<nav class="pillnav np"><a class="logo" href="{home}"><i></i><span class="wm">regret<em>amine</em></span></a>
 <div class="links"><a class="on" href="{home}">VCs</a><a href="{home}scoring/">Scoring</a><a href="{home}plans/">Pricing</a><!-- Our Story --></div>
 <div class="r" id="navSlot"><a class="b w" href="{home}login/">Log in</a><a class="b v" href="{home}account/#watchlist">Get alerts</a></div></nav>
<div class="ftop"><div class="wrap" id="report">
 <div class="crumb np"><a href="{home}">← All VCs</a></div>
 <div class="fh np"><div><h1>{fund_heading(fund)}<button type="button" class="save" id="save" data-tip="Save" aria-label="Save to watchlist" aria-pressed="false">{SAVE_SVG}</button></h1>
  {ALERT_LINE}</div></div>
 <p class="report-wait">Loading the report…</p>
</div></div>
<footer class="np"><div class="wrap"><span class="logo" style="font-size:17px;color:var(--ink)"><i style="width:22px;height:22px;border-radius:7px"></i><span class="wm">regret<em>amine</em></span></span><span>regretamine.com</span><span style="margin-left:auto"><a href="{home}scoring/">Scoring</a> · <a href="{home}privacy/">Privacy</a> · <a href="{home}terms/">Terms</a></span></div></footer>
<div class="scrim"></div><aside class="drawer" role="dialog" aria-modal="true" aria-label="Details"><div class="dh"><div><div class="dk" id="dk"></div><div class="dtt" id="dt"></div></div><button class="dx" id="dx" aria-label="Close">×</button></div><div class="db" id="db"></div></aside><div class="toast"></div>'''
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
<link rel="icon" href="{prefix}assets/favicon.svg">
<link rel="stylesheet" href="{prefix}css/common.css">
<link rel="stylesheet" href="{prefix}css/fund.css">
<link rel="stylesheet" href="{prefix}css/auth.css">
<meta name="regret-root" content="{prefix}">
</head><body data-firm="{esc(fund["slug"])}" data-report="1">
{body}{scripts}</body></html>
'''


def publish_report_pages(funds):
    """Rewrite every stored report. Pull requests skip this so they cannot replace production."""
    if os.environ.get("REPORT_PUBLISH", "").strip() != "1":
        print("report pages: not uploaded (REPORT_PUBLISH is not 1)")
        return
    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not (url and key):
        raise SystemExit("REPORT_PUBLISH=1 but the service role key is missing")
    from regrettamine.supabase_load import store_report
    errors = []
    for slug, fund in funds.items():
        html = render_report_payload(fund, "../../")
        try:
            store_report(url, key, slug, html)
        except Exception as exc:
            errors.append(f"{slug}: {exc}")
            continue
        print(f"stored report {slug}")
    if errors:
        raise SystemExit("report upload failed: " + "; ".join(errors))


def assign_list_ranks(funds):
    """Same order as the landing list: higher shown score first, then name."""
    ranked = sorted(
        funds.values(),
        key=lambda fund: (-int(fund.get("scoreShown") or 0), fund.get("name") or ""),
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
    home, funds = load_site()
    home = strip_toxy(home)
    assign_list_ranks(funds)
    linked = [f.get("report") for f in home["funds"] if f.get("report")]
    missing = [slug for slug in linked if slug not in funds]
    if missing:
        raise SystemExit("home.json links reports that have no data file: " + ", ".join(missing))
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
        '<title>Watchlist · Regretamine</title>'
        '<script>location.replace("../#watchlist")</script></head>'
        '<body><p><a href="../#watchlist">Watchlist</a></p></body></html>\n',
        encoding="utf-8",
    )
    build_shell("login.html", SITE / "login" / "index.html")
    build_shell("reset.html", SITE / "login" / "reset" / "index.html")
    build_legal("privacy.html", SITE / "privacy" / "index.html")
    build_legal("terms.html", SITE / "terms" / "index.html")
    build_shell("how.html", SITE / "how" / "index.html")
    build_shell("plans.html", SITE / "plans" / "index.html")
    build_shell("settings.html", SITE / "settings" / "index.html")
    build_shell("admin.html", SITE / "admin" / "index.html")
    build_shell("deleted.html", SITE / "deleted" / "index.html")
    not_found = SITE / "404.html"
    not_found.write_text((SRC / "404.html").read_text(encoding="utf-8"), encoding="utf-8")
    build_scoring(funds)
    for slug, fund in funds.items():
        dest = SITE / "vc" / slug / "index.html"
        dest.parent.mkdir(parents=True, exist_ok=True)
        # Two levels under the site root: /vc/<slug>/. Body comes from open_report.
        dest.write_text(render_fund_shell(fund, "../../"), encoding="utf-8")
        print(f"built /vc/{slug}/")
    publish_report_pages(funds)
    copy_static()
    (SITE / "data" / "home.json").write_text(
        json.dumps(public, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    write_config()
    print(f"built {SITE} ({len(list(SITE.rglob('*')))} files)")


if __name__ == "__main__":
    sys.exit(main() or 0)
