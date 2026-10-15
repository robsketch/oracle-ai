# Oracle Diagnostic Review: FREE (whole instance, CDB$ROOT + FREEPDB1)

| | |
|---|---|
| **Overall status** | **CRIT**: the worst area rating, driven by repeated unclean restarts (crash recovery twice on 2026-10-07). The cause is known and the fix was verified today |
| **Run at** | 2026-10-08 12:13 UTC (13:13 BST host time) |
| **Sources** | MCP: `demo_dbmon_cdb` (alert log, ADR incidents, traces, AWR snapshot list). AWR report file `reports/awr/awr_4_5.txt` (awr-text) |
| **Window** | alert log / traces / incidents: last 7 days (2026-10-01 to 2026-10-08 12:11 UTC). Workload: AWR snaps 4–5 (2026-10-07 07:45:52 to 09:00:46 UTC, 74.9 min) |
| **Database** | Oracle AI Database 26ai Free 23.26.3.0.0, instance `FREE` on `9c6b064276dd` (container `oracle-free`), 16 CPUs (8 cores), 7.7 GB RAM |

## Summary

No internal errors (ORA-600/7445), no memory errors (ORA-4031) and no corruption in the last 7 days. The
instance ran crash recovery at 4 of its 5 startups because `docker stop` (10 s timeout) or a WSL
shutdown killed Oracle. Two of those were on 2026-10-07, which makes the lifecycle rating CRIT
under the skill's guide. The cause is known: the 12:08 UTC restart today followed a clean `shutdown immediate`,
which shows `docker stop -t 120` works. The other findings are all known or deliberate: ORA-00800 "Set
Priority Failed" incidents at every startup (container lacks `SYS_NICE`), two demo deadlocks on
`HR.DIAG_DEMO` at 08:15 and 08:17 UTC on 2026-10-07, and a soft parse ratio of 80.6% from the demo's
literal SQL. Do this first: always stop the container with `docker stop -t 120 oracle-free`.

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Critical errors (ORA-600/7445/4031/corruption) | OK | None in alert log or trace signatures (7 days) |
| ADR incidents | WARN | 10 incidents in window, all problem 1 `ORA 800` (Set Priority Failed, VKTM/LGWR), 2 per startup. Known, kept for demo |
| Instance lifecycle (restarts, crash recovery) | CRIT | 5 startups in 3 days. Crash recovery at 4 of them, 2 on 2026-10-07 (07:35, 11:00). Latest start (2026-10-08 12:08) was clean. Cause known, kept for demo |
| Application errors (deadlocks, 1555, space) | WARN | 2x ORA-00060 in FREEPDB1 (2026-10-07 08:15, 08:17), HR sessions from SQLcl on `DIAG_DEMO`. Demo artefact |
| Redo / log writer | WARN | "online redo log writes ... taking longer than expected" x2 (2026-10-06 13:58, 2026-10-07 09:13). `log file sync` avg 1.08 ms (fine). LGWR runs at normal priority (ORA-00800) |
| Workload: CPU | OK | Host 97.9% idle. DB CPU 158 s = 93% of 170 s DB time over 75 min (AAS ~0.04). No single SQL dominates |
| Workload: parsing | WARN | Soft parse 80.57%, 6.4 hard parses/s, execute-to-parse 56%, library hit 85.8%. Literal SQL from the demo load |
| Workload: waits & locking | WARN | `enq: TX - row lock contention` 5 waits, avg 2,312 ms (6.8% DB time). Matches the deadlocks |
| Workload: I/O & efficiency | OK | Buffer hit 99.99%, 0.6 physical reads/s, `db file sequential read` avg 0.17 ms |

## Timeline

All times UTC.

