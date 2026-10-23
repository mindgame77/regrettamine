#!/usr/bin/env python3
"""Night-run monitor. Usage: python3 ingest_report.py [--errors 10]"""
import sys, json
from _supa import sql
n = int(sys.argv[sys.argv.index("--errors") + 1]) if "--errors" in sys.argv else 10
p = sql("select public.ingest_progress() p")[0]["p"]
p = json.loads(p) if isinstance(p, str) else p
tot = p["queue_total"]; st = p["by_status"]
print(f"Queue {tot} firms | paused={p['paused']} | DB {p['db_size']} (submissions {p['submissions_size']})")
for k in ["queued", "claimed", "submitted", "failed", "accepted", "rejected"]:
    print(f"  {k:<10}{st.get(k, 0):>6}  {100*st.get(k,0)/max(tot,1):5.1f}%")
print(f"Submissions: total {p['submissions_total']}, last hour {p['submissions_last_hour']} "
      f"(invalid {p['invalid_last_hour']}, error rate {p['error_rate_last_hour']}), valid records total {p['records_total']}, stale claims {p['stale_claims']}")
rate = p["submissions_last_hour"] - p["invalid_last_hour"]
if rate: print(f"ETA at current rate: {st.get('queued',0)/rate:.1f} h")
if p["db_size_bytes"] > 400e6: print("WARNING: DB > 400 MB (free plan limit 500 MB)")
rows = sql(f"select registry_id, status, attempts, claimed_by, left(last_error,160) err, updated_at from public.research_queue where last_error is not null order by updated_at desc limit {n}")
if rows:
    print(f"Latest errors:")
    for r in rows: print(f"  {r['registry_id']} {r['status']} att={r['attempts']} {r['claimed_by'] or ''}: {r['err']}")
