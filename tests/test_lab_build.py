"""The default site build is the 10 lab firms. LAB_ONLY=0 is the manual rollout."""
import importlib.util
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAB = (
    'a16z', 'y-combinator', 'sequoia', 'lightspeed', 'generalcatalyst',
    'plugandplay', 'accel', 'greenoaks', 'khosla-ventures', 'mio-partners',
)


def _lab_slugs_in_source():
    text = (ROOT / 'launch' / 'build.py').read_text()
    m = re.search(r'LAB_SLUGS = \(([^)]*)\)', text, re.S)
    assert m, 'LAB_SLUGS missing'
    return tuple(re.findall(r"'([^']+)'", m.group(1)))


def test_build_lists_the_ten_lab_firms():
    assert _lab_slugs_in_source() == LAB


def test_default_build_writes_lab_snapshots_only():
    env = os.environ.copy()
    env.pop('SUPABASE_URL', None)
    env.pop('SUPABASE_ANON_KEY', None)
    env['LAB_ONLY'] = '1'
    r = subprocess.run(['python3', 'launch/build.py'], cwd=ROOT, check=True, capture_output=True, text=True, env=env)
    assert '(lab)' in r.stdout
    built = {p.name for p in (ROOT / 'site-launch' / 'vc').iterdir() if p.is_dir()}
    snaps = {p.stem for p in (ROOT / 'data' / 'launch').glob('*.json')}
    assert built == (set(LAB) & snaps)
    assert 'founders-fund' not in built
    assert 'a16z' in built


def test_rollout_flag_selects_every_local_snapshot(monkeypatch):
    import sys
    monkeypatch.setenv('LAB_ONLY', '0')
    monkeypatch.delenv('SUPABASE_URL', raising=False)
    monkeypatch.delenv('SUPABASE_ANON_KEY', raising=False)
    monkeypatch.syspath_prepend(str(ROOT / 'launch'))
    sys.modules.pop('legal', None)
    spec = importlib.util.spec_from_file_location('launch_build_rollout', ROOT / 'launch' / 'build.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    slugs = [f['slug'] for f in mod.launch_firms()]
    snaps = {p.stem for p in (ROOT / 'data' / 'launch').glob('*.json')}
    assert set(slugs) == snaps
    assert 'founders-fund' in slugs
    assert len(slugs) > len(LAB)


def test_live_check_workflow_and_deploy_guard():
    live = (ROOT / 'scripts' / 'check_live_reports.mjs').read_text()
    m = re.search(r"REGRET_FIRMS \|\| '([^']+)'", live)
    assert m.group(1).split(',') == list(LAB)
    assert 'forbion' not in m.group(1)
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
