"""Review + import accepted research submissions into the company-page tables (firm_page() reads them).
Takes the latest valid submission per firm (research_submissions, id <= --max-id), reviews it, writes a review CSV,
and (with --apply) upserts only the firms that pass. Idempotent: rows get deterministic ids and each firm's
imported rows are replaced in one transaction. New firms: launch_page = true, published = false (old site unchanged).
Usage: python3 tools/ingest/import_research.py --max-id 48 [--only vc-000004,...] [--apply]   (needs SUPABASE_ACCESS_TOKEN, never printed)"""
import argparse, csv, json, os, re, sys, urllib.error, uuid
from urllib.parse import urlparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _supa import sql

NS = uuid.UUID('6f1c2b1e-5a4d-4c55-9a43-7e0b8d1f2a10')
CERTAINTY = {'adjudicated', 'reported', 'alleged', 'self_reported'}
ENTITY_TYPES = {'firm', 'fund', 'partner', 'company', 'lp', 'gp_entity'}
FIELD_PATHS = {'hq', 'founded', 'aum', 'legal_entities', 'people', 'peopleMoves', 'funds', 'latestRaise', 'limitedPartners',
               'portfolio', 'lawsuits', 'regulatoryActions', 'sanctions', 'controversies', 'posts', 'reviews', 'politicalContext'}
URL_OK = re.compile(r'^https?://[^\s/]+\.[^\s]+$', re.I)
COLLISION = re.compile(r'same[- ]name|name[- ]collision|namesake|not the same (firm|entity|company|person)|different (firm|entity|company)'
                       r'|unrelated (firm|entity|company)|no relation to|not affiliated with', re.I)
BANNED = re.compile(r'\b(safe|verdict|score)\b', re.I)
TEST_BOT = re.compile(r'test', re.I)
CHILD = ['firm_profile_facts', 'firm_legal_items', 'firm_people_roles', 'timeline_events']

def q(v):
    return 'null' if v is None else "'" + str(v).replace("'", "''") + "'"
def uid(*k):
    return str(uuid.uuid5(NS, '|'.join(map(str, k))))
def slugify(s):
    return re.sub(r'-+', '-', re.sub(r'[^a-z0-9]+', '-', s.lower().replace('&', ' and '))).strip('-')
def money(n):
    if not isinstance(n, (int, float)): return None
    for d, u in ((1e9, 'B'), (1e6, 'M'), (1e3, 'K')):
        if n >= d: return f'${n / d:.1f}{u}'.replace('.0' + u, u)
    return f'${n:,.0f}'
def clip(s, n=600):
    s = re.sub(r'\s+', ' ', str(s or '')).strip()
    return s if len(s) <= n else s[:n - 1].rsplit(' ', 1)[0] + '…'
def norm(s):
    return re.sub(r'[^a-z0-9]', '', str(s or '').lower())
# docs/DATA_RULES.md: same text rule as the database checker (_note_text / _person_name_bad).
NOTE_RE = re.compile(r"(\bbot [a-z ]*records?\b|schedule [a-d] (individuals|lists)|related persons?:|\bmatch(es)? an? (schedule|surname|fund)"
                     r"|\(log entry|no source url|\[the 10 checks\]|\bsearched\b.*\bfound\b)", re.I)
def note_text(t, maxlen=300):
    t = str(t or '').strip()
    if not t: return None
    if NOTE_RE.search(t): return 'reads like a bot note, not a fact'
    if re.search(r'https?://|www\.', t, re.I): return 'contains a URL'
    if len(t) > maxlen: return f'longer than {maxlen} characters'
    return None
def person_name_bad(n):
    n = str(n or '').strip()
    if not n: return 'person needs name'
    if note_text(n, 80): return 'name: ' + note_text(n, 80)
    if re.search(r'[0-9;:|/()\[\]]', n): return 'name has digits or punctuation'
    if re.search(r' and | & ', n, re.I): return 'one person per item'
    if ',' in re.sub(r',\s*(Jr|Sr|II|III|IV)\.?$', '', n): return 'one person per item'
    if len(n.split()) > 6: return 'name too long'
    return None
CHECK_COLS = {'firm_people_roles': (('role', 200),), 'firm_legal_items': (('title', 160),), 'timeline_events': (('body', 300),),
              'firm_profile_facts': (('label', 120), ('value', 400))}