```
2026-10-06 13:29:16 | alert   | Instance start (normal), then crash recovery of 1 thread (previous stop unclean)
2026-10-06 13:29:17 | ADR     | Incidents 8051 (VKTM) / 8171 (LGWR): ORA-00800 Set Priority Failed
2026-10-06 13:29:19 | AWR     | Snap 1 (startup 13:29:19)
2026-10-06 13:58    | alert   | Redo log writes taking longer than expected (FREE_lgwr_89.trc)
2026-10-06 16:00    | AWR     | Snap 3, the last snapshot before the container stopped (gap until next day)
2026-10-07 07:35:08 | alert   | Instance start, crash recovery (unclean stop overnight)
2026-10-07 07:35:10 | ADR     | Incidents 9653 / 9773: ORA-00800 VKTM / LGWR
2026-10-07 07:45:52 | AWR     | Snap 4, start of the analysed window
2026-10-07 08:15:06 | alert   | ORA-00060 deadlock, FREEPDB1, FREE_ora_3455.trc (HR, SQLcl, DIAG_DEMO)
2026-10-07 08:17:07 | alert   | ORA-00060 deadlock, FREEPDB1, FREE_ora_3613.trc (same pair of statements)
2026-10-07 09:00:46 | AWR     | Snap 5, end of the analysed window
2026-10-07 09:13    | alert   | Redo log writes taking longer than expected (FREE_lgwr_88_1.trc)
2026-10-07 11:00:58 | alert   | Instance start, crash recovery (second unclean stop that day)
2026-10-07 11:00:59 | ADR     | Incidents 11255 / 11375: ORA-00800 VKTM / LGWR
2026-10-07 13:00    | AWR     | Snap 9, the last snapshot before the container stopped
2026-10-08 11:56:43 | alert   | Instance start, crash recovery (unclean stop overnight)
2026-10-08 11:56:44 | ADR     | Incidents 12857 / 12977: ORA-00800 VKTM / LGWR
2026-10-08 12:07    | AWR     | Snap 10 (only snapshot of the 11:56 startup)
2026-10-08 12:08:20 | alert   | Shutting down instance (immediate), clean, "Instance shutdown complete" 12:08:25
2026-10-08 12:08:27 | alert   | Instance start, clean (no "Beginning crash recovery"). Not started by this review
2026-10-08 12:08:27 | ADR     | Incidents 14459 / 14579: ORA-00800 VKTM / LGWR
2026-10-08 12:11    | review  | This review run (no AWR snapshot yet for the 12:08 startup)
```

## Findings

### CRIT: Repeated unclean shutdowns causing crash recovery (known, kept for demo)
- **Evidence:** `alert_lifecycle`: "Beginning crash recovery of 1 threads" at 2026-10-06 13:29:18,
  2026-10-07 07:35:10, 2026-10-07 11:01:00 and 2026-10-08 11:56:44, each with no "Instance shutdown
  complete" before it. Two on 2026-10-07. The 2026-10-08 12:08:27 start followed "Shutting down
  ORACLE instance (immediate)" and "Instance shutdown complete" (12:08:25). It shows only the
  informational "Crash Recovery excluding pdb 2/3 which was cleanly closed" lines and no recovery of threads.
- **What it means:** When Oracle is killed instead of shut down, the next startup has to replay
  the online redo log (crash recovery) to bring datafiles back to a consistent state. Here it
  worked in about 2 seconds each time. However, every kill risks a longer restart and, on unreliable
  storage, data loss. The skill's guide rates repeated crash recovery within a day as CRIT. The
  cause is known: `docker stop` waits only 10 s before SIGKILL, and a WSL shutdown kills the
  container outright. Today's 12:08 restart shows the fix works.
- **Recommendation (not executed):** Always use `docker stop -t 120 oracle-free`. Before
  `wsl --shutdown`, or closing the laptop for a long time, stop the container that way first.
  Consider a `--stop-timeout 120` on the container when it's next recreated.

### WARN: ORA-00800 Set Priority Failed for VKTM and LGWR (known, kept for demo)
- **Evidence:** `adr_problems`: problem 1 `ORA 800`, 20 incidents since 2026-07-05, 10 in window.
  `adr_incidents`: exactly two per startup (VKTM + LGWR), status 2, not flood-controlled.
  `FREE_lgwr_86.trc` lines 34-37: "WARNING: Failed to disable OOMK", "Incident 14579 created",
  "ORA-00800: soft external error, arguments: [Set Priority Failed], [LGWR]". The alert log says
  "Failed to elevate LGWR's priority from 0 to 1, policy 5 ... ErrMsg(Operation not permitted)".
