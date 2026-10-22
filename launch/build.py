"""Regretamin launch build: search page + one result template per firm, from DB snapshots in data/launch/*.json.
Output: site-launch/. Does not touch the existing site/ build.
Refresh a snapshot (read-only): run launch/firm_snapshot.sql with :slug, save the JSON as data/launch/<slug>.json."""
import os, json, html, glob, shutil, datetime
from checks import checks
E = html.escape
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE); OUT = os.path.join(ROOT, 'site-launch')
PILL = {'clear': ('p-ok', 'Clear'), 'review': ('p-rev', 'Review'), 'red': ('p-red', 'Red flag'), 'wk': ('p-g', 'Worth knowing'), 'nf': ('p-g', 'None found'), 'nc': ('p-g', 'Not checked yet')}
CFG = {'url': os.environ.get('SUPABASE_URL', ''), 'key': os.environ.get('SUPABASE_ANON_KEY', ''),
       'prices': {'single': os.environ.get('STRIPE_PRICE_SINGLE', ''), 'm10': os.environ.get('STRIPE_PRICE_M10', ''), 'm30': os.environ.get('STRIPE_PRICE_M30', '')}}

def page(path, body, root, title='Regretamin'):
    nav = (f'<nav><a class="logo" href="{root}"><img src="{root}logo.svg" alt="">Regretamin</a><div class="r">'
           f'<a href="#" data-open="paywall">Pricing</a><span class="left" id="left"></span><a href="#" data-open="signup" id="signin">Sign in</a></div></nav>')
    modals = f'''<div class="ov" id="signup" hidden><div class="md"><button class="x" data-close>×</button><h2 id="suh">Get 4 more free checks</h2><p class="s">Create a free account. No card needed.</p>
<button class="g" id="google">Continue with Google</button><div class="or">or</div><input class="in" id="em" type="email" placeholder="you@startup.com"><button class="btn" id="magic">Email me a sign-in link</button><p class="msg" id="sumsg"></p></div></div>
<div class="ov" id="paywall" hidden><div class="md w"><button class="x" data-close>×</button><h2 id="pwh">Pricing</h2><p class="s">Counting is in checks: 1 firm = 1 check. Monthly plans renew; if you run out, buy more checks any time.</p><div class="price">
<div class="pr"><h4>Single check</h4><b>$10</b><p>One firm, full details and sources.</p><button class="btn o" data-buy="single">Buy 1 check</button></div>
<div class="pr hl"><h4>Starter</h4><b>$19<small>/mo</small></b><p>10 checks a month.</p><button class="btn" data-buy="m10">Get 10 checks</button></div>
<div class="pr"><h4>Pro</h4><b>$49<small>/mo</small></b><p>30 checks a month.</p><button class="btn o" data-buy="m30">Get 30 checks</button></div></div></div></div>'''
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write(f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{E(title)}</title>
<link rel="stylesheet" href="{root}style.css"><script>window.REGRET={json.dumps(CFG)};window.REGRET_ROOT="{root}"</script>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script><script src="{root}firms.js"></script><script defer src="{root}app.js"></script></head><body>{nav}{body}{modals}</body></html>''')

def SB(ph, sm=False):
    return f'<form class="sb{" sm" if sm else ""}" data-search><input name="q" list="firms" placeholder="{ph}" autocomplete="off"><button class="btn">Check</button></form>'

def result(D):
    F = D['firm']; rows = checks(D)
    chk = datetime.date.fromisoformat(max(x['retrieved_at'] for x in D['facts'])[:10]).strftime('%b %-d, %Y')
    o = ''
    for i, r in enumerate(rows, 1):
        cls, lab = PILL[r['state']]
        cnt = f'<span class="cnt {"cg" if r["state"] == "clear" else "ca"}">{E(r["count"])}</span>' if r['count'] else ''
        line = f'<em>{E(r["line"])}</em>' if r['line'] else ''
        o += (f'<div class="row{" last" if i == 10 else ""}"><span class="n">{i:02d}</span><div class="tx"><b>{E(r["title"])}</b><span>{E(r["desc"])}</span>{line}</div>'
              f'<div class="pc"><span class="pill {cls}"><i></i>{lab}</span>{cnt}</div><span class="lk">🔒 Details</span><div class="det" data-row="{i}"></div></div>')
    meta = ' · '.join(x for x in [F.get('hq'), f'since {F["founded_year"]}' if F.get('founded_year') else '', F.get('primary_domain'), f'checked {chk}'] if x)
    return f'''<main class="wrap" data-firm="{E(F["slug"])}"><div class="hd"><div><h1>{E(F["name"])}</h1><div class="m">{E(meta)}</div></div>{SB("Check another VC", True)}</div>
<div class="list">{o}</div><div class="unlock"><div><b>See details and sources for every check</b><p>Case summaries, list names and links, for this firm.</p></div><button class="btn" id="unlock">Unlock with 1 check</button></div>
<p class="fine">Facts from public records as of {chk}. Political ties are shown for context and are not counted. Name-only matches on different people are left out.</p></main>'''

def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    for f in ('style.css', 'logo.svg', 'app.js'): shutil.copy(os.path.join(HERE, f if f != 'app.js' else 'js/app.js'), OUT)
    firms = []
    for p in sorted(glob.glob(os.path.join(ROOT, 'data', 'launch', '*.json'))):
        D = json.load(open(p)); F = D['firm']; firms.append((F['slug'], F['name'], F.get('short_name')))
        page(os.path.join(OUT, 'vc', F['slug'], 'index.html'), result(D), '../../', F['name'] + ' · Regretamin')
    dl = '<datalist id="firms">' + ''.join(f'<option value="{E(n)}">' for _, n, _ in firms) + '</datalist>'
    idx = json.dumps({(s2 or n).lower(): s for s, n, s2 in firms} | {n.lower(): s for s, n, _ in firms})
    CH = ['Sanctions & terrorism lists', 'Export & investment restrictions', 'Financial regulators', 'Money laundering penalties', 'US & worldwide courts', 'Registration', 'People behind the fund', 'Political ties']
    page(os.path.join(OUT, 'index.html'), f'''<main class="wrap"><div class="hero"><h1>Check your VC<br><span>before you sign.</span></h1><p>10 checks on any venture firm and the people behind it, in one place.</p>
{SB("Search a VC firm, e.g. Andreessen Horowitz")}<div class="chips">{"".join(f"<span>{c}</span>" for c in CH)}</div>
<p class="note">We check government sanctions lists, financial regulators, court records and public registries.</p></div><div style="height:90px"></div></main>''', '')
    page(os.path.join(OUT, 'pending', 'index.html'), '''<main class="wrap"><div class="pend"><div class="sp"></div><h1>We're checking this firm now</h1><p style="color:var(--ink2);font-size:18px"><b id="pq"></b> isn't in our database yet. We're running all 10 checks — we'll let you know in 5 minutes.</p>
<form id="notify"><input class="in" type="email" name="email" required placeholder="you@startup.com"><button class="btn">Email me</button></form><p class="msg" id="pmsg"></p><p class="note">This uses 1 check only when the result is ready.</p></div></main>''', '../')
    open(os.path.join(OUT, 'firms.js'), 'w').write('window.REGRET_FIRMS=' + idx + ';' + f'document.addEventListener("DOMContentLoaded",()=>document.body.insertAdjacentHTML("beforeend",{json.dumps(dl)}))')
    print('built', len(firms), 'firms ->', OUT)

if __name__ == '__main__': main()
