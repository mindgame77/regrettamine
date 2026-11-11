"""One copy.json setting accepts a hosted MP4 or a YouTube URL."""
from html import escape as E
from urllib.parse import urlparse, parse_qs
import re

def render_video(setting, caption):
    if isinstance(setting, str):
        setting = {'src': setting}
    setting = setting or {}
    src = setting.get('src', '').strip()
    if not src:
        return '<div class="vspot-ph" role="img" aria-label="Video coming soon"></div>'
    u = urlparse(src)
    if u.scheme and u.scheme != 'https':
        raise ValueError('Video must be a site-relative MP4 path or HTTPS URL')
    if not u.scheme and (not src.startswith('/') or src.startswith('//')):
        raise ValueError('Local video must start with a single /')
    host = (u.hostname or '').lower()
    yt = ''
    if host in ('youtu.be', 'www.youtu.be'):
        yt = u.path.strip('/')
    elif host in ('youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtube-nocookie.com', 'www.youtube-nocookie.com'):
        parts = u.path.strip('/').split('/')
        yt = parse_qs(u.query).get('v', [''])[0] if u.path == '/watch' else (parts[1] if len(parts) == 2 and parts[0] in ('embed', 'shorts', 'live') else '')
    if yt:
        if not re.fullmatch(r'[A-Za-z0-9_-]{11}', yt):
            raise ValueError('Invalid YouTube video ID')
        return (f'<iframe class="vspot-media" src="https://www.youtube-nocookie.com/embed/{yt}" '
                f'title="{E(caption, quote=True)}" allow="accelerometer;autoplay;clipboard-write;encrypted-media;gyroscope;picture-in-picture;web-share" '
                'allowfullscreen loading="lazy" referrerpolicy="strict-origin-when-cross-origin"></iframe>')
    if not u.path.lower().endswith('.mp4'):
        raise ValueError('Video source must be an MP4 file or YouTube URL')
    poster = setting.get('poster', '')
    if poster:
        pu = urlparse(poster)
        if not (pu.scheme == 'https' or (not pu.scheme and poster.startswith('/') and not poster.startswith('//'))):
            raise ValueError('Poster must be site-relative or HTTPS')
    return (f'<video class="vspot-media" controls autoplay muted loop playsinline preload="metadata" '
            f'poster="{E(poster, quote=True)}" aria-label="{E(caption, quote=True)}">'
            f'<source src="{E(src, quote=True)}" type="video/mp4">'
            'Your browser does not support this video.</video>'
            '<script>(function(){var v=document.currentScript.previousElementSibling;'
            'if(window.matchMedia("(prefers-reduced-motion: reduce)").matches){v.autoplay=false;v.pause();}})();</script>')