- **What it means:** Oracle tries to run its timekeeper (VKTM) and log writer (LGWR) at
  real-time scheduling priority. The container doesn't have `CAP_SYS_NICE`, so the kernel
  refuses. This isn't a crash. However, LGWR at normal priority can make commits (`log file sync`) slower under
  CPU pressure, and it also generates an ADR incident on every startup.
- **Recommendation (not executed):** Recreate the container with `--cap-add=SYS_NICE` (data is
  on the named volume `oracle-free-data`). Purge old incidents with `adrci` afterwards if wanted.

### WARN: ORA-00060 deadlocks on HR.DIAG_DEMO (demo artefact)
- **Evidence:** `alert_errors`: 2x ORA-00060 in FREEPDB1, 2026-10-07 08:15 and 08:17.
  Traces `FREE_ora_3455.trc` and `FREE_ora_3613.trc` (both FREEPDB1, user HR, program/module
  SQLcl, client `sketchPC`) show the same graph each time. Two TX locks are held in X mode crosswise:
  - session A: `update diag_demo set pad = 'A' where id = 2` (sql_id `1spp42b1cfff6`), which holds id 1
  - session B: `update diag_demo set pad = 'B' where id = 1`, which holds id 2
  AWR snaps 4-5 cover both deadlocks. They show as `enq: TX - row lock contention` (5 waits, avg 2.31 s)
  and as "Segments by Row Lock Waits" on two `** MISSING **` objects (73436, 73438) in FREEPDB1.
  "Missing" because `scripts/demo-diag-load.sh` drops `DIAG_DEMO` afterwards.
- **What it means:** Each session locked one row and then wanted the other's row. Oracle broke
  the cycle by rolling back one statement (ORA-00060). Oracle classes this as an application
  design problem, not a database fault. Here it's injected on purpose by the demo script.
- **Recommendation (not executed):** In real code, lock rows in a consistent order (e.g. always
  ascending `id`, or `SELECT ... FOR UPDATE` ordered by key) and keep transactions short.

### WARN: Low soft parse ratio, literal SQL (demo artefact)
- **Evidence:** AWR 4-5: Soft Parse 80.57%, hard parses 6.4/s (about 28,700 in 75 min), parses
  32.7/s vs executes 75/s (execute-to-parse 56.45%), library hit 85.82%, hard parse elapsed
  21.4 s = 12.6% of DB time. Captured SQL covers only 5% of DB time. That's typical when the load
  is thousands of unique, individually cheap statements that never reach the top-SQL lists.
- **What it means:** Each statement with literal values (e.g. `... where id = 42`) is a new
  cursor that Oracle must parse and optimise from scratch, burning CPU and churning the shared
  pool. At scale this leads to `latch: shared pool` / ORA-04031. Here it's just under the CRIT
  threshold (80%) and comes from the demo load's literal-SQL phase.
- **Recommendation (not executed):** Use bind variables in the application. `cursor_sharing=FORCE`
  is a stop-gap only.

### WARN: Slow online redo log writes (laptop disk)
- **Evidence:** `alert_errors`: "The system is observing online redo log writes that are taking
  longer than expected" x2, 2026-10-06 13:58 and 2026-10-07 09:13 (12 minutes after the AWR window
  ended). Inside the window `log file sync` was fine: 3,815 waits, avg 1.08 ms.
- **What it means:** LGWR write latency spiked briefly. On WSL2/Docker the redo logs sit on the
  laptop's virtual disk, shared with everything else. Not a sustained problem.
- **Recommendation (not executed):** Nothing for the PoC. On real systems put redo on dedicated
  low-latency storage, and fix ORA-00800 so LGWR gets real-time priority.

