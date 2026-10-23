"""Prints SQL that upserts firm_check_rows from firm snapshots (launch/firm_snapshot.sql output).
Usage: python3 launch/sync_checks.py data/launch/a16z.json data/launch/nb-alternatives.json > migration.sql"""
import sys, json
from checks import checks

q = lambda s: 'null' if s is None else "'" + str(s).replace("'", "''") + "'"
for p in sys.argv[1:]:
    D = json.load(open(p)); slug = D['firm']['slug']
    for n, r in enumerate(checks(D), 1):
        print(f"insert into firm_check_rows (firm_id, n, title, descr, state, count_label) select id, {n}, {q(r['title'])}, {q(r['desc'])}, {q(r['state'])}, {q(r['count'])} "
              f"from firms where slug = {q(slug)} on conflict (firm_id, n) do update set title = excluded.title, descr = excluded.descr, state = excluded.state, count_label = excluded.count_label;")
