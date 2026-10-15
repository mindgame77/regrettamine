"""Read the published site from Supabase with the service role key.

The key is used only by the build process. It is never written into the site.
"""
import json
import urllib.request

from regrettamine.assemble import assemble_site


def fetch_bundle(url, key, rpc="published_site_bundle"):
    endpoint = url.rstrip("/") + "/rest/v1/rpc/" + rpc
    request = urllib.request.Request(
        endpoint,
        data=b"{}",
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if isinstance(payload, str):
        payload = json.loads(payload)
    return payload


def load_site(url, key):
    return assemble_site(fetch_bundle(url, key))


def store_report(url, key, slug, html):
    endpoint = url.rstrip("/") + "/rest/v1/rpc/store_report_page"
    request = urllib.request.Request(
        endpoint,
        data=json.dumps({"p_slug": slug, "p_html": html}).encode("utf-8"),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        response.read()


def fetch_public_bundle(url, anon_key):
    return fetch_bundle(url, anon_key, rpc="public_site_bundle")


def fetch_db_bundle(database_url):
    import psycopg

    with psycopg.connect(database_url) as conn:
        value = conn.execute("select published_site_bundle()").fetchone()[0]
    return json.loads(value) if isinstance(value, str) else value


def store_fragment(url, key, fragment_key, html):
    endpoint = url.rstrip("/") + "/rest/v1/rpc/store_site_fragment"
    request = urllib.request.Request(
        endpoint,
        data=json.dumps({"p_key": fragment_key, "p_html": html}).encode("utf-8"),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        response.read()