def row_reject(table, cols):
    if table == 'firm_people_roles':
        bad = person_name_bad(cols.get('person_name'))
        if bad: return bad
    for c, m in CHECK_COLS.get(table, ()):
        bad = note_text(cols.get(c), m)
        if bad: return f'{c}: {bad}'
    return None
def human(s):
    return str(s or '').replace('_', ' ').strip().capitalize() or None

def latest(max_id):
    return sql(f"""select distinct on (s.registry_id) s.id, s.registry_id, s.bot_id, s.payload, q.name qname, q.website, q.hq_city, q.state, q.sec_crd
      from research_submissions s join research_queue q using (registry_id)
      where s.valid and s.id <= {int(max_id)} order by s.registry_id, s.received_at desc, s.id desc""")

def review(sub, lps, taken):
    """returns (issues_fail, issues_warn, kept_records)"""
    p, fail, warn = sub['payload'] or {}, [], []
    if TEST_BOT.search(sub['bot_id'] or ''): fail.append(f"test submission (bot_id {sub['bot_id']})")
    if p.get('schema_version') != 'dump-1.2': fail.append('schema_version is not dump-1.2')
    for k in ('firm', 'coverage', 'records', 'leads', 'search_log'):
        if k not in p: fail.append(f'missing {k}')
    if (p.get('firm') or {}).get('firm_id') != sub['registry_id']: fail.append('firm.firm_id != registry_id')
    if not p.get('coverage'): fail.append('coverage empty')
    qids = {x.get('query_id') for x in p.get('search_log') or []}
    seen, kept, ids = {}, [], set()
    for r in p.get('records') or []:
        rid, e = r.get('record_id'), []
        if not rid or rid in ids: e.append('record_id missing/duplicate')
        ids.add(rid)
        if r.get('field_path') not in FIELD_PATHS: e.append(f"field_path {r.get('field_path')}")
        if not isinstance(r.get('entity'), dict) or r['entity'].get('type') not in ENTITY_TYPES or not r['entity'].get('name'): e.append('entity invalid')
        if not isinstance(r.get('value'), dict): e.append('value not object')
        if r.get('certainty') not in CERTAINTY: e.append(f"certainty {r.get('certainty')}")
        if any(x not in qids for x in r.get('query_ids') or []): e.append('query_id not in search_log')
        srcs = r.get('sources') or []
        if not srcs or any(not URL_OK.match(str(s.get('url') or '')) for s in srcs): e.append('fact without a valid source URL')
        if e: fail.append(f'{rid}: ' + '; '.join(e)); continue
        if r['field_path'] in ('controversies', 'lawsuits', 'regulatoryActions') and str(r.get('certainty')).lower() == 'confirmed':
            fail.append(f'{rid}: controversy certainty confirmed'); continue
        txt = json.dumps(r['value'], ensure_ascii=False)
        if r['field_path'] in ('controversies', 'lawsuits') and COLLISION.search(txt):
            warn.append(f"{rid} ({r['field_path']}) name-collision/same-name flag: not imported"); continue
        if BANNED.search(txt):
            warn.append(f"{rid} contains banned word '{BANNED.search(txt).group(0)}': not imported"); continue
        v = r['value']
        if r['field_path'] in ('funds', 'people'):  # same vehicle / person twice: one fact, values and sources merged
            key = (r['field_path'], norm(v.get('vehicle_name') or v.get('name') or r['entity']['name']))
        else:
            key = (r['field_path'], norm(r['entity']['name']), norm(txt))
        if key in seen:
            first = seen[key]
            for k, x in v.items():
                if first['value'].get(k) is None: first['value'][k] = x
            first['sources'] = first['sources'] + r['sources']
            warn.append(f"{rid} duplicate of {first['record_id']} ({r['field_path']}): merged"); continue
        r = dict(r, value=dict(v)); seen[key] = r; kept.append(r)
    payload_lps = [r for r in p.get('records') or [] if r.get('field_path') == 'limitedPartners']
    if payload_lps and not lps: fail.append(f'{len(payload_lps)} LP records in the dump but none in firm_lps')
    elif len({norm(l['lp_name']) for l in lps}) < len({norm(r['value'].get('name') or r['entity']['name']) for r in payload_lps}):
        warn.append('firm_lps has fewer distinct LP names than the dump')
    for l in lps:
        if not URL_OK.match(l['source_url'] or ''): fail.append(f"LP {l['lp_name']}: no source URL")
    brand = ((p.get('firm') or {}).get('name_forms') or {}).get('brand') or (p.get('firm') or {}).get('name') or sub['qname']
    slug = slugify(brand)
    if slug in taken and taken[slug] != sub['registry_id']: fail.append(f'slug {slug} already used by another firm')
    crd_owner = taken.get('crd:' + str(sub['sec_crd']))
    if sub['sec_crd'] and crd_owner and crd_owner != sub['registry_id']: fail.append(f"SEC CRD {sub['sec_crd']} already on firm {crd_owner}")
    return fail, warn, kept, brand, slug

