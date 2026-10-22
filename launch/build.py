"""Regretamin launch build: search page + one result template per firm, from DB snapshots in data/launch/*.json.
Output: site-launch/. Does not touch the existing site/ build.
Refresh a snapshot (read-only): run launch/firm_snapshot.sql with :slug, save the JSON as data/launch/<slug>.json."""
import os, json, html, glob, shutil, datetime
from checks import checks
E = html.escape
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE); OUT = os.path.join(ROOT, 'site-launch')
PILL = {'clear': ('p-ok', 'Clear'), 'review': ('p-rev', 'Review'), 'red': ('p-red', 'Red flag'), 'wk': ('p-g', 'Worth knowing'), 'nf': ('p-g', 'None found'), 'nc': ('p-g', 'Not checked yet')}
NOINDEX = os.environ.get('REGRET_NOINDEX') == '1'
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
    open(path, 'w').write(f'''<!doctype html><html lang="en"><head>{'<meta name="robots" content="noindex">' if NOINDEX else ''}<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{E(title)}</title>
<link rel="stylesheet" href="{root}style.css"><script>window.REGRET={json.dumps(CFG)};window.REGRET_ROOT="{root}"</script>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script><script src="{root}firms.js"></script><script defer src="{root}app.js"></script></head><body>{nav}{body}{modals}</body></html>''')

PRESS = [  # approved press option 1; links checked 2026-10-22 (Reuters/Bloomberg bot-block curl but are live)
    ('Reuters', 'Uber investor sues to force former CEO Kalanick off board', 'Aug 2017', 'https://www.reuters.com/article/world/uber-investor-sues-to-force-former-ceo-kalanick-off-board-idUSKBN1AQ2EV/'),
    ('CNBC', 'SoftBank sues social media startup it invested in, alleging it faked user numbers', 'Aug 2023', 'https://www.cnbc.com/2023/08/04/softbank-sues-social-media-startup-irl-alleging-fake-user-numbers.html'),
    ('TechCrunch', 'Byju’s investors vote to remove founder', 'Feb 2024', 'https://techcrunch.com/2024/02/23/byjus-investors-unanimously-vote-to-remove-founder/'),
    ('Bloomberg', 'A $1 Million Bet on a Tech Startup Spawns Investor-Founder Fight', 'Apr 2024', 'https://www.bloomberg.com/news/articles/2024-04-24/toptal-founder-and-investor-tensions-spark-lawsuit'),
    ('Axios', 'Khosla sues entrepreneur for fraud', 'Sep 2017', 'https://www.axios.com/2017/12/15/khosla-sues-entrepreneur-for-fraud-1513305375'),
]
def press():
    wm = lambda o: f'<span class="wm{" s" if o in ("TechCrunch", "CNBC", "Axios") else ""}">{E(o)}</span>'
    li = ''.join(f'<li><a href="{E(u)}" target="_blank" rel="noopener">{wm(o)}<span>{E(h)}</span><em>{d}</em></a></li>' for o, h, d, u in PRESS)
    return f'<section class="press"><h2>Founders vs. their investors, in the news</h2><div class="logos">{"".join(wm(o) for o, *_ in PRESS)}</div><ul>{li}</ul></section>'

def SB(ph, sm=False):
    return f'<form class="sb{" sm" if sm else ""}" data-search><input name="q" list="firms" placeholder="{ph}" autocomplete="off"><button class="btn">Check</button></form>'

