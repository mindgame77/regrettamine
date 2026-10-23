"""Regretamin launch build: search page + one static company-page shell per firm in data/launch/*.json.
The shell holds no firm data beyond the name: every section is filled from the firm_page() RPC (js/company.js).
All copy, plans and section presentation come from launch/copy.json (also handed to the JS as window.REGRET.copy).
Output: site-launch/. Deploy to the preview with launch/deploy_preview.sh (see launch/HOW-TO-CHANGE.md).
Refresh a snapshot (read-only): run launch/firm_snapshot.sql with :slug, save the JSON as data/launch/<slug>.json;
then python3 launch/sync_checks.py data/launch/*.json > a new migration to update the 10 check rows."""
import os, json, html, glob, shutil
from legal import privacy, terms
E = html.escape
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE); OUT = os.path.join(ROOT, 'site-launch')
COPY = json.load(open(os.path.join(HERE, 'copy.json')))
S = COPY['site']
NOINDEX = os.environ.get('REGRET_NOINDEX') == '1'
CFG = {'url': os.environ.get('SUPABASE_URL', ''), 'key': os.environ.get('SUPABASE_ANON_KEY', ''), 'copy': COPY}
GLOGO = '''<svg width="18" height="18" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"/><path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"/><path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z"/><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"/></svg>'''

def billing():  # Monthly|Yearly toggle for both pricing popups; their plan cards are drawn by js/app.js (drawPlans) from copy.json plans
    B = S['billing']
    return (f'<div class="bt" role="radiogroup" aria-label="{B["aria"]}"><div><button type="button" role="radio" aria-checked="true" class="on" data-yearly="0">{B["monthly"]}</button>'
            f'<button type="button" role="radio" aria-checked="false" data-yearly="1">{B["yearly"]} <em>{B["badge"]}</em></button></div></div>')

def code_field():  # "Have a code?" field for both pricing popups (checked by the validate-code function)
    K = S['code']
    return (f'<div class="code"><a href="#" data-codeopen>{K["link"]}</a><form class="cf" data-code hidden><input name="code" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="{K["placeholder"]}" aria-label="{K["aria"]}">'
            f'<button class="pb v" data-apply>{K["apply"]}</button><button type="button" class="pb v" data-remove hidden>{K["remove"]}</button></form><p class="cn" data-codemsg></p></div>')

def pricing_modal():  # nav "Pricing" popup
    p = S['pricing']
    return f'<div class="ov" id="paywall" hidden><div class="md w"><button class="x" data-close>×</button><h2 id="pwh">{p["title"]}</h2><p class="s">{p["sub"]}</p>{billing()}<div class="price" data-plans="nav"></div><p class="msg" id="pwmsg"></p>{code_field()}</div></div>'

def page(path, body, root, title=S['brand'], company=False, active=''):
    n, su = S['nav'], S['signup']
    hon = ' class="on" aria-current="page"' if active == 'hwc' else ''
    scripts = (f'<script defer src="{root}company.js"></script>' if company else '') + f'<script defer src="{root}app.js"></script>'
    nav = (f'<nav><a class="logo" href="{root}"><img src="{root}logo.svg" alt="">{S["brand"]}</a><div class="r">'
           f'<a href="{root}how-we-check/"{hon}>{n["how_we_check"]}</a><a href="#" data-open="paywall">{n["pricing"]}</a><span class="left" id="left"></span><a href="#" data-open="signup" id="signin">{n["sign_in"]}</a>'
           f'<span class="navr" id="acct" hidden><button type="button" class="ab" id="acctbtn" aria-haspopup="true" aria-expanded="false"><span class="av" id="av"></span><span class="nm">{n["account_btn"]}</span></button>'
           f'<div class="dd" id="acctdd" hidden><div class="hd2"><div class="em" id="ddem"></div><div class="pl2" id="ddplan"></div><div class="bal"><span>{n["checks_left"]}</span><b id="ddleft"></b></div></div>'
           f'<a href="{root}account/">{n["account"]}</a><a href="{root}my-checks/">{n["my_checks"]}</a><a href="#" data-open="paywall">{n["buy_more"]}</a><div class="sep"></div><a class="so" href="#" id="signout">{n["sign_out"]}</a></div></span></div></nav>')
    modals = f'''<div class="ov sgo" id="signup" hidden><div class="md sgm" role="dialog" aria-modal="true" aria-labelledby="suh"><div class="sgi"><button class="x" data-close aria-label="Close">×</button><div class="sg4" aria-hidden="true"><b>+4</b><span>free<br>credits</span></div><h2 id="suh" data-t="{su["title"]}">{su["title"]}</h2><p class="s">{su["sub"]}</p>
<button type="button" class="gbx" id="google"><span class="gi">{GLOGO}</span><span class="gl">{su["google"]}</span></button><div class="orx">{su["or"]}</div><div class="emr"><input class="in" id="em" type="email" placeholder="{su["email_placeholder"]}" aria-label="{su["email_aria"]}"><button type="button" class="btn o" id="magic">{su["magic"]}</button></div><p class="sgt">{"".join(f"<span>{t}</span>" for t in su["trust"])}</p><p class="msg" id="sumsg"></p></div></div></div>
{pricing_modal()}'''
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write(f'''<!doctype html><html lang="en"><head>{'<meta name="robots" content="noindex">' if NOINDEX else ''}<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{E(title)}</title>
<link rel="icon" href="{root}logo.svg"><link rel="stylesheet" href="{root}style.css"><script>window.REGRET={json.dumps(CFG)};window.REGRET_ROOT="{root}"</script>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>{scripts}</head><body>{nav}{body}{FOOT(root)}{modals}</body></html>''')

