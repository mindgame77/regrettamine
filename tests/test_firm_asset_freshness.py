"""The published firm shell must point at the company.js and copy that this build just wrote."""
import hashlib
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _build():
    env = os.environ.copy()
    env.pop('SUPABASE_URL', None)
    env.pop('SUPABASE_ANON_KEY', None)
    env['LAB_ONLY'] = '1'
    subprocess.run(['python3', 'launch/build.py'], cwd=ROOT, check=True, capture_output=True, text=True, env=env)


def _sha1(rel):
    return hashlib.sha1((ROOT / rel).read_bytes()).hexdigest()[:10]


def test_built_a16z_full_page_uses_this_build_assets_and_investors_copy():
    _build()
    html = (ROOT / 'site-launch/vc/a16z/full/index.html').read_text()
    tpl = (ROOT / 'site-launch/_tpl/full.html').read_text()
    company = _sha1('launch/js/company.js')
    app = _sha1('launch/js/app.js')
    css = _sha1('launch/style.css')
    for page in (html, tpl):
        assert set(re.findall(r'company\.js\?v=([0-9a-f]+)', page)) == {company}
        assert set(re.findall(r'app\.js\?v=([0-9a-f]+)', page)) == {app}
        assert set(re.findall(r'style\.css\?v=([0-9a-f]+)', page)) == {css}
        assert '"key": "investors"' in page
        assert 'What investors look for' in page
        assert 'c951a9bd68' not in page
    built_js = hashlib.sha1((ROOT / 'site-launch/company.js').read_bytes()).hexdigest()[:10]
    assert built_js == company
    edge = (ROOT / 'launch/edge/firm.mjs').read_text()
    summary = (ROOT / 'site-launch/_tpl/summary.html').read_text()
    slugs = ','.join(sorted(p.name for p in (ROOT / 'site-launch' / 'vc').iterdir() if p.is_dir()))
    version = hashlib.sha256((edge + summary + tpl + '\n' + slugs + '\n' + 'lightspeed').encode()).hexdigest()[:12]
    assert (ROOT / 'site-launch/_tpl/version.txt').read_text() == version
    headers = (ROOT / 'site-launch/_headers').read_text()
    for name in ('/company.js', '/app.js', '/search.js', '/dates.js', '/style.css'):
        assert name in headers
    assert 'max-age=0, must-revalidate' in headers
    assert 's-maxage' not in headers
