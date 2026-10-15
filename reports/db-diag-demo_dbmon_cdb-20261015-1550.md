# Oracle Diagnostic Review: FREE (whole instance: CDB$ROOT + FREEPDB1)

| | |
|---|---|
| **Overall status** | 🟡 WARN |
| **Run at** | 2026-10-15 15:50 BST (host) / 14:50 UTC (DB) |
| **Sources** | MCP: `demo_dbmon_cdb` (alert log, traces, incidents, AWR on Free). Statspack (`demo_dbmon`) not used |
| **Window** | alert log / traces: last 7 days (from 2026-10-08 14:50 UTC) · workload: AWR snaps 8–9 (2026-10-07 12:00:07 → 13:00:30 UTC, 60.4 min), **before the latest restart** |
| **Database** | Oracle AI Database 26ai Free 23.26.3.0.0, instance `FREE` on `9c6b064276dd` (container), 16 CPUs (8 cores), 7.7 GB RAM |

## Summary

There are no critical errors, no corruption and no application errors in the last 7 days. The
database was down from 2026-10-08 until this review started it (`started_by_preflight=yes`,
14:50:19 UTC). So the only alert-log activity in the window comes from that one startup.
That startup needed **crash recovery**, which means the previous stop was unclean. It also
raised the usual two **ORA-00800 Set Priority Failed** incidents (VKTM, LGWR). Both are known
and kept unfixed for the demo. The newest valid AWR hour (7 Oct, 12:00–13:00 UTC) was idle and
healthy: 11 s of DB time in an hour, 97% of it CPU, and Oracle's own maintenance jobs at the top.
Before the demo, stop the container with `docker stop -t 120 oracle-free`.

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Critical errors (ORA-600/7445/4031/corruption) | 🟢 OK | `alert_errors`: no `1-critical` rows. `trace_signatures`: only ORA-00800 |
| ADR incidents | 🟡 WARN | 2 incidents, both ORA-00800 Set Priority Failed (VKTM 16061, LGWR 16181), 14:50:20 UTC. Known-benign, side effect of this run's startup |
| Instance lifecycle (restarts, crash recovery) | 🟡 WARN | 1 startup (14:50:19 UTC, started by awr-analyst), with "Beginning crash recovery of 1 threads". Cause known (unclean stop). Known, kept for demo |
| Application errors (deadlocks, 1555, space) | 🟢 OK | No ORA-00060/01555/0165x in alert log or traces in the window |
| Redo / log writer | 🟢 OK | No checkpoint/archiver/slow-write messages. AWR `log file sync` avg 2.72 ms. LGWR at normal priority (see ORA-00800) |
| Workload: CPU | 🟢 OK | Host 99.6% idle. DB CPU 97.3% of only 11.3 s DB time over 60 min |
| Workload: parsing | 🟢 OK | Soft parse 96.80%, 0.4 hard parses/s |
| Workload: waits & locking | 🟢 OK | Top: DB CPU 97.3%, `log file sync` 4.8%. No row lock waits (Segments by Row Lock Waits: no data) |
| Workload: I/O & efficiency | 🟢 OK | Buffer hit 99.64%, `db file sequential read` 0.19 ms, 0.3 phys reads/s |

## Timeline

All times UTC.

