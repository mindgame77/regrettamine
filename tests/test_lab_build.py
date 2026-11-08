"""A build writes a page for every live firm. There is no slug list."""
import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _snaps():
    return {p.stem for p in (ROOT / 'data' / 'launch').glob('*.json')}


def test_sources_have_no_firm_slug_list():
    build = (ROOT / 'launch' / 'build.py').read_text()
    assert 'LAB_SLUGS' not in build
    assert 'firm_sitemap' in build and 'firm_meta' in build
    js = (ROOT / 'launch' / 'js' / 'company.js').read_text()
    assert 'LAB_FIRMS' not in js
    assert 'const labFirm = (P) => !!(P.firm && P.firm.slug);' in js
    live = (ROOT / 'scripts' / 'check_live_reports.mjs').read_text()
    speed = (ROOT / 'scripts' / 'check_page_speed.mjs').read_text()
    y = (ROOT / '.github' / 'workflows' / 'pages.yml').read_text()
    for text in (live, speed, y, build, js):
        assert 'a16z,y-combinator' not in text
        assert 'forbion' not in text
    assert 'firmSlugs' in live
    assert 'firm_sitemap' in speed


def test_default_build_writes_every_local_snapshot():
    env = os.environ.copy()
    env.pop('SUPABASE_URL', None)
    env.pop('SUPABASE_ANON_KEY', None)
    env['LAB_ONLY'] = '1'
    import subprocess
    r = subprocess.run(['python3', 'launch/build.py'], cwd=ROOT, check=True, capture_output=True, text=True, env=env)
    assert '(lab)' not in r.stdout
    assert 'firms' in r.stdout
    built = {p.name for p in (ROOT / 'site-launch' / 'vc').iterdir() if p.is_dir()}
    snaps = _snaps()
    assert built == snaps
    assert 'founders-fund' in built
    assert 'a16z' in built


def test_offline_launch_firms_includes_every_snapshot(monkeypatch):
    monkeypatch.delenv('SUPABASE_URL', raising=False)
    monkeypatch.delenv('SUPABASE_ANON_KEY', raising=False)
    monkeypatch.syspath_prepend(str(ROOT / 'launch'))
    sys.modules.pop('legal', None)
    spec = importlib.util.spec_from_file_location('launch_build_live', ROOT / 'launch' / 'build.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    snaps = _snaps()
    for flag in ('1', '0'):
        monkeypatch.setenv('LAB_ONLY', flag)
        slugs = [f['slug'] for f in mod.launch_firms()]
        assert set(slugs) == snaps
        assert 'founders-fund' in slugs
        assert 'accel' in slugs


def test_live_check_workflow_and_deploy_guard():
    y = (ROOT / '.github' / 'workflows' / 'pages.yml').read_text()
    assert "docs/**" in y and "'*.md'" in y and "'**/*.md'" in y
    assert 'cancel-in-progress: false' in y
    assert 'pages-pr-' in y and "|| 'pages'" in y
    assert 'rollout:' in y
    sh = (ROOT / 'scripts' / 'pages_deploy.sh').read_text()
    assert 'founders-fund' in sh
    assert 'Uploading Functions bundle' in sh
    assert 'functions/vc/[[path]].js' in sh
    assert 'deploy main' in sh
    assert '-lt 100' not in sh
    assert "grep -q '/vc/a16z/'" in sh
