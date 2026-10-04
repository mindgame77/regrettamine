"""Read the published site from Supabase with the anon key."""
import json
import urllib.request

from regrettamine.assemble import assemble_site


def fetch_bundle(url, key):
    endpoint = url.rstrip("/") + "/rest/v1/rpc/published_site_bundle"
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
