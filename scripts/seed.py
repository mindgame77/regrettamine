#!/usr/bin/env python3
"""Load data/home.json and every data/funds/<slug>.json report into Postgres.

Nothing is invented. Vehicles, portfolio companies, reviews, filings, and
docket entries stay empty for the real firms: the source files do not list
them. People, entities, matters, press, scores, and sources are the ones
named in those files.

Usage:
    DATABASE_URL=postgresql:///regrettamine python3 scripts/seed.py
"""
import json
import os
import re
import sys
import uuid
from datetime import date
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from regrettamine.score_v2 import A16Z_SCORE_INPUTS  # noqa: E402

MONTHS = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}


def uid():
    return str(uuid.uuid4())


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def month_date(text):
    match = re.search(
        r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{4})",
        text or "",
        re.I,
    )
    if not match:
        return None
    return date(int(match.group(2)), MONTHS[match.group(1)[:3].lower()], 1)


def full_date(text):
    match = re.search(
        r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{1,2}),\s+(\d{4})",
        text or "",
        re.I,
    )
    if not match:
        return None
    return date(int(match.group(3)), MONTHS[match.group(1)[:3].lower()], int(match.group(2)))


def points_from_badge(badge):
    match = re.search(r"[−-](\d+(?:\.\d+)?)", badge or "")
    if match:
        return -float(match.group(1)) if "." in match.group(1) else -int(match.group(1))
    if re.search(r"\b0\b", badge or ""):
        return 0
    return None


def domain_of(url):
    host = urlparse(url).netloc.lower()
    if host.startswith("www."):
        host = host[4:]
    return host


class Loader:
    def __init__(self, cur):
        self.cur = cur
        self.sources = {}

    def add(self, table, **cols):
        keys = list(cols)
        sql = f"insert into {table} ({', '.join(keys)}) values ({', '.join(['%s'] * len(keys))})"
        self.cur.execute(sql, [cols[key] for key in keys])
        return cols.get("id")

    def source(self, url, publisher=None, verified=True):
        if url in self.sources:
            return self.sources[url]
        source_id = uid()
        self.add(
            "sources",
            id=source_id,
            url=url,
            publisher=publisher,
            domain=domain_of(url),
            verified=verified,
            junk=False,
        )
        self.sources[url] = source_id
        return source_id

    def cite(self, source_id, firm_id, fact_type, fact_id, label, sort_order):
        self.add(
            "fact_sources",
            id=uid(),
            source_id=source_id,
            firm_id=firm_id,
            fact_type=fact_type,
            fact_id=fact_id,
            label=label,
            sort_order=sort_order,
        )


def reset(cur):
    cur.execute(
        """
        truncate table
          public.firms,
          public.people,
          public.portfolio_companies,
          public.sources,
          public.legal_matters,
          public.press_items,
          public.site_stats,
          public.site_updates,
          public.fact_events
        restart identity cascade
        """
    )


def seed_home(loader, home, firm_ids, version_ids):
    for index, row in enumerate(home["funds"]):
        firm_id = uid()
        firm_ids[row["id"]] = firm_id
        loader.add(
            "firms",
            id=firm_id,
            slug=row["id"],
            name=row["name"],
            initials=row["ini"],
            short_name=row.get("short"),
            hq=row["hq"],
            metro=row["metro"],
            founded_year=row["since"],
            firm_type=row["type"],
            aum_billions=row["aum"],
            aum_display=json.dumps(row["aum"]),
            aum_as_of=row["aumAsOf"],
            aum_stale=row["aumStale"],
            aum_source=row["aumSrc"],
            list_score=row["score"],
            list_band=row["band"],
            list_v2=row["v2"],
            list_range_low=row.get("lo"),
            list_range_high=row.get("hi"),
            list_previous_score=row.get("old"),
            list_coverage=row.get("cov"),
            list_verdict=row.get("verdict"),
            list_legal_active=row["legal"],
            legal_note=row["legalNote"],
            updated_on=row["updated"],
            updated_ts=row["updatedTs"],
            updated_label=row["updatedS"],
            report_slug=row.get("report"),
            list_sort=index,
            published=True,
            is_test=False,
        )
        if not row.get("report"):
            loader.add(
                "score_results",
                id=uid(),
                firm_id=firm_id,
                version_id=version_ids["legacy-list"],
                total=row["score"],
                total_shown=row["score"],
                band=row["band"],
                is_current=True,
                computed_at=row["updatedTs"],
            )
    for index, stat in enumerate(home["stats"]):
        loader.add(
            "site_stats",
            id=uid(),
            sort_order=index,
            n=stat["n"],
            label=stat["l"],
            detail=stat["s"],
            verified=stat["v"],
            unverified_label=stat.get("u"),
        )
    seen_updates = set()
    sort_order = 0
    for upd in home["updates"]:
        # The owner deleted the three duplicate "Ten funds rescored" rows.
        # Skip that entry even if a future data file puts it back, and skip
        # any other exact duplicate so seeding stays idempotent.
        if "rescored on Toxy Score v2. Empty blocks stay empty." in (upd.get("t") or ""):
            continue
        key = (upd.get("no"), upd.get("t"), upd.get("u"))
        if key in seen_updates:
            continue
        seen_updates.add(key)
        loader.add(
            "site_updates",
            id=uid(),
            sort_order=sort_order,
            update_no=upd["no"],
            happened_on=upd["d"],
            happened_label=upd["ds"],
            firm_id=firm_ids.get(upd["fid"]) if upd.get("fid") else None,
            firm_name=upd["f"],
            kind=upd["k"],
            body=upd["t"],
            source_name=upd["src"],
            url=upd["u"],
            verification=upd["v"],
        )
        sort_order += 1


