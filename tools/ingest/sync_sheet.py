#!/usr/bin/env python3
"""Write research_queue status back into registry.csv (status column; 'research_<status>' prefix so it never
collides with build/mark_status values; rows with status=loaded are never touched). Backs up registry.csv first.
Usage: python3 sync_sheet.py [--dry-run]"""
import csv, shutil, sys, time, os
from _supa import sql
here = os.path.dirname(os.path.abspath(__file__)); path = os.path.join(here, "registry.csv")
q = {r["registry_id"]: r for r in sql("select registry_id, status, attempts, submitted_at from public.research_queue")}
rows = list(csv.DictReader(open(path, newline=""))); fields = list(rows[0].keys())
changed = 0
for r in rows:
    s = q.get(r["registry_id"])
    if not s or r["status"] == "loaded" or (s["status"] == "queued" and not s["attempts"]): continue
    new = "research_" + s["status"]
    if r["status"] != new:
        r["status"] = new; changed += 1
        if s["status"] in ("submitted", "accepted") and s["submitted_at"]: r["done_at"] = s["submitted_at"][:19]
print(f"{changed} rows changed")
if changed and "--dry-run" not in sys.argv:
    bak = path + time.strftime(".bak-%Y%m%d-%H%M%S"); shutil.copy2(path, bak)
    w = csv.DictWriter(open(path + ".tmp", "w", newline=""), fieldnames=fields); w.writeheader(); w.writerows(rows)
    os.replace(path + ".tmp", path); print(f"written; backup {bak}")
