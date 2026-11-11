"""Regretamin launch build: search page + one static company-page shell per live firm.
Live firms are whoever firm_sitemap and firm_meta return (v2_firm_live joined to v2_firms). There is no slug list.
The page body is filled in the browser from firm_page, which is v2_firm_page.
Local runs without SUPABASE_URL fall back to every data/launch/*.json snapshot.
The shell holds no firm data beyond the name: every section is filled from the firm_page() RPC (js/company.js).
All copy, plans and section presentation come from launch/copy.json (also handed to the JS as window.REGRET.copy).
Output: site-launch/. Deploy to the preview with launch/deploy_preview.sh (see launch/HOW-TO-CHANGE.md).
Refresh a snapshot (read-only): run launch/firm_snapshot.sql with :slug, save the JSON as data/launch/<slug>.json;
then python3 launch/sync_checks.py data/launch/*.json > a new migration to update the 10 check rows."""
import os, re, json, html, glob, shutil, hashlib, urllib.request
from types import SimpleNamespace
from pages.registry import PAGES, page_head, nav_links, footer_links
E = html.escape
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE); OUT = os.path.join(ROOT, 'site-launch')
def _v(f):  # query on the script/link. The file path does not change, so _headers makes the CDN revalidate.
    return hashlib.sha1(open(os.path.join(HERE, f), 'rb').read()).hexdigest()[:10]
V = {k: _v(f) for k, f in (('company', 'js/company.js'), ('app', 'js/app.js'), ('search', 'js/search.js'), ('dates', 'js/dates.js'), ('css', 'style.css'))}
COPY = json.load(open(os.path.join(HERE, 'copy.json')))
S = COPY['site']
NOINDEX = os.environ.get('REGRET_NOINDEX') == '1'
CFG = {'url': os.environ.get('SUPABASE_URL', ''), 'key': os.environ.get('SUPABASE_ANON_KEY', ''), 'copy': {**COPY, 'site': {k: v for k, v in S.items() if k not in ('legal', 'pages')}}}
GLOGO = '''<svg width="18" height="18" viewBox="0 0 48 48"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"/><path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z"/><path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z"/><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z"/></svg>'''

def billing():  # Monthly|Yearly toggle for both pricing popups; their plan cards are drawn by js/app.js (drawPlans) from copy.json plans
    B = S['billing']
    return (f'<div class="bt" role="radiogroup" aria-label="{B["aria"]}"><div><button type="button" role="radio" aria-checked="true" class="on" data-yearly="0">{B["monthly"]}</button>'
            f'<button type="button" role="radio" aria-checked="false" data-yearly="1">{B["yearly"]} <em>{B["badge"]}</em></button></div></div>')

def code_field():  # "Have a code?" field for both pricing popups (checked by the validate-code function)
    K = S['code']
    return (f'<div class="code"><a href="#" data-codeopen>{K["link"]}</a><form class="cf" data-code hidden><input name="code" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="{K["placeholder"]}" aria-label="{K["aria"]}">'
            f'<button class="pb v" data-apply>{K["apply"]}</button><button type="button" class="pb v" data-remove hidden>{K["remove"]}</button></form><p class="cn" data-codemsg></p></div>')

def pricing_inner(close=True):  # shared by the Pricing popup and /plans/
    p = S['pricing']
    x = '<button class="x" data-close>×</button>' if close else ''
    return f'{x}<h2 id="pwh">{p["title"]}</h2><p class="s">{p["sub"]}</p>{billing()}<div class="price" data-plans="nav"></div><p class="msg" id="pwmsg"></p>{code_field()}'

def pricing_modal():  # nav "Pricing" popup
    return f'<div class="ov" id="paywall" hidden><div class="md w">{pricing_inner()}</div></div>'