| Time | Source | Event |
|---|---|---|
| 2026-10-07 11:01:02 | AWR | Instance startup (from snapshot `startup_time`) |
| 2026-10-07 12:00:07 → 13:00:30 | AWR | **Workload window**: snaps 8–9, idle hour |
| 2026-10-08 11:56:46 | AWR | Instance startup (snap 10 is the only snapshot from it) |
| 2026-10-08 12:08:29 | AWR | Instance startup (clean, as verified on 2026-10-08). Snap 11 at 13:00 is the last snapshot taken |
| 2026-10-08 13:00 → 2026-10-15 14:50 | — | No AWR snapshots. Instance down (stopped at an unknown time, uncleanly, outside the 7-day alert window) |
| 2026-10-15 14:50:19 | alert | `Starting ORACLE instance (normal)`: **started by awr-analyst for this review** |
| 2026-10-15 14:50:20 | ADR | Incident 16061 ORA-00800 [Set Priority Failed] [VKTM] |
| 2026-10-15 14:50:20 | ADR | Incident 16181 ORA-00800 [Set Priority Failed] [LGWR] |
| 2026-10-15 14:50:22 | alert | `Crash Recovery excluding pdb 2 which was cleanly closed` / `Beginning crash recovery of 1 threads` |
| 2026-10-15 14:50:25 | alert | FREEPDB1 opened read write. `Completed: ALTER DATABASE OPEN` |
| 2026-10-15 14:50:31 | preflight | DB time at preflight check. `awr_snaps_since_startup=0` |

## Findings

### 🟡 Crash recovery at startup (known, kept for demo)
- **Evidence:** `alert_lifecycle`: 14:50:22 `Crash Recovery excluding pdb 2 which was cleanly closed`
  and `kcvcrv: Beginning crash recovery of 1 threads`. No "Instance shutdown complete" before it
  in the window. The container was `exited` before preflight. Recovery finished and the DB opened
  in 6 s (14:50:19 → 14:50:25).
- **What it means:** Oracle's last stop wasn't a clean shutdown, so at startup it replayed the
  online redo log to bring the datafiles back to a consistent state ("crash" or "instance"
  recovery). It worked, and nothing was lost. The cause is known: `docker stop` with its 10 s
  default, or a WSL shutdown, kills Oracle before `shutdown immediate` finishes. The 2026-10-08
  12:08 startup came after a `docker stop -t 120` and had no crash recovery. The stop after it
  was evidently unclean. It was only one recovery, not repeated within a day, so WARN.
- **Recommendation (not executed):** always stop with `docker stop -t 120 oracle-free`, and stop
  the container before `wsl --shutdown` or a Windows reboot.

### 🟡 ORA-00800 Set Priority Failed for VKTM and LGWR (known, kept for demo)
- **Evidence:** `adr_incidents`: 16061 (VKTM) and 16181 (LGWR), 14:50:20, `background_proc`, con_id 1.
  `adr_problems`: problem 1 `ORA 800`, 22 incidents all-time, first on 2026-07-05. That date is
  before this environment existed (2026-10-06), so it probably comes from the image's own build.
  Alert: `Failed to elevate LGWR's priority from 0 to 1, policy 5 ... ErrMsg(Operation not permitted)`.
  The VKTM trace shows `kstmmainvktm(): failed in setting elevated priority` and `highres_disabled`.
- **What it means:** Oracle tries to run its timekeeper (VKTM) and log writer (LGWR) at real-time
  priority. The container doesn't have `CAP_SYS_NICE`, so the OS refuses. This isn't a crash.
  LGWR at normal priority can make commits slower under heavy load, but `log file sync` was
  2.7 ms in the AWR window. These two incidents are side effects of this run's startup.
- **Recommendation (not executed):** recreate the container with `--cap-add=SYS_NICE` (same volume
  `oracle-free-data`) when the demo no longer needs this finding.

### 🔵 "WARNING: Failed to disable OOMK" in background traces
- **Evidence:** `FREE_lgwr_88.trc` and `FREE_vktm_46.trc`, line 34, just before the ORA-00800.
- **What it means (general guidance, not checked against this system):** Oracle tries to protect
  critical background processes from the Linux OOM killer by adjusting `oom_score_adj`. The
  container isn't allowed to, so on a 7.7 GB host under memory pressure the kernel could kill an
  Oracle background process, which takes the instance down. It has the same root cause as
  ORA-00800 (restricted container privileges).
- **Recommendation (not executed):** keep an eye on memory headroom in WSL (`.wslconfig`). If the
  instance ever dies unexpectedly, check `dmesg` for OOM-killer entries.