def src_rows(srcs):
    out, seen = [], set()
    for s in srcs:
        u = s['url'].strip()
        if u in seen: continue
        seen.add(u); out.append((u, urlparse(u).netloc.replace('www.', ''), s.get('retrieved_at') or s.get('published_at')))
    return out

def day(d):
    """Source date as YYYY-MM-DD; partial dates (2017, 2017-03) pad to the first day, missing ones to the import day."""
    d = str(d or '2026-10-23')[:10]
    return d + '-01-01'[len(d) - 4:] if re.fullmatch(r'\d{4}(-\d{2})?', d) else d


def build(sub, kept, lps, brand, slug):
    """rows per table for one firm: list of (table, id, columns dict, sources)"""
    reg, fid = sub['registry_id'], uid(sub['registry_id'], 'firm')
    rows, by = [], {}
    for r in kept: by.setdefault(r['field_path'], []).append(r)
    def add(table, key, cols, srcs):
        bad = row_reject(table, cols)
        if bad:
            print('skipped', table, key, '-', bad, file=sys.stderr); return
        rows.append((table, uid(reg, table, key), cols, src_rows(srcs)))
    def fact(section, key, label, value, srcs, hero=None, order=0):
        if value: add('firm_profile_facts', key, dict(section=section, label=clip(label, 120), value=clip(value, 400),
                     hero_label=hero[0] if hero else None, hero_value=hero[1] if hero else None, sort_order=order), srcs)
    hq = (by.get('hq') or [None])[0]
    city = None
    if hq:
        v = hq['value']; city = ', '.join(x for x in (v.get('city'), v.get('region')) if x)
        fact('overview', 'hq', 'Headquarters', v.get('address') or city, hq['sources'], ('HQ', v.get('city')) if v.get('city') else None, 10)
    for r in by.get('founded', [])[:1]:
        y = r['value'].get('year')
        fact('overview', 'founded', 'Founded', ' · '.join(str(x) for x in (y, r['value'].get('note')) if x), r['sources'], ('Founded', str(y)) if y else None, 20)
    for i, r in enumerate(by.get('legal_entities', [])):
        v = r['value']
        val = ' · '.join(str(x) for x in (human(v.get('kind')), v.get('crd') and 'CRD ' + str(v['crd']), v.get('registration_status'), v.get('owner') and 'Owner: ' + str(v['owner'])) if x)
        fact('overview', f"le{i}:{r['record_id']}", v.get('name') or r['entity']['name'], val, r['sources'], None, 30 + i)
    for i, r in enumerate(x for x in by.get('regulatoryActions', []) if 'none' in str(x['value'].get('action_type', '')).lower()):
        fact('overview', 'regnone' + r['record_id'], 'Disclosures (' + (r['value'].get('regulator') or 'regulator') + ')', r['value'].get('summary'), r['sources'], None, 80 + i)
    sanc = by.get('sanctions', [])
    if sanc:
        hits = [r for r in sanc if str(r['value'].get('result', '')).lower() not in ('no_match', 'clear', 'none')]
        lists = sorted({str(r['value'].get('list')) for r in sanc if r['value'].get('list')})
        val = (f"No match on {len(lists)} lists: " if not hits else f"{len(hits)} possible match(es) to review on: ") + ', '.join(lists)
        fact('overview', 'sanctions', 'Sanctions screening', val, [s for r in sanc for s in r['sources']], None, 90)
    for i, r in enumerate(by.get('aum', [])):
        v = r['value']; m = money(v.get('amount_usd'))
        val = ' · '.join(str(x) for x in (m, human(v.get('basis')), v.get('employees') and f"{v['employees']} employees") if x)
        fact('funds', 'aum' + r['record_id'], 'Assets under management', val, r['sources'], ('Assets', m) if m and i == 0 else None, i)
    for i, r in enumerate(by.get('latestRaise', [])):
        v = r['value']
        val = ' · '.join(str(x) for x in (money(v.get('amount_usd')), v.get('fund_name'), v.get('detail'), v.get('date') or v.get('announced_at'), human(v.get('status'))) if x)
        fact('funds', 'raise' + r['record_id'], 'Latest raise', val, r['sources'], None, 5 + i)
        d = v.get('date') or v.get('announced_at')
        if d: add('timeline_events', 'raise' + r['record_id'], dict(date_label=str(d), kind='Fund raise', body=clip(val, 300), sort_order=0), r['sources'])
    for i, r in enumerate(by.get('funds', [])):
        v = r['value']
        val = ' · '.join(str(x) for x in (human(v.get('fund_type')), money(v.get('gross_asset_value_usd')) and 'gross assets ' + money(v.get('gross_asset_value_usd')),
                                          v.get('beneficial_owners') and f"{v['beneficial_owners']} beneficial owners", (v.get('vintage') or v.get('vintage_year')) and f"vintage {v.get('vintage') or v.get('vintage_year')}",
                                          money(v.get('total_sold_usd') or v.get('form_d_amount_sold_usd')) and 'Form D sold ' + money(v.get('total_sold_usd') or v.get('form_d_amount_sold_usd'))) if x)
        fact('funds', 'fund' + r['record_id'], v.get('vehicle_name') or v.get('name') or r['entity']['name'], val or 'Fund vehicle', r['sources'], None, 10 + i)
    for i, l in enumerate(sorted(lps, key=lambda l: (l['status'] != 'confirmed', l['lp_name'].lower()))):
        val = ' · '.join(str(x) for x in (human(l['lp_type']), l['fund_name'], l['commitment_amount'] is not None and money(float(l['commitment_amount'])),
                                          l['commitment_year'], 'Confirmed' if l['status'] == 'confirmed' else 'Lead (not confirmed)') if x)
        fact('lps', f"lp{l['id']}", l['lp_name'], val, [{'url': l['source_url'], 'retrieved_at': str(l['checked_at'])[:10]}], None, i)
    order = 0
    for r in by.get('lawsuits', []) + by.get('controversies', []) + [x for x in by.get('regulatoryActions', []) if 'none' not in str(x['value'].get('action_type', '')).lower()]:
        v, fp = r['value'], r['field_path']; order += 1
        st = str(v.get('status') or '').lower()
        state = 'Active' if re.search(r'pending|open|active|ongoing|expanding', st) else 'Closed' if re.search(r'closed|settled|dismiss|resolved|complete|decided|terminated|divested|vacated|affirmed|transferred', st) else 'Unverified'
        role = str(v.get('firm_role') or '').lower()
        if fp == 'regulatoryActions': grp = 'regulator'
        elif fp == 'lawsuits' or (str(v.get('theme', '')).startswith('legal.') and re.search(r'defendant|plaintiff|respondent', role)): grp = 'case'
        else: grp = 'context'
        title = v.get('caption') or v.get('event_anchor') or v.get('regulator') or r['entity']['name']
        year = str(v.get('filed_at') or v.get('event_date') or v.get('date') or '')[:4] or None
        cs = bool(v.get('case_summary') and v.get('summary') and v.get('summary_source_url'))
        note = v.get('allegation') if cs else v.get('summary') or v.get('allegation')
        add('firm_legal_items', r['record_id'], dict(grp=grp, title=clip(title, 160), year_label=year, role=human(v.get('firm_role')) or (v.get('named_as') and 'Named'),
            state=state, status_label={'adjudicated': 'Adjudicated', 'alleged': 'Alleged', 'reported': 'Reported', 'self_reported': 'Self-reported'}[r['certainty']],
            tone='g', note=clip(note, 700), sort_order=order,
            **(dict(summary=v['summary'], summary_date=v.get('summary_date'), summary_source_url=v['summary_source_url'], summary_by='research') if cs else {})), r['sources'])
        d = v.get('filed_at') or v.get('event_date') or v.get('date')
        if d: add('timeline_events', 'ev' + r['record_id'], dict(date_label=str(d)[:10], kind='Case filed' if grp == 'case' else 'Regulator' if grp == 'regulator' else 'Reported',
                  body=clip(title, 200), sort_order=order), r['sources'])
    for i, r in enumerate(by.get('people', [])):
        v = r['value']
        add('firm_people_roles', r['record_id'], dict(kind='officer', person_name=clip(v.get('name') or r['entity']['name'], 120),
            role=clip(v.get('title') or human(v.get('role')) or 'Officer', 200), badge=None if v.get('current', True) else 'Former', sort_order=i), r['sources'])
    for i, r in enumerate(by.get('peopleMoves', [])):
        v = r['value']
        role = ' '.join(str(x) for x in (human(v.get('move')), v.get('from_org') and 'from ' + v['from_org'], v.get('to_org') and 'to ' + v['to_org']) if x)
        add('firm_people_roles', r['record_id'], dict(kind='move', person_name=clip(v.get('name') or r['entity']['name'], 120), role=clip(role or 'Moved', 200),
            badge=v.get('date'), sort_order=i), r['sources'])
        if v.get('date'): add('timeline_events', 'mv' + r['record_id'], dict(date_label=str(v['date']), kind='People move', body=clip((v.get('name') or '') + ' ' + role, 200), sort_order=100 + i), r['sources'])
    rows.sort(key=lambda x: (x[0], x[2].get('date_label', '')), reverse=False)
    tl = [x for x in rows if x[0] == 'timeline_events']
    for i, x in enumerate(sorted(tl, key=lambda x: x[2]['date_label'], reverse=True)): x[2]['sort_order'] = i
    return fid, rows

