# Oracle Diagnostic Review: FREE (whole instance, CDB$ROOT + FREEPDB1)

| | |
|---|---|
| **Overall status** | 🟡 WARN (worst area rating; no CRIT) |
| **Run at** | 2026-10-08 12:47 UTC (13:47 BST host time) |
| **Sources** | MCP: `demo_dbmon_cdb` (alert log, ADR incidents, traces, AWR snapshot list). AWR reports: `reports/awr/awr_4_5.txt` (primary, existing) and `reports/awr/awr_8_9.txt` (generated this run). Statspack not used |
| **Window** | alert log / traces: last 7 days · workload: AWR snaps 4–5 (2026-10-07 07:45:52 → 09:00:46 UTC, 74.9 min); comparison: snaps 8–9 (2026-10-07 12:00:07 → 13:00:30 UTC, 60.4 min) |
| **Database** | Oracle AI Database 26ai Free 23.26.3.0.0, instance `FREE` on `9c6b064276dd` (container `oracle-free`), 16 CPUs / 8 cores, 7.73 GB |

## Summary

Nothing is broken. There are no ORA-600, ORA-7445, ORA-4031 or corruption errors. All the
warnings have a known cause, and most are deliberate demo artefacts or known container
settings. The issues: every startup except the latest one needed crash recovery, because
`docker stop` killed Oracle (4 in 7 days, 2 of them on 2026-10-07). Each startup also logs
ORA-00800 "Set Priority Failed" for VKTM/LGWR (10 ADR incidents). The demo workload in the
AWR 4–5 window produced two ORA-00060 deadlocks on `HR.DIAG_DEMO`, 5 `enq: TX - row lock
contention` waits (avg 2.3 s) and a soft parse ratio of 80.6% from literal SQL. First action:
stop the container with `docker stop -t 120 oracle-free`. The 12:08 UTC restart today shows
this works.

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Critical errors (ORA-600/7445/4031/corruption) | 🟢 OK | None in alert log or trace signatures (7 days) |
| ADR incidents | 🟡 WARN | 10 incidents, all ORA-00800 [Set Priority Failed] VKTM/LGWR, 2 per startup. Known-benign, kept for demo |
| Instance lifecycle (restarts, crash recovery) | 🟡 WARN | Crash recovery at 4 of 5 startups (10-06 13:29, 10-07 07:35 and 11:00, 10-08 11:56). 10-08 12:08 startup was clean after `shutdown immediate`. Cause known, kept for demo |
| Application errors (deadlocks, 1555, space) | 🟡 WARN | 2× ORA-00060 in FREEPDB1, 2026-10-07 08:15 and 08:17 UTC (demo `HR.DIAG_DEMO`) |
| Redo / log writer | 🟡 WARN | 2× "online redo log writes ... taking longer than expected" (10-06 13:58, 10-07 09:13). `log file sync` avg 1.08 ms (fine) |
| Workload: CPU | 🟢 OK | Host 97.9% idle. DB CPU 158 s = 93% of DB time, but no single SQL dominates (top SQL 3.6%) |
| Workload: parsing | 🟡 WARN | Soft parse 80.57% (just above the CRIT line of 80%), 6.4 hard parses/s, hard parse = 12.6% of DB time |
| Workload: waits & locking | 🟡 WARN | `enq: TX - row lock contention` 5 waits, avg 2,312 ms, 6.8% of DB time |
| Workload: I/O & efficiency | 🟢 OK | Buffer hit 99.99%, 0.6 physical reads/s, `db file sequential read` avg 0.17 ms |

## Timeline (UTC)

