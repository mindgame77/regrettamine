"""Turn design/system a16z-benchmark.json into SQL for vc_source_facts / vc_ai_summaries / vc_scores.

Usage: python3 scripts/load_vc_benchmark.py docs/design/a16z-benchmark.json > /tmp/a16z.sql
Idempotent: facts and summaries upsert on (source_system, external_id) / are replaced per firm.
Summaries are inserted as draft, linked to facts, then approved only when every cited fact is real.
"""
import json
import sys
import uuid

NS = uuid.UUID("6f1d8a52-6c0e-4a39-9d55-3c1f0b7a2e11")


def q(v):
    if v is None:
        return "null"
    s = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
    tag = "$b$"
    assert tag not in s
    return tag + s + tag


def qj(v):
    return q(json.dumps(v, ensure_ascii=False))


def main(path):
    d = json.load(open(path, encoding="utf-8"))
    p = d["vc_profile"]
    slug = p["slug"]
    fid = lambda local: str(uuid.uuid5(NS, f"{slug}:fact:{local}"))
    sid = lambda local: str(uuid.uuid5(NS, f"{slug}:summary:{local}"))
    out = ["begin;", f"do $$ begin if not exists (select 1 from public.firms where slug = {q(slug)}) then raise exception 'firm {slug} missing'; end if; end $$;"]
    firm = f"(select id from public.firms where slug = {q(slug)})"
    out.append(
        f"update public.firms set sec_crd = {q(p['sec_crd'])}, legal_name = {q(p['legal_name'])}, primary_domain = {q(p['primary_domain'])}, "
        f"founded_year = {int(p['founded_year'])}, disambiguation = {q(p['disambiguation'])}, report_date = {q(p['report_date'])}::date, "
        f"external_id = coalesce(external_id, {q(slug)}) where slug = {q(slug)};"
    )
    for a in p["aliases"]:
        out.append(
            f"insert into public.vc_aliases (firm_id, alias_type, value, source_system) values ({firm}, {q(a['alias_type'])}, {q(a['value'])}, 'repo_json') "
            "on conflict (alias_type, lower(value)) do nothing;"
        )
    out.append(f"delete from public.vc_ai_summaries where firm_id = {firm};")
    for f in d["vc_source_facts"]:
        out.append(
            "insert into public.vc_source_facts (id, firm_id, fact_type, section, value, source_url, source_label, source_type, retrieved_at, record_id, quote, status, data_status, needs_refetch, source_system, external_id) values ("
            f"{q(fid(f['id']))}::uuid, {firm}, {q(f['fact_type'])}, {q(f['section'])}, {qj(f['value'])}::jsonb, {q(f['source_url'])}, {q(f['source_label'])}, {q(f['source_type'])}, "
            f"{q(f['retrieved_at'])}::timestamptz, {q(f['record_id'])}, {q(f['quote'])}, {q(f['status'])}, {q(f['data_status'])}::public.data_status, {str(bool(f['needs_refetch'])).lower()}, {q(f['source_system'])}, {q(f['external_id'])}) "
            "on conflict (id) do update set value = excluded.value, source_url = excluded.source_url, retrieved_at = excluded.retrieved_at, data_status = excluded.data_status;"
        )
    for n, a in enumerate(d["vc_ai_summaries"]):
        out.append(
            "insert into public.vc_ai_summaries (id, firm_id, kind, variant, section, sort_order, text, model, prompt_version, generated_at, review_status, stale, data_status) values ("
            f"{q(sid(a['id']))}::uuid, {firm}, {q(a['kind'])}, {q(a['variant'])}, {q(a['section'])}, {n}, {qj(a['text'])}::jsonb, {q(a['model'])}, {q(a['prompt_version'])}, "
            f"{q(a['generated_at'])}::timestamptz, 'draft', false, 'test');"
        )
        for f in a["fact_ids"]:
            out.append(f"insert into public.vc_ai_summary_facts (summary_id, fact_id) values ({q(sid(a['id']))}::uuid, {q(fid(f))}::uuid) on conflict do nothing;")
    # approve + mark real only where every cited fact is real (the trigger enforces the same rule)
    out.append(
        f"update public.vc_ai_summaries s set review_status = 'approved', data_status = 'real' where s.firm_id = {firm} "
        "and exists (select 1 from public.vc_ai_summary_facts l where l.summary_id = s.id) "
        "and not exists (select 1 from public.vc_ai_summary_facts l join public.vc_source_facts f on f.id = l.fact_id "
        "where l.summary_id = s.id and (f.data_status <> 'real' or f.status <> 'current'));"
    )
    sc = d["score"]
    score_id = str(uuid.uuid5(NS, f"{slug}:score:{sc['method_version']}"))
    out.append(f"update public.vc_scores set is_current = false where firm_id = {firm} and id <> {q(score_id)}::uuid;")
    out.append(
        "insert into public.vc_scores (id, firm_id, method_version, score_exact, score_shown, band, range_low, range_high, coverage_pct, rank_place, rank_of, is_current, data_status) values ("
        f"{q(score_id)}::uuid, {firm}, {q(sc['method_version'])}, {sc['score_exact']}, {sc['score_shown']}, {q(sc['band'])}, {sc['range'][0]}, {sc['range'][1]}, {sc['coverage_pct']}, "
        f"{sc['rank']['place']}, {sc['rank']['of']}, true, 'real') on conflict (id) do nothing;"
    )
    for i, part in enumerate(sc["parts"]):
        pid = str(uuid.uuid5(NS, f"{score_id}:{part['id']}"))
        out.append(
            f"insert into public.vc_score_parts (id, score_id, part_key, name, got, max_label, sort_order) values ({q(pid)}::uuid, {q(score_id)}::uuid, {q(part['id'])}, {q(part['name'])}, {part['got']}, {q(part['max_label'])}, {i}) on conflict (id) do nothing;"
        )
        for j, inp in enumerate(part["inputs"]):
            iid = str(uuid.uuid5(NS, f"{pid}:{j}"))
            out.append(f"insert into public.vc_score_inputs (id, part_id, name, points) values ({q(iid)}::uuid, {q(pid)}::uuid, {q(inp['name'])}, {q(inp['points'])}) on conflict (id) do nothing;")
    out.append("commit;")
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1])