### 🔵 ARCHIVELOG with no FRA (known, kept for demo, not re-checked here)
- **Evidence:** this is a finding from `/db-health-check`. This review's queries don't check it
  directly. There were no archiver errors (`ORA-00257`/`19809`/`19815`) in the alert log window.
- **What it means:** archived redo goes to `$ORACLE_HOME/dbs/arch` in the container's writable
  layer, not the data volume. It is lost if the container is recreated, and it can fill the layer.
- **Recommendation (not executed):** set `db_recovery_file_dest` (and its size) on the
  `/opt/oracle/oradata` volume.

### 🔵 No AWR coverage since 2026-10-08 13:00, and no usable pair for the current startup
- **Evidence:** `awr_snapshots`: the newest snapshot is 11 (2026-10-08 13:00). Snaps 10 and 11 are
  singletons from separate startups, and `awr_snaps_since_startup=0`.
- **What it means:** the AWR window used below is 8 days old and comes from before three restarts.
  The 7-day alert-log window doesn't overlap it, so there is nothing to correlate (no deadlocks or
  demo workload runs fall inside it).
- **Recommendation (not executed):** to get a fresh window, wait for the hourly snapshots (the
  first comes about 10 min after startup, then on the hour), or run `scripts/awr-report.sh --snap`
  before and after a workload such as `scripts/demo-diag-load.sh`.

## Workload profile (AWR snaps 8–9)

- **Window:** 2026-10-07 12:00:07 → 13:00:30 UTC (60.38 min), startup 2026-10-07 11:01. DB time
  11.3 s, DB CPU 11.0 s, average active sessions ≈ 0.003. Background CPU 32.3 s.

| Event | Waits | Time (s) | Avg | % DB time |
|---|---|---|---|---|
| DB CPU | — | 11 | — | 97.3 |
| log file sync | 202 | 0.5 | 2.72 ms | 4.8 |
| direct path write | 59 | 0.1 | 0.96 ms | 0.5 |
| db file sequential read | 159 | 0.0 | 0.19 ms | 0.3 |
| Allocate UGA memory from OS | 2,175 | 0.0 | 10 µs | 0.2 |

- **Load profile:** 16.6 executes/s, 11.3 parses/s (0.4 hard), 76.6 logical reads/s, 0.3
  physical reads/s, 4.2 KB redo/s, 0.5 user calls/s. Almost no user transactions.
- **Efficiency:** buffer hit 99.64%, soft parse 96.80%, library hit 93.70%, execute-to-parse
  31.80% (low, but it comes from internal recursive SQL parsing each call, e.g. `7qb74y7hp6cwd`
  7,426 parses / 7,427 execs), in-memory sort 100%.
- **Top SQL** (all Oracle maintenance, which is noise on an idle box):

| sql_id | PDB / module | Execs | Elapsed (s) | CPU (s) | Text |
|---|---|---|---|---|---|
| b39m8n96gxk7c | FREEPDB1 / DBMS_SCHEDULER | 15 | 0.9 | 0.9 | `call dbms_autotask_prvt.run_autotask` |
| 2pkpuk0vd342z | CDB$ROOT | 1 | 0.6 | 0.6 | `insert into wrh$_mvparameter` (the AWR snapshot itself) |
| ampw9ddqufjd3 | FREEPDB1 / DBMS_SCHEDULER | 4 | 0.4 | 0.4 | `dbms_auto_index_internal.capture_sts` |
| a95n8p4vpxmps | CDB$ROOT | 1 | 0.2 | 0.2 | `prvt_hdm.execute_slave_actions` (ADDM auto-run) |
| 61znfd8fvgha6 | FREEPDB1 / SYS_AUTO_STS_MODULE | 4 | 0.2 | 0.2 | automatic SQL tuning set capture |

- **Where did the time go?** Nowhere much. In an hour the instance did 11 s of foreground work,
  almost all CPU in Oracle's automatic maintenance (autotask, auto-index capture, automatic SQL
  tuning set, AWR's own snapshot and ADDM). The host was 99.6% idle. Commits were fast (2.7 ms)
  and single-block reads sub-millisecond. There's no application workload in this window to
  judge.