| Time | Source | Event |
|---|---|---|
| 2026-10-06 13:29:16 | alert | Instance start, **crash recovery** (unclean previous stop). ORA-00800 VKTM/LGWR (incidents 8051, 8171) |
| 2026-10-06 13:58 | alert | Redo log writes taking longer than expected |
| 2026-10-07 07:35:08 | alert | Instance start, **crash recovery**. ORA-00800 VKTM/LGWR (9653, 9773) |
| 2026-10-07 07:45:52 | AWR | Snap 4: **start of analysed window** |
| 2026-10-07 08:15:06 | alert/trace | ORA-00060 deadlock, FREEPDB1, HR via SQLcl (`FREE_ora_3455.trc`) |
| 2026-10-07 08:17:07 | alert/trace | ORA-00060 deadlock, FREEPDB1, HR via SQLcl (`FREE_ora_3613.trc`) |
| 2026-10-07 09:00:46 | AWR | Snap 5: **end of analysed window** |
| 2026-10-07 09:13 | alert | Redo log writes taking longer than expected |
| 2026-10-07 11:00:58 | alert | Instance start, **crash recovery** (2nd that day). ORA-00800 (11255, 11375) |
| 2026-10-07 12:00–13:00 | AWR | Snaps 8–9, newest valid pair: idle hour (DB time 11 s) |
| 2026-10-08 11:56:43 | alert | Instance start, **crash recovery**. ORA-00800 (12857, 12977) |
| 2026-10-08 12:07 | AWR | Snap 10. It is the only snapshot of that startup, so it has no pair |
| 2026-10-08 12:08:20–25 | alert | `shutdown immediate`, "Instance shutdown complete" (clean stop) |
| 2026-10-08 12:08:27 | alert | Instance start, **no crash recovery** (clean). ORA-00800 (14459, 14579). Not started by awr-analyst (already running) |
| 2026-10-08 12:46 | preflight | Review run. 0 AWR snapshots since the 12:08 startup |

## Findings

### 🟡 Crash recovery at startup after unclean stops (known, kept for demo)
- **Evidence:** `alert_lifecycle`: "Beginning crash recovery of 1 threads" at 2026-10-06 13:29,
  2026-10-07 07:35 and 11:00, and 2026-10-08 11:56. None of these follows an "Instance shutdown
  complete". The 2026-10-08 12:08:27 startup follows "Instance shutdown complete" (12:08:25)
  and only logs "Crash Recovery excluding pdb N which was cleanly closed", with no recovery of
  threads. That startup was clean.
- **What it means:** Oracle was killed rather than shut down. The cause is known: the default
  10 s timeout of `docker stop`, or a WSL shutdown. At startup it replayed the redo log to
  make the datafiles consistent. Recovery took about 2 s each time, but every kill is a
  risk. Two crash recoveries on 2026-10-07 would be CRIT on a strict reading of the rating
  guide. I rated the area WARN because the cause is known and the fix was verified at
  2026-10-08 12:08.
- **Recommendation (not executed):** always stop with `docker stop -t 120 oracle-free`. Before
  `wsl --shutdown`, stop the container first.

### 🟡 ORA-00800 Set Priority Failed for VKTM and LGWR (known, kept for demo)
- **Evidence:** `adr_incidents`: 10 incidents in 7 days (problem 1 "ORA 800", 20 incidents since
  2026-07-05), 2 per startup. Alert: "Failed to elevate LGWR's priority from 0 to 1 ...
  ErrMsg(Operation not permitted)". `FREE_lgwr_86.trc` line 37.
- **What it means:** Oracle asks the OS for real-time scheduling priority for its timekeeper
  (VKTM) and log writer (LGWR). The container lacks `CAP_SYS_NICE`, so the OS refuses. This
  is not a crash. Under heavy commit load, LGWR at normal priority can make commits slower.
- **Recommendation (not executed):** recreate the container with `--cap-add=SYS_NICE`.

### 🟡 ORA-00060 deadlocks on HR.DIAG_DEMO (demo artefact)
- **Evidence:** alert 2026-10-07 08:15 and 08:17 UTC (FREEPDB1). Traces `FREE_ora_3455.trc` and
  `FREE_ora_3613.trc` each show two HR sessions from SQLcl (machine sketchPC) in a TX X/X cycle:
  `update diag_demo set pad = 'A' where id = 2` (sql_id 1spp42b1cfff6) vs
  `update diag_demo set pad = 'B' where id = 1`. Both deadlocks fall in AWR 4–5, which shows
  `enq: TX - row lock contention` 5 waits / 11.6 s, avg 2.31 s. "Segments by Row Lock Waits"
  lists `** MISSING **` objects 73436/73438 in FREEPDB1 USERS (2 waits each). That is the
  dropped `DIAG_DEMO` table.
