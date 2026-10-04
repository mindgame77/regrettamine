"""Turn a published_site_bundle() document into the site's JSON shapes.

The shapes match data/home.json and data/funds/<slug>.json. Empty collections
that the approved a16z page does not show (portfolio companies, reviews,
vehicles) are omitted, so a firm with none of them renders the current page.
"""


def _by(rows, key):
    grouped = {}
    for row in rows or []:
        grouped.setdefault(row.get(key), []).append(row)
    return grouped


def _sort(rows, *keys):
    return sorted(rows or [], key=lambda row: tuple(row.get(key) if row.get(key) is not None else 0 for key in keys))


def _whole(value):
    if value is None:
        return None
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, str):
        return value
    try:
        number = float(value)
    except (TypeError, ValueError):
        return value
    if number.is_integer():
        return int(number)
    return number


def _copy_map(blocks):
    return {block["block_key"]: block["body"] for block in blocks or [] if block.get("fund_id") is None}


def _version_code(bundle, version_id):
    for version in bundle.get("score_versions") or []:
        if version["id"] == version_id:
            return version["code"]
    return None


def assemble_home(bundle):
    firms = _sort(bundle.get("firms"), "list_sort", "slug")
    funds = []
    for firm in firms:
        row = {
            "id": firm["slug"],
            "name": firm["name"],
            "ini": firm["initials"],
            "hq": firm["hq"],
            "metro": firm["metro"],
            "since": int(firm["founded_year"]),
            "type": firm["firm_type"],
            "aum": _aum(firm["aum_display"]),
            "aumAsOf": firm["aum_as_of"],
            "aumStale": bool(firm["aum_stale"]),
            "aumSrc": firm["aum_source"],
            "score": int(firm["list_score"]),
            "v2": bool(firm["list_v2"]),
            "band": firm["list_band"],
            "legal": int(firm["list_legal_active"]),
            "legalNote": firm["legal_note"],
            "updated": firm["updated_on"] if isinstance(firm["updated_on"], str) else _date(firm["updated_on"]),
            "updatedTs": firm["updated_ts"],
            "updatedS": firm["updated_label"],
        }
        if firm.get("short_name"):
            row["short"] = firm["short_name"]
        if firm.get("list_previous_score") is not None:
            row["old"] = int(firm["list_previous_score"])
        if firm.get("list_range_low") is not None:
            row["lo"] = int(firm["list_range_low"])
        if firm.get("list_range_high") is not None:
            row["hi"] = int(firm["list_range_high"])
        if firm.get("list_coverage") is not None:
            row["cov"] = int(firm["list_coverage"])
        if firm.get("list_verdict"):
            row["verdict"] = firm["list_verdict"]
        # `report` stays last, matching data/home.json, so the embedded JSON matches.
        row["report"] = firm.get("report_slug")
        funds.append(row)
    stats = []
    for stat in _sort(bundle.get("site_stats"), "sort_order"):
        item = {
            "n": _whole(stat["n"]),
            "l": stat["label"],
            "s": stat["detail"],
            "v": bool(stat["verified"]),
        }
        if stat.get("unverified_label"):
            item["u"] = stat["unverified_label"]
        stats.append(item)
    slug_by_id = {firm["id"]: firm["slug"] for firm in firms}
    updates = []
    for upd in _sort(bundle.get("site_updates"), "sort_order"):
        updates.append({
            "d": upd["happened_on"] if isinstance(upd["happened_on"], str) else _date(upd["happened_on"]),
            "ds": upd["happened_label"],
            "f": upd["firm_name"],
            "fid": slug_by_id.get(upd.get("firm_id"), "") or "",
            "k": upd["kind"],
            "t": upd["body"],
            "src": upd["source_name"],
            "u": upd["url"],
            "v": upd["verification"],
            "no": int(upd["update_no"]),
        })
    return {"funds": funds, "stats": stats, "updates": updates}


def _date(value):
    if value is None:
        return None
    text = str(value)
    return text[:10]


def _aum(display):
    import json
    return json.loads(display)


def _firm_rows(bundle, table, firm_id):
    return [row for row in bundle.get(table) or [] if row.get("firm_id") == firm_id]