def copy_block(loader, firm_id, key, body, sort_order):
    if body is None:
        return
    loader.add(
        "copy_blocks",
        id=uid(),
        firm_id=firm_id,
        block_key=key,
        body=body,
        sort_order=sort_order,
    )


def seed_report(loader, fund, firm_id, version_ids, score_inputs, old_score, computed_at, checked_on):
    blocks = {
        "page_title": fund["title"],
        "not_token": fund["notToken"],
        "updated_display": fund["updated"],
        "method_label": fund["method"],
        "question": fund["question"],
        "verdict": fund["verdict"],
        "verdict_sub": fund["verdictSub"],
        "summary": fund["summary"],
        "footnote": fund["footnote"],
        "score_footer": fund["scoreFooter"],
        "score_bar_note": fund["scoreBarNote"],
        "not_counted_title": fund["notCountedTitle"],
        "regulatory_title": fund["regulatory"]["title"],
        "regulatory_note": fund["regulatory"]["note"],
        "regulatory_records_title": fund["regulatory"]["recordsTitle"],
        "sanctions_title": fund["regulatory"]["sanctionsTitle"],
        "fund_facts_title": fund["fundTab"]["factsTitle"],
        "fund_facts_note": fund["fundTab"]["factsNote"],
        "boards_title": fund["fundTab"]["boards"]["title"],
        "boards_note": fund["fundTab"]["boards"]["note"],
        "moves_title": fund["fundTab"]["moves"]["title"],
        "moves_note": fund["fundTab"]["moves"]["note"],
        "moves_foot": fund["fundTab"]["moves"]["foot"],
        "media_title": fund["fundTab"]["media"]["title"],
        "media_note": fund["fundTab"]["media"]["note"],
        "media_foot": fund["fundTab"]["media"]["foot"],
        "public_title": fund["public"]["title"],
        "public_intro": fund["public"]["intro"],
        "public_sentiment_title": fund["public"]["sentimentTitle"],
        "public_sentiment_note": fund["public"]["sentimentNote"],
        "public_empty": fund["public"]["empty"],
        "portfolio_title": fund["portfolio"]["title"],
        "portfolio_note": fund["portfolio"]["note"],
        "portfolio_foot": fund["portfolio"]["foot"],
        "portfolio_size_title": fund["portfolio"]["size"]["title"],
        "portfolio_size_value": fund["portfolio"]["size"]["value"],
        "portfolio_size_text": fund["portfolio"]["size"]["text"],
        "portfolio_health_title": fund["portfolio"]["healthTitle"],
        "portfolio_health_note": fund["portfolio"]["healthNote"],
        "portfolio_lit_title": fund["portfolio"]["litigation"]["title"],
        "portfolio_lit_value": fund["portfolio"]["litigation"]["value"],
        "portfolio_lit_text": fund["portfolio"]["litigation"]["text"],
        "ask_title": fund["ask"]["title"],
        "ask_note": fund["ask"]["note"],
        "ask_print_head": fund["ask"]["printHead"],
        "ask_clipboard": fund["ask"]["clipboard"],
    }
    for index, (key, body) in enumerate(blocks.items()):
        copy_block(loader, firm_id, key, body, index)

    for index, label in enumerate(fund["meta"]):
        loader.add("firm_meta_items", id=uid(), firm_id=firm_id, kind="meta", sort_order=index, label=label)
    for index, label in enumerate(fund["notCounted"]):
        loader.add("firm_meta_items", id=uid(), firm_id=firm_id, kind="not_counted", sort_order=index, label=label)

    rank = fund["rank"]
    loader.add(
        "firm_ranks",
        id=uid(),
        firm_id=firm_id,
        place=rank["place"],
        tier=rank["tier"],
        of_count=rank["of"],
        is_example=rank["example"],
        is_current=True,
    )
    for index, chip in enumerate(fund["floats"]):
        loader.add(
            "page_chips",
            id=uid(),
            firm_id=firm_id,
            slot="float",
            sort_order=index,
            css_class=chip["class"],
            evidence_key=chip["ev"],
            icon_bg=chip["iconBg"],
            icon=chip["icon"],
            label=chip["text"],
            small_label=chip["small"],
        )
    for index, chip in enumerate(fund["badges"]):
        loader.add(
            "page_chips",
            id=uid(),
            firm_id=firm_id,
            slot="badge",
            sort_order=index,
            evidence_key=chip["ev"],
            icon=chip["icon"],
            label=chip["text"],
        )

    # Entities named in the report. No vehicle list is in the source, so funds stays empty.
    if fund["slug"] == "a16z":
        loader.add(
            "fund_entities",
            id=uid(),
            firm_id=firm_id,
            name="AH Capital Management, L.L.C.",
            entity_kind="adviser",
            crd="160489",
            notes="SEC adviser · CRD 160489",
            sort_order=0,
        )
        loader.add(
            "fund_entities",
            id=uid(),
            firm_id=firm_id,
            name="a16z Capital Management",
            entity_kind="management",
            notes="Named in the Oct 2, 2026 sanctions screen",
            sort_order=1,
        )
    else:
        crd = ""
        for label in fund.get("meta") or []:
            match = re.search(r"CRD\s+(\d+)", label)
            if match:
                crd = match.group(1)
        legal_name = fund["meta"][1] if len(fund.get("meta") or []) > 1 else fund["name"]
        loader.add(
            "fund_entities",
            id=uid(),
            firm_id=firm_id,
            name=legal_name,
            entity_kind="adviser",
            crd=crd or None,
            notes=fund["meta"][0] if fund.get("meta") else None,
            sort_order=0,
        )

    people = {}

    def person(name):
        if name not in people:
            people[name] = uid()
            loader.add("people", id=people[name], full_name=name)
        return people[name]

    for index, item in enumerate(fund["fundTab"]["boards"]["items"]):
        person_id = person(item["name"])
        loader.add(
            "fund_people",
            id=uid(),
            person_id=person_id,
            firm_id=firm_id,
            role="Partner, board seat",
            notes=item["value"],
            sort_order=index,
        )
        loader.add(
            "list_items",
            id=uid(),
            firm_id=firm_id,
            group_key="boards",
            sort_order=index,
            name=item["name"],
            value=item["value"],
            badge=item.get("badge"),
            tone=item.get("tone"),
        )
    for index, item in enumerate(fund["fundTab"]["moves"]["items"]):
        person_id = person(item["name"])
        when = month_date(item.get("badge"))
        badge = item.get("badge") or ""
        start = when if badge.lower().startswith("joined") else None
        end = when if not badge.lower().startswith("joined") else None
        loader.add(
            "fund_people",
            id=uid(),
            person_id=person_id,
            firm_id=firm_id,
            role=item["role"],
            start_date=start,
            end_date=end,
            date_precision="month" if when else None,
            notes=badge,
            sort_order=100 + index,
        )
        loader.add(
            "list_items",
            id=uid(),
            firm_id=firm_id,
            group_key="moves",
            sort_order=index,
            name=item["name"],
            role_text=item["role"],
            badge=item.get("badge"),
            tone=item.get("tone"),
        )
    # Named in the a16z sanctions note as a GP. No start date is given.
    if fund["slug"] == "a16z":
        person("Anne Neuberger")
        loader.add(
            "fund_people",
            id=uid(),
            person_id=people["Anne Neuberger"],
            firm_id=firm_id,
            role="GP",
            notes="Named on Russia and Iran counter-sanctions lists for a former White House role. Not a Western sanction.",
            sort_order=200,
        )

    for index, tile in enumerate(fund["fundTab"]["facts"]):
        loader.add(
            "list_items",
            id=uid(),
            firm_id=firm_id,
            group_key="facts",
            sort_order=index,
            name=tile["k"],
            value=tile["v"],
            note=tile["s"],
        )
    for index, tile in enumerate(fund["fundTab"]["media"]["items"]):
        loader.add(
            "list_items",
            id=uid(),
            firm_id=firm_id,
            group_key="media",
            sort_order=index,
            name=tile["name"],
            value=tile["value"],
        )

    for index, event in enumerate(fund["portfolio"]["events"]):
        loader.add(
            "portfolio_metrics",
            id=uid(),
            firm_id=firm_id,
            metric_kind="event",
            sort_order=index,
            label=event["label"],
            examples=event["examples"],
            width_label=event["width"],
            count_label=event["count"],
        )
    for index, sliver in enumerate(fund["portfolio"]["health"]):
        loader.add(
            "portfolio_metrics",
            id=uid(),
            firm_id=firm_id,
            metric_kind="health",
            sort_order=index,
            label=sliver["label"],
            value_text=sliver["pct"],
            color=sliver["color"],
        )

    evidence_ids = {}
    for index, (key, card) in enumerate(fund["evidence"].items()):
        card_id = uid()
        evidence_ids[key] = card_id
        loader.add(
            "evidence_cards",
            id=card_id,
            firm_id=firm_id,
            evidence_key=key,
            kicker=card.get("kicker") or "",
            title=card.get("title") or "",
            body=card.get("body") or "",
            tone=card.get("tone") or "",
            sort_order=index,
        )
        for line_index, pair in enumerate(card.get("rows") or []):
            loader.add(
                "evidence_lines",
                id=uid(),
                card_id=card_id,
                sort_order=line_index,
                label=pair[0],
                value=pair[1],
            )
        for source_index, pair in enumerate(card.get("sources") or []):
            source_id = loader.source(pair[1])
            loader.cite(source_id, firm_id, "evidence_card", card_id, pair[0], source_index)

    matter_ids = {}
    role_by_matter = {}
    for key, card in fund["evidence"].items():
        if not key.startswith("L"):
            continue
        role = {}
        for label, value in card.get("rows") or []:
            role[label] = value
        role_by_matter[key] = role
    featured = {matter_id: index + 1 for index, matter_id in enumerate(fund["topLegal"])}
    for index, matter in enumerate(fund["matters"]):
        matter_id = uid()
        matter_ids[matter["id"]] = matter_id
        loader.add(
            "legal_matters",
            id=matter_id,
            source_key=matter["id"],
            title=matter["sub"],
        )
        role = role_by_matter.get(matter["id"], {})
        party_role = next((value for label, value in role.items() if label.endswith(" role")), None)
        points = points_from_badge(matter["badge"])
        link_id = uid()
        loader.add(
            "legal_matter_firms",
            id=link_id,
            matter_id=matter_id,
            firm_id=firm_id,
            party_role=party_role,
            status=role.get("Status"),
            counted=points not in (None, 0),
            relevance=role.get("Founder relevance"),
            points=points,
            year_label=matter["year"],
            summary=matter["text"],
            detail=matter["sub"],
            badge=matter["badge"],
            tone=matter["tone"],
            sort_order=index,
            featured_rank=featured.get(matter["id"]),
            evidence_key=matter["id"],
        )
        if party_role:
            loader.add(
                "legal_matter_parties",
                id=uid(),
                matter_id=matter_id,
                name=fund["name"],
                party_role=party_role,
                firm_id=firm_id,
                sort_order=0,
            )
        if role.get("Other party"):
            loader.add(
                "legal_matter_parties",
                id=uid(),
                matter_id=matter_id,
                name=role["Other party"],
                party_role="other",
                sort_order=1,
            )
        card_id = evidence_ids.get(matter["id"])
        if card_id:
            for source_index, pair in enumerate(fund["evidence"][matter["id"]].get("sources") or []):
                loader.cite(loader.source(pair[1]), firm_id, "legal_matter", matter_id, pair[0], source_index)

    for index, group in enumerate(fund["legalGroups"]):
        group_id = uid()
        loader.add(
            "legal_groups",
            id=group_id,
            firm_id=firm_id,
            title=group["title"],
            note=group["note"],
            sort_order=index,
        )
        for item_index, evidence_key in enumerate(group["ids"]):
            loader.add(
                "legal_group_items",
                id=uid(),
                group_id=group_id,
                evidence_key=evidence_key,
                sort_order=item_index,
            )
        more = group.get("more")
        if more:
            more_id = uid()
            loader.add(
                "legal_groups",
                id=more_id,
                firm_id=firm_id,
                parent_id=group_id,
                summary=more["summary"],
                hint=more["hint"],
                sort_order=0,
            )
            for item_index, evidence_key in enumerate(more["ids"]):
                loader.add(
                    "legal_group_items",
                    id=uid(),
                    group_id=more_id,
                    evidence_key=evidence_key,
                    sort_order=item_index,
                )

    for index, record in enumerate(fund["regulatory"]["records"]):
        record_id = uid()
        loader.add(
            "regulatory_records",
            id=record_id,
            firm_id=firm_id,
            title=record["title"],
            detail=record["detail"],
            points=points_from_badge(record["points"]),
            icon=record["icon"],
            tone=record["tone"],
            points_label=record["points"],
            evidence_key=record["ev"],
            sort_order=index,
        )
        card = fund["evidence"].get(record["ev"]) or {}
        for source_index, pair in enumerate(card.get("sources") or []):
            loader.cite(loader.source(pair[1]), firm_id, "regulatory_record", record_id, pair[0], source_index)

    sanctions = fund["regulatory"]["sanctions"]
    sanctions_id = uid()
    loader.add(
        "sanctions_checks",
        id=sanctions_id,
        firm_id=firm_id,
        checked_on=checked_on,
        result="no_match" if sanctions.get("ok") else "match",
        exact_identity_match=False,
        points=0,
        title=sanctions["title"],
        detail=sanctions["text"],
        note=sanctions.get("note"),
        is_clear=sanctions.get("ok", False),
        evidence_key=sanctions["ev"],
        link_label=sanctions.get("link"),
        sort_order=0,
    )
    card = fund["evidence"].get(sanctions["ev"]) or {}
    for source_index, pair in enumerate(card.get("sources") or []):
        loader.cite(loader.source(pair[1]), firm_id, "sanctions_check", sanctions_id, pair[0], source_index)

    for index, item in enumerate(fund["public"]["items"]):
        press_id = uid()
        loader.add(
            "press_items",
            id=press_id,
            publisher=item["publisher"],
            domain=item["domain"],
            url=item["url"],
            published_on=full_date(item["date"]),
            published_label=item["date"],
            headline=item["headline"],
            sentiment=item["sentiment"],
            why=item["why"],
            group_label=item["group"],
            sort_order=index,
        )
        loader.add(
            "press_item_firms",
            press_item_id=press_id,
            firm_id=firm_id,
            sort_order=index,
        )
        source_id = loader.source(item["url"], publisher=item["publisher"])
        loader.cite(source_id, firm_id, "press_item", press_id, item["publisher"], 0)

    takeaway_ids = {}
    for index, takeaway in enumerate(fund["takeaways"]):
        takeaway_id = uid()
        takeaway_ids[takeaway["ev"]] = takeaway_id
        loader.add(
            "takeaways",
            id=takeaway_id,
            firm_id=firm_id,
            sort_order=index,
            title=takeaway["title"],
            body=takeaway["text"],
            evidence_key=takeaway["ev"],
        )
        for source_index, pair in enumerate((fund["evidence"].get(takeaway["ev"]) or {}).get("sources") or []):
            loader.cite(loader.source(pair[1]), firm_id, "takeaway", takeaway_id, pair[0], source_index)

    for index, question in enumerate(fund["ask"]["questions"]):
        loader.add(
            "ask_questions",
            id=uid(),
            firm_id=firm_id,
            sort_order=index,
            number_label=question["n"],
            title=question["title"],
            question=question["q"],
        )

    # History: the old list score, then the current v2 result.
    if old_score is not None:
        loader.add(
            "score_results",
            id=uid(),
            firm_id=firm_id,
            version_id=version_ids["legacy-list"],
            total=old_score,
            total_shown=old_score,
            is_current=False,
        )
    result_id = uid()
    coverage = None
    for chip in fund.get("floats") or []:
        if chip.get("ev") == "cov":
            match = re.search(r"(\d+)", chip.get("text") or "")
            if match:
                coverage = int(match.group(1))
    loader.add(
        "score_results",
        id=result_id,
        firm_id=firm_id,
        version_id=version_ids["v2"],
        total=fund["scoreExact"],
        total_shown=fund["scoreShown"],
        band=fund["band"],
        range_low=fund["range"][0],
        range_high=fund["range"][1],
        coverage_pct=coverage,
        confidence=f"likely {fund['range'][0]}–{fund['range'][1]}",
        is_current=True,
        computed_at=computed_at,
    )
    part_ids = {}
    for index, part in enumerate(fund["parts"]):
        part_id = uid()
        part_ids[part["id"]] = part_id
        loader.add(
            "score_result_parts",
            id=part_id,
            result_id=result_id,
            section_code=part["id"],
            sort_order=index,
            name=part["name"],
            legend=part["legend"],
            got=part["got"],
            max_label=part["maxLabel"],
            legend_of=part.get("legendOf"),
            rule_text=part["rule"],
            aria=part["aria"],
            card_class=part["cardClass"],
            bar_class=part["barClass"],
            legend_class=part["legendClass"],
            hero_flex=part["heroFlex"],
            hero_fill=part["heroFill"],
            score_bar=part["scoreBar"],
        )
        for line_index, line in enumerate(part["inputs"]):
            loader.add(
                "score_lines",
                id=uid(),
                result_id=result_id,
                section_code=part["id"],
                sort_order=line_index,
                name=line["name"],
                points_label=line["points"],
                why=line["why"],
            )
        card = fund["evidence"].get(part["id"]) or {}
        for source_index, pair in enumerate(card.get("sources") or []):
            loader.cite(loader.source(pair[1]), firm_id, "score_result", part_id, pair[0], source_index)
    for index, row in enumerate(score_inputs):
        loader.add(
            "score_inputs",
            id=uid(),
            result_id=result_id,
            section_code=row["section_code"],
            sort_order=index,
            name=row["name"],
            value_numeric=row.get("value_numeric"),
            value_text=row.get("value_text"),
            max_numeric=row.get("max_numeric"),
        )


