# Oracle Diagnostic Review: FREE (whole instance, CDB$ROOT + FREEPDB1), 2026-10-16 09:30 → 12:30 UTC (10:30 → 13:30 BST)

| | |
|---|---|
| **Overall status** | 🟢 OK |
| **Run at** | 2026-10-20 09:38 UTC (10:38 BST, UK local) |
| **Sources** | MCP: `demo_dbmon_cdb` (alert log, traces, ADR incidents, AWR on Free). Statspack (`demo_dbmon`) not needed because AWR fully covers the window |
| **Window** | requested: 2026-10-16 09:30 → 12:30 UTC (10:30 → 13:30 BST) · alert log / incidents / traces: that window · workload: AWR snaps 4–8 (2026-10-16 09:00:42 → 13:00:50 UTC, 240.1 min; **FULL** cover) |
| **Database** | Oracle AI Database 26ai Free 23.26.3.0.0, instance `FREE` on `dd934a827d71` (container `oracle-free`), 14 CPUs / 7 cores, 15.4 GB RAM |

## Summary

Nothing went wrong in the requested window. The instance had been up since 2026-10-15 20:02 UTC and ran
through the whole window with no restarts. There were no errors, no ADR incidents and no serious trace
signatures, and the alert log has only two routine lines. AWR shows a nearly idle database: 1.7 minutes
of DB time in 4 hours (0.007 average active sessions), host CPU 98.8% idle, and all the top SQL is
Oracle's own maintenance jobs. The demo workload (`demo-diag-load.sh`) did not run in this window. No
action needed. The standing known-for-demo items (ORA-00800, crash recovery, ARCHIVELOG without an FRA)
don't show up in this window.

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Critical errors (ORA-600/7445/4031/corruption) | 🟢 OK | `alert_errors`: 0 rows. `trace_signatures`: 0 rows |
| ADR incidents | 🟢 OK | `adr_incidents`: 0 in window. Only ADR problem is `ORA 800` (16 incidents total, 0 in window) |
| Instance lifecycle (restarts, crash recovery) | 🟢 OK | `alert_lifecycle`: no events in window. One startup (2026-10-15 20:02:50) covers all of it |
| Application errors (deadlocks, 1555, space) | 🟢 OK | No ORA-00060/01555/165x in the alert log or traces. AWR "Segments by Row Lock Waits": no data |
| Redo / log writer | 🟢 OK | `log file sync` 755 waits, avg 0.89 ms. No checkpoint or log-allocation messages. Redo NoWait 100% |
| Workload: CPU | 🟢 OK | Host 98.8% idle. Instance uses 0.2% of total CPU. DB CPU 98.9 s in 240 min |
| Workload: parsing | 🟢 OK | Soft parse 96.71%. Hard parses 0.4/s |
| Workload: waits & locking | 🟢 OK | DB CPU 96.2% of DB time. Top wait `log file sync` 0.7%. `enq: TX - contention` 7 waits, 1.1 ms avg |
| Workload: I/O & efficiency | 🟢 OK | Buffer hit 99.89%. 0.1 physical reads/s. Avg read 0.1–0.4 ms |

## Timeline

All times UTC.

```
2026-10-15 20:02:50 | AWR/alert | Instance startup that covers the whole window (outside the window; not reviewed here)
2026-10-15 21:00    | AWR       | snap 3 begins. Next snap is 08:05 on the 16th, an 11 h interval with no hourly snapshots (host probably asleep; outside window)
2026-10-16 09:00:42 | AWR       | snap 4 (begin of pair used)
2026-10-16 09:30    | review    | requested window starts
2026-10-16 09:30–12:30 | alert  | 2 lines in total (1 CDB$ROOT, 1 FREEPDB1), neither is an error, warning or lifecycle event
2026-10-16 10:00, 11:00, 12:00 | AWR | automatic hourly snaps 5, 6, 7
2026-10-16 12:30    | review    | requested window ends
2026-10-16 13:00:50 | AWR       | snap 8 (end of pair used)
2026-10-19 13:58:10 | AWR       | next instance startup (outside window)
2026-10-20 09:24:27 | preflight | current instance startup (not started by this review; container already running)
```