def signup_inner(close=True):  # shared by the sign-in popup and /login/
    su = S['signup']
    x = '<button class="x" data-close aria-label="Close">×</button>' if close else ''
    return f'''<div class="sgi sgcard">{x}<div class="sg4" aria-hidden="true"><b>+4</b><span>free<br>credits</span></div><h2 id="suh" data-t="{su["title"]}">{su["title"]}</h2><p class="s" id="sus">{su["sub"]}</p>
<button type="button" class="gbx" id="google"><span class="gi">{GLOGO}</span><span class="gl">{su["google"]}</span></button><div class="orx">{su["or"]}</div><div class="emr"><input class="in" id="em" type="email" placeholder="{su["email_placeholder"]}" aria-label="{su["email_aria"]}"><button type="button" class="btn o" id="magic">{su["magic"]}</button></div><p class="sgt">{"".join(f"<span>{t}</span>" for t in su["trust"])}</p>
<hr class="sudiv"><p class="sufoot"><span id="sufootnew">{su["have"]} <button type="button" id="sulinkin">{su["sign_in"]}</button></span><span id="sufootin" hidden><button type="button" id="sulinknew">{su["title"]}</button></span></p><p class="msg" id="sumsg"></p></div>'''

def signup_modal():
    su = S['signup']
    return f'<div class="ov sgo" id="signup" hidden><div class="md sgm" role="dialog" aria-modal="true" aria-labelledby="suh">{signup_inner()}</div></div>'

def outcredits_modal():  # signed-out purchase (approved out-of-credits popup). Not the Sign in popup.
    o = S['outcredits']
    return f'''<div class="ov sgo" id="outcredits" hidden><div class="md sgm" role="dialog" aria-modal="true" aria-labelledby="outh"><div class="sgi">
<button class="x" data-close aria-label="Close">×</button><p class="firm" id="outfirm" hidden></p><h2 id="outh">{o["title"]}</h2><p class="s">{o["sub"]}</p>
<div class="orows" id="outplans" role="radiogroup" aria-label="{o["plans_aria"]}"></div>
<button type="button" class="gbx" data-google><span class="gi">{GLOGO}</span><span class="gl">{o["google"]}</span></button><div class="orx">{o["or"]}</div>
<input class="in" id="outem" type="email" placeholder="{o["email_placeholder"]}" aria-label="{o["email_aria"]}" autocomplete="email">
<button type="button" class="btn y" id="outgo">{o["checkout"]}</button><p class="fine2">{o["fine"]}</p><p class="msg" id="outmsg"></p></div></div></div>'''