def seed_report_bundles(cur):
    """Store the rendered report body. open_report reads it; the site build does not upload it."""
    from build import render_report_payload

    cur.execute("select id, slug from firms where published and not is_test")
    rows = cur.fetchall()
    for firm_id, slug in rows:
        path = ROOT / "data" / "funds" / f"{slug}.json"
        if not path.exists():
            continue
        html = render_report_payload(load(path), "../../")
        cur.execute(
            """
            insert into report_bundles (firm_id, payload)
            values (%s, jsonb_build_object('html', %s::text))
            on conflict (firm_id) do update
              set payload = excluded.payload, updated_at = now()
            """,
            (firm_id, html),
        )


def main():
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        sys.exit("DATABASE_URL is required, for example postgresql:///regrettamine")
    import psycopg

    home = load(ROOT / "data" / "home.json")
    score_inputs = load(ROOT / "data" / "score_inputs.json")
    with psycopg.connect(url) as conn:
        with conn.cursor() as cur:
            reset(cur)
            cur.execute("select code, id from score_versions")
            version_ids = {code: str(version_id) for code, version_id in cur.fetchall()}
            loader = Loader(cur)
            firm_ids = {}
            seed_home(loader, home, firm_ids, version_ids)
            for row in home["funds"]:
                if not row.get("report"):
                    continue
                fund = load(ROOT / "data" / "funds" / f"{row['report']}.json")
                inputs = A16Z_SCORE_INPUTS if row["report"] == "a16z" else score_inputs[row["report"]]
                computed_at = "2026-10-02T00:00:00-07:00" if row["report"] == "a16z" else row["updatedTs"]
                checked_on = date(2026, 10, 2) if row["report"] == "a16z" else date(2026, 10, 4)
                seed_report(
                    loader,
                    fund,
                    firm_ids[row["id"]],
                    version_ids,
                    inputs,
                    row.get("old"),
                    computed_at,
                    checked_on,
                )
            seed_report_bundles(cur)
        conn.commit()
    print(f"seeded {len(home['funds'])} firms, {sum(1 for row in home['funds'] if row.get('report'))} reports, {len(home['updates'])} updates")


if __name__ == "__main__":
    main()
