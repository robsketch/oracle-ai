#!/usr/bin/env bash
# Demo workload for /db-diag-review.
# Takes a Statspack snapshot, runs a short mixed workload as HR in FREEPDB1, then takes a
# second snapshot. The workload deliberately leaves evidence for the review to find:
#   - CPU-heavy SQL                 -> top SQL by CPU / elapsed, "DB CPU" in top events
#   - single-row insert + commit     -> "log file sync" waits, high commits per second
#   - literal (unshared) SQL         -> hard parses per second
#   - a two-session deadlock         -> ORA-00060 in the alert log plus a deadlock trace file
# All work happens in a scratch table HR.DIAG_DEMO, which is dropped at the end.
# Usage: scripts/demo-diag-load.sh [--no-deadlock]
set -euo pipefail

DEADLOCK=1
[[ "${1:-}" == "--no-deadlock" ]] && DEADLOCK=0

snap() {  # $1 = comment. Statspack can't run in CDB$ROOT, so switch to the PDB first.
  docker exec -i oracle-free sqlplus -S / as sysdba <<EOF
alter session set container = FREEPDB1;
set feedback off heading off
variable s number
exec :s := perfstat.statspack.snap(i_snap_level => 7, i_ucomment => '$1');
select 'Statspack snapshot ' || :s || ' ($1)' from dual;
EOF
}

hr() { sql -S -name demo_hr; }

echo "== Begin snapshot"; snap "demo begin"

echo "== Setup scratch table HR.DIAG_DEMO"
hr <<'EOF' >/dev/null
whenever sqlerror continue
drop table diag_demo purge;
create table diag_demo (id number primary key, pad varchar2(200));
insert into diag_demo select level, rpad('x', 200, 'x') from dual connect by level <= 1000;
commit;
EOF

echo "== CPU-heavy query (about 30-60 s, background)"
hr <<'EOF' >/dev/null &
select /* diag-demo cpu */ count(*)
from employees a, employees b, employees c, (select level n from dual connect by level <= 200) d
where a.salary + b.salary > c.salary - d.n;
EOF
CPU_PID=$!

echo "== Commit storm: 3,000 single-row inserts, each committed from the client"
# Client-side commits on purpose. Inside one PL/SQL block, Oracle batches commits and only
# waits once at the end, so there would be hardly any "log file sync" waits.
for i in $(seq 1001 4000); do
  echo "insert /* diag-demo commit */ into diag_demo values ($i, 'y');"
  echo "commit;"
done | { echo "set feedback off"; cat; } | hr >/dev/null

echo "== Hard-parse storm: 5,000 statements with literals"
hr <<'EOF' >/dev/null
declare n number;
begin
  for i in 1 .. 5000 loop
    execute immediate 'select /* diag-demo literal */ count(*) from diag_demo where id = ' || i into n;
  end loop;
end;
/
EOF

if (( DEADLOCK )); then
  echo "== Deadlock: two sessions lock rows 1 and 2 in opposite order"
  hr <<'EOF' >/dev/null &
whenever sqlerror continue
update diag_demo set pad = 'A' where id = 1;
exec dbms_session.sleep(4)
update diag_demo set pad = 'A' where id = 2;
rollback;
EOF
  A=$!
  sleep 1
  hr <<'EOF' >/dev/null &
whenever sqlerror continue
update diag_demo set pad = 'B' where id = 2;
exec dbms_session.sleep(4)
update diag_demo set pad = 'B' where id = 1;
rollback;
EOF
  B=$!
  wait "$A" "$B" || true
fi

echo "== Waiting for the CPU query to finish"
wait "$CPU_PID" || true

echo "== Drop scratch table"
echo "drop table diag_demo purge;" | hr >/dev/null

echo "== End snapshot"; snap "demo end"
echo "Done. Run /db-diag-review to analyse the snapshot pair, alert log and trace files."
