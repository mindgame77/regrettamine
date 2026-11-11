"""Static page routing and media regressions; no live service or credentials needed."""
import importlib.util
import json
import sys
from pathlib import Path
from types import SimpleNamespace
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'launch'))
from pages.registry import PAGES, page_head, nav_links
from pages.video import render_video


def test_registry_unique_routes_and_complete_metadata():
    site = json.loads((ROOT / 'launch/copy.json').read_text())['site']
    assert len({p.slug for p in PAGES}) == len(PAGES)
    for p in PAGES:
        m = site['pages'][p.slug or 'home']
        assert m['title'] and m['description']
        h = page_head(p, site, 'https://regretamin.com/')
        assert 'name="description"' in h and 'rel="canonical"' in h
        assert 'og:title' in h and 'og:description' in h and 'og:url' in h
        if p.nav:
            assert m['nav_label']
            assert p.slug + '/' in nav_links(site, '../', p.nav)
        assert not (p.sitemap and p.noindex)


def test_every_page_builder_renders(monkeypatch):
    monkeypatch.delenv('SUPABASE_URL', raising=False)
    monkeypatch.delenv('SUPABASE_ANON_KEY', raising=False)
    spec = importlib.util.spec_from_file_location('static_registry_build', ROOT / 'launch/build.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    c = SimpleNamespace(**vars(mod))
    for p in PAGES:
        assert '<main' in p.builder(c)


@pytest.mark.parametrize('src', [
    'https://www.youtube.com/watch?v=dQw4w9WgXcQ&feature=share',
    'https://youtu.be/dQw4w9WgXcQ',
    'https://www.youtube.com/shorts/dQw4w9WgXcQ',
    'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
])
def test_youtube_privacy_embed(src):
    out = render_video({'src': src}, 'Video')
    assert 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ' in out
    assert '<iframe' in out and 'allowfullscreen' in out


def test_hosted_video_has_mobile_and_accessibility_attributes():
    out = render_video({'src': '/assets/video/test.mp4', 'poster': '/assets/video/test.jpg'}, 'Team & ideas')
    for attr in ('muted', 'loop', 'playsinline', 'autoplay', 'controls', 'poster=', 'video/mp4'):
        assert attr in out
    assert 'Team &amp; ideas' in out
    assert 'prefers-reduced-motion' in out


@pytest.mark.parametrize('src', ['javascript:alert(1)', '//host/file.mp4', 'https://evil.example/watch?v=dQw4w9WgXcQ', '/unknown.html'])
def test_video_rejects_untrusted_embeds(src):
    with pytest.raises(ValueError):
        render_video({'src': src}, 'Video')