- **What it means:** each session locked one row and then wanted the other session's row.
  Oracle detected the cycle and rolled back one statement. Oracle treats this as an
  application design problem. Here it is caused on purpose by `scripts/demo-diag-load.sh`.
- **Recommendation (not executed):** in real code, update rows in a consistent order (for
  example `ORDER BY id`) or commit sooner.

### 🟡 Hard parsing from literal SQL (demo artefact)
- **Evidence:** AWR 4–5: Soft Parse 80.57%, Library Hit 85.82%, Execute to Parse 56.45%,
  hard parses 6.4/s (1.2 per transaction). Hard parse elapsed time 21.4 s = 12.6% of DB time.
  Captured SQL covers only 5.0% of DB time, which is typical when thousands of unique literal
  statements each fall below AWR's capture threshold.
- **What it means:** each SQL statement with literal values in place of bind variables is
  compiled from scratch, which costs CPU and churns the shared pool. On this demo the cause
  is the literal-SQL step in `demo-diag-load.sh`. The idle comparison window (8–9) has 96.8%
  soft parse.
- **Recommendation (not executed):** use bind variables. `cursor_sharing=FORCE` is a stop-gap only.

### 🟡 Slow online redo log writes (2 occurrences)
- **Evidence:** alert "The system is observing online redo log writes that are taking longer than
  expected" at 2026-10-06 13:58 and 2026-10-07 09:13 UTC (13 min after the 4–5 window).
  AWR 4–5 `log file sync` avg 1.08 ms. AWR 8–9 avg 2.72 ms.
- **What it means:** LGWR write latency spiked briefly. Here that means WSL2/Docker on a laptop
  disk. The average commit latency is healthy.
- **Recommendation (not executed):** no action for the demo. On a real system, check
  redo-log storage latency.

### 🔵 Row-by-row commits (demo artefact)
- **Evidence:** AWR 4–5: 3,815 `log file sync` waits, 5.3 transactions/s, about 2.9 KB redo per
  transaction.
- **What it means:** each commit waits for a redo write. Batching commits would cut this.
  The impact is small here (2.4% of DB time).
- **Recommendation (not executed):** commit per batch, not per row.

### 🔵 Other notes
- `FREE_lgwr_86.trc`: "WARNING: Failed to disable OOMK". LGWR couldn't exempt itself from the
  Linux OOM killer, which is also a container privilege limit. This is general guidance and
  wasn't checked against this system. The impact is low unless the host runs short of memory.
- ARCHIVELOG with no FRA (archives in the container layer) is a known finding kept for the demo.
  It was not re-checked in this review, which only uses base `V$DIAG_*` checks.

## Workload profile (AWR 4–5)

- **Window:** 2026-10-07 07:45:52 → 09:00:46 UTC (74.9 min). DB time 169.8 s, DB CPU 158.1 s,
  average active sessions about 0.04. Host 16 CPUs, 97.9% idle.

| Event | Waits | Time (s) | Avg | % DB time |
|---|---|---|---|---|
| DB CPU | | 158.1 | | 93.1 |
| enq: TX - row lock contention | 5 | 11.6 | 2,311.99 ms | 6.8 |
| log file sync | 3,815 | 4.1 | 1.08 ms | 2.4 |
| direct path sync | 3 | 0.3 | 92.88 ms | 0.2 |
| db file sequential read | 658 | 0.1 | 0.17 ms | 0.1 |

- **Load profile:** 75 executes/s, 32.7 parses/s, 6.4 hard parses/s, 5.3 transactions/s,
  4,383 logical reads/s, 0.6 physical reads/s, 15.4 KB redo/s.
- **Efficiency:** buffer hit 99.99%, soft parse 80.57%, library hit 85.82%, execute-to-parse
  56.45%, in-memory sort 100%.
- **Top SQL:** only Oracle's own maintenance (`dbms_auto_report_internal.i_save_report` 6.1 s,
  `DBMS_REPORT`, `prvt_hdm`, `wrh$_*` inserts, dictionary queries). This is noise. The demo's
  user SQL was too cheap per statement to be captured.
- **Where did the time go?** Mostly CPU spent on the demo workload's many small statements,
  about 1/8 of it on hard parsing. Then about 12 s of sessions blocked on each other's row
  locks, which is the two deadlocks, and a small commit overhead. I/O is negligible.