## Findings

### 🔵 INFO: The window was idle, with only Oracle housekeeping running
- **Evidence:** AWR 4–8: DB time 102.8 s over 240.13 min, 0.0 DB time/s. Transactions near 0 per
  second. Top SQL by elapsed time: `b39m8n96gxk7c` `dbms_autotask_prvt.run_autotask` (5.5 s, 48 execs),
  `ampw9ddqufjd3` `dbms_auto_index_internal.capture_sts` (5.2 s), `a95n8p4vpxmps`
  `prvt_hdm.execute_slave_actions` (4.3 s, ADDM auto-run), `2pkpuk0vd342z` `insert into wrh$_mvparameter`
  (AWR snapshot itself). No HR / `DIAG_DEMO` / `employees` statements.
- **What it means:** Nothing ran in the window except Oracle's scheduled maintenance: automatic tasks,
  auto-indexing capture into a SQL tuning set, ADDM after each snapshot, and the AWR snapshots. These are
  background jobs Oracle runs by itself. The demo load script didn't run here, so none of the usual demo
  artefacts (deadlocks, literal SQL, commit storms, Cartesian join) appear.
- **Recommendation (not executed):** None. To review demo-load behaviour, rerun the review for the window
  in which `scripts/demo-diag-load.sh` ran.

### 🔵 INFO: Low execute-to-parse ratio (34%) and library hit (93.8%), both caused by internal SQL
- **Evidence:** Execute to Parse 34.13%, Library Hit 93.84%, Soft Parse 96.71%. The top parse-call SQL is
  `7qb74y7hp6cwd` (autotask scheduler select, 30,000 parses for 30,000 execs, 17.5% of all parses), then
  `sensitive_fixed$` and `obj$` dictionary lookups.
- **What it means:** "Execute to parse" counts how often a statement is run without re-parsing it. A low
  value usually means the app re-parses its SQL every time. Here the re-parsing comes from Oracle's own
  recursive SQL on an idle box, where a few cache misses weigh heavily. It isn't an application problem.
- **Recommendation (not executed):** None. Check again under real application load.

### 🔵 INFO: Standing known issues are outside this window (known, kept for demo)
- **Evidence:** ADR problem 1 `ORA 800`: 16 incidents from 2026-07-05 21:57 to 2026-10-20 09:24, **0 in
  window**. No crash recovery or startup lines in the window.
- **What it means:** ORA-00800 [Set Priority Failed] for VKTM/LGWR (container lacks `CAP_SYS_NICE`)
  appears at every startup, and so does crash recovery after an unclean `docker stop`. No startup fell in
  this window, so neither appears here. ARCHIVELOG with no FRA is a configuration fact and produced no
  messages in the window.
- **Recommendation (not executed):** Unchanged from earlier reviews: `--cap-add=SYS_NICE` when the
  container is recreated, `docker stop -t 120 oracle-free`, and configure `db_recovery_file_dest` on the
  data volume.

### 🔵 INFO: AWR gap before the window (outside scope)
- **Evidence:** `awr_snapshots`: snap 3 runs from 2026-10-15 21:00 to 2026-10-16 08:05 with the same
  `startup_time`, an 11-hour interval instead of hourly.
- **What it means:** Most likely the WSL VM or laptop was suspended overnight, so MMON (the process that
  takes AWR snapshots) missed the hourly ticks. It doesn't affect this window, which has hourly snapshots
  throughout.
- **Recommendation (not executed):** None. If overnight trends matter, keep the host awake.

## Workload profile (AWR)

- **Header:** snaps 4–8, 2026-10-16 09:00:42 → 13:00:50 UTC (240.13 min). DB time 102.8 s, DB CPU 98.9 s,
  average active sessions ≈ 0.007. Background CPU 336.5 s (77% of total CPU). Sessions 89 → 85.
- **Top foreground events:**

