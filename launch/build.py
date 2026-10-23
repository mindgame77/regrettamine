"""Regretamin launch build: search page + one static company-page shell per firm in data/launch/*.json.
The shell holds no firm data beyond the name: every section is filled from the firm_page() RPC (js/company.js).
Output: site-launch/. Does not touch the existing site/ build.
Refresh a snapshot (read-only): run launch/firm_snapshot.sql with :slug, save the JSON as data/launch/<slug>.json;
then python3 launch/sync_checks.py data/launch/*.json > a new migration to update the 10 check rows."""
import os, json, html, glob, shutil
E = html.escape
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE); OUT = os.path.join(ROOT, 'site-launch')
PILL = {'clear': ('p-ok', 'Clear'), 'review': ('p-rev', 'Review'), 'red': ('p-red', 'Red flag'), 'wk': ('p-g', 'Worth knowing'), 'nf': ('p-g', 'None found'), 'nc': ('p-g', 'Not checked yet')}
NOINDEX = os.environ.get('REGRET_NOINDEX') == '1'
CFG = {'url': os.environ.get('SUPABASE_URL', ''), 'key': os.environ.get('SUPABASE_ANON_KEY', ''),
       'prices': {'single': os.environ.get('STRIPE_PRICE_SINGLE', ''), 'm10': os.environ.get('STRIPE_PRICE_M10', ''), 'm30': os.environ.get('STRIPE_PRICE_M30', '')}}

def page(path, body, root, title='Regretamin', company=False):
    scripts = (f'<script defer src="{root}company.js"></script>' if company else '') + f'<script defer src="{root}app.js"></script>'
    nav = (f'<nav><a class="logo" href="{root}"><img src="{root}logo.svg" alt="">Regretamin</a><div class="r">'
           f'<a href="#" data-open="paywall">Pricing</a><span class="left" id="left"></span><a href="#" data-open="signup" id="signin">Sign in</a>'
           f'<span class="navr" id="acct" hidden><button type="button" class="ab" id="acctbtn" aria-haspopup="true" aria-expanded="false"><span class="av" id="av"></span><span class="nm">Account ▾</span></button>'
           f'<div class="dd" id="acctdd" hidden><div class="hd2"><div class="em" id="ddem"></div><div class="pl2" id="ddplan"></div><div class="bal"><span>Checks left</span><b id="ddleft"></b></div></div>'
           f'<a href="{root}account/">Account</a><a href="{root}my-checks/">My checks</a><a href="#" data-open="paywall">Buy more checks</a><div class="sep"></div><a class="so" href="#" id="signout">Sign out</a></div></span></div></nav>')
    modals = f'''<div class="ov" id="signup" hidden><div class="md"><button class="x" data-close>×</button><h2 id="suh">Get 4 more free checks</h2><p class="s">Create a free account. No card needed.</p>
<button class="g" id="google">Continue with Google</button><div class="or">or</div><input class="in" id="em" type="email" placeholder="you@startup.com"><button class="btn" id="magic">Email me a sign-in link</button><p class="msg" id="sumsg"></p></div></div>
<div class="ov" id="paywall" hidden><div class="md w"><button class="x" data-close>×</button><h2 id="pwh">Pricing</h2><p class="s">Counting is in checks: 1 firm = 1 check. Monthly plans renew; if you run out, buy more checks any time.</p><div class="price">
<div class="pr"><h4>Single check</h4><b>$10</b><p>One firm, full details and sources.</p><button class="btn o" data-buy="single">Buy 1 check</button></div>
<div class="pr hl"><h4>Starter</h4><b>$19<small>/mo</small></b><p>10 checks a month.</p><button class="btn" data-buy="m10">Get 10 checks</button></div>
<div class="pr"><h4>Pro</h4><b>$49<small>/mo</small></b><p>30 checks a month.</p><button class="btn o" data-buy="m30">Get 30 checks</button></div></div></div></div>'''
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write(f'''<!doctype html><html lang="en"><head>{'<meta name="robots" content="noindex">' if NOINDEX else ''}<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{E(title)}</title>
<link rel="icon" href="{root}logo.svg"><link rel="stylesheet" href="{root}style.css"><script>window.REGRET={json.dumps(CFG)};window.REGRET_ROOT="{root}"</script>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>{scripts}</head><body>{nav}{body}{modals}</body></html>''')

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
    return f'<form class="sb{" sm" if sm else ""}" data-search><input name="q" placeholder="{ph}" autocomplete="off" aria-label="VC firm"><button class="btn">Check</button></form>'