### INFO: Commit-per-row pattern (demo artefact)
- **Evidence:** AWR 4-5: 5.3 transactions/s (about 24,000 in the window), 1.2 user calls per
  transaction, `log file sync` 3,815 waits.
- **What it means:** The demo's commit-storm phase commits row by row. Each commit waits for a redo
  write, which is cheap here (1 ms) but adds up at volume.
- **Recommendation (not executed):** Batch commits in real applications.

### INFO: ARCHIVELOG with no FRA (known, kept for demo)
- **Evidence:** Not visible in this review's sources (no archiver errors). It comes from the
  project notes and the `/db-health-check` finding: archives go to `$ORACLE_HOME/dbs/arch` in the
  container layer.
- **What it means:** Archived redo isn't on the persistent volume and has no space management.
  If that filesystem fills, the archiver stops and the DB hangs (ORA-00257).
- **Recommendation (not executed):** Set `db_recovery_file_dest` / `_size` on the data volume.

## Workload profile (AWR snaps 4–5)

- **Window:** 2026-10-07 07:45:52 to 09:00:46 UTC (74.9 min), same startup (07:35), so the deltas are valid.
- **DB time** 169.8 s, **DB CPU** 158.1 s, background CPU 53.8 s, **AAS** ≈ 0.04. Host: 16 CPUs, 97.9% idle,
  instance used 0.3% of total CPU.

| Event | Waits | Time (s) | Avg | % DB time |
|---|---|---|---|---|
| DB CPU | | 158.1 | | 93.1 |
| enq: TX - row lock contention | 5 | 11.6 | 2,311.99 ms | 6.8 |
| log file sync | 3,815 | 4.1 | 1.08 ms | 2.4 |
| direct path sync | 3 | 0.3 | 92.88 ms | 0.2 |
| db file sequential read | 658 | 0.1 | 0.17 ms | 0.1 |

**Load profile (per s / per txn):** redo 15.4 KB / 2.9 KB, logical reads 4,383 / 835, physical
reads 0.6 / 0.1, user calls 6.3 / 1.2, parses 32.7 / 6.2, hard parses 6.4 / 1.2, executes 75.0 / 14.3,
transactions 5.3/s.

**Efficiency:** buffer hit 99.99%, soft parse 80.57%, execute-to-parse 56.45%, library hit
85.82%, in-memory sort 100%, latch hit 99.99%.

**Top SQL:** all of it is Oracle's own maintenance (noise). `fhf8upax5cxsz`
`dbms_auto_report_internal.i_save_report` (6.1 s, 15 execs, CDB$ROOT), `DBMS_REPORT`
summaries, `prvt_hdm` (ADDM auto-run), `wrh$_*` inserts from the AWR snapshot, and dictionary
recursive SQL (`hist_head$`, `obj$`, `sensitive_fixed$`). The demo's user SQL (literal inserts,
DIAG_DEMO updates, the Cartesian join on `employees`) doesn't appear individually. It shows only
in the load profile and parse statistics.

**Where did the time go?** The instance was nearly idle: 170 s of DB time in 75 minutes. 93% of
it was CPU, mostly spent hard-parsing thousands of literal statements (12.6% of DB time is hard
parse alone) and executing many small uncaptured statements. The only notable wait was about 12 s
of row-lock waiting from the two deliberate deadlocks. Each waited a little over 2 s on average
before Oracle's deadlock detection broke the cycle. Commits were frequent but fast. I/O was negligible.

## Trace excerpts