FOOT = lambda root: f'<footer class="ft"><span>© 2026 Know Your Group INC.</span><a href="{root}privacy/">Privacy</a><a href="{root}terms/">Terms</a></footer>'

def press():
    L = S['landing']
    wm = lambda o: f'<span class="wm{" s" if o in L["press_small_wordmarks"] else ""}">{E(o)}</span>'
    li = ''.join(f'<li><a href="{E(u)}" target="_blank" rel="noopener">{wm(o)}<span>{E(h)}</span><em>{d}</em></a></li>' for o, h, d, u in L['press'])
    return f'<section class="press"><h2>{L["press_h2"]}</h2><div class="logos">{"".join(wm(o) for o, *_ in L["press"])}</div><ul>{li}</ul></section>'

def SB(sm=False):
    return f'<form class="sb{" sm" if sm else ""}" data-search><input name="q" placeholder="{S["search_placeholder"]}" autocomplete="off" aria-label="{S["search_aria"]}"><button class="btn">{S["search_button"]}</button></form>'

def pay_plans():  # plan area in the company-page unlock popup
    return billing() + '<section class="pp-plans" data-plans="pay"></section>' + code_field()

def bigsearch(F, cls=''):
    return f'<form class="sb big{" " + cls if cls else ""}" data-search><svg class="mg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg><input name="q" value="{E(F["name"])}" aria-label="{S["search_aria"]}" autocomplete="off" onfocus="this.select()"><button class="btn">{S["search_button"]}</button></form>'

# Save button by the firm name (js/app.js saveBtn shows it only to signed-in users who checked the firm)
SAVE = f'<button type="button" class="sv" data-save hidden aria-pressed="false"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linejoin="round"><path d="M6 3h12v18l-6-4-6 4z"/></svg><span>{COPY["js"]["save_btn"]}</span></button>'

def summary(F):  # /vc/<slug>/: name + Save, key facts, the 10 checks (closed), "See the full check" (js/company.js summary)
    Q = S['summary']
    return f'''<main class="wrap sumpg unlocked" data-firm="{E(F["slug"])}" data-view="summary"><div class="rh">{bigsearch(F)}</div>
<div class="fh"><h1>{E(F["name"])}</h1><div>{SAVE}</div></div><div class="kf"></div><div class="list"></div>
<div class="full"><div><b>{E(Q["full_h"].format(firm=F["name"]))}</b><p>{Q["full_p"]}</p></div><a href="full/">{Q["full_btn"]}</a></div><p class="fine">{S["result"]["fine"]}</p></main>'''