## Trace excerpts

**`FREE_lgwr_88.trc`**: log writer (background), CDB$ROOT, signature ORA-00800 (lines 22–157 requested, 33 returned)
```
34  WARNING: Failed to disable OOMK
35  Incident 16181 created, dump file: .../incident/incdir_16181/FREE_lgwr_88_i16181.trc
37  ORA-00800: soft external error, arguments: [Set Priority Failed], [LGWR], [Check traces and OS configuration], ...
43  *** MODULE NAME:(sys$abs_action)
44  *** ACTION NAME:(Open/close/mount/dismount thread)
51  Overlapped redo/writes by log writer are disabled (size=2048, stall size=2048, poke=100%, LGWR mode=serial)
52  kcb_tsemk_rolling_rekey: kcbtsecfdbkod is NULL or the master key is not active for pdb 1, ... Skip rolling rekey.
```
The ORA-00800 is raised when LGWR starts. After that LGWR opens its thread normally. The
TDE "rolling rekey" lines are informational: no TDE master key is configured, so the step is
skipped.

**`FREE_vktm_46.trc`**: virtual keeper of time (background), CDB$ROOT, signature ORA-00800 (lines 22–157 requested, 23 returned)
```
34  WARNING: Failed to disable OOMK
35  Incident 16061 created, dump file: .../incident/incdir_16061/FREE_vktm_46_i16061.trc
37  ORA-00800: soft external error, arguments: [Set Priority Failed], [VKTM], ...
45  kstmmainvktm(): failed in setting elevated priority
46  kstmmainvktm(): Verify: SETUID is set on ORADISM and restart the instance
47  kstmmainvktm(): highres_disabled
```
VKTM couldn't get real-time priority, so it fell back to lower-resolution timekeeping. The
ORADISM hint is the generic bare-metal advice. Here the cause is the missing `CAP_SYS_NICE`
in the container.

## Method

- MCP mode on `demo_dbmon_cdb` (CDB root, read-only `C##DBMON`). I ran 10 checks from
  `.claude/skills/db-diag-review/queries.sql`, which is 11 statements: `alert_overview`,
  `alert_errors`, `alert_lifecycle`, `adr_problems`, `adr_incidents`, `trace_inventory`,
  `trace_signatures`, `trace_excerpt` ×2 (line windows 22–157), `edition_gate` and
  `awr_snapshots`. None errored.
- Preflight: `scripts/db-preflight.sh` found the container `exited` and **started it**
  (`started_by_preflight=yes`, instance startup 14:50:19 UTC).
- Workload source: the AWR report `reports/awr/awr_8_9.txt`, analysed with `extract_report.py`.
  AWR is allowed because `edition_gate` returned `EDITION=FREE`, `is_free=Y` (the Diagnostics
  Pack is included in Free; see `LICENSING.md`). No ASH/ADDM queries and no Tuning Pack. I took
  no snapshot.
- **Choice of pair (made without asking):** the current startup has no snapshots, and snaps 10
  and 11 are singletons from separate startups on 2026-10-08. No alert-log evidence (deadlocks,
  workload) fell in any AWR window, so I used the **newest valid pair, 8–9**: same startup
  2026-10-07 11:01:02, adjacent, a full hour. It's from before the latest restarts. I didn't
  check Statspack, because the skill only falls back to it when AWR has no usable pair.
- Caveats: the 7-day alert window (from 2026-10-08 14:50 UTC) contains only today's startup.
  The 2026-10-08 sessions and the unclean stop that followed them are just outside it. The AWR
  window is an idle hour, 8 days old, so the workload ratings say little about application
  behaviour.
- Audit: MCP sessions are tagged `SQLcl-MCP` in `V$SESSION`. `DBTOOLS$MCP_LOG` isn't written for
  the read-only `dbmon` users.
