#!/usr/bin/env bash
# Preflight for /db-diag-review and the awr-analyst agent: make sure the local Oracle Free
# container is up and the CDB monitoring connection works, then print key=value facts.
# The only change it can make is `docker start oracle-free` when the container isn't running.
#
# Usage: scripts/db-preflight.sh            (no arguments)
# Env:   ORACLE_CONTAINER (default oracle-free), CDB_CONN (default demo_dbmon_cdb),
#        WAIT_SECS (default 300, how long to wait for "healthy")
# Exit:  0 ready · 1 Docker unusable · 2 container missing · 3 not healthy in time · 4 connection failed
set -uo pipefail

cd "$(dirname "$0")/.."
# Non-interactive shells (Claude Code's Bash tool) don't read ~/.bashrc.
export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/java}"
export PATH="$HOME/.local/opt/sqlcl/bin:$JAVA_HOME/bin:$PATH"

C="${ORACLE_CONTAINER:-oracle-free}"
CONN="${CDB_CONN:-demo_dbmon_cdb}"
WAIT="${WAIT_SECS:-300}"
say() { echo "$1=$2"; }

if ! docker info >/dev/null 2>&1; then
  say docker unavailable
  echo "hint: Docker daemon not reachable. After a WSL restart: sudo snap start docker (needs the user)." >&2
  exit 1
fi
if ! docker inspect "$C" >/dev/null 2>&1; then
  say container missing
  echo "hint: container $C doesn't exist. Recreate it with setup.md step 1." >&2
  exit 2
fi

started=no
state=$(docker inspect -f '{{.State.Status}}' "$C")
say container_state_before "$state"
if [[ "$state" != running ]]; then
  docker start "$C" >/dev/null
  started=yes
fi
say started_by_preflight "$started"

health=""
for ((i = 0; i < WAIT; i += 5)); do
  health=$(docker inspect -f '{{.State.Health.Status}}' "$C")
  [[ "$health" == healthy ]] && break
  sleep 5
done
say health "$health"
if [[ "$health" != healthy ]]; then
  echo "hint: not healthy after ${WAIT}s. Check: docker logs --tail 50 $C" >&2
  exit 3
fi

# One round trip: edition (base views, any edition), then AWR facts only if this is Free.
out=$(sql -S -name "$CONN" 2>&1 <<'EOF'
set heading off feedback off pagesize 0 linesize 400
set sqlformat default
select 'edition=' || edition from v$instance;
select 'instance_startup_utc=' || to_char(startup_time, 'YYYY-MM-DD HH24:MI:SS') from v$instance;
select 'db_time_utc=' || to_char(sys_extract_utc(systimestamp), 'YYYY-MM-DD HH24:MI:SS') from dual;
select 'is_free=' || case when edition = 'FREE' then 'Y' else 'N' end from v$instance;
EOF
)
if ! grep -q '^edition=' <<<"$out"; then
  say cdb_connection failed
  echo "$out" | grep -m3 -E 'ORA-|Error|error' >&2
  exit 4
fi
say cdb_connection "ok ($CONN)"
grep -E '^(edition|instance_startup_utc|db_time_utc|is_free)=' <<<"$out"

if grep -q '^is_free=Y' <<<"$out"; then
  # AWR (DBA_HIST_*) is touched only on Free, where the Diagnostics Pack is included. See LICENSING.md.
  sql -S -name "$CONN" <<'EOF' | grep -E '^awr_'
set heading off feedback off pagesize 0 linesize 400
set sqlformat default
select 'awr_snaps_since_startup=' || count(*)
from dba_hist_snapshot
where dbid = (select dbid from v$database)
  and startup_time >= (select startup_time from v$instance);  -- AWR's startup_time is a few s later than V$INSTANCE's
select 'awr_latest_snap=' || nvl(max(snap_id || ' at ' || to_char(end_interval_time, 'YYYY-MM-DD HH24:MI')), 'none')
from dba_hist_snapshot
where dbid = (select dbid from v$database)
  and snap_id = (select max(snap_id) from dba_hist_snapshot where dbid = (select dbid from v$database));
EOF
fi
exit 0