def result(F):
    r, p = S['result'], S['pay']
    return f'''<main class="wrap prof" data-firm="{E(F["slug"])}">{bigsearch(F, "ps0")}
<div class="ph"><h1>{E(F["name"])}{SAVE}</h1><p class="m"></p><div class="hfs"></div></div><div class="csum" hidden></div><div class="spl"></div>
<div class="unlock" id="lockcard" hidden><div><b></b><p></p></div><button class="btn" id="unlock">{r["lock_button"]}</button></div>
<div class="pgrid"><div class="pmain"></div><nav class="toc" aria-label="{r["toc_aria"]}"></nav></div><p class="fine">{r["fine"]}</p></main>
<div class="ov pp-ov" id="paycase" hidden><div class="pp" role="dialog" aria-modal="true" aria-labelledby="pph"><button class="pp-x" data-close aria-label="{p["close"]}">×</button><header class="pp-hero"><span class="lockctx" id="pcase"></span><h1 id="pph">{p["title"]}</h1><p class="sub">{p["sub"]}</p></header><div class="pp-bal"><div><b id="pbal">{p["balance_loading"]}</b><span id="puse"></span></div><button class="pb v" id="usecheck" disabled>{p["use"]}</button></div><p class="msg" id="pmsg2"></p>{pay_plans()}<div class="pp-sgn" id="panon" hidden><div><b id="psgnh">{p["sign_title"]}</b><span>{p["sign_sub"]}</span></div><div class="sb2"><button class="pb w gbtn" data-google>{GLOGO}{p["google"]}</button><div class="or">{p["or"]}</div><form class="ml" data-magic><input type="email" name="email" required placeholder="{p["email_placeholder"]}" aria-label="{p["email_aria"]}"><button class="pb v">{p["magic"]}</button></form></div><p class="msg" data-magicmsg></p></div><p class="fine2" data-fine>{p["fine"]}</p></div></div>'''

A, M, SO = S['account'], S['my_checks'], S['signed_out']
def why(k, q):  # optional exit question; values match exit_reasons.reason
    r = ''.join(f'<label><input type="radio" name="{k}why" value="{v}">{E(t)}</label>' for v, t in A['reasons'])
    return f'<fieldset class="why" id="{k}why"><legend class="q">{E(q)}<small>{A["why_optional"]}</small></legend>{r}<textarea id="{k}other" maxlength="500" placeholder="{A["why_more"]}" aria-label="{A["why_more_aria"]}"></textarea></fieldset>'
def signed_out(k):  # centered prompt shown by js/app.js when there is no session
    return f'<div class="emp" data-out hidden><h2>{SO[k + "_h2"]}</h2><p>{SO[k + "_p"]}</p><button class="btn" data-open="signup" style="margin-top:20px">{SO["button"]}</button></div>'