| Event | Waits | Time (s) | Avg | % DB time |
|---|---|---|---|---|
| DB CPU | | 98.9 | | 96.2 |
| log file sync | 755 | 0.7 | 0.89 ms | 0.7 |
| direct path write | 188 | 0.2 | 1.13 ms | 0.2 |
| Allocate UGA memory from OS | 8,476 | 0.1 | 11.6 µs | 0.1 |
| Disk file operations I/O | 1,021 | 0.1 | 84 µs | 0.1 |
| latch: shared pool | 121 | 0.1 | 0.67 ms | 0.1 |

- **Load profile (per second):** redo 4.7 KB, logical reads 80.1, physical reads 0.1, user calls 0.6,
  parses 11.9, hard parses 0.4, executes 18.1, logons 0.1.
- **Efficiency:** buffer hit 99.89%, soft parse 96.71%, library hit 93.84%, execute to parse 34.13%,
  latch hit 99.95%, in-memory sort 100%.
- **Host:** load 0.06 → 0.32, %user 0.6, %sys 0.4, %iowait 0.0, %idle 98.8.
- **Top SQL:** only Oracle maintenance (autotask, auto-index STS capture, ADDM `prvt_hdm`, AWR `wrh$_*`
  inserts, dictionary lookups), listed as noise per the skill. No application SQL appears.
- **Where did the time go?** Nearly nowhere. Of 4 hours of wall clock, foreground sessions used under 2
  minutes, almost all on CPU in scheduler maintenance jobs in FREEPDB1 and ADDM/AWR in the root. Wait
  time is negligible and I/O latency is sub-millisecond.

## Trace excerpts

None. `trace_signatures` found no ORA-600/7445/4031, corruption, deadlock, ORA-00800, ORA-01555 or
space-error lines time-stamped inside the window, so no `trace_excerpt` was run. `trace_inventory` lists
files modified since 09:30 on the 16th, mostly from the later startups (19th and 20th). Only the `q` and
`cjq` files (last modified 2026-10-16 13:57) are from this instance's lifetime, and they had no
signatures in the window.

## Method

- MCP mode: 10 read-only queries from `.claude/skills/db-diag-review/queries.sql` via SQLcl MCP `sql_run`
  on `demo_dbmon_cdb`: `alert_overview`, `alert_errors`, `alert_lifecycle`, `adr_problems`,
  `adr_incidents`, `trace_inventory`, `trace_signatures`, `edition_gate`, `awr_snapshots`,
  `awr_window_pairs`. Window placeholders were `timestamp '2026-10-16 09:30:00 +00:00'` →
  `timestamp '2026-10-16 12:30:00 +00:00'`.
- Preflight: container already running and healthy. Instance started 2026-10-20 09:24:27 UTC, before
  this review, so the review did **not** start the DB. `awr_snaps_since_startup=1`, which doesn't matter
  because the requested window belongs to the 2026-10-15 20:02 startup.
- Workload source: AWR report `reports/awr/awr_4_8.txt` (generated with `scripts/awr-report.sh 4 8`,
  then `extract_report.py`). AWR is allowed because `edition_gate` returned `FREE` / `is_free = Y`, and
  Oracle Database Free includes the Diagnostics Pack (see `LICENSING.md`). `awr_window_pairs` returned
  one row (snaps 4–8, FULL), so only one report was needed. No ASH/ADDM queries and no Tuning Pack. No
  AWR snapshot was taken.
- Choices made without asking: Statspack was skipped because AWR fully covers the window. AWR snaps
  round out to whole hours, so the workload figures cover 09:00–13:00, 30 minutes either side of the
  requested window.
- Caveats: the query set doesn't print the raw text of the 2 alert lines in the window. They failed every
  error, warning and lifecycle filter, so they are routine. The AWR window is 4 hours of hourly data,
  which is a trend, but an idle one.
- Audit: MCP sessions are tagged `SQLcl-MCP` in `V$SESSION`. `DBTOOLS$MCP_LOG` isn't written for the
  read-only `dbmon` users.