**`FREE_ora_3613.trc`** (user session `ora`, FREEPDB1, ORA-00060 deadlock, lines 24-159). `FREE_ora_3455.trc`
(08:15) is identical apart from session ids.
```
*** 2026-10-07T08:17:07.703222+00:00 (FREEPDB1(3))
*** MODULE NAME:(SQLcl)
DEADLOCK DETECTED ( ORA-00060 )
Resource Name                             process session holds waits serial  process session holds waits serial
TX-00050020-000002BD-CE1992F3-00000000         72      22     X         2824      84      58           X  39177
TX-0008001E-000002A7-CE1992F3-00000000         84      58     X        39177      72      22           X   2824
  sid: 22 ser: 2824 audsid: 190001 user: 136/HR   pdb: 3/FREEPDB1   program: SQLcl
  current SQL: update diag_demo set pad = 'A' where id = 2
  sid: 58 ser: 39177 audsid: 190002 user: 136/HR  pdb: 3/FREEPDB1   program: SQLcl
  current SQL: update diag_demo set pad = 'B' where id = 1
----- Current SQL Statement for this session (sql_id=1spp42b1cfff6) -----
```
Interpretation: this is a classic two-row TX deadlock. Each session holds one row in X mode and waits for the
other's row. Session 22 (the trace owner) received ORA-00060 and its statement was rolled back.

**`FREE_lgwr_86.trc`** (background `lgwr`, CDB$ROOT, ORA-00800, lines 22-157; 28 lines returned)
```
*** 2026-10-08T12:08:27.880723+00:00 (CDB$ROOT(1))
WARNING: Failed to disable OOMK
Incident 14579 created, dump file: /opt/oracle/diag/rdbms/free/FREE/incident/incdir_14579/FREE_lgwr_86_i14579.trc
ORA-00800: soft external error, arguments: [Set Priority Failed], [LGWR], [Check traces and OS configuration], [Check Oracle document and MOS notes], []
Overlapped redo/writes by log writer are disabled (size=2048, stall size=2048, poke=100%, LGWR mode=serial)
```
Interpretation: the OS refused both the real-time priority change and the OOM-killer opt-out
(no `CAP_SYS_NICE` and related capabilities in the container). LGWR carries on at normal priority.
The VKTM traces carry the same signature and weren't excerpted separately.

## Method

- MCP mode: read-only queries from `.claude/skills/db-diag-review/queries.sql` via SQLcl MCP
  `sql_run` on `demo_dbmon_cdb`. 13 statements: alert_overview, alert_errors, alert_lifecycle,
  adr_problems, adr_incidents, trace_inventory, trace_signatures, 3x trace_excerpt (bounded
  line windows), edition_gate, awr_snapshots. No check errored.
- Preflight: container was already running and healthy. **This review did not start the
  database.** The 12:08:27 UTC startup came from someone else's clean restart before this run.
- **Edition gate:** `V$INSTANCE.EDITION = FREE`, banner "Oracle AI Database 26ai Free Release
  23.26.3.0.0", so `is_free = Y`. AWR is allowed because the Diagnostics Pack is included in Free
  (see `LICENSING.md`). No ASH/ADDM queries, no Tuning Pack. No AWR snapshot was taken.
- **AWR pair choice (my decision):** The current startup (12:08 UTC) has 0 snapshots, so no valid pair
  yet. The newest valid pair is 8–9 (2026-10-07 12:00–13:00, startup 11:01). I chose **4–5**
  (2026-10-07 07:45:52 to 09:00:46, both startup 07:35:11) because it covers both deadlocks and
  the demo workload, and that evidence is what makes the window useful. It's from before the
  latest two restarts. Report generated with `scripts/awr-report.sh 4 5`, then
  `reports/awr/awr_4_5.txt` analysed with `extract_report.py` (awr-text, 22 sections).
- Statspack (`demo_dbmon`) wasn't used, because AWR was available and covered the evidence.
- Caveats: the AWR window is 75 minutes on a mostly idle box, so the ratios are dominated by the
  demo load bursts. AWR covers the whole instance (CDB$ROOT + PDBs). The extractor found no
  "Top Timed Events" heading (26ai uses "Top 10 Foreground Events"). The lifecycle CRIT follows the
  skill guide literally (repeated crash recovery within a day). With the cause known and the fix
  verified, a DBA may reasonably treat it as WARN for this demo box.
- Times: the DB logs in UTC. The host clock is BST (UTC+1).
- Audit: sessions are tagged `SQLcl-MCP` in `V$SESSION`. `DBTOOLS$MCP_LOG` isn't written for the
  read-only `dbmon` users.
