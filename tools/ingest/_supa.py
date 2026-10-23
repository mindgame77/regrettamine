"""Shared helper: run read SQL on project sxxgvkdwgiouyqciztec via the Supabase Management API.
Needs env SUPABASE_ACCESS_TOKEN (never printed)."""
import json, os, urllib.request
REF = "sxxgvkdwgiouyqciztec"
def sql(q):
    tok = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not tok: raise SystemExit("SUPABASE_ACCESS_TOKEN not set")
    r = urllib.request.Request(f"https://api.supabase.com/v1/projects/{REF}/database/query", data=json.dumps({"query": q}).encode(),
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json", "User-Agent": "regretamin-ingest/1"})
    return json.load(urllib.request.urlopen(r, timeout=60))
