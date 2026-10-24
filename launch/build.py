"""Regretamin launch build: search page + one static company-page shell per firm in data/launch/*.json.
The shell holds no firm data beyond the name: every section is filled from the firm_page() RPC (js/company.js).
All copy, plans and section presentation come from launch/copy.json (also handed to the JS as window.REGRET.copy).
Output: site-launch/. Deploy to the preview with launch/deploy_preview.sh (see launch/HOW-TO-CHANGE.md).
Refresh a snapshot (read-only): run launch/firm_snapshot.sql with :slug, save the JSON as data/launch/<slug>.json;
then python3 launch/sync_checks.py data/launch/*.json > a new migration to update the 10 check rows."""
import os, json, html, glob, shutil, hashlib
from legal import privacy, terms
E = html.escape
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE); OUT = os.path.join(ROOT, 'site-launch')
def _v(f):  # content hash so browsers never run a stale cached copy (assets are max-age=600)
    return hashlib.sha1(open(os.path.join(HERE, f), 'rb').read()).hexdigest()[:10]
V = {k: _v(f) for k, f in (('company', 'js/company.js'), ('app', 'js/app.js'), ('css', 'style.css'))}
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

def page(path, body, root, title=S['brand'], company=False, active='', head=''):
    n, su = S['nav'], S['signup']
    hon = ' class="on" aria-current="page"' if active == 'hwc' else ''
    scripts = (f'<script defer src="{root}company.js?v={V['company']}"></script>' if company else '') + f'<script defer src="{root}app.js?v={V['app']}"></script>'
    nav = (f'<nav><a class="logo" href="{root}"><img src="{root}logo.svg" alt="">{S["brand"]}</a><div class="r">'
           f'<a href="{root}how-we-check/"{hon}>{n["how_we_check"]}</a><a href="#" data-open="paywall">{n["pricing"]}</a><span class="left" id="left"></span><a href="#" data-open="signup" id="signin">{n["sign_in"]}</a>'
           f'<span class="navr" id="acct" hidden><button type="button" class="ab" id="acctbtn" aria-haspopup="true" aria-expanded="false"><span class="av" id="av"></span><span class="nm">{n["account_btn"]}</span></button>'
           f'<div class="dd" id="acctdd" hidden><div class="hd2"><div class="em" id="ddem"></div><div class="pl2" id="ddplan"></div><div class="bal"><span>{n["checks_left"]}</span><b id="ddleft"></b></div></div>'
           f'<a href="{root}account/">{n["account"]}</a><a href="{root}account/firms/">{n["my_checks"]}</a><a href="#" data-open="paywall">{n["buy_more"]}</a><div class="sep"></div><a class="so" href="#" id="signout">{n["sign_out"]}</a></div></span></div></nav>')
    modals = f'''<div class="ov sgo" id="signup" hidden><div class="md sgm" role="dialog" aria-modal="true" aria-labelledby="suh"><div class="sgi"><button class="x" data-close aria-label="Close">×</button><div class="sg4" aria-hidden="true"><b>+4</b><span>free<br>credits</span></div><h2 id="suh" data-t="{su["title"]}">{su["title"]}</h2><p class="s">{su["sub"]}</p>
<button type="button" class="gbx" id="google"><span class="gi">{GLOGO}</span><span class="gl">{su["google"]}</span></button><div class="orx">{su["or"]}</div><div class="emr"><input class="in" id="em" type="email" placeholder="{su["email_placeholder"]}" aria-label="{su["email_aria"]}"><button type="button" class="btn o" id="magic">{su["magic"]}</button></div><p class="sgt">{"".join(f"<span>{t}</span>" for t in su["trust"])}</p><p class="msg" id="sumsg"></p></div></div></div>
{pricing_modal()}'''
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write(f'''<!doctype html><html lang="en"><head>{'<meta name="robots" content="noindex">' if NOINDEX else ''}<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{E(title)}</title>{head}
<link rel="icon" href="{root}logo.svg"><link rel="stylesheet" href="{root}style.css?v={V['css']}"><script>window.REGRET={json.dumps(CFG)};window.REGRET_ROOT="{root}";{AUTH_HINT}</script>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>{scripts}</head><body>{nav}{body}{FOOT(root)}{modals}</body></html>''')

# Runs before first paint: read the cached Supabase session (sb-<ref>-auth-token in localStorage) so the header starts in the right state
# (html.au-in: account button, html.au-out: Sign in). No cache read possible -> html.au-wait hides both until js/app.js resolves auth.
AUTH_HINT = ('(function(){var d=document.documentElement,c="au-out";try{for(var i=0;i<localStorage.length;i++){var k=localStorage.key(i);'
             'if(/^sb-.*-auth-token$/.test(k)){var v=JSON.parse(localStorage.getItem(k)||"null");if(v&&(v.refresh_token||(v.currentSession&&v.currentSession.refresh_token))){c="au-in";'
             'window.REGRET_AU={email:(v.user&&v.user.email)||""}}}}}catch(e){c="au-wait"}d.classList.add(c)})()')