ACCOUNT = f'''<main class="ac" id="account"><h1>{A["h1"]}</h1><p class="sub" id="aem"></p>{signed_out("account")}<div data-in hidden>
<div class="sum"><div><small>{A["plan"]}</small><b id="aplan"></b><span id="aplan2"></span></div><div><small>{A["checks_left"]}</small><b class="v" id="aleft"></b><span id="aleft2"></span></div><div><small id="arenl">{A["renews"]}</small><b id="aren"></b><span id="aren2"></span></div></div>
<div class="banner" id="cban" hidden></div><div class="acts"><button class="btn" id="resume" hidden>{A["resume"]}</button><button class="btn o" id="manage" hidden>{A["manage"]}</button><button class="btn o" data-open="cancelsub" id="cancel" hidden>{A["cancel"]}</button><button class="btn o" data-open="paywall" id="pick" hidden>{A["pick"]}</button><button class="btn" data-open="paywall" id="buymore">{A["buy_more"]}</button></div><p class="msg err" id="amsg"></p>
<section class="sec"><h2>{A["my_checks_h2"]}</h2><div class="card mck"><div><b id="mcn"></b><p id="mcl"></p></div><a class="btn o" href="../my-checks/">{A["view_all"]}</a></div></section>
<section class="sec" id="saved"><h2>{A["saved_h2"]} <span class="svn" id="svn"></span></h2><div class="card svl"><div id="svrows"></div><p class="hint" id="svnone" hidden>{A["saved_none"]}</p></div></section>
<section class="sec"><h2>{A["email_h2"]}</h2><p class="d">{A["email_d"]}</p><form class="card" id="emform"><label for="nem">{A["email_label"]}</label><div class="frm"><input class="in" id="nem" name="email" type="email" required placeholder="{A["email_placeholder"]}"><button class="btn o">{A["email_button"]}</button></div><p class="hint" id="emmsg">{A["email_hint"]}</p></form></section>
<section class="sec"><h2>{A["danger_h2"]}</h2><div class="dz"><div><b>{A["delete_b"]}</b><p id="dzp">{A["delete_p"]}</p></div><button class="btn dg" data-open="delacct">{A["delete_button"]}</button></div></section></div></main>
<div class="ov tall" id="delacct" hidden><div class="md" role="dialog" aria-modal="true" aria-labelledby="delh"><button class="x" data-close>×</button><h2 id="delh">{A["del_h2"]}</h2><p class="s">{A["del_s"]}</p><ul class="cons" id="cons"></ul>
{why('del', A['del_why'])}<div class="row2"><button class="btn o" data-close>{A["del_keep"]}</button><button class="btn dgs" id="delgo">{A["del_go"]}</button></div><p class="msg err" id="delmsg"></p></div></div>
<div class="ov tall" id="cancelsub" hidden><div class="md" role="dialog" aria-modal="true" aria-labelledby="canh"><button class="x" data-close>×</button><h2 id="canh"></h2><p class="s" id="cans"></p>
{why('can', A['can_why'])}<div class="row2"><button class="btn o" data-close>{A["can_keep"]}</button><button class="btn dgs" id="cango">{A["can_go"]}</button></div><p class="msg err" id="canmsg"></p></div></div>'''
MYCHECKS = f'''<main class="ac mc" id="mychecks"><h1>{M["h1"]}</h1><p class="sub">{M["sub"]}</p>{signed_out("checks")}<div data-in hidden><div class="bal2" id="mbal"></div>
<div id="mlist" hidden><div class="tb"><label class="srch">⌕<input id="mq" type="search" placeholder="{M["search"]}" aria-label="{M["search"]}"></label><select class="sort" id="msort" aria-label="{M["sort_aria"]}">{"".join(f'<option value="{v}">{t}</option>' for v, t in M["sort"])}</select></div>
<div class="ck" style="margin-top:16px"><div class="mr h">{"".join(f"<span>{c}</span>" for c in M["cols"])}</div><div id="mrows"></div></div><p class="hint" id="mnone" hidden>{M["none"]}</p></div>
<div class="emp" id="mempty" hidden><h2>{M["empty_h2"]}</h2><p>{M["empty_p"]}</p>{SB()}</div></div></main>'''

def landing():
    L, PILL = S['landing'], S['pills']
    cnt = lambda st, c: f"<span class='cnt {'ca' if st == 'review' else 'cg'}'>{E(c)}</span>" if c else ''
    demo = ''.join(f'<div class="dr"><span>{E(t)}</span><span class="pc"><span class="pill {PILL[st][0]}"><i></i>{PILL[st][1]}</span>{cnt(st, c)}</span></div>' for t, st, c in L['demo_rows'])
    return f'''<main class="wrap"><div class="hero"><h1>{L["h1"]}<br><span>{L["h1_accent"]}</span></h1>
{SB()}<div class="chips">{"".join(f"<span>{c}</span>" for c in L["chips"])}</div></div>
<div class="demo" aria-hidden="true"><div class="dh"><b>{L["demo_firm"]}</b><em>{L["demo_tag"]}</em></div>{demo}<div class="dr fade"><span>{L["demo_more"]}</span></div></div><div style="height:64px"></div></main>{press()}<div style="height:80px"></div>'''

def pending():
    P = S['pending']
    return f'''<main class="wrap"><div class="pend"><div class="sp"></div><h1>{P["h1"]}</h1><p style="color:var(--ink2);font-size:18px"><b id="pq"></b> {P["body"]}</p>
<form id="notify"><input class="in" type="email" name="email" required placeholder="{P["email_placeholder"]}"><button class="btn">{P["button"]}</button></form><p class="msg" id="pmsg"></p><p class="note">{P["note"]}</p></div></main>'''

