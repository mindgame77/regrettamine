"""Prints SQL that upserts firm_check_rows from firm snapshots (launch/firm_snapshot.sql output).
Usage: python3 launch/sync_checks.py data/launch/a16z.json data/launch/nb-alternatives.json > migration.sql
Guard (straight checks, 2026-10-23): rows may also come from bot uploads (apply_checks_for_firm), so
 - a snapshot with 0 facts is skipped (it would only produce nc rows), and
 - an existing non-nc row is never overwritten with nc."""
import sys, json
sys.exit("checks are off (Alex, 2026-10-28): firm_check_rows is no longer filled; pages show the 10 checks as a static list")
from checks import checks

q = lambda s: 'null' if s is None else "'" + str(s).replace("'", "''") + "'"
for p in sys.argv[1:]:
    D = json.load(open(p)); slug = D['firm']['slug']
    if not D.get('facts'):
        print(f"-- skipped {slug}: snapshot has 0 facts", file=sys.stderr); continue
    for n, r in enumerate(checks(D), 1):
        print(f"insert into firm_check_rows (firm_id, n, title, descr, state, count_label) select id, {n}, {q(r['title'])}, {q(r['desc'])}, {q(r['state'])}, {q(r['count'])} "
              f"from firms where slug = {q(slug)} on conflict (firm_id, n) do update set title = excluded.title, descr = excluded.descr, state = excluded.state, count_label = excluded.count_label "
              f"where excluded.state <> 'nc' or firm_check_rows.state = 'nc';")