SITE = 'https://regretamin.com/'
# Firm pages: ONE template per view (summary, full) with {{...}} placeholders. Static pages (GitHub Pages) and the
# Cloudflare Pages Function (launch/functions/_firm.js) fill the same template the same way: keep fill() and fillFirm() identical.
T_NAME, T_SLUG, T_HEAD = '{{NAME}}', '{{SLUG}}', '{{HEAD}}'

def firm_desc(F):
    bits = ', '.join(E(x) for x in (F.get('firm_type'), F.get('hq')) if x)
    return f'Background check on {E(F["name"])}' + (f' ({bits})' if bits else '') + ': SEC filings, legal matters, team changes and 10 checks before you take the meeting or the money.'

def firm_head(F, full=False):
    url = f'{SITE}vc/{F["slug"]}/' + ('full/' if full else '')
    title = E(F['name'] + S['title_suffix'])
    d = firm_desc(F)
    org = {'@type': 'Organization', 'name': F['name']}
    if F.get('legal_name'): org['legalName'] = F['legal_name']
    if F.get('primary_domain'): org['url'] = 'https://' + F['primary_domain']
    if F.get('hq'): org['address'] = F['hq']
    if F.get('founded_year'): org['foundingDate'] = str(F['founded_year'])
    ld = {'@context': 'https://schema.org', '@type': 'WebPage', 'name': F['name'] + S['title_suffix'], 'url': url, 'about': org}
    ldj = json.dumps(ld, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
    return (f'<meta name="description" content="{d}"><link rel="canonical" href="{url}">'
            f'<meta property="og:type" content="website"><meta property="og:site_name" content="{S["brand"]}"><meta property="og:title" content="{title}">'
            f'<meta property="og:description" content="{d}"><meta property="og:url" content="{url}"><meta name="twitter:card" content="summary">'
            f'<script type="application/ld+json">{ldj}</script>')

def fill(tpl, F, full=False):
    return tpl.replace(T_HEAD, firm_head(F, full)).replace(T_NAME, E(F['name'])).replace(T_SLUG, E(F['slug']))

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

# Save button by the firm name on every firm page (js/app.js saveBtn: signed in toggles watch_fund/unwatch_fund, signed out opens sign-in)
SAVE = f'<button type="button" class="sv" data-save aria-pressed="false"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linejoin="round"><path d="M6 3h12v18l-6-4-6 4z"/></svg><span>{COPY["js"]["save_btn"]}</span></button>'

def checking_box():  # "Email me when it's ready" + "What's happening?" (shown by js/company.js only while checks are running)
    K = COPY['company']['checking']
    return (f'<aside class="cside" hidden><form class="cbox" data-notify><h3>{K["email_h"]}</h3><p>{K["email_p"]}</p>'
            f'<div class="cin"><input type="email" name="email" required placeholder="{K["email_ph"]}" aria-label="{K["email_aria"]}"><em hidden>{K["signed_in"]}</em></div>'
            f'<button class="btn">{K["email_btn"]}</button><p class="cmsg" role="status"></p><p class="cclose">{K["close_line"]}</p></form>'
            f'<div class="cbox cwhat"><p><b>{K["what_h"]}</b> {K["what_p"]}</p></div></aside>')

# Loading skeleton (grey shapes, style.css .sk): built into the page shells so the first paint already has the real layout;
# js/app.js draw() replaces each container's contents and removes main.ld. Widths are fixed (no data), heights match the real rows.
SK = lambda w, cls='': f'<i class="sk{(" " + cls) if cls else ""}" style="width:{w}"></i>'
SK_KF = ''.join(f'<span class="skp">{SK(w)}</span>' for w in ('290px', '310px', '300px', '320px'))
SK_HFS = ''.join(f'<div class="hf skc">{SK("62%", "s")}{SK("80%", "b")}{SK("46%", "c")}</div>' for _ in range(4))
SK_CSUM = '<div class="csh">' + SK('120px') + SK('110px', 's') + '</div><div class="cks">' + ''.join(f'<span class="ck skc">{SK("16px", "s")}{SK(w, "s")}{SK("58px", "c")}</span>' for w in ('70%', '60%', '75%', '55%', '68%') * 2) + '</div>'
SK_SPL = ''.join(f'<span class="spp skc">{SK(w, "s")}</span>' for w in ('70px', '90px', '110px', '96px', '108px', '120px', '82px', '64px'))
SK_PMAIN = ''.join(f'<div class="ps skc"><h2>{SK("62%")}</h2><p class="psub">{SK("50%", "s")}</p>' + ''.join(f'<div class="kv"><span class="k">{SK("80%", "s")}</span><span>{SK(w, "s")}</span></div>' for w in ('70%', '55%', '64%')) + '</div>' for _ in range(2))
SK_TOC = SK('60%') + ''.join(SK(w, 's') for w in ('40%', '55%', '48%', '62%', '44%', '58%'))
def skel():  # loading placeholder for the checks table (same table markup, grey shapes), replaced by js/company.js once firm_page() answers
    T = COPY['company']['table']
    row = lambda i: (f'<tr class="skr"><td class="kcn">{SK("14px", "s")}</td><td class="kct"><b>{SK("70%")}</b><span>{SK("92%", "s")}{SK("58%", "s")}</span></td>'
                     f'<td class="kcr">{SK("56px", "p")}</td><td class="kcf"><b>{SK("70%")}</b></td><td class="kcd">{SK("48px", "s")}</td></tr>')
    return (f'<table class="ctab skt" aria-busy="true" aria-label="{E(T["loading"])}"><thead><tr><th>#</th><th>{T["h_check"]}</th><th>{T["h_result"]}</th><th>{T["h_found"]}</th><th>{T["h_date"]}</th></tr></thead><tbody>'
            + ''.join(row(i) for i in range(10)) + '</tbody></table>')

def ftabs(on, base):  # two-tab switch between /vc/<slug>/ (Checks) and /vc/<slug>/full/ (Full report)
    Q = S['summary']
    a = lambda k, href, t, n: f'<a class="rgt-tab{" on" if on == k else ""}" href="{href}"{' aria-current="page"' if on == k else ""}>{t}{n}</a>'
    return f'<nav class="rgt-tabs" aria-label="{Q["tabs_aria"]}">' + a('c', base, Q['tab_checks'], ' <em>10</em>') + a('f', base + 'full/', Q['tab_full'], ' <em class="rgt-n" hidden></em>') + '</nav>'

def summary(F):  # /vc/<slug>/: name + Save, key facts, the 10 checks (closed), "See the full check" (js/company.js summary)
    Q = S['summary']
    return f'''<main class="wrap sumpg unlocked ld" data-firm="{E(F["slug"])}" data-view="summary"><div class="rh">{bigsearch(F)}</div>
<div class="fh"><h1>{E(F["name"])}</h1><div>{SAVE}</div></div>{checking_box()}<div class="kf">{SK_KF}</div>{ftabs("c", "./")}<div class="cban" hidden></div><div class="list">{skel()}</div>
<div class="rgt-see"><a href="full/">{Q["see_full"]}</a></div><p class="fine">{S["result"]["fine"]}</p></main>'''

def result(F):
    r, p = S['result'], S['pay']
    return f'''<main class="wrap prof ld" data-firm="{E(F["slug"])}">{bigsearch(F, "ps0")}
<div class="ph"><h1>{E(F["name"])}{SAVE}</h1><p class="m"><i class="sk" style="width:300px"></i></p><div class="hfs">{SK_HFS}</div></div>{ftabs("f", "../")}<div class="csum">{SK_CSUM}</div><div class="spl">{SK_SPL}</div>
<div class="unlock" id="lockcard" hidden><div><b></b><p></p></div><button class="btn" id="unlock">{r["lock_button"]}</button></div>
<div class="pgrid"><div class="pmain">{SK_PMAIN}</div><nav class="toc" aria-label="{r["toc_aria"]}">{SK_TOC}</nav></div><p class="fine">{r["fine"]}</p></main>
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
<section class="sec"><h2>{A["my_checks_h2"]}</h2><div class="card mck"><div><b id="mcn"></b><p id="mcl"></p></div><a class="btn o" href="firms/">{A["view_all"]}</a></div></section>
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

F_ = S['my_firms']
MYFIRMS = f'''<main class="ac mf" id="myfirms"><h1>{F_["h1"]}</h1><p class="sub">{F_["sub"]}</p><div class="emp" data-out hidden><h2>{F_["signed_out_h2"]}</h2><p>{F_["signed_out_p"]}</p><button class="btn" data-open="signup" style="margin-top:20px">{SO["button"]}</button></div><div data-in hidden>
<div id="flist" hidden><div class="tabs"><div class="tg" role="tablist" aria-label="{F_["tabs_aria"]}">{"".join(f'<button type="button" role="tab" data-tab="{k}"{' class="on" aria-selected="true"' if k == 'all' else ' aria-selected="false"'}>{t} <em id="fn-{k}"></em></button>' for k, t in F_["tabs"])}</div>
<label class="srch">⌕<input id="fq" type="search" placeholder="{F_["search"]}" aria-label="{F_["search"]}"></label></div>
<div class="ftab"><div class="mfr h">{"".join(f"<span>{c}</span>" for c in F_["cols"])}</div><div id="frows"></div></div><p class="hint" id="fnone" hidden></p></div>
<div class="emp" id="fempty" hidden><h2>{F_["empty_h2"]}</h2><p>{F_["empty_p"]}</p>{SB()}</div></div></main>'''
# /my-checks/ moved to /account/firms/ (My firms); keep old links working
REDIRECT = lambda to, t: f'<!doctype html><meta charset="utf-8"><meta name="robots" content="noindex"><meta http-equiv="refresh" content="0;url={to}"><script>location.replace("{to}"+location.search+location.hash)</script><title>{t}</title><a href="{to}">{t}</a>'

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
    T = {'name': T_NAME, 'slug': T_SLUG}
    page(os.path.join(OUT, '_tpl', 'summary.html'), summary(T), '../../', T_NAME + S['title_suffix'], company=True, head=T_HEAD)
    page(os.path.join(OUT, '_tpl', 'full.html'), result(T), '../../../', T_NAME + S['title_suffix'], company=True, head=T_HEAD)
    nf = COPY.get('not_found', {'h1': 'We could not find that firm', 'p': 'It may not be checked yet. Search for it and we will start a check.'})
    page(os.path.join(OUT, '_tpl', '404.html'), f'<main class="wrap"><div class="hero"><h1>{E(nf["h1"])}</h1><p>{E(nf["p"])}</p>{SB()}</div></main>', '/', 'Not found' + S['title_suffix'], head='<meta name="robots" content="noindex">')
    tpl = {v: open(os.path.join(OUT, '_tpl', v + '.html')).read() for v in ('summary', 'full')}
    for p in sorted(glob.glob(os.path.join(ROOT, 'data', 'launch', '*.json'))):
        F = json.load(open(p))['firm']; firms.append(F['slug'])
        for v, sub in (('summary', ''), ('full', 'full')):
            d = os.path.join(OUT, 'vc', F['slug'], sub); os.makedirs(d, exist_ok=True)
            open(os.path.join(d, 'index.html'), 'w').write(fill(tpl[v], F, v == 'full'))
    page(os.path.join(OUT, 'index.html'), landing(), '')
    page(os.path.join(OUT, 'pending', 'index.html'), pending(), '../')
    page(os.path.join(OUT, 'how-we-check', 'index.html'), how_we_check(), '../', S['how_we_check']['title'] + S['title_suffix'], active='hwc')
    page(os.path.join(OUT, 'account', 'index.html'), ACCOUNT, '../', A['h1'] + S['title_suffix'])
    page(os.path.join(OUT, 'account', 'firms', 'index.html'), MYFIRMS, '../../', F_['title'] + S['title_suffix'])
    os.makedirs(os.path.join(OUT, 'my-checks'), exist_ok=True)
    open(os.path.join(OUT, 'my-checks', 'index.html'), 'w').write(REDIRECT('../account/firms/', F_['title']))
    page(os.path.join(OUT, 'privacy', 'index.html'), privacy(), '../', 'Privacy Policy' + S['title_suffix'])
    page(os.path.join(OUT, 'terms', 'index.html'), terms(), '../', 'Terms of Service' + S['title_suffix'])
    os.makedirs(os.path.join(OUT, 'pricing'), exist_ok=True)  # /pricing/ has no page of its own: send it to the home page Pricing popup (no 404); kept out of the sitemap
    open(os.path.join(OUT, 'pricing', 'index.html'), 'w').write('<!doctype html><meta charset="utf-8"><meta name="robots" content="noindex"><link rel="canonical" href="/"><meta http-equiv="refresh" content="0;url=../?pricing=1"><script>location.replace("../?pricing=1"+location.hash)</script><title>Pricing</title><a href="../?pricing=1">Pricing</a>')
    site = SITE  # sitemap + robots (account and my-checks are left out)
    urls = [site] + [site + p + '/' for p in ('how-we-check', 'privacy', 'terms') if os.path.exists(os.path.join(OUT, p, 'index.html'))] + [f'{site}vc/{f}/{x}' for f in firms for x in ('', 'full/')]
    open(os.path.join(OUT, 'sitemap.xml'), 'w').write('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(f'<url><loc>{u}</loc></url>\n' for u in urls) + '</urlset>\n')
    open(os.path.join(OUT, 'robots.txt'), 'w').write(f'User-agent: *\nAllow: /\nDisallow: /_tpl/\n\nSitemap: {site}sitemap.xml\n')
    print('built', len(firms), 'firms ->', OUT)

if __name__ == '__main__': main()