def page(path, body, root, title=S['brand'], company=False, active='', head='', modals='both'):
    n = S['nav']
    scripts = f'<script defer src="{root}dates.js?v={V["dates"]}"></script>' + (f'<script defer src="{root}company.js?v={V["company"]}"></script>' if company else '') + f'<script defer src="{root}search.js?v={V["search"]}"></script><script defer src="{root}app.js?v={V["app"]}"></script>'
    nav = (f'<nav><a class="logo" href="{root}"><img src="{root}logo.svg" alt="">{S["brand"]}</a><div class="r">'
           f'{nav_links(S, root, "main", active)}'
           f'<span class="navr" id="acct" hidden><button type="button" class="ab" id="acctbtn" aria-haspopup="true" aria-expanded="false"><span class="av" id="av"></span><span class="nm">{n["account_btn"]}</span></button>'
           f'<div class="dd" id="acctdd" hidden><div class="hd2"><div class="em" id="ddem"></div><div class="pl2" id="ddplan"></div><div class="bal"><span>{n["checks_left"]}</span><b id="ddleft"></b></div></div>'
           f'{nav_links(S, root, "account", active)}<a href="#" data-open="paywall">{n["buy_more"]}</a><div class="sep"></div><a class="so" href="#" id="signout">{n["sign_out"]}</a></div></span></div></nav>')
    modals = (signup_modal() if modals in ('both', 'signup') else '') + (pricing_modal() if modals in ('both', 'pricing') else '') + outcredits_modal()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write(f'''<!doctype html><html lang="en"><head>{'<meta name="robots" content="noindex">' if NOINDEX else ''}<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{E(title)}</title>{head}
<link rel="icon" href="{root}logo.svg"><link rel="stylesheet" href="{root}style.css?v={V['css']}"><script>window.REGRET={json.dumps(CFG)};window.REGRET_ROOT="{root}";{AUTH_HINT}</script>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.118.0"></script>{scripts}</head><body>{nav}{body}{FOOT(root)}{modals}</body></html>''')

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
    ld = {'@context': 'https://schema.org', '@type': 'WebPage', 'name': F['name'] + S['title_suffix'], 'url': url, 'about': org,
          'isAccessibleForFree': False, 'hasPart': {'@type': 'WebPageElement', 'isAccessibleForFree': False, 'cssSelector': '.gveil'}}
    ldj = json.dumps(ld, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c').replace('>', '\\u003e').replace('&', '\\u0026')
    # /full/ and 'Not checked yet' pages (indexable false: no research yet) are noindex, follow
    return (('<meta name="robots" content="noindex, follow">' if full or F.get('indexable') is False else '') + f'<meta name="description" content="{d}"><link rel="canonical" href="{url}">'
            f'<meta property="og:type" content="website"><meta property="og:site_name" content="{S["brand"]}"><meta property="og:title" content="{title}">'
            f'<meta property="og:description" content="{d}"><meta property="og:url" content="{url}"><meta name="twitter:card" content="summary">'
            f'<script type="application/ld+json">{ldj}</script>')

# Official SEC names arrive in ALL CAPS ("IVP MANAGEMENT, L.L.C."). /full/ shows them in normal (title) case, display only
# (the stored name and the JSON-LD legalName stay as filed). Keep identical to secTitle() in launch/edge/firm.mjs.
SEC_KEEP = {'LLC': 'LLC', 'L.L.C.': 'L.L.C.', 'L.L.C': 'L.L.C', 'LP': 'LP', 'L.P.': 'L.P.', 'L.P': 'L.P', 'LLP': 'LLP', 'L.L.P.': 'L.L.P.',
            'INC': 'Inc', 'INC.': 'Inc.', 'LTD': 'Ltd', 'LTD.': 'Ltd.', 'CO': 'Co', 'CO.': 'Co.', 'CORP': 'Corp', 'CORP.': 'Corp.',
            'PLC': 'PLC', 'GP': 'GP', 'SA': 'SA', 'S.A.': 'S.A.', 'AG': 'AG', 'GMBH': 'GmbH', 'SARL': 'SARL', 'S.A.R.L.': 'S.à r.l.',
            'BV': 'BV', 'B.V.': 'B.V.', 'NV': 'NV', 'AB': 'AB', 'AS': 'AS', 'SPA': 'SpA', 'PTE': 'Pte', 'PTY': 'Pty', 'LLLP': 'LLLP',
            'A16Z': 'a16z', 'YC': 'YC', 'ES20': 'ES20', 'US': 'US', 'USA': 'USA', 'UK': 'UK', 'VC': 'VC', 'AI': 'AI', 'II': 'II', 'III': 'III', 'IV': 'IV', 'VI': 'VI',
            'VII': 'VII', 'VIII': 'VIII', 'IX': 'IX', 'XI': 'XI', 'XII': 'XII', 'NEA': 'NEA', 'IVP': 'IVP', 'KKR': 'KKR', 'TPG': 'TPG',
            'GGV': 'GGV', 'USV': 'USV', 'TCV': 'TCV', 'IDG': 'IDG', 'NFX': 'NFX', 'DST': 'DST', 'EQT': 'EQT', 'QED': 'QED', 'SOSV': 'SOSV',
            'HV': 'HV', 'GV': 'GV', 'DCM': 'DCM', 'JMI': 'JMI', 'TA': 'TA', 'RRE': 'RRE', 'FPV': 'FPV', 'AVF': 'AVF', 'ESP': 'ESP', 'HIG': 'HIG',
            'H.I.G.': 'H.I.G.', 'UBS': 'UBS', 'LGT': 'LGT', 'GCM': 'GCM', 'HGGC': 'HGGC', 'BVP': 'BVP',
  'SEC': 'SEC', 'FEC': 'FEC', 'PAC': 'PAC', 'CRD': 'CRD', 'LEI': 'LEI', 'FINRA': 'FINRA', 'OFAC': 'OFAC', 'FCA': 'FCA', 'EU': 'EU', 'UN': 'UN', 'SBIC': 'SBIC', 'ERISA': 'ERISA', 'NYC': 'NYC', 'IAPD': 'IAPD', 'ADV': 'ADV', 'RIA': 'RIA', 'AUM': 'AUM', 'LDA': 'LDA', 'FTX': 'FTX', 'RD': 'Rd', 'RD.': 'Rd.', 'ST.': 'St.', 'AVE': 'Ave', 'AVE.': 'Ave.', 'STE': 'Ste', 'STE.': 'Ste.', 'BLVD': 'Blvd', 'BLVD.': 'Blvd.'}
SEC_SMALL = {'OF', 'AND', 'THE', 'FOR', 'DE', 'DU', 'LA', 'LE', 'VON', 'VAN', 'DER', 'DES', 'ET', 'AN', 'AT', 'ON', 'IN', 'A'}

def _sec_part(w):  # one hyphen / slash / apostrophe part, already upper
    if not re.search('[A-Z]', w): return w
    if w in SEC_KEEP: return SEC_KEEP[w]
    core = re.sub('[^A-Z]', '', w)
    if re.fullmatch('[IVX]{2,5}', core): return w  # fund number: XVII
    if len(core) <= 4 and not re.search('[AEIOUY]', core): return w  # short acronym: GP, BRV, SVB
    lw = w.lower(); m = re.search('[a-z]', lw)
    return lw[:m.start()] + lw[m.start()].upper() + lw[m.start() + 1:]  # first letter up: 83NORTH -> 83North

def sec_title(s):
    s = s or ''
    if not s or re.search('[a-z]', s): return s  # already in mixed case: as filed
    out = []
    for i, w in enumerate(s.split(' ')):
        bare = w.strip(',;()')
        if i and bare in SEC_SMALL: out.append(w.lower()); continue
        if bare.rstrip('.,') in SEC_KEEP or bare in SEC_KEEP:
            k = bare if bare in SEC_KEEP else bare.rstrip('.,'); out.append(w.replace(k, SEC_KEEP[k], 1)); continue
        out.append(re.sub("[^\\s\\-/'’&]+", lambda m: _sec_part(m.group(0)), w))
    return ' '.join(out)

def fill(tpl, F, full=False):  # header and search use the common name; legalName in the page head stays the SEC name
    return tpl.replace(T_HEAD, firm_head(F, full)).replace(T_NAME, E(F['name'])).replace(T_SLUG, E(F['slug']))

FOOT = lambda root: '<footer class="ft"><span>' + E(S["footer"]["copyright"]) + '</span>' + footer_links(S, root) + '</footer>'


def SB(sm=False):
    return f'<form class="sb{" sm" if sm else ""}" data-search><input name="q" placeholder="{S["search_placeholder"]}" autocomplete="off" aria-label="{S["search_aria"]}"><button class="btn">{S["search_button"]}</button></form>'

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
SK_PMAIN = ''.join(f'<div class="ps skc"><h2>{SK("62%")}</h2>' + ''.join(f'<div class="kv"><span class="k">{SK("80%", "s")}</span><span>{SK(w, "s")}</span></div>' for w in ('70%', '55%', '64%')) + '</div>' for _ in range(2))
SK_TOC = SK('60%') + ''.join(SK(w, 's') for w in ('40%', '55%', '48%', '62%', '44%', '58%'))
def skel():  # loading placeholder for the checks table (same table markup, grey shapes), replaced by js/company.js once firm_page() answers
    T = COPY['company']['table']
    row = lambda i: (f'<tr class="skr"><td class="kcn">{SK("14px", "s")}</td><td class="kct"><b>{SK("70%")}</b><span>{SK("92%", "s")}{SK("58%", "s")}</span></td>'
                     f'<td class="kcr">{SK("56px", "p")}</td><td class="kcf"><b>{SK("70%")}</b></td><td class="kcd">{SK("48px", "s")}</td></tr>')
    return (f'<table class="ctab skt" aria-busy="true" aria-label="{E(T["loading"])}"><thead><tr><th>#</th><th>{T["h_check"]}</th><th>{T["h_result"]}</th><th>{T["h_found"]}</th><th>{T["h_date"]}</th></tr></thead><tbody>'
            + ''.join(row(i) for i in range(10)) + '</tbody></table>')

def ftabs(on):  # Checks and Full report are both in the page. js/app.js shows one; the address changes without a reload.
    Q = S['summary']
    b = lambda k, t, n: f'<button type="button" class="rgt-tab{" on" if on == k else ""}" data-tab="{k}" aria-selected="{"true" if on == k else "false"}">{t}{n}</button>'
    return f'<nav class="rgt-tabs" aria-label="{Q["tabs_aria"]}">' + b('checks', Q['tab_checks'], ' <em>10</em>') + b('full', Q['tab_full'], ' <em class="rgt-n" hidden></em>') + '</nav>'

def pay_case(root=''):  # simpler unlock popup (approved mockup). Summary and /full/ both include it.
    p = S['pay']
    return (f'<div class="ov pp-ov" id="paycase" hidden><div class="pp s" role="dialog" aria-modal="true" aria-labelledby="pph">'
            f'<button class="pp-x" data-close aria-label="{p["close"]}">×</button><header class="pp-hero"><h1 id="pph"></h1></header>'
            f'<label class="pready" id="pready" hidden><span>{p["ready_label"]}</span>'
            f'<input type="email" name="email" placeholder="{p["email_placeholder"]}" aria-label="{p["ready_label"]}" autocomplete="email"></label>'
            f'<button class="pb v big" id="usecheck" type="button" disabled>{p["check"]}</button>'
            f'<p class="helper" id="preadyh" hidden>{p["ready_help"]}</p><p class="msg" id="pmsg2"></p>'
            f'<div class="lks"><a href="{root}plans/" data-open="paywall">{p["see_plans"]}</a>'
            f'<span id="psign">{p["have_account"]} <a href="{root}login/" data-open="signup">{p["sign_in"]}</a></span></div></div></div>')

def firm_shell(F, root, tab):  # both tabs in one shell. tab is the one shown before JS runs.
    Q, r = S['summary'], S['result']
    checks_hidden = '' if tab == 'checks' else ' hidden'
    full_hidden = '' if tab == 'full' else ' hidden'
    return f'''<main class="wrap sumpg prof ld" data-firm="{E(F["slug"])}" data-tab="{tab}"><div class="rh">{bigsearch(F, "ps0")}</div>
<div class="ph"><h1>{E(F["name"])}{SAVE}</h1><p class="m"><i class="sk" style="width:300px"></i></p><div class="actw"><div class="hfs">{SK_HFS}</div></div></div>
{checking_box()}{ftabs(tab)}<div class="cban" hidden></div>
<div id="panel-checks"{checks_hidden}><div class="list">{skel()}</div>
<div class="rgt-see"><button type="button" data-tab="full">{Q["see_full"]}</button></div></div>
<div id="panel-full"{full_hidden}><div class="spl">{SK_SPL}</div>
<div class="unlock" id="lockcard" hidden><div><b></b><p></p></div><button class="btn" id="unlock">{r["lock_button"]}</button></div>
<div class="pgrid"><div class="pmain">{SK_PMAIN}</div><nav class="toc" aria-label="{r["toc_aria"]}">{SK_TOC}</nav></div></div>
<p class="fine">{r["fine"]}</p></main>
{pay_case(root)}'''

def summary(F, root='./'):  # /vc/<slug>/ opens on Checks. Full report is already in the page.
    return firm_shell(F, root, 'checks')

def result(F, root='../'):  # /vc/<slug>/full/ opens on Full report. Checks is already in the page.
    return firm_shell(F, root, 'full')

A, M, SO = S['account'], S['my_checks'], S['signed_out']
def why(k, q):  # optional exit question; values match exit_reasons.reason
    r = ''.join(f'<label><input type="radio" name="{k}why" value="{v}">{E(t)}</label>' for v, t in A['reasons'])
    return f'<fieldset class="why" id="{k}why"><legend class="q">{E(q)}<small>{A["why_optional"]}</small></legend>{r}<textarea id="{k}other" maxlength="500" placeholder="{A["why_more"]}" aria-label="{A["why_more_aria"]}"></textarea></fieldset>'
def signed_out(k):  # centered prompt shown by js/app.js when there is no session
    return f'<div class="emp" data-out hidden><h2>{SO[k + "_h2"]}</h2><p>{SO[k + "_p"]}</p><button class="btn" data-open="signup" style="margin-top:20px">{SO["button"]}</button></div>'

F_ = S['my_firms']


def _rpc(fn, args):
    req = urllib.request.Request(f"{CFG['url']}/rest/v1/rpc/{fn}", json.dumps(args).encode(),
        {'apikey': CFG['key'], 'authorization': 'Bearer ' + CFG['key'], 'content-type': 'application/json'})
    with urllib.request.urlopen(req, timeout=30) as r: return json.load(r)

def launch_firms():
    """Firms that get a page. With SUPABASE_URL/ANON_KEY, walk firm_sitemap and load firm_meta
    for each slug. Those RPCs read v2_firm_live joined to v2_firms, so a firm that goes live
    is included on the next build. There is no slug list. Without the keys, read every
    data/launch/*.json snapshot. An RPC failure fails the build."""
    if not (CFG['url'] and CFG['key']):
        firms = []
        for p in sorted(glob.glob(os.path.join(ROOT, 'data', 'launch', '*.json'))):
            firms.append(json.load(open(p))['firm'])
        if not firms: raise SystemExit('launch build: no firm snapshots in data/launch')
        return firms
    slugs, page_n = [], 1
    while True:
        rows = _rpc('firm_sitemap', {'p_page': page_n, 'p_size': 1000})
        slugs += [r['slug'] for r in rows]
        if len(rows) < 1000: break
        page_n += 1
    firms = []
    for slug in slugs:
        rows = _rpc('firm_meta', {'p_slug': slug})
        if rows: firms.append(rows[0])
    if not firms: raise SystemExit('launch build: firm_sitemap returned no firms firm_meta can open')
    return firms

def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    for f in ('style.css', 'logo.svg', 'js/app.js', 'js/company.js', 'js/search.js', 'js/dates.js'): shutil.copy(os.path.join(HERE, f), OUT)
    shutil.copytree(os.path.join(HERE, 'fav'), os.path.join(OUT, 'fav'))
    shutil.copytree(os.path.join(HERE, 'assets', 'video'), os.path.join(OUT, 'assets', 'video'))
    # Email templates load this from https://regretamin.com/assets/logo/lockup-light@2x.png
    logo_dir = os.path.join(OUT, 'assets', 'logo')
    os.makedirs(logo_dir, exist_ok=True)
    shutil.copy(os.path.join(HERE, 'assets', 'logo', 'lockup-light@2x.png'), logo_dir)
    shutil.copy(os.path.join(HERE, 'CNAME'), OUT)  # GitHub Pages custom domain (regretamin.com)
    firms = []
    T = {'name': T_NAME, 'slug': T_SLUG}
    page(os.path.join(OUT, '_tpl', 'summary.html'), summary(T, '../../'), '../../', T_NAME + S['title_suffix'], company=True, head=T_HEAD)
    page(os.path.join(OUT, '_tpl', 'full.html'), result(T, '../../../'), '../../../', T_NAME + S['title_suffix'], company=True, head=T_HEAD)
    nf = COPY.get('not_found', {'h1': 'We could not find that firm', 'p': 'It may not be checked yet. Search for it and we will start a check.'})
    page(os.path.join(OUT, '_tpl', '404.html'), f'<main class="wrap"><div class="hero"><h1>{E(nf["h1"])}</h1><p>{E(nf["p"])}</p>{SB()}</div></main>', '/', 'Not found' + S['title_suffix'], head='<meta name="robots" content="noindex">')
    # Site-wide 404: Cloudflare Pages serves /404.html with status 404 for unknown paths (no soft-404 SPA fallback).
    tpl = {v: open(os.path.join(OUT, '_tpl', v + '.html')).read() for v in ('summary', 'full')}
    # Edge cache key version: changes whenever the template or edge renderer changes, so a deploy never serves stale heads.
    import hashlib
    edge = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'edge', 'firm.mjs')).read()
    # The live slug set is part of the cache key, so a firm that just went live is not stuck on a cached 404.
    # lightspeed's cached 404 needs its own token: it was already a known slug when that 404 was stored.
    live_token = 'lightspeed'
    built = launch_firms()
    live_slugs = ','.join(sorted(F['slug'] for F in built))
    open(os.path.join(OUT, '_tpl', 'version.txt'), 'w').write(hashlib.sha256((edge + tpl['summary'] + tpl['full'] + '\n' + live_slugs + '\n' + live_token).encode()).hexdigest()[:12])
    for F in built:
        firms.append(F['slug'])
        for v, sub in (('summary', ''), ('full', 'full')):
            d = os.path.join(OUT, 'vc', F['slug'], sub); os.makedirs(d, exist_ok=True)
            open(os.path.join(d, 'index.html'), 'w').write(fill(tpl[v], F, v == 'full'))
    context = SimpleNamespace(**globals())
    for spec in PAGES:
        root = '../' * len(spec.slug.split('/')) if spec.slug else ''
        if spec.slug == '404': root = '/'
        dest = os.path.join(OUT, spec.slug, 'index.html') if spec.slug != '404' else os.path.join(OUT, '404.html')
        meta = S['pages'][spec.slug or 'home']
        page(dest, spec.builder(context), root, meta['title'], active=spec.active,
             head=page_head(spec, S, SITE), modals=spec.modals)
    # Edge and static hosts consume the exact same registered sitemap paths.
    static_paths = [spec.slug + '/' if spec.slug else '' for spec in PAGES if spec.sitemap]
    open(os.path.join(HERE, 'edge', 'static-pages.mjs'), 'w').write(
        '// Generated by launch/build.py from pages/registry.py. Do not edit.\nexport default ' + json.dumps(static_paths) + ';\n')
    site = SITE  # sitemap + robots (account and my-checks are left out)
    urls = [site + path for path in static_paths] + [f'{site}vc/{f}/' for f in firms]
    open(os.path.join(OUT, 'sitemap.xml'), 'w').write('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(f'<url><loc>{u}</loc></url>\n' for u in urls) + '</urlset>\n')
    open(os.path.join(OUT, 'robots.txt'), 'w').write(f'User-agent: *\nAllow: /\nDisallow: /_tpl/\n\nSitemap: {site}sitemap.xml\n')
    # company.js, app.js, search.js, dates.js and style.css keep one path. ?v= is only a browser
    # cache buster. Without these headers Cloudflare kept the previous file for four hours.
    open(os.path.join(OUT, '_headers'), 'w').write(
        '/company.js\n  Cache-Control: public, max-age=0, must-revalidate\n'
        '/app.js\n  Cache-Control: public, max-age=0, must-revalidate\n'
        '/search.js\n  Cache-Control: public, max-age=0, must-revalidate\n'
        '/dates.js\n  Cache-Control: public, max-age=0, must-revalidate\n'
        '/style.css\n  Cache-Control: public, max-age=0, must-revalidate\n')
    print('built', len(firms), 'firms', '->', OUT)

if __name__ == '__main__': main()
