"""The 10 checks for a firm, derived from a DB snapshot (launch/firm_snapshot.sql). Pills only, no verdict, no score.
Logic ported from toxybase design/flow-v5/render_a16z.py."""
import re, json
NON_PARTY = re.compile(r'\bnon-party\b|\bnot a party\b', re.I)  # the firm is not a party: not counted (same rule as _firm_cases() in the DB)
NAME_ONLY = re.compile(r'different (person|people)|surname-only|name-only hit|name-order variant|not treated as a match|similar name', re.I)

def _txt(x):
    v = x.get('value')
    return json.dumps(v, ensure_ascii=False) if isinstance(v, (dict, list)) else str(v)

def _classify(t):
    if 'DOJ' in t: return 'probe'
    if 'plaintiff' in t or 'backed' in t: return 'Plaintiff'
    if 'subpoena' in t or 'non-party' in t: return 'Non-party'
    if 'Active' in t or 'Open' in t: return 'Open'
    if re.search(r'[Dd]ismissed|terminated|summary judgment', t): return 'Closed'
    return 'Unverified'

def _pl(n, w): return f'{n} {w}' + ('s' if n != 1 else '')
def _and(xs): return ', '.join(xs[:-1]) + ' and ' + xs[-1] if len(xs) > 1 else (xs[0] if xs else '')

def checks(D):
    """Returns list of dicts: title, desc, state (clear|review|red|wk|nf|nc), count, line."""
    F = [x for x in D['facts'] if not NAME_ONLY.search(_txt(x))]
    latest = {}
    for x in F:
        if x['fact_type'] == 'legal_matter' and isinstance(x['value'], dict) and 'detail' in x['value']:
            k = x['value']['detail']
            if k not in latest or x['retrieved_at'] > latest[k]['retrieved_at']: latest[k] = x
    F = [x for x in F if not (x['fact_type'] == 'legal_matter' and isinstance(x['value'], dict) and 'detail' in x['value'] and latest[x['value']['detail']] is not x)]
    def NEW(field, ft='sanctions_check'):
        return [x for x in F if x['fact_type'] == ft and isinstance(x['value'], dict) and x['value'].get('field') == field]
    SAN = [x for x in F if x['fact_type'] == 'sanctions_check' and 'result' in x['value']]
    LEG = [x for x in F if x['fact_type'] == 'legal_matter' and 'title' in x['value']]
    cases = [(_classify(x['value']['title']), x) for x in LEG if not NON_PARTY.search(x['value']['title'])]
    probe = [x for t, x in cases if t == 'probe']; us = [(t, x) for t, x in cases if t != 'probe']
    opn = [x for t, x in us if t == 'Open']
    TER, EXP, AML, WW, PEP = (NEW(f) for f in ('terrorism_lists', 'export_restrictions', 'aml_penalties', 'courts_worldwide', 'pep'))
    PEPHIT = [x for x in PEP if x['value'].get('entity', '').startswith('partner:')]
    REG = NEW('registration_status', 'fund_fact')
    san_ok = bool(SAN) and SAN[0]['value'].get('result') == 'no_match'
    tok = [m.group(1) for x in opn for m in [re.search(r'by (\w+) token buyers', x['value']['title'])] if m]
    R = lambda t, d, s, c=None, l=None: dict(title=t, desc=d, state=s, count=c, line=l)
    closed = len(us) - len(opn)
    return [
        R('Sanctions', "Government lists of people and companies you can't do business with.", 'clear' if san_ok else 'nc'),
        R('Terrorism financing lists', 'Lists of people and groups linked to funding terrorism.', 'clear' if TER else 'nc'),
        R('Export and investment restrictions', 'Trade or investment bans, e.g. deals with military-linked firms.', 'clear' if EXP else 'nc'),
        R('Financial regulator actions', 'Fines, bans and charges from financial regulators.',
          'review' if probe else 'nc', _pl(len(probe), 'open probe') if probe else None,
          '; '.join(re.sub(r':\s*interlocking', ' into', x['value']['detail']).replace(' at Databricks and Fivetran', '') + (', no charges' if 'no charges' in x['value']['title'] else '') for x in probe) or None),
        R('Money laundering penalties', 'Anti-money-laundering fines and enforcement.', 'clear' if AML else 'nc'),
        R('US court records', 'Federal and state cases, civil and criminal.',
          ('review' if opn else 'clear') if us else 'nc',
          (f'{_pl(len(opn), "active case")} · {len(us)} on file' if opn else (f'{closed} closed' if closed else None)),
          ((_and(tok) + ' token class actions') if tok and len(tok) == len(opn) else _and([x['value']['detail'] for x in opn])) if opn else None),
        R('Court records worldwide', 'Cases outside the U.S.', 'clear' if WW else 'nc', _pl(len(WW), 'non-party mention') if WW else None),
        R('Registration check', 'Registered with the regulator as an investment adviser, and active.', 'clear' if REG else 'nc'),
        R('People behind the fund', 'Partners and owners, each checked against the lists above.', 'clear' if san_ok else 'nc'),
        R('Political ties', 'People at the firm who held government or political roles.', 'wk' if PEPHIT else ('nf' if PEP else 'nc')),
    ]