def result(F):
    return f'''<main class="wrap prof" data-firm="{E(F["slug"])}"><form class="sb big ps0" data-search><svg class="mg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg><input name="q" value="{E(F["name"])}" aria-label="VC firm" autocomplete="off" onfocus="this.select()"><button class="btn">Check</button></form>
<div class="ph"><h1>{E(F["name"])}</h1><p class="m"></p><div class="hfs"></div></div><div class="csum" hidden></div><div class="spl"></div>
<div class="unlock" id="lockcard" hidden><div><b></b><p></p></div><button class="btn" id="unlock">See them with 1 check</button></div>
<div class="pgrid"><div class="pmain"></div><nav class="toc" aria-label="On this page"></nav></div><p class="fine">Public-record information, not legal or investment advice.</p></main>
<div class="ov pp-ov" id="paycase" hidden><div class="pp" role="dialog" aria-modal="true" aria-labelledby="pph"><button class="pp-x" data-close aria-label="Close">×</button><header class="pp-hero"><span class="lockctx" id="pcase"></span><h1 id="pph">Unlock this firm</h1><p class="sub">Open the gray entries with a check. Pay once or monthly.</p></header><div class="pp-bal"><div><b id="pbal">Checking your balance…</b><span id="puse"></span></div><button class="pb v" id="usecheck" disabled>Use 1 check</button></div><p class="msg" id="pmsg2"></p><section class="pp-plans"><div class="pl"><h3>Single check</h3><div class="pp-price"><b>$10</b><span>one time</span><small>$10 per check</small></div><p class="bill">Opens one firm</p><button class="pb w" data-buy="single">Buy 1 check</button><ul><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>Every gray entry for this firm</li><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>Names, parties, courts, sources</li><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>Yours to keep</li></ul></div><div class="pl rec"><span class="rtag">Most picked</span><h3>Starter</h3><div class="pp-price"><b>$19</b><span>/month</span><small>$1.90 per check</small></div><p class="bill">10 checks a month</p><button class="pb c" data-buy="m10">Start Starter</button><ul><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>10 firms a month</li><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>Full sources on every entry</li></ul></div><div class="pl"><h3>Pro</h3><div class="pp-price"><b>$49</b><span>/month</span><small>$1.63 per check</small></div><p class="bill">30 checks a month</p><button class="pb w" data-buy="m30">Start Pro</button><ul><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>30 firms a month</li><li><i><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></i>Full sources on every entry</li></ul></div></section><div class="pp-sgn" id="panon" hidden><div><b id="psgnh">Sign in to buy</b><span>Checks are saved to your account. Free checks on this device move over.</span></div><div class="sb2"><button class="pb w gbtn" data-google><svg width="18" height="18" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"/><path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"/><path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z"/><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"/></svg>Continue with Google</button><div class="or">or</div><form class="ml" data-magic><input type="email" name="email" required placeholder="you@company.com" aria-label="Email"><button class="pb v">Email me a link</button></form></div><p class="msg" data-magicmsg></p></div><p class="fine2">Monthly plans renew each month. 1 firm = 1 check.</p></div></div>'''

