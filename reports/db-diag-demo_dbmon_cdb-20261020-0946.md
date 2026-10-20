# Oracle Diagnostic Review: FREE (window 2026-10-20 07:00 → 09:44 UTC / 08:00 → 10:44 BST)

| | |
|---|---|
| **Overall status** | 🟡 WARN (known container side effects at the 09:24 startup; no workload data for the window) |
| **Run at** | 2026-10-20 09:46 UTC (10:46 BST, host clock) |
| **Sources** | MCP: `demo_dbmon_cdb` (alert log, traces, incidents, AWR on Free), `demo_dbmon` (Statspack) |
| **Window** | requested: 2026-10-20 07:00 → 09:44 UTC (08:00 → 10:44 BST) · alert log / incidents / traces: that window · workload: **AWR: no usable pair** (only snap 14 at 09:34 UTC exists since the 09:24 startup; `covers_window = NO`) · **Statspack: no snapshots at all** |
| **Database** | Oracle AI Database 26ai Free 23.26.3.0.0, instance `FREE` (CDB), PDB `FREEPDB1`, container `oracle-free` |

## Summary

The database was **not running for most of the requested window**. The instance started at
09:24:27 UTC, 2 h 24 min into the window, so only the last 20 minutes have any evidence. That
startup needed **crash recovery**, which means the previous stop (some time after the last AWR
snapshot, 2026-10-19 16:00 UTC) wasn't a clean shutdown. It also raised two **ORA-00800 Set
Priority Failed** incidents (LGWR, VKTM). Both are known, kept for the demo, and caused by how
the container is run (`docker stop`'s 10 s timeout, and no `--cap-add=SYS_NICE`). There were no
ORA-600/7445/4031, corruption, deadlocks or redo stalls. There's **no workload data** for this
window: AWR has only one snapshot since the startup, and Statspack has none. Nothing urgent.
To review workload, rerun after 10:00 UTC, when the next hourly AWR snapshot gives a valid pair.

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Critical errors (ORA-600/7445/4031/corruption) | 🟢 OK | None in alert log or trace signatures (`alert_errors`, `trace_signatures`) |
| ADR incidents | 🟡 WARN | 2 incidents, both ORA-00800 Set Priority Failed (11255 VKTM, 11375 LGWR) at 09:24:28. Known, kept for demo |
| Instance lifecycle (restarts, crash recovery) | 🟡 WARN | 1 startup at 09:24:27 with crash recovery (no preceding "Instance shutdown complete"). Known, kept for demo |
| Application errors (deadlocks, 1555, space) | 🟢 OK | None, but the DB was up for only ~20 min of the window |
| Redo / log writer | 🟢 OK | No checkpoint/log-switch/archiver messages. LGWR runs at normal priority (see ORA-00800) |
| Workload: CPU | ⚪ N/A | No AWR pair or Statspack snapshots in the window |
| Workload: parsing | ⚪ N/A | as above |
| Workload: waits & locking | ⚪ N/A | as above |
| Workload: I/O & efficiency | ⚪ N/A | as above |

## Timeline

All times UTC (BST = UTC+1).

| Time | Source | Event |
|---|---|---|
| 2026-10-19 16:00 | AWR | Snap 13: last snapshot of the previous startup (13:58:10). The instance was stopped some time after this, outside the window |
| 07:00 → 09:24 | — | **Window opens. Instance down**: no alert-log lines, no AWR snapshots |
| 09:24:27 | alert log | `Starting ORACLE instance (normal)`. **Not** started by this review (preflight found the container already running) |
| 09:24:28 | alert / ADR | ORA-00800 Set Priority Failed: VKTM (incident 11255) and LGWR (incident 11375) |
| 09:24:28 | trace `FREE_lgwr_87.trc` | `WARNING: Failed to disable OOMK` |
| 09:24:29 | alert log | `Crash Recovery excluding pdb 2 which was cleanly closed`; `Beginning crash recovery of 1 threads` |
| 09:24:31 | AWR | AWR startup_time for the new instance |
| 09:24:35 | alert log | FREEPDB1 opened read write; `Completed: ALTER DATABASE OPEN` |
| 09:34 | AWR | Snap 14: the first automatic snapshot after the startup (only one, so no usable pair) |
| 09:37 | traces | `vkrm` trace last written (resource manager, routine) |
| 09:44 | — | Window closes |
| 09:45 | review | Preflight: container running and healthy, `awr_snaps_since_startup=1` |

## Findings

### 🟡 Crash recovery at the 09:24 startup (known, kept for demo)
- **Evidence:** `alert_lifecycle`: 09:24:29 `Crash Recovery excluding pdb 2 which was cleanly closed`
  and `kcvcrv: Beginning crash recovery of 1 threads`. There's no "Instance shutdown complete"
  before it, and the previous instance's last AWR snapshot was 2026-10-19 16:00. The database
  opened normally at 09:24:35.
- **What it means:** the previous instance was killed rather than shut down. Oracle replayed the
  online redo log to bring the datafiles back to a consistent state, which is like replaying a
  kdb+ tickerplant log after a crash. It worked, but every unclean stop is a risk. The cause is
  known: `docker stop` (10 s timeout) or a WSL shutdown kills Oracle before `shutdown immediate`
  finishes.
- **Recommendation (not executed):** stop with `docker stop -t 120 oracle-free` (shown clean on
  2026-10-08), and stop the container before `wsl --shutdown`. Rated WARN: there's only one
  restart in the window.

### 🟡 ORA-00800 Set Priority Failed for LGWR and VKTM (known, kept for demo)
- **Evidence:** `adr_incidents` 11255 (VKTM) and 11375 (LGWR) at 09:24:28, under problem 1 `ORA 800`
  (16 incidents since 2026-07-05; 2 in this window). Alert log: `Failed to elevate LGWR's priority
  from 0 to 1, policy 5 ... ErrMsg(Operation not permitted)`. The same appears for VKTM.
- **What it means:** Oracle tries to run its timekeeper (VKTM) and log writer (LGWR) at real-time
  scheduling priority. The container doesn't have `CAP_SYS_NICE`, so the kernel refuses. This
  isn't a crash. It can slow commits (`log file sync`) under heavy load, but it doesn't matter
  on an idle demo box.
- **Recommendation (not executed):** recreate the container with `--cap-add=SYS_NICE`. Optionally
  close the ADR incidents with `adrci` after the demo.

### 🔵 LGWR could not opt out of the OOM killer
- **Evidence:** `FREE_lgwr_87.trc` line 34: `WARNING: Failed to disable OOMK`.
- **What it means (general guidance, not checked against this system):** Oracle tries to set
  its critical background processes' `oom_score_adj` so the Linux OOM killer won't pick them.
  The container isn't allowed to, so if WSL2 runs short of memory, LGWR could be killed, which
  would take the instance down. This has the same cause as ORA-00800: restricted container
  privileges.
- **Recommendation (not executed):** keep enough memory in `.wslconfig` for the SGA/PGA plus
  headroom. If you need protection, run with the privileges Oracle's container docs list.

### 🔵 No workload coverage for the requested window
- **Evidence:** `awr_window_pairs` returned one row, 14 → 14 (`covers_window = NO`). `awr_snapshots`:
  the nearest snapshots are 13 (2026-10-19 16:00, previous startup) and 14 (2026-10-20 09:34).
  `sp_snapshots` returned no rows, so the `PERFSTAT` snapshot table is empty.
- **What it means:** the instance was down from 07:00 to 09:24, and AWR only takes its first
  snapshot ~10 min after a startup, so no delta can be computed. A pair must never span a restart.
  Snaps 13 and 14 belong to different startups, so they can't be paired.
- **Recommendation (not executed):** rerun after the 10:00 UTC automatic snapshot (pair 14 → 15). For
  a specific workload, run `scripts/awr-report.sh --snap` before and after it, or run
  `scripts/demo-diag-load.sh`, which also takes Statspack snapshots.

## Workload profile (Statspack / AWR)

Not available. There's no valid AWR pair or Statspack pair in the window (see the finding above). No
AWR report was generated.

## Trace excerpts

**`FREE_lgwr_87.trc`**: LGWR (log writer, background), CDB$ROOT, signature ORA-00800, lines 22–157
(the file has content up to line 59):
```
26  *** 2026-10-20T09:24:28.316521+00:00 (CDB$ROOT(1))
34  WARNING: Failed to disable OOMK
35  Incident 11375 created, dump file: /opt/oracle/diag/rdbms/free/FREE/incident/incdir_11375/FREE_lgwr_87_i11375.trc
37  ORA-00800: soft external error, arguments: [Set Priority Failed], [LGWR], [Check traces and OS configuration], [Check Oracle document and MOS notes], []
43  *** MODULE NAME:(sys$abs_action)
44  *** ACTION NAME:(Open/close/mount/dismount thread)
51  Overlapped redo/writes by log writer are disabled (size=2048, stall size=2048, poke=100%, LGWR mode=serial)
52  kcb_tsemk_rolling_rekey: ... master key is not active for pdb 1 ... Skip rolling rekey.
```
Interpretation: the priority failure happens once at process start. LGWR then opens the redo thread
normally. The `rolling_rekey` lines are routine (TDE isn't configured), and serial LGWR mode is normal
for a small Free instance. `FREE_vktm_47.trc` has the same signature (line 39) and wasn't excerpted,
because it's the same known cause.

## Method

- MCP mode: read-only queries from `.claude/skills/db-diag-review/queries.sql` via SQLcl MCP
  `sql_run`: 13 checks (`alert_overview`, `alert_errors`, `alert_lifecycle`, `adr_problems`,
  `adr_incidents`, `trace_inventory`, `trace_signatures`, 1× `trace_excerpt`, `edition_gate`,
  `awr_snapshots`, `awr_window_pairs` on `demo_dbmon_cdb`; `sp_snapshots`, `sp_window_pairs` on
  `demo_dbmon`). All placeholders used `timestamp '... +00:00'` (UTC).
- Preflight (`scripts/db-preflight.sh`, exit 0): container already running and healthy,
  `started_by_preflight=no`, `instance_startup_utc=2026-10-20 09:24:27`, `awr_snaps_since_startup=1`.
  So the 09:24 startup and its incidents were **not** caused by this review.
- Workload source: the edition gate found **Oracle AI Database 26ai Free** (`is_free=Y`), so AWR was
  allowed (see `LICENSING.md`). But `awr_window_pairs` returned no usable pair. Choice made: I
  did **not** substitute an older pair (e.g. 12→13 on 2026-10-19) because the user asked about
  this window and it's outside it. I didn't take a snapshot (that's not allowed). Fallback to
  Statspack found no snapshots. The `sp_*` delta checks were skipped. No ASH/ADDM or Tuning Pack was used.
- Caveats: the instance was up for only ~20 of the 164 minutes in the window, so "OK" ratings
  apply to that period only. The shutdown that caused the crash recovery was outside the window and
  wasn't examined. The known ARCHIVELOG-without-FRA finding doesn't show up in this window's
  evidence and wasn't checked. Only 1 of 2 trace signatures was excerpted (same cause).
- Audit: sessions are tagged `SQLcl-MCP` in `V$SESSION`. `DBTOOLS$MCP_LOG` isn't written for the
  read-only `dbmon` users.