**Comparison: AWR 8–9 (newest valid pair, 2026-10-07 12:00–13:00 UTC).** This hour was idle.
DB time was 11.3 s, DB CPU 97% of that, soft parse 96.8%, buffer hit 99.64% and host 99.6%
idle. The only activity was autotask and AWR housekeeping. There were no findings.

## Trace excerpts

**`FREE_ora_3455.trc`**: user session (ora), FREEPDB1, ORA-00060 deadlock, 2026-10-07 08:15:06 UTC
```
DEADLOCK DETECTED ( ORA-00060 )
Resource Name                             process session holds waits serial  process session holds waits serial
TX-00040021-00000275-CE1992F3-00000000         31     213     X        58643      86      46           X   2114
TX-00060021-00000296-CE1992F3-00000000         86      46     X         2114      31     213           X  58643
Session 213: user: 136/HR  pdb: 3/FREEPDB1  program: SQLcl
  current SQL: update diag_demo set pad = 'A' where id = 2
Session 46:  user: 136/HR  pdb: 3/FREEPDB1  program: SQLcl
  current SQL: update diag_demo set pad = 'B' where id = 1
```
This is a classic two-row lock-order deadlock. Session 213's statement (sql_id 1spp42b1cfff6)
was rolled back.

**`FREE_ora_3613.trc`**: user session, FREEPDB1, ORA-00060 deadlock, 2026-10-07 08:17:07 UTC.
It has the same two statements and pattern (sessions 22 and 58) and is a second run of the
demo.

**`FREE_lgwr_86.trc`**: LGWR background process, CDB$ROOT, ORA-00800, 2026-10-08 12:08:27 UTC
```
WARNING: Failed to disable OOMK
Incident 14579 created, dump file: .../incdir_14579/FREE_lgwr_86_i14579.trc
ORA-00800: soft external error, arguments: [Set Priority Failed], [LGWR], [Check traces and OS configuration], ...
Overlapped redo/writes by log writer are disabled (... LGWR mode=serial)
```
Container privilege limits (no SYS_NICE). Not a failure.

## Method

- MCP mode: read-only queries from `.claude/skills/db-diag-review/queries.sql` via SQLcl MCP
  `sql_run` on `demo_dbmon_cdb` (10 checks: alert_overview, alert_errors, alert_lifecycle,
  adr_problems, adr_incidents, trace_inventory, trace_signatures, edition_gate, awr_snapshots,
  plus 3 bounded `trace_excerpt` reads of lines 22–159). Preflight: container already running
  and healthy (`started_by_preflight=no`).
- Workload source: AWR, allowed because `edition_gate` returned `FREE` / `is_free = Y`, and Free
  includes the Diagnostics Pack (see `LICENSING.md`). No ASH, ADDM or Tuning Pack. No snapshot
  was taken.
- **AWR pair choice (made without asking the user):** the latest two snapshots (9 and 10) span
  restarts (startup 11:01 on 10-07 vs 11:56 on 10-08), so their deltas are invalid. Snapshot 10
  is the only one from the 11:56 startup. The current 12:08 startup has none yet, because the
  first automatic snapshot comes about 10 minutes after startup and then hourly. The newest
  *valid* pair is **8–9**, which no existing report covered, so I generated
  `reports/awr/awr_8_9.txt` with `scripts/awr-report.sh 8 9`. It is an idle hour. The newest
  existing file, `reports/awr/awr_4_5.txt` (written 2026-10-08 12:12 UTC, after snap 10), covers
  the window with the deadlocks and the demo workload. I used it as the **primary** workload
  evidence and kept 8–9 as a comparison.
- Caveats: all windows are from before the latest restart (2026-10-08 12:08 UTC). AWR covers
  the whole instance (CDB$ROOT and FREEPDB1). The lifecycle rating is WARN rather than a strict
  CRIT for the two crash recoveries on 10-07, because the cause is known and the fix has been
  verified. Statspack was not used. FRA/ARCHIVELOG was not re-checked.
- Audit: MCP sessions show as `SQLcl-MCP` in `V$SESSION`. `DBTOOLS$MCP_LOG` isn't written for the
  read-only `dbmon` users.