SIGNED_OUT = '<div class="emp" data-out hidden><h2>Sign in to see this page</h2><p>Your account, checks and saved firms are here once you sign in.</p><button class="btn" data-open="signup" style="margin-top:20px">Sign in</button></div>'
ACCOUNT = f'''<main class="ac" id="account"><h1>Account</h1><p class="sub" id="aem"></p>{SIGNED_OUT}<div data-in hidden>
<div class="sum"><div><small>Plan</small><b id="aplan"></b><span id="aplan2"></span></div><div><small>Checks left</small><b class="v" id="aleft"></b><span id="aleft2"></span></div><div><small>Renews</small><b id="aren"></b><span id="aren2"></span></div></div>
<div class="acts"><button class="btn o" id="manage" hidden>Manage subscription</button><button class="btn o" data-open="paywall" id="pick" hidden>Pick a plan</button><button class="btn" data-open="paywall">Buy more checks</button></div><p class="msg err" id="amsg"></p>
<section class="sec"><h2>My checks</h2><div class="card mck"><div><b id="mcn"></b><p id="mcl"></p></div><a class="btn o" href="../my-checks/">View all →</a></div></section>
<section class="sec"><h2>Email</h2><p class="d">Used to sign in. No password needed.</p><form class="card" id="emform"><label for="nem">New email</label><div class="frm"><input class="in" id="nem" name="email" type="email" required placeholder="you@company.com"><button class="btn o">Send confirmation link</button></div><p class="hint" id="emmsg">We email a link to the new address. Your email changes when you open it.</p></form></section>
<section class="sec"><h2>Danger zone</h2><div class="dz"><div><b>Delete account</b><p id="dzp">Permanently deletes your account, remaining checks and history.</p></div><button class="btn dg" data-open="delacct">Delete account</button></div></section></div></main>
<div class="ov" id="delacct" hidden><div class="md" role="dialog" aria-modal="true" aria-labelledby="delh"><button class="x" data-close>×</button><h2 id="delh">Delete your account?</h2><p class="s">This can’t be undone. Here’s what happens:</p><ul class="cons" id="cons"></ul>
<label for="deltype" style="font-weight:700;font-size:14px">Type DELETE to confirm</label><input class="in" id="deltype" autocomplete="off" style="margin-top:8px"><div class="row2"><button class="btn o" data-close>Keep my account</button><button class="btn dgs" id="delgo" disabled>Delete account</button></div><p class="msg err" id="delmsg"></p></div></div>'''
MYCHECKS = f'''<main class="ac mc" id="mychecks"><h1>My checks</h1><p class="sub">Every firm you’ve checked. Reopening a result is free.</p>{SIGNED_OUT}<div data-in hidden><div class="bal2" id="mbal"></div>
<div id="mlist" hidden><div class="tb"><label class="srch">⌕<input id="mq" type="search" placeholder="Search your checks" aria-label="Search your checks"></label><select class="sort" id="msort" aria-label="Sort"><option value="new">Newest first</option><option value="old">Oldest first</option><option value="az">Name A–Z</option></select></div>
<div class="ck" style="margin-top:16px"><div class="mr h"><span></span><span>Firm</span><span>Checked</span><span>Status</span><span></span></div><div id="mrows"></div></div><p class="hint" id="mnone" hidden>No checks match your search.</p></div>
<div class="emp" id="mempty" hidden><h2>No checks yet</h2><p>Check your VC before you sign. Search a firm to run your first check.</p>{SB("Search a VC firm, e.g. Andreessen Horowitz")}</div></div></main>'''

def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    for f in ('style.css', 'logo.svg', 'js/app.js', 'js/company.js'): shutil.copy(os.path.join(HERE, f), OUT)
    shutil.copytree(os.path.join(HERE, 'fav'), os.path.join(OUT, 'fav'))
    firms = []
    for p in sorted(glob.glob(os.path.join(ROOT, 'data', 'launch', '*.json'))):
        F = json.load(open(p))['firm']; firms.append(F['slug'])
        page(os.path.join(OUT, 'vc', F['slug'], 'index.html'), result(F), '../../', F['name'] + ' · Regretamin', company=True)
    CH = ['Sanctions & terrorism lists', 'Export & investment restrictions', 'Financial regulators', 'Money laundering penalties', 'US & worldwide courts', 'Registration', 'People behind the fund', 'Political ties']
    DEMO = [('Sanctions', 'clear', None), ('Financial regulator actions', 'review', '1 open probe'), ('US court records', 'clear', '3 closed'), ('People behind the fund', 'clear', None)]
    demo = ''.join(f'<div class="dr"><span>{E(t)}</span><span class="pc"><span class="pill {PILL[st][0]}"><i></i>{PILL[st][1]}</span>{f"<span class=\'cnt {"ca" if st=="review" else "cg"}\'>{E(c)}</span>" if c else ""}</span></div>' for t, st, c in DEMO)
    page(os.path.join(OUT, 'index.html'), f'''<main class="wrap"><div class="hero"><h1>Check your VC<br><span>before you sign.</span></h1>
{SB("Search a VC firm, e.g. Andreessen Horowitz")}<div class="chips">{"".join(f"<span>{c}</span>" for c in CH)}</div></div>
<div class="demo" aria-hidden="true"><div class="dh"><b>Example Ventures</b><em>10 checks · example</em></div>{demo}<div class="dr fade"><span>+ 6 more checks</span></div></div><div style="height:64px"></div></main>{press()}<div style="height:80px"></div>''', '')
    page(os.path.join(OUT, 'pending', 'index.html'), '''<main class="wrap"><div class="pend"><div class="sp"></div><h1>We're checking this firm now</h1><p style="color:var(--ink2);font-size:18px"><b id="pq"></b> isn't in our database yet. We're running all 10 checks — we'll let you know in 5 minutes.</p>
<form id="notify"><input class="in" type="email" name="email" required placeholder="you@startup.com"><button class="btn">Email me</button></form><p class="msg" id="pmsg"></p><p class="note">This uses 1 check only when the result is ready.</p></div></main>''', '../')
    page(os.path.join(OUT, 'account', 'index.html'), ACCOUNT, '../', 'Account · Regretamin')
    page(os.path.join(OUT, 'my-checks', 'index.html'), MYCHECKS, '../', 'My checks · Regretamin')
    print('built', len(firms), 'firms ->', OUT)

if __name__ == '__main__': main()
