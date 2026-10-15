"""Load a research workbook (Facts / Sources / Fact_Sources / Partners / Score / Summary sheets) into the
existing schema. The workbook is only a carrier: provenance is the source URL of each fact.

Usage: python3 scripts/load_research_xlsx.py OUT_DIR file.xlsx [...]
Writes OUT_DIR/<slug>.sql and OUT_DIR/report.json (counts, conflicts, unmapped fields).
Rules (Alex, Oct 14 2026):
- 'real' only when the sheet status is 'verified' AND the fact has a source URL AND a checked date.
- 'test' only for rows the workbook itself rejected ('excluded'); test means placeholder/mock data.
- everything else is a genuine but unproven claim: 'needs_proof' (firm says, unverified, context, conflict, ...).
- Only raw facts are imported. Workbook scores, score sections, confidence, trust tiers, verdicts, summaries,
  red banners, worst-case floors and other AI conclusions are NOT stored anywhere (not even staging).
- Re-runs are idempotent and also re-apply the data_status rule to rows loaded earlier.
"""
import collections
import datetime as dt
import glob
import hashlib
import json
import re
import sys
import uuid

import openpyxl

NS = uuid.UUID("2b0f6c1e-9a77-4c5e-8f43-77d1a0b5e9c2")
ROOT = __import__("pathlib").Path(__file__).resolve().parent.parent

FACT_TYPE = {
    "crd": "sec_crd", "legal_entity": "legal_entity",
    **{k: "fund_fact" for k in ("regulatory_aum", "private_fund_count", "employees", "investment_staff",
                                 "registration_status", "files_13f", "latest_raise", "fundraise")},
    **{k: "legal_matter" for k in ("legal_matter", "matter_status", "matter_class", "matter_party", "matter_role", "matter_outcome", "matter_filed_date")},
    "regulatory_action_type": "regulatory_record", "regulatory_action_amount": "regulatory_record",
    "portfolio_count": "portfolio_size", "media_podcast": "media_reach",
    "sec_disciplinary": "regulatory_record", "regulatory_action": "regulatory_record",
    "sanctions_check": "sanctions_check",
    "press_item": "press_item", "partner_departure_press": "press_item",
    "public_board_seat": "board_seat", "private_board_seat": "board_seat",
    **{k: "partner_move" for k in ("partner_start_date", "tenure_start", "tenure_end", "role_change", "partner_departure")},
    "media_x_followers": "media_reach",
    **{k: "founder_experience" for k in ("founder_account", "account_tone", "account_first_hand",
                                          "account_verification", "account_author_role")},
}
OTHER_TABLE = {"alias": "vc_aliases", "fund": "funds", "related_org": "fund_entities", "hq": "firms.hq",
               **{k: "fund_people" for k in ("partner", "investing_partner", "officer", "adv_owner", "adv_executive", "title")}}
EXISTING = {"general catalyst": "generalcatalyst", "lightspeed venture partners": "lightspeed", "sequoia capital": "sequoia"}


def q(v):
    if v is None:
        return "null"
    s = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
    assert "$x$" not in s
    return "$x$" + s + "$x$"


def qj(v):
    return q(json.dumps(v, ensure_ascii=False, default=str))


def sheet(wb, name):
    rows = [r for r in wb[name].iter_rows(values_only=True) if any(c not in (None, "") for c in r)]
    hdr = [str(h).strip() if h is not None else f"c{i}" for i, h in enumerate(rows[0])]
    return [dict(zip(hdr, r)) for r in rows[1:]]


def source_system(url):
    u = (url or "").lower()
    for key, name in (("adviserinfo", "sec_iapd"), ("sec.gov", "sec_edgar"), ("courtlistener", "courtlistener"),
                      ("pacer", "pacer"), ("gleif", "gleif"), ("opencorporates", "opencorporates"),
                      ("opensanctions", "opensanctions"), ("treasury.gov", "ofac"), ("fec.gov", "fec"),
                      ("x.com", "x"), ("twitter.com", "x")):
        if key in u:
            return name
    return "web" if u else "unknown"