def firm_sql(sub, brand, slug, rows, p):
    reg, fid = sub['registry_id'], uid(sub['registry_id'], 'firm')
    f = p.get('firm') or {}
    hq = next((r for r in p['records'] if r['field_path'] == 'hq'), None)
    hqs = ', '.join(x for x in ((hq or {}).get('value', {}).get('city'), (hq or {}).get('value', {}).get('region')) if x) or None
    short = ((f.get('name_forms') or {}).get('short') or [None])[0]
    dom = urlparse(f.get('website') or '').netloc.replace('www.', '') or None
    legal = ((f.get('name_forms') or {}).get('legal') or [sub['qname']])[0]
    out = [f"""insert into firms (id, slug, name, short_name, hq, legal_name, sec_crd, primary_domain, published, launch_page, is_test, data_status, source_system, external_id)
      values ({q(fid)}, {q(slug)}, {q(brand)}, {q(short)}, {q(hqs)}, {q(legal)}, {q(sub['sec_crd'])}, {q(dom)}, false, true, false, 'real', 'research_import', {q(reg)})
      on conflict (id) do update set slug = excluded.slug, name = excluded.name, short_name = excluded.short_name, hq = excluded.hq, legal_name = excluded.legal_name,
        sec_crd = excluded.sec_crd, primary_domain = excluded.primary_domain, launch_page = true, deleted_at = null;"""]
    out.append(f"delete from fact_sources where firm_id = {q(fid)};")
    for t in CHILD: out.append(f"delete from {t} where firm_id = {q(fid)};")
    urls = {}
    for _, _, _, ss in rows:
        for u, dom_, d in ss: urls.setdefault(u, (dom_, d))
    if urls:
        out.append("insert into sources (url, publisher, title, domain, retrieved_at, data_status, source_system) values "
                   + ',\n'.join(f"({q(u)}, {q(d)}, {q(d)}, {q(d)}, {q(day(r))}::timestamptz, 'real', 'research_import')" for u, (d, r) in urls.items())
                   + " on conflict (url) do nothing;")
    by = {}
    for t, i, c, ss in rows: by.setdefault(t, []).append((i, c, ss))
    for t, items in by.items():
        cols = list(dict.fromkeys(k for _, c, _ in items for k in c))  # union: a legal row may carry the summary fields
        out.append(f"insert into {t} (id, firm_id, {', '.join(cols)}) values " + ',\n'.join(
            f"({q(i)}, {q(fid)}, " + ', '.join(q(c.get(k)) for k in cols) + ')' for i, c, _ in items) + ';')
        fs = [(i, u, d, n) for i, _, ss in items for n, (u, _, d) in enumerate(ss)]
        if fs:
            out.append("insert into fact_sources (id, source_id, firm_id, fact_type, fact_id, label, date_label, sort_order, data_status) select v.id::uuid, s.id, "
                       + f"{q(fid)}, {q(t)}, v.fid::uuid, s.publisher, v.d, v.n, 'real' from (values " + ',\n'.join(
                           f"({q(uid(i, 'src', n))}, {q(i)}, {q(u)}, {q(str(d)[:10] if d else None)}, {n})" for i, u, d, n in fs)
                       + ") v(id, fid, url, d, n) join sources s on s.url = v.url;")
    # Enricher results sit on top of the friend's rows: re-apply them (and their correction overrides) after the replace.
    out.append(f"select promote_enrichment({q(fid)}) where to_regprocedure('public.promote_enrichment(uuid)') is not null;")
    return 'begin;\n' + '\n'.join(out) + '\ncommit;'

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--max-id', type=int, required=True); ap.add_argument('--apply', action='store_true')
    ap.add_argument('--out', default='/workspace/toxybase/import-review')
    ap.add_argument('--only', help='comma-separated registry_ids: review/import just these firms (sheet gets a -<tag> suffix)')
    ap.add_argument('--tag', default='run2'); a = ap.parse_args()
    subs = latest(a.max_id)
    if a.only: subs = [s for s in subs if s['registry_id'] in a.only.split(',')]
    lps_all = sql("select id, registry_id, lp_name, lp_type, fund_name, commitment_amount, commitment_year, status, source_url, checked_at from firm_lps")
    taken = {}
    for f in sql("select slug, sec_crd, external_id from firms where deleted_at is null"):
        taken[f['slug']] = f['external_id'] or f['slug']
        if f['sec_crd']: taken['crd:' + f['sec_crd']] = f['external_id'] or f['slug']
    os.makedirs(a.out, exist_ok=True)
    sheet, plan, slugs = [], [], {}
    for s in subs:
        lps = [l for l in lps_all if l['registry_id'] == s['registry_id']]
        fail, warn, kept, brand, slug = review(s, lps, taken)
        if slug in slugs: fail.append(f'slug {slug} also used by {slugs[slug]}')
        slugs[slug] = s['registry_id']
        fid, rows = build(s, kept, lps, brand, slug) if not fail else (None, [])
        cnt = {t: sum(1 for r in rows if r[0] == t) for t in CHILD}
        sheet.append(dict(registry_id=s['registry_id'], submission_id=s['id'], firm=brand, slug=slug, result='fail' if fail else 'pass',
            records_in_dump=len(s['payload'].get('records') or []), records_kept=len(kept), firm_lps=len(lps), **cnt,
            fact_sources=sum(len(r[3]) for r in rows), issues=' | '.join(fail + warn) or 'none'))
        if not fail: plan.append((s, brand, slug, rows))
    path = os.path.join(a.out, 'review-2026-10-23' + (f'-{a.tag}' if a.only else '') + '.csv')
    with open(path, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(sheet[0])); w.writeheader(); w.writerows(sheet)
    print('review sheet:', path)
    for r in sheet: print(f"{r['registry_id']} #{r['submission_id']:<3} {r['result']:4} {r['firm'][:32]:32} kept {r['records_kept']}/{r['records_in_dump']} lps {r['firm_lps']}")
    if not a.apply: return
    for s, brand, slug, rows in plan:
        try: sql(firm_sql(s, brand, slug, rows, s['payload']))
        except urllib.error.HTTPError as e: raise SystemExit(f"{slug}: import failed, rolled back: {e.read().decode()[:800]}")
        json.dump({'firm': {'slug': slug, 'name': brand, 'external_id': s['registry_id']}}, open(os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'launch', slug + '.json'), 'w'), indent=1)
        print('imported', slug)

if __name__ == '__main__': main()