def how_we_check():
    H = S['how_we_check']
    card = lambda t, p, extra='': f'<div class="card"><h3>{t}</h3><p>{p}</p>{extra}</div>'
    li = lambda xs: '<ul>' + ''.join(f'<li><span>{x}</span></li>' for x in xs) + '</ul>'
    return f'''<main class="hp"><span class="ey">{H["eyebrow"]}</span><h1>{H["h1"]} <span>{H["h1_accent"]}</span></h1><p class="lead">{H["lead"]}</p>
<div class="strip">{"".join(f'<span class="st{" big" if i == 0 else ""}"><b>{b}</b>{t}</span>' for i, (b, t) in enumerate(H["strip"]))}</div>
<div class="steps">{"".join(f'<div class="card"><b class="n">{i + 1}</b><h3>{t}</h3><p>{p}</p></div>' for i, (t, p) in enumerate(H["steps"]))}</div>
<h2>{H["what_h2"]}</h2><div class="areas">{"".join(card(t, p, f'<span class="tag">{g}</span>') for t, p, g in H["areas"])}</div>
<h2>{H["read_h2"]}</h2><div class="two"><div class="card"><p style="margin-bottom:10px">{H["read_p"]}</p><div class="pills">{"".join(f'<span class="pl {c}">{t}</span>' for c, t in H["read_pills"])}</div>{li(H["read_list"])}</div>
<div class="card"><h3 style="margin-top:0">{H["principles_h3"]}</h3>{li(H["principles"])}</div></div>
<h2>{H["corr_h2"]}</h2><div class="card corr"><p>{H["corr_p"]}</p><a class="btn w" href="mailto:{H["corr_email"]}?subject={H["corr_subject"]}">{H["corr_button"]}</a></div>
<p class="dis">{H["disclaimer"]}</p></main>'''

def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    for f in ('style.css', 'logo.svg', 'js/app.js', 'js/company.js'): shutil.copy(os.path.join(HERE, f), OUT)
    shutil.copytree(os.path.join(HERE, 'fav'), os.path.join(OUT, 'fav'))
    shutil.copy(os.path.join(HERE, 'CNAME'), OUT)  # GitHub Pages custom domain (regretamin.com)
    firms = []
    for p in sorted(glob.glob(os.path.join(ROOT, 'data', 'launch', '*.json'))):
        F = json.load(open(p))['firm']; firms.append(F['slug'])
        page(os.path.join(OUT, 'vc', F['slug'], 'index.html'), summary(F), '../../', F['name'] + S['title_suffix'], company=True)
        page(os.path.join(OUT, 'vc', F['slug'], 'full', 'index.html'), result(F), '../../../', F['name'] + S['title_suffix'], company=True)
    page(os.path.join(OUT, 'index.html'), landing(), '')
    page(os.path.join(OUT, 'pending', 'index.html'), pending(), '../')
    page(os.path.join(OUT, 'how-we-check', 'index.html'), how_we_check(), '../', S['how_we_check']['title'] + S['title_suffix'], active='hwc')
    page(os.path.join(OUT, 'account', 'index.html'), ACCOUNT, '../', A['h1'] + S['title_suffix'])
    page(os.path.join(OUT, 'my-checks', 'index.html'), MYCHECKS, '../', M['h1'] + S['title_suffix'])
    page(os.path.join(OUT, 'privacy', 'index.html'), privacy(), '../', 'Privacy Policy' + S['title_suffix'])
    page(os.path.join(OUT, 'terms', 'index.html'), terms(), '../', 'Terms of Service' + S['title_suffix'])
    site = 'https://regretamin.com/'  # sitemap + robots (account and my-checks are left out)
    urls = [site] + [site + p + '/' for p in ('how-we-check', 'pricing', 'privacy', 'terms') if os.path.exists(os.path.join(OUT, p, 'index.html'))] + [f'{site}vc/{f}/{x}' for f in firms for x in ('', 'full/')]
    open(os.path.join(OUT, 'sitemap.xml'), 'w').write('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(f'<url><loc>{u}</loc></url>\n' for u in urls) + '</urlset>\n')
    open(os.path.join(OUT, 'robots.txt'), 'w').write(f'User-agent: *\nAllow: /\n\nSitemap: {site}sitemap.xml\n')
    print('built', len(firms), 'firms ->', OUT)

if __name__ == '__main__': main()