def day(v):
    if isinstance(v, (dt.date, dt.datetime)):
        return v.strftime("%Y-%m-%d")
    s = str(v or "").strip()
    return s[:10] if re.match(r"\d{4}-\d{2}-\d{2}", s) else None


# Fields that are the workbook's own judgments (AI conclusions), never imported.
SKIP_FIELDS = {"adverse_event_candidate", "conflict_candidate", "firm_claim_contradiction", "employee_sentiment"}
# Extra fields -> (table, kind column value).
EXTRA = {
    **{k: "vc_entity_identifiers" for k in ("cik", "lei", "company_number", "entity_status")},
    **{k: "vc_partner_history" for k in ("career_stint", "prior_firm", "founded_company", "deal_led", "team", "partner_statement")},
    **{k: "vc_political_activity" for k in ("political_donation", "lobbying_spend", "lobbying_issue")},
    **{k: "vc_firm_claims" for k in ("stated_focus_sector", "stated_focus_stage", "stated_geography", "team_size",
                                     "investing_partner_count", "platform_team")},
    **{k: "vc_context_notes" for k in ("context", "community_report", "negative_alias")},
}


def classify(status, url, checked, field=None):
    if status == "excluded":
        return "test"
    if EXTRA.get(field) == "vc_firm_claims" or status == "firm says":
        return "needs_proof"
    if status == "verified" and url and checked:
        return "real"
    return "needs_proof"


def extra_row(table, firm, f, field, ds, url, label, quote, checked, ext, slug):
    val = str(f.get("value") or "")
    ent = str(f.get("entity") or "")
    person = ent.split(":", 1)[1].strip() if ent.startswith("partner:") else None
    cols = {"firm_id": None, "entity": ent or None, "field": field, "value": val, "source_url": url, "source_label": label,
            "quote": quote, "published_date": day(f.get("published_date")), "retrieved_at": checked,
            "data_status": ds, "source_system": "research_workbook", "external_id": ext}
    if table == "vc_entity_identifiers":
        parts = [x.strip() for x in val.split("|")]
        cols["id_type"] = field
        if field == "cik":
            m = re.search(r"CIK\s*(\d+)", val)
            cols["id_value"] = m.group(1) if m else None
        elif field == "lei":
            m = re.search(r"\b([0-9A-Z]{20})\b", val)
            cols["id_value"] = m.group(1) if m else None
        elif field == "company_number":
            cols["id_value"] = parts[2] if len(parts) > 2 else None
            cols["jurisdiction"] = parts[1] if len(parts) > 1 else None
        if field in ("lei",) and len(parts) > 1 and re.fullmatch(r"[A-Z]{2}", parts[1] or ""):
            cols["jurisdiction"] = parts[1]
    elif table == "vc_partner_history":
        cols.update(person_name=person, kind=field, organization=val.split("|")[0].strip()[:300])
    elif table == "vc_political_activity":
        cols.update(person_name=person, kind=field)
    elif table == "vc_firm_claims":
        cols.update(subject=ent or None, kind=field)
    elif table == "vc_context_notes":
        cols.update(kind=field)
    names = ", ".join(cols)
    vals = ", ".join(firm if k == "firm_id" else (f"{q(v)}::date" if k == "published_date" else f"{q(v)}::timestamptz" if k == "retrieved_at"
                     else f"{q(v)}::public.data_status" if k == "data_status" else q(v)) for k, v in cols.items())
    sets = ", ".join(f"{k} = excluded.{k}" for k in cols if k not in ("firm_id", "source_system", "external_id"))
    sql = f"insert into public.{table} ({names}) values ({vals}) on conflict (source_system, external_id) do update set {sets};"
    if table == "vc_partner_history" and person:
        sql += f"\nupdate public.vc_partner_history set person_id = (select id from public.people where full_name = {q(person)} limit 1) where source_system = 'research_workbook' and external_id = {q(ext)};"
    return sql


def slugify(name):
    return re.sub(r"[^a-z0-9]+", "", name.lower())[:40]