def assemble_fund(bundle, firm):
    firm_id = firm["id"]
    copy = _copy_map(_firm_rows(bundle, "copy_blocks", firm_id))
    versions = {row["id"]: row["code"] for row in bundle.get("score_versions") or []}
    results = [
        row for row in _firm_rows(bundle, "score_results", firm_id)
        if row.get("is_current") and row.get("fund_id") is None and versions.get(row["version_id"]) == "v2"
    ]
    if not results:
        raise ValueError(f"{firm['slug']}: no current firm-level v2 score")
    result = results[0]
    parts = [row for row in bundle.get("score_result_parts") or [] if row["result_id"] == result["id"]]
    lines = [row for row in bundle.get("score_lines") or [] if row["result_id"] == result["id"]]
    lines_by_section = _by(lines, "section_code")
    part_objs = []
    for part in _sort(parts, "sort_order"):
        section_lines = _sort(lines_by_section.get(part["section_code"]), "sort_order")
        part_objs.append({
            "id": part["section_code"],
            "cardClass": part["card_class"],
            "barClass": part["bar_class"],
            "legendClass": part["legend_class"],
            "name": part["name"],
            "legend": part["legend"],
            "got": part["got"],
            "maxLabel": part["max_label"],
            "legendOf": part["legend_of"],
            "heroFlex": part["hero_flex"],
            "heroFill": part["hero_fill"],
            "scoreBar": part["score_bar"],
            "aria": part["aria"],
            "rule": part["rule_text"],
            "inputs": [
                {"name": line["name"], "points": line["points_label"], "why": line["why"]}
                for line in section_lines
            ],
        })

    matter_links = _sort(_firm_rows(bundle, "legal_matter_firms", firm_id), "sort_order")
    matters = [
        {
            "id": link["evidence_key"],
            "year": link["year_label"],
            "text": link["summary"],
            "sub": link["detail"],
            "badge": link["badge"],
            "tone": link["tone"],
        }
        for link in matter_links
    ]
    featured = [link for link in matter_links if link.get("featured_rank") is not None]
    featured.sort(key=lambda link: link["featured_rank"])

    groups = _firm_rows(bundle, "legal_groups", firm_id)
    items_by_group = _by(bundle.get("legal_group_items"), "group_id")
    top_groups = [group for group in groups if group.get("parent_id") is None]
    legal_groups = []
    for group in _sort(top_groups, "sort_order"):
        entry = {
            "title": group["title"],
            "note": group["note"],
            "ids": [item["evidence_key"] for item in _sort(items_by_group.get(group["id"]), "sort_order")],
        }
        children = [child for child in groups if child.get("parent_id") == group["id"]]
        if children:
            child = _sort(children, "sort_order")[0]
            entry["more"] = {
                "summary": child["summary"],
                "hint": child["hint"],
                "ids": [item["evidence_key"] for item in _sort(items_by_group.get(child["id"]), "sort_order")],
            }
        legal_groups.append(entry)

    records = []
    for record in _sort(_firm_rows(bundle, "regulatory_records", firm_id), "sort_order"):
        records.append({
            "icon": record["icon"],
            "title": record["title"],
            "detail": record["detail"],
            "points": record["points_label"],
            "tone": record["tone"],
            "ev": record["evidence_key"],
        })
    checks = _sort(_firm_rows(bundle, "sanctions_checks", firm_id), "sort_order")
    sanctions = {}
    if checks:
        check = checks[0]
        sanctions = {
            "ok": bool(check["is_clear"]),
            "title": check["title"],
            "text": check["detail"],
            "ev": check["evidence_key"],
            "link": check["link_label"],
            "note": check["note"],
        }

    def items(group_key):
        return _sort(
            [row for row in _firm_rows(bundle, "list_items", firm_id) if row["group_key"] == group_key and row.get("fund_id") is None],
            "sort_order",
        )

    facts = [{"k": row["name"], "v": row["value"], "s": row["note"]} for row in items("facts")]
    boards = []
    for row in items("boards"):
        item = {"name": row["name"], "value": row["value"]}
        if row.get("badge"):
            item["badge"] = row["badge"]
        if row.get("tone"):
            item["tone"] = row["tone"]
        boards.append(item)
    moves = []
    for row in items("moves"):
        item = {"name": row["name"], "role": row["role_text"], "badge": row["badge"]}
        if row.get("tone"):
            item["tone"] = row["tone"]
        moves.append(item)
    media = [{"name": row["name"], "value": row["value"]} for row in items("media")]

    press_by_id = {row["id"]: row for row in bundle.get("press_items") or []}
    press_links = _sort(
        [row for row in bundle.get("press_item_firms") or [] if row["firm_id"] == firm_id],
        "sort_order",
    )
    public_items = []
    for link in press_links:
        item = press_by_id[link["press_item_id"]]
        public_items.append({
            "publisher": item["publisher"],
            "domain": item["domain"],
            "date": item["published_label"],
            "headline": item["headline"],
            "url": item["url"],
            "group": item["group_label"],
            "sentiment": item["sentiment"],
            "why": item["why"],
        })

    metrics = [row for row in _firm_rows(bundle, "portfolio_metrics", firm_id) if row.get("fund_id") is None]
    events = []
    health = []
    for metric in _sort(metrics, "sort_order"):
        if metric["metric_kind"] == "event":
            events.append({
                "label": metric["label"],
                "examples": metric["examples"],
                "width": metric["width_label"],
                "count": metric["count_label"],
            })
        elif metric["metric_kind"] == "health":
            health.append({
                "label": metric["label"],
                "pct": metric["value_text"],
                "color": metric["color"],
            })

    questions = [
        {"n": row["number_label"], "title": row["title"], "q": row["question"]}
        for row in _sort(_firm_rows(bundle, "ask_questions", firm_id), "sort_order")
        if row.get("fund_id") is None
    ]
    takeaways = [
        {"ev": row["evidence_key"], "title": row["title"], "text": row["body"]}
        for row in _sort(_firm_rows(bundle, "takeaways", firm_id), "sort_order")
        if row.get("fund_id") is None
    ]

    cards = _firm_rows(bundle, "evidence_cards", firm_id)
    card_ids = {card["id"] for card in cards}
    line_groups = _by(
        [line for line in bundle.get("evidence_lines") or [] if line["card_id"] in card_ids],
        "card_id",
    )
    source_by_id = {row["id"]: row for row in bundle.get("sources") or []}
    fact_groups = _by(
        [row for row in bundle.get("fact_sources") or [] if row.get("firm_id") == firm_id and row["fact_type"] == "evidence_card"],
        "fact_id",
    )
    evidence = {}
    for card in cards:
        evidence[card["evidence_key"]] = {
            "kicker": card["kicker"],
            "title": card["title"],
            "body": card["body"],
            "rows": [[line["label"], line["value"]] for line in _sort(line_groups.get(card["id"]), "sort_order")],
            "sources": [
                [link["label"], source_by_id[link["source_id"]]["url"]]
                for link in _sort(fact_groups.get(card["id"]), "sort_order")
            ],
            "tone": card["tone"] or "",
        }

    chips = _firm_rows(bundle, "page_chips", firm_id)
    floats = []
    badges = []
    for chip in _sort(chips, "sort_order"):
        if chip["slot"] == "float":
            floats.append({
                "class": chip["css_class"],
                "ev": chip["evidence_key"],
                "iconBg": chip["icon_bg"],
                "icon": chip["icon"],
                "text": chip["label"],
                "small": chip["small_label"],
            })
        elif chip["slot"] == "badge":
            badges.append({
                "ev": chip["evidence_key"],
                "icon": chip["icon"],
                "text": chip["label"],
            })

    meta = [row["label"] for row in _sort(_firm_rows(bundle, "firm_meta_items", firm_id), "sort_order") if row["kind"] == "meta"]
    not_counted = [row["label"] for row in _sort(_firm_rows(bundle, "firm_meta_items", firm_id), "sort_order") if row["kind"] == "not_counted"]
    ranks = [row for row in bundle.get("firm_ranks") or [] if row["firm_id"] == firm_id and row.get("is_current")]
    rank = ranks[0]

    shown = _whole(result["total_shown"])
    exact = float(result["total"])
    page = {
        "slug": firm["slug"],
        "name": firm["name"],
        "short": firm["short_name"],
        "title": copy["page_title"],
        "hq": firm["hq"],
        "since": str(int(firm["founded_year"])),
        "meta": meta,
        "notToken": copy["not_token"],
        "updated": copy["updated_display"],
        "method": copy["method_label"],
        "scoreShown": shown,
        "scoreExact": exact,
        "band": result["band"],
        "range": [int(result["range_low"]), int(result["range_high"])],
        "rank": {
            "place": int(rank["place"]),
            "tier": rank["tier"],
            "of": int(rank["of_count"]),
            "example": bool(rank["is_example"]),
        },
        "question": copy["question"],
        "verdict": copy["verdict"],
        "verdictSub": copy["verdict_sub"],
        "floats": floats,
        "badges": badges,
        "scoreBarNote": copy["score_bar_note"],
        "parts": part_objs,
        "summary": copy["summary"],
        "takeaways": takeaways,
        "topLegal": [link["evidence_key"] for link in featured],
        "matters": matters,
        "regulatory": {
            "title": copy["regulatory_title"],
            "note": copy["regulatory_note"],
            "recordsTitle": copy["regulatory_records_title"],
            "sanctionsTitle": copy["sanctions_title"],
            "records": records,
            "sanctions": sanctions,
        },
        "legalGroups": legal_groups,
        "notCountedTitle": copy["not_counted_title"],
        "notCounted": not_counted,
        "fundTab": {
            "factsTitle": copy["fund_facts_title"],
            "factsNote": copy["fund_facts_note"],
            "facts": facts,
            "boards": {"title": copy["boards_title"], "items": boards, "note": copy["boards_note"]},
            "moves": {
                "title": copy["moves_title"],
                "note": copy["moves_note"],
                "items": moves,
                "foot": copy["moves_foot"],
            },
            "media": {
                "title": copy["media_title"],
                "note": copy["media_note"],
                "items": media,
                "foot": copy["media_foot"],
            },
        },
        "public": {
            "title": copy["public_title"],
            "intro": copy["public_intro"],
            "sentimentTitle": copy["public_sentiment_title"],
            "sentimentNote": copy["public_sentiment_note"],
            "empty": copy["public_empty"],
            "items": public_items,
        },
        "portfolio": {
            "title": copy["portfolio_title"],
            "note": copy["portfolio_note"],
            "events": events,
            "foot": copy["portfolio_foot"],
            "size": {
                "title": copy["portfolio_size_title"],
                "value": copy["portfolio_size_value"],
                "text": copy["portfolio_size_text"],
            },
            "healthTitle": copy["portfolio_health_title"],
            "healthNote": copy["portfolio_health_note"],
            "health": health,
            "litigation": {
                "title": copy["portfolio_lit_title"],
                "value": copy["portfolio_lit_value"],
                "text": copy["portfolio_lit_text"],
            },
        },
        "ask": {
            "title": copy["ask_title"],
            "note": copy["ask_note"],
            "printHead": copy["ask_print_head"],
            "questions": questions,
            "clipboard": copy["ask_clipboard"],
        },
        "footnote": copy["footnote"],
        "scoreFooter": copy["score_footer"],
        "evidence": evidence,
    }
    companies = _companies(bundle, firm_id)
    reviews = _reviews(bundle, firm_id)
    vehicles = _vehicles(bundle, firm_id)
    if companies:
        page["companies"] = companies
    if reviews:
        page["reviews"] = reviews
    if vehicles:
        page["vehicles"] = vehicles
    return page


