"""Privacy Policy (/privacy/) and Terms of Service (/terms/).

The words live in launch/legal/privacy.md and launch/legal/terms.md. This module
turns those files into the existing legal page: kicker, title, lead, effective
date, a table of contents from the headings, then one section per heading.
Plan names and prices come from copy.json through {{plan.starter.price}} style
placeholders. Editing a markdown file and deploying rebuilds the page.
"""
import html
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
PLANS = json.load(open(os.path.join(HERE, '..', 'copy.json')))['plans']
EMAIL = 'malytskyyo@gmail.com'
# Friendly names for the plan keys in copy.json. single / m10 / m30 still work.
ALIASES = {'starter': 'm10', 'pro': 'm30', 'single': 'single'}


def _lookup(path):
    parts = path.split('.')
    if parts[0] not in ('plan', 'plans') or len(parts) < 3:
        raise KeyError(path)
    key = parts[1]
    if parts[0] == 'plan':
        key = ALIASES.get(key, key)
    node = PLANS[key]
    for part in parts[2:]:
        node = node[part]
    if isinstance(node, (dict, list)):
        raise KeyError(path)
    return str(node)


def _fill(text):
    def repl(match):
        token = match.group(1).strip()
        try:
            return _lookup(token)
        except KeyError:
            raise ValueError(f'unknown placeholder in legal markdown: {{{{{token}}}}}') from None
    filled = re.sub(r'\{\{\s*([^}]+?)\s*\}\}', repl, text)
    if '{{' in filled or '[DATE]' in filled:
        raise ValueError('legal markdown still has an unfilled placeholder')
    return filled


def _inline(text):
    text = html.escape(_fill(text), quote=True)
    text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)

    def link(match):
        label, url = match.group(1), match.group(2)
        if not re.match(r'^(https://|mailto:|\.\./|#)', url):
            raise ValueError(f'legal markdown link is not allowed: {url}')
        return f'<a href="{url}">{label}</a>'

    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', link, text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', text)
    return text.replace(EMAIL, f'<a href="mailto:{EMAIL}">{EMAIL}</a>')


def _slug(heading, used):
    base = re.sub(r'[^a-z0-9]+', '-', heading.lower()).strip('-') or 'section'
    slug, n = base, 2
    while slug in used:
        slug = f'{base}-{n}'
        n += 1
    used.add(slug)
    return slug


def _blocks(lines):
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        if line.startswith('### '):
            out.append(f'<h3>{_inline(line[4:].strip())}</h3>')
            i += 1
            continue
        if line.lstrip().startswith('- '):
            items = []
            while i < len(lines) and lines[i].lstrip().startswith('- '):
                items.append(_inline(lines[i].lstrip()[2:].strip()))
                i += 1
            out.append('<ul>' + ''.join(f'<li>{item}</li>' for item in items) + '</ul>')
            continue
        para = []
        while i < len(lines) and lines[i].strip() and not lines[i].lstrip().startswith('- ') and not lines[i].startswith('### '):
            para.append(lines[i].strip())
            i += 1
        out.append('<p>' + _inline(' '.join(para)) + '</p>')
    return ''.join(out)


def _render(filename):
    raw = open(os.path.join(HERE, filename), encoding='utf-8').read().replace('\r\n', '\n')
    lines = raw.split('\n')
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i >= len(lines) or not lines[i].startswith('# '):
        raise ValueError(f'{filename} must start with a # title')
    title = lines[i][2:].strip()
    i += 1
    lead, eff = [], None
    while i < len(lines) and not (lines[i].startswith('## ') and not lines[i].startswith('### ')):
        line = lines[i].strip()
        i += 1
        if not line:
            continue
        if line.startswith('Effective '):
            eff = line
        else:
            lead.append(line)
    if not lead or not eff:
        raise ValueError(f'{filename} needs a lead paragraph and an Effective line')
    used, sections = set(), []
    heading, buf = None, []
    while i <= len(lines):
        line = lines[i] if i < len(lines) else None
        if line is None or (line.startswith('## ') and not line.startswith('### ')):
            if heading:
                sections.append((heading, _blocks(buf)))
            if line is None:
                break
            heading, buf = line[3:].strip(), []
        else:
            buf.append(line)
        i += 1
    if not sections:
        raise ValueError(f'{filename} needs at least one ## heading')
    ids = [_slug(h, used) for h, _ in sections]
    toc = ''.join(f'<a href="#{sid}">{_inline(h)}</a>' for sid, (h, _) in zip(ids, sections))
    body = ''.join(f'<section id="{sid}"><h2>{_inline(h)}</h2>{b}</section>' for sid, (h, b) in zip(ids, sections))
    return (f'<main class="hp lg"><span class="ey">Legal</span><h1>{_inline(title)}</h1>'
            f'<p class="lead">{_inline(" ".join(lead))}</p><p class="eff">{_inline(eff)}</p>'
            f'<div class="toc">{toc}</div>{body}</main>')


def privacy():
    return _render('privacy.md')


def terms():
    return _render('terms.md')