def result(D, P):
    F = D['firm']; rows = checks(D)
    cp = P[:-5] + '.counts.json'
    CN = json.load(open(cp)) if os.path.exists(cp) else {'rows': {}, 'total': 0}
    chk = datetime.date.fromisoformat(max(x['retrieved_at'] for x in D['facts'])[:10]).strftime('%b %-d, %Y')
    o = ''
    def lk(i):
        n = CN['rows'].get(str(i), 0)
        return f'<span class="lk">{n} fact{"s" if n != 1 else ""}</span>' if n else '<span class="lk"></span>'
    for i, r in enumerate(rows, 1):
        cls, lab = PILL[r['state']]
        cnt = f'<span class="cnt {"cg" if r["state"] == "clear" else "ca"}">{E(r["count"])}</span>' if r['count'] else ''
        line = ''  # option A: row 'line' names cases (e.g. Lido/Compound, DOJ); not shown in the public HTML, details come after unlock
        o += (f'<div class="row{" last" if i == 10 else ""}"><span class="n">{i:02d}</span><div class="tx"><b>{E(r["title"])}</b><span>{E(r["desc"])}</span>{line}</div>'
              f'<div class="pc"><span class="pill {cls}"><i></i>{lab}</span>{cnt}</div>{lk(i)}<div class="gl" data-row="{i}"></div><div class="det" data-row="{i}"></div></div>')
    meta = ' · '.join(x for x in [F.get('hq'), f'since {F["founded_year"]}' if F.get('founded_year') else '', F.get('primary_domain'), f'checked {chk}'] if x)
    return f'''<main class="wrap" data-firm="{E(F["slug"])}" data-total="{CN['total']}"><div class="rh"><form class="sb big" data-search><svg class="mg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg><input name="q" list="firms" value="{E(F["name"])}" aria-label="VC firm" autocomplete="off" onfocus="this.select()"><button class="btn">Check</button></form><div class="m">{E(meta)}</div></div>
<div class="unlock" id="lockcard"><div><b>🔒 {CN['total']} facts with sources about {E(F['name'])}</b><p>Gray entries open with 1 check: names, parties, courts and source links for all 10 checks.</p></div><button class="btn" id="unlock">See them with 1 check</button></div>
<div class="list">{o}</div><p class="fine">Facts from public records as of {chk}. Gray entries show the kind of record, year and status only; names, parties, courts, list names and sources open with a check. Political ties are shown for context and are not counted. Name-only matches on different people are left out.</p></main>
<div class="ov pp-ov" id="paycase" hidden><div class="pp" role="dialog" aria-modal="true" aria-labelledby="pph"><button class="pp-x" data-close aria-label="Close">×</button><header class="pp-hero"><span class="lockctx" id="pcase"></span><h1 id="pph">Check first.<br><span class="mark">Sign second</span>.</h1><p class="sub">Open the gray entries with a check. Pay once or monthly.</p></header><div class="pp-bal"><div><b id="pbal">Checking your balance…</b><span>Use 1 to open all {CN['total']} sourced facts about {E(F['name'])}.</span></div><button class="pb v" id="usecheck" disabled>Use 1 check</button></div><p class="msg" id="pmsg2"></p><section class="pp-plans"><div class="pl"><h3>Single check</h3><div class="pp-price"><b>$10</b><span>one time</span></div><p class="bill">Opens one firm</p><button class="pb w" data-buy="single">Buy 1 check</button><ul><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>Every gray entry for this firm</li><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>Names, parties, courts, sources</li><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>Yours to keep</li></ul></div><div class="pl rec"><span class="rtag">Most picked</span><h3>Starter</h3><div class="pp-price"><b>$19</b><span>/month</span></div><p class="bill">10 checks a month</p><button class="pb c" data-buy="m10">Start Starter</button><ul><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>10 firms a month</li><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>Full sources on every entry</li></ul></div><div class="pl"><h3>Pro</h3><div class="pp-price"><b>$49</b><span>/month</span></div><p class="bill">30 checks a month</p><button class="pb w" data-buy="m30">Start Pro</button><ul><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>30 firms a month</li><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>Full sources on every entry</li></ul></div></section><div class="pp-sgn" id="panon" hidden><div><b id="psgnh">Sign in to buy</b><span>Checks are saved to your account. Free checks on this device move over.</span></div><div class="sb2"><button class="pb w gbtn" data-google><svg width="18" height="18" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"/><path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"/><path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z"/><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"/></svg>Continue with Google</button><div class="or">or</div><form class="ml" data-magic><input type="email" name="email" required placeholder="you@company.com" aria-label="Email"><button class="pb v">Email me a link</button></form></div><p class="msg" data-magicmsg></p></div><p class="fine2">Monthly plans renew each month. 1 firm = 1 check.</p></div></div>'''

def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    for f in ('style.css', 'logo.svg', 'app.js'): shutil.copy(os.path.join(HERE, f if f != 'app.js' else 'js/app.js'), OUT)
    firms = []
    for p in sorted(x for x in glob.glob(os.path.join(ROOT, 'data', 'launch', '*.json')) if not x.endswith('.counts.json')):
        D = json.load(open(p)); F = D['firm']; firms.append((F['slug'], F['name'], F.get('short_name')))
        page(os.path.join(OUT, 'vc', F['slug'], 'index.html'), result(D, p), '../../', F['name'] + ' · Regretamin')
    dl = '<datalist id="firms">' + ''.join(f'<option value="{E(n)}">' for _, n, _ in firms) + '</datalist>'
    idx = json.dumps({(s2 or n).lower(): s for s, n, s2 in firms} | {n.lower(): s for s, n, _ in firms})
    CH = ['Sanctions & terrorism lists', 'Export & investment restrictions', 'Financial regulators', 'Money laundering penalties', 'US & worldwide courts', 'Registration', 'People behind the fund', 'Political ties']
    DEMO = [('Sanctions', 'clear', None), ('Financial regulator actions', 'review', '1 open probe'), ('US court records', 'clear', '3 closed'), ('People behind the fund', 'clear', None)]
    demo = ''.join(f'<div class="dr"><span>{E(t)}</span><span class="pc"><span class="pill {PILL[st][0]}"><i></i>{PILL[st][1]}</span>{f"<span class=\'cnt {"ca" if st=="review" else "cg"}\'>{E(c)}</span>" if c else ""}</span></div>' for t, st, c in DEMO)
    page(os.path.join(OUT, 'index.html'), f'''<main class="wrap"><div class="hero"><h1>Check your VC<br><span>before you sign.</span></h1>
{SB("Search a VC firm, e.g. Andreessen Horowitz")}<div class="chips">{"".join(f"<span>{c}</span>" for c in CH)}</div></div>
<div class="demo" aria-hidden="true"><div class="dh"><b>Example Ventures</b><em>10 checks · example</em></div>{demo}<div class="dr fade"><span>+ 6 more checks</span></div></div><div style="height:64px"></div></main>{press()}<div style="height:80px"></div>''', '')
    page(os.path.join(OUT, 'pending', 'index.html'), '''<main class="wrap"><div class="pend"><div class="sp"></div><h1>We're checking this firm now</h1><p style="color:var(--ink2);font-size:18px"><b id="pq"></b> isn't in our database yet. We're running all 10 checks — we'll let you know in 5 minutes.</p>
<form id="notify"><input class="in" type="email" name="email" required placeholder="you@startup.com"><button class="btn">Email me</button></form><p class="msg" id="pmsg"></p><p class="note">This uses 1 check only when the result is ready.</p></div></main>''', '../')
    open(os.path.join(OUT, 'firms.js'), 'w').write('window.REGRET_FIRMS=' + idx + ';' + f'document.addEventListener("DOMContentLoaded",()=>document.body.insertAdjacentHTML("beforeend",{json.dumps(dl)}))')
    print('built', len(firms), 'firms ->', OUT)

if __name__ == '__main__': main()
