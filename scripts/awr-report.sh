#!/usr/bin/env bash
# Generate an AWR report for /db-diag-review (file mode) or for a human to read.
# AWR is part of the Diagnostics Pack. It's included in Oracle AI Database Free but is a paid
# option on Enterprise Edition and unavailable on Standard Edition 2. This script refuses to
# run unless the banner says "Free", or AWR_LICENSED=1 is set by someone who has confirmed the
# target is licensed. See LICENSING.md.
#
# Usage: scripts/awr-report.sh [--snap] [--html] [<begin_snap> <end_snap>]
#   --snap   take a manual AWR snapshot first (as the newest end point)
#   --html   write HTML instead of text
#   default  newest two adjacent snapshots from the same instance startup
# Output: reports/awr/awr_<begin>_<end>.{txt,html}. Connection: $AWR_CONN (default demo_dbmon_cdb).
set -euo pipefail

cd "$(dirname "$0")/.."
# Non-interactive shells (Claude Code's Bash tool) don't read ~/.bashrc.
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/java}"
export PATH="$HOME/.local/opt/sqlcl/bin:$JAVA_HOME/bin:$PATH"

CONN="${AWR_CONN:-demo_dbmon_cdb}"
FMT=text; SNAP=0; B=""; E=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --snap) SNAP=1 ;;
    --html) FMT=html ;;
    *) if [[ -z "$B" ]]; then B="$1"; else E="$1"; fi ;;
  esac
  shift
done
[[ -n "$B" && -z "$E" ]] && { echo "Give both begin and end snapshot ids" >&2; exit 2; }

q() { sql -S -name "$CONN" | sed '/^\s*$/d'; }  # one-value queries, blank lines dropped

banner=$(printf "set heading off feedback off\nset sqlformat default\nselect banner from v\$version;\n" | q)
if [[ "$banner" != *Free* && "${AWR_LICENSED:-0}" != 1 ]]; then
  echo "Refusing: not Oracle Database Free ($banner)." >&2
  echo "AWR needs the Diagnostics Pack licence here. Use Statspack, or set AWR_LICENSED=1" >&2
  echo "only after confirming the licence (see LICENSING.md)." >&2
  exit 3
fi

if [[ $SNAP == 1 ]]; then
  printf "set feedback off\nexec dbms_workload_repository.create_snapshot\n" | q
  echo "Took an AWR snapshot"
fi

if [[ -z "$B" ]]; then
  # Newest pair of adjacent snapshots with the same startup_time (deltas across a restart are invalid).
  read -r B E < <(q <<'EOF'
set heading off feedback off
set sqlformat default
select prev_id || ' ' || snap_id from (
  select snap_id, startup_time,
         lag(snap_id) over (order by snap_id) prev_id,
         lag(startup_time) over (order by snap_id) prev_start
  from dba_hist_snapshot where dbid = (select dbid from v$database))
where startup_time = prev_start
order by snap_id desc fetch first 1 row only;
EOF
)
  [[ -z "${E:-}" ]] && { echo "Need two AWR snapshots from the same startup. Try --snap, wait, then --snap again." >&2; exit 4; }
fi

mkdir -p reports/awr
out="reports/awr/awr_${B}_${E}.$([[ $FMT == html ]] && echo html || echo txt)"
fn=$([[ $FMT == html ]] && echo awr_report_html || echo awr_report_text)
sql -S -name "$CONN" > "$out" <<EOF
set heading off feedback off pagesize 0 linesize 1500 trimspool on long 1000000
set sqlformat default
select /* db-diag-review */ output
from table(dbms_workload_repository.$fn(
  (select dbid from v\$database), (select instance_number from v\$instance), $B, $E));
EOF
echo "AWR report snaps $B-$E -> $out ($(wc -l < "$out") lines)"