def main(out_dir, files):
    existing_meta = {}
    for f in glob.glob(str(ROOT / "data" / "funds" / "*.json")):
        d = json.load(open(f, encoding="utf-8"))
        meta = " ".join(map(str, d.get("meta") or []))
        m = re.search(r"CRD (\d+)", meta)
        existing_meta[d["slug"]] = {"crd": m.group(1) if m else None, "hq": d.get("hq"),
                                    "score": d.get("scoreShown"), "legal": [x for x in d.get("meta") or [] if "CRD" not in str(x)]}
    report = {}
    for path in files:
        wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
        summary = {str(r[0]).strip(): (r[1] if len(r) > 1 else None) for r in wb["Summary"].iter_rows(values_only=True) if r and r[0]}
        name = str(summary["Firm"]).strip()
        slug = EXISTING.get(name.lower()) or {"plug and play tech center": "plugandplay"}.get(name.lower()) or slugify(name)
        new = name.lower() not in EXISTING
        facts = sheet(wb, "Facts")
        sources = {r["source_id"]: r for r in sheet(wb, "Sources")}
        fsrc = collections.defaultdict(list)
        for r in sheet(wb, "Fact_Sources"):
            fsrc[r["fact_id"]].append(r)
        firm = f"(select id from public.firms where slug = {q(slug)})"
        out = ["begin;"]
        rep = {"firm": name, "slug": slug, "new": new, "facts_real": 0, "facts_test": 0, "by_type": collections.Counter(),
               "other_tables": collections.Counter(), "unmapped": collections.Counter(), "conflicts": [], "status": collections.Counter(),
               "data_status": collections.Counter(), "skipped_ai_judgment": collections.Counter(), "extra": collections.Counter()}
        crds = [str(f["value"]).split("|")[-1].strip() for f in facts if f["field"] == "crd"]
        crds = [re.sub(r"\D", "", c) for c in crds if re.search(r"\d{5,}", c)]
        primary_crd = crds[0] if crds else None
        legal = next((str(f["value"]).split("|")[0].strip() for f in facts if f["field"] == "legal_entity"), None)
        hq = next((str(f["value"]) for f in facts if f["field"] == "hq"), None)
        if new:
            ini = "".join(w[0] for w in name.split()[:3]).upper()
            out.append(
                "insert into public.firms (slug, name, initials, short_name, hq, firm_type, published, is_test, data_status, sec_crd, legal_name, source_system, external_id) "
                f"values ({q(slug)}, {q(name)}, {q(ini)}, {q(name.split()[0])}, {q(hq)}, 'VC', false, true, 'needs_proof', {q(primary_crd)}, {q(legal)}, 'sec_iapd', {q(primary_crd)}) "
                "on conflict (slug) do nothing;"
            )
            # a real firm we have not finished proving: needs_proof (never purged), stays unpublished
            out.append(f"update public.firms set data_status = 'needs_proof' where slug = {q(slug)} and data_status = 'test';")
        else:
            out.append(f"update public.firms set sec_crd = coalesce(sec_crd, {q(primary_crd)}), legal_name = coalesce(legal_name, {q(legal)}) where slug = {q(slug)};")
        for f in facts:
            field = str(f.get("field") or "").strip()
            status = str(f.get("status") or "").strip()
            rep["status"][status] += 1
            srcs = [sources.get(s["source_id"]) for s in fsrc.get(f["fact_id"], []) if sources.get(s["source_id"])]
            url = (srcs[0]["url"] if srcs else None) or (str(f.get("source_urls") or "").split()[0] if f.get("source_urls") else None)
            checked = (day(fsrc[f["fact_id"]][0]["checked_date"]) if fsrc.get(f["fact_id"]) else None) or (day(srcs[0]["checked_date"]) if srcs else None)
            quote = fsrc[f["fact_id"]][0].get("quote") if fsrc.get(f["fact_id"]) else None
            ds = classify(status, url, checked, field)
            real = ds == "real"
            rep["data_status"][ds] += 1
            if field in SKIP_FIELDS:
                rep["skipped_ai_judgment"][field] += 1
                continue
            ext = hashlib.md5(f"{slug}|{field}|{f.get('entity')}|{f.get('value')}|{url}".encode()).hexdigest()
            ftype = FACT_TYPE.get(field)
            if ftype:
                fid = uuid.uuid5(NS, f"{slug}:{ext}")
                value = {"field": field, "entity": f.get("entity"), "value": f.get("value"), "sheet_status": status,
                         "published_date": day(f.get("published_date")), "publisher": srcs[0]["publisher"] if srcs else None}
                out.append(
                    "insert into public.vc_source_facts (id, firm_id, fact_type, section, value, source_url, source_label, source_type, retrieved_at, quote, status, data_status, needs_refetch, source_system, external_id) values ("
                    f"{q(str(fid))}::uuid, {firm}, {q(ftype)}, {q(ftype)}, {qj(value)}::jsonb, {q(url)}, {q(srcs[0]['publisher'] if srcs else None)}, {q(source_system(url))}, "
                    f"{q(checked)}::timestamptz, {q(quote)}, 'current', {q(ds)}::public.data_status, false, {q(source_system(url))}, {q(ext)}) on conflict (id) do nothing;"
                )
                out.append(f"update public.vc_source_facts set data_status = {q(ds)}::public.data_status where id = {q(str(fid))}::uuid;")
                rep["by_type"][ftype] += 1
                rep["facts_real" if real else "facts_test"] += 1
            elif field in OTHER_TABLE:
                target = OTHER_TABLE[field]
                rep["other_tables"][target] += 1
                val = str(f.get("value") or "")
                if target == "vc_aliases":
                    kind = "domain" if re.search(r"\b[a-z0-9-]+\.(com|vc|net|org|io)\b", val.lower()) else "name"
                    alias = re.search(r"([a-z0-9-]+\.(?:com|vc|net|org|io))", val.lower()).group(1) if kind == "domain" else val.split("(")[0].strip()
                    out.append(f"insert into public.vc_aliases (firm_id, alias_type, value, source_system) values ({firm}, {q(kind)}, {q(alias)}, {q(source_system(url))}) on conflict do nothing;")
                elif target == "funds":
                    fname = val.split("|")[0].strip()
                    out.append(
                        f"insert into public.funds (firm_id, name, notes, data_status, source_system, external_id) select {firm}, {q(fname)}, {q(val)}, {q(ds)}::public.data_status, {q(source_system(url))}, {q(ext)} "
                        f"where not exists (select 1 from public.funds where source_system = {q(source_system(url))} and external_id = {q(ext)});"
                    )
                    out.append(f"update public.funds set data_status = {q(ds)}::public.data_status where source_system = {q(source_system(url))} and external_id = {q(ext)};")
                elif target == "fund_entities":
                    out.append(
                        f"insert into public.fund_entities (firm_id, name, entity_kind, notes, data_status) select {firm}, {q(val.split('|')[0][:200])}, 'related_org', {q(val)}, {q(ds)}::public.data_status "
                        f"where not exists (select 1 from public.fund_entities where firm_id = {firm} and notes = {q(val)});"
                    )
                    out.append(f"update public.fund_entities set data_status = {q(ds)}::public.data_status where firm_id = {firm} and notes = {q(val)};")
                elif target == "fund_people":
                    ent = str(f.get("entity") or "")
                    if ent.startswith("partner:"):
                        person = ent.split(":", 1)[1].strip()
                        out.append(f"insert into public.people (full_name, data_status) select {q(person)}, 'test' where not exists (select 1 from public.people where full_name = {q(person)});")
                        out.append(
                            f"insert into public.fund_people (person_id, firm_id, role, notes, data_status) select (select id from public.people where full_name = {q(person)} limit 1), {firm}, {q(field)}, {q(val)}, {q(ds)}::public.data_status "
                            f"where not exists (select 1 from public.fund_people fp where fp.firm_id = {firm} and fp.role = {q(field)} and fp.notes = {q(val)});"
                        )
                        out.append(f"update public.fund_people set data_status = {q(ds)}::public.data_status where firm_id = {firm} and role = {q(field)} and notes = {q(val)};")
                elif target == "firms.hq":
                    old = existing_meta.get(slug, {}).get("hq")
                    if not new and old and old.split(",")[0].lower() not in val.lower():
                        rep["conflicts"].append({"field": "hq", "existing": old, "sheet": val, "url": url})
            elif field in EXTRA:
                rep["extra"][EXTRA[field]] += 1
                lbl = srcs[0]["publisher"] if srcs else None
                out.append(extra_row(EXTRA[field], firm, f, field, ds, url, lbl, quote, checked, ext, slug))
            else:
                rep["unmapped"][field] += 1
        # firm-level conflicts with what we already publish (facts only; workbook scores are never compared or stored)
        if not new:
            em = existing_meta.get(slug, {})
            if em.get("crd") and primary_crd and em["crd"] != primary_crd:
                rep["conflicts"].append({"field": "sec_crd", "existing": em["crd"], "sheet": primary_crd})
        for c in rep["conflicts"]:
            out.append(
                "insert into public.vc_fact_conflicts (firm_id, field, fact_a_table, fact_a_id, fact_b_table, fact_b_id, status) select "
                f"{firm}, {q(c['field'])}, 'firms', {q(slug + ':' + str(c['existing']))}, 'research_import', {q(str(c['sheet']))}, 'open' "
                f"where not exists (select 1 from public.vc_fact_conflicts where firm_id = {firm} and field = {q(c['field'])} and fact_b_id = {q(str(c['sheet']))});"
            )
        # Cleanup of what an earlier version of this loader stored from the workbook's own judgments:
        # its scores (vc_scores 'research-draft' + parts/inputs by cascade), score conflicts, and AI text.
        out.append(f"delete from public.vc_scores where firm_id = {firm} and method_version = 'research-draft';")
        out.append(f"delete from public.vc_fact_conflicts where firm_id = {firm} and field = 'score' and fact_b_table = 'research_import';")
        out.append(f"delete from public.vc_ai_summaries where firm_id = {firm} and model = 'research-bot';")
        # people created by the import: best status of their links (fund_people roles, partner history):
        # real > needs_proof > test. A named person with no link yet is a genuine claim: needs_proof.
        out.append(
            "with l as (select person_id, data_status from public.fund_people union all select person_id, data_status from public.vc_partner_history where person_id is not null) "
            "update public.people p set data_status = coalesce((select case when bool_or(l.data_status = 'real') then 'real' "
            "when bool_or(l.data_status = 'needs_proof') then 'needs_proof' when bool_or(l.data_status = 'test') then 'test' end from l where l.person_id = p.id), 'needs_proof')::public.data_status "
            f"where p.data_status <> 'real' and (exists (select 1 from public.fund_people fp where fp.person_id = p.id and fp.firm_id = {firm}) "
            f"or exists (select 1 from public.vc_partner_history h where h.person_id = p.id and h.firm_id = {firm}) "
            "or exists (select 1 from public.fact_events e where e.table_name = 'people' and e.row_id = p.id and e.import_run_id is not null));"
        )
        rep["unmapped_sheets"] = [s for s in wb.sheetnames if s not in ("Summary", "Facts", "Sources", "Fact_Sources", "Score", "Partners")]
        out.append(
            "with run as (insert into public.import_runs (source_system, file_or_url, run_by, notes, finished_at) "
            f"values ('research_workbook', {q(path.split('/')[-1])}, 'load_research_xlsx', {q(name)}, now()) returning id) "
            "update public.fact_events set import_run_id = (select id from run) where import_run_id is null and created_at = now() and data_status <> 'real';"
        )
        out.append("commit;")
        open(f"{out_dir}/{slug}.sql", "w", encoding="utf-8").write("\n".join(out))
        report[slug] = rep
    json.dump(report, open(f"{out_dir}/report.json", "w"), indent=1, default=lambda o: dict(o))
    for s, r in report.items():
        print(s, "new" if r["new"] else "existing", "real", r["facts_real"], "test", r["facts_test"], "conflicts", len(r["conflicts"]), "unmapped", sum(r["unmapped"].values()))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