def _companies(bundle, firm_id):
    by_id = {row["id"]: row for row in bundle.get("portfolio_companies") or []}
    people = {row["id"]: row["full_name"] for row in bundle.get("people") or []}
    rows = []
    for investment in bundle.get("investments") or []:
        if investment.get("firm_id") != firm_id:
            continue
        company = by_id.get(investment["company_id"]) or {}
        rows.append({
            "name": company.get("name") or "",
            "domain": company.get("domain") or "",
            "round": investment.get("round_name") or "",
            "outcome": investment.get("outcome") or "",
            "lead": bool(investment.get("is_lead")),
            "board": bool(investment.get("board_seat")),
        })
    rows.sort(key=lambda row: row["name"])
    return rows


def _reviews(bundle, firm_id):
    people = {row["id"]: row["full_name"] for row in bundle.get("people") or []}
    companies = {row["id"]: row["name"] for row in bundle.get("portfolio_companies") or []}
    ratings = _by(bundle.get("review_ratings"), "review_id")
    rows = []
    for review in _firm_rows(bundle, "reviews", firm_id):
        rows.append({
            "founder": people.get(review.get("founder_person_id"), ""),
            "company": companies.get(review.get("company_id"), ""),
            "partner": people.get(review.get("partner_person_id"), ""),
            "body": review.get("body") or "",
            "firstHand": bool(review.get("first_hand")),
            "verification": review.get("verification_status") or "",
            "moderation": review.get("moderation_status") or "",
            "date": _date(review.get("reviewed_on")) or "",
            "ratings": [
                {"dimension": rating["dimension"], "score": _whole(rating["score"])}
                for rating in _sort(ratings.get(review["id"]), "dimension")
            ],
        })
    return rows


def _vehicles(bundle, firm_id):
    rows = []
    for fund in _sort(_firm_rows(bundle, "funds", firm_id), "sort_order"):
        rows.append({
            "name": fund["name"],
            "vintage": fund.get("vintage"),
            "size": fund.get("size_usd"),
            "status": fund.get("status") or "",
            "kind": fund.get("vehicle_kind") or "",
        })
    return rows


def assemble_site(bundle):
    home = assemble_home(bundle)
    funds = {}
    for firm in bundle.get("firms") or []:
        if firm.get("report_slug"):
            funds[firm["report_slug"]] = assemble_fund(bundle, firm)
    return home, funds
