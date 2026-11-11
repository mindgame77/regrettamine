"""One list controls static routes, builders, navigation, metadata and sitemaps.

Page words and metadata live in copy.json -> site.pages[slug or 'home'].
Builders take the shared build context; they never write files or deploy.
"""
from dataclasses import dataclass
from html import escape as E
from . import home, pending, how_we_check, account, my_firms, privacy, terms, plans, login, firms
from . import my_checks_redirect, pricing_redirect, not_found

@dataclass(frozen=True)
class Page:
    slug: str
    builder: object
    nav: str = ''  # main, account, footer, or hidden
    sitemap: bool = False
    active: str = ''
    attributes: str = ''
    prefix: str = ''
    noindex: bool = False
    modals: str = 'both'
    redirect: str = ''

PAGES = (
    Page('', home.render, sitemap=True),
    Page('pending', pending.render, noindex=True),
    Page('investors', firms.render, nav='main', sitemap=True, active='investors'),
    Page('how-we-check', how_we_check.render, nav='main', sitemap=True, active='hwc'),
    Page('account', account.render, nav='account', noindex=True),
    Page('account/firms', my_firms.render, nav='account', noindex=True),
    Page('my-checks', my_checks_redirect.render, noindex=True, redirect='../account/firms/'),
    Page('privacy', privacy.render, nav='footer', sitemap=True),
    Page('terms', terms.render, nav='footer', sitemap=True),
    Page('plans', plans.render, nav='main', attributes=' data-open="paywall"', noindex=True, modals='signup'),
    Page('login', login.render, nav='main', attributes=' data-open="signup" id="signin"',
         prefix='<span class="left" id="left"></span>', noindex=True, modals='pricing'),
    Page('pricing', pricing_redirect.render, noindex=True, redirect='../?pricing=1'),
    Page('404', not_found.render, noindex=True),
)

def metadata(spec, site):
    return site['pages'][spec.slug or 'home']

def nav_links(site, root, group, active=''):
    links = []
    for spec in PAGES:
        if spec.nav != group:
            continue
        m = metadata(spec, site)
        on = ' class="on" aria-current="page"' if active and spec.active == active else ''
        links.append(f'{spec.prefix}<a href="{root}{spec.slug}/"{on}{spec.attributes}>{E(m["nav_label"])}</a>')
    return ''.join(links)

def footer_links(site, root):
    return nav_links(site, root, 'footer')

def page_head(spec, site, base):
    m = metadata(spec, site)
    url = base + (spec.slug + '/' if spec.slug else '')
    if spec.slug == '404': url = base + '404.html'
    if spec.redirect:
        # Redirects preserve query/hash behavior, and still have the shared shell.
        import json
        target = json.dumps(spec.redirect)
        suffix = '+location.search+location.hash' if '?' not in spec.redirect else '+location.hash'
        redirect = (f'<meta http-equiv="refresh" content="0;url={E(spec.redirect, quote=True)}">'
                    f'<script>location.replace({target}{suffix})</script>')
    else:
        redirect = ''
    return (('<meta name="robots" content="noindex">' if spec.noindex else '')
            + f'<meta name="description" content="{E(m["description"], quote=True)}">'
            + f'<link rel="canonical" href="{E(url, quote=True)}">'
            + f'<meta property="og:type" content="website"><meta property="og:site_name" content="{E(site["brand"], quote=True)}">'
            + f'<meta property="og:title" content="{E(m["title"], quote=True)}">'
            + f'<meta property="og:description" content="{E(m["description"], quote=True)}">'
            + f'<meta property="og:url" content="{E(url, quote=True)}"><meta name="twitter:card" content="summary">'
            + redirect)
