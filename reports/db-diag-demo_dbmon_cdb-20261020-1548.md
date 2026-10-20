# Oracle Diagnostic Review: FREE (CDB, whole instance), window 2026-10-20 13:48 → 14:48 UTC (14:48 → 15:48 BST)

| | |
|---|---|
| **Overall status** | 🟢 OK. Nothing went wrong in the window, but AWR only covers its first 12 minutes (see Window) |
| **Run at** | 2026-10-20 14:48 UTC (15:48 BST, UK local) |
| **Sources** | MCP: `demo_dbmon_cdb` (alert log, traces, ADR incidents, AWR on Free). Statspack (`demo_dbmon`) not used because AWR was available |
| **Window** | requested: 2026-10-20 13:48 → 14:48 UTC (14:48 → 15:48 BST) · alert log / incidents / traces: that exact window · workload: AWR snaps 17–18 (13:00:38 → 14:00:40 UTC, 60 min; **PARTIAL** cover: overlaps only 13:48–14:00, 12 of the 60 requested minutes). 14:00–14:48 UTC has no AWR coverage yet because the next automatic snapshot is due at 15:00 UTC |
| **Database** | Oracle AI Database 26ai Free 23.26.3.0.0, instance `FREE` on `dd934a827d71` (container `oracle-free`), 14 CPUs / 7 cores, 15.4 GB RAM. Instance up since 2026-10-20 09:24:27 UTC |

## Summary

The database was healthy and essentially idle during the requested hour. The alert log has a
single routine line for the hour, with no errors, warnings, startups or shutdowns. No ADR
incidents were raised, and no trace file contains a serious signature (internal errors,
deadlocks, corruption or space errors). The AWR hour that overlaps the window (13:00–14:00 UTC)
shows 22.5 s of DB time across 60 minutes, a host 99% idle, a 97% soft parse ratio and a 99.75%
buffer hit ratio. Almost all of the work came from Oracle's own maintenance jobs. Nothing needs
action. If the last 48 minutes of the window matter, re-run the review after the 15:00 UTC
snapshot (16:00 BST).

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Critical errors (ORA-600/7445/4031/corruption) | 🟢 OK | `alert_errors`: 0 rows. `trace_signatures`: 0 rows |
| ADR incidents | 🟢 OK | `adr_incidents`: none in window. The only ADR problem (ORA 800) last fired at 09:24 UTC, before the window |
| Instance lifecycle (restarts, crash recovery) | 🟢 OK | `alert_lifecycle`: no events in window. Instance up continuously since 09:24:27 UTC |
| Application errors (deadlocks, 1555, space) | 🟢 OK | No ORA-00060/01555/0165x in the alert log or traces. AWR "Segments by Row Lock Waits": no data |
| Redo / log writer | 🟢 OK | No redo warnings. `log file sync` 201 waits, avg 1.66 ms (threshold 10 ms) |
| Workload: CPU | 🟢 OK | Host 99.2% idle (0.4% usr, 0.3% sys). Instance uses 0.2% of total CPU. AAS ≈ 0.006 |
| Workload: parsing | 🟢 OK | Soft parse 97.27%, 0.3 hard parses/s |
| Workload: waits & locking | 🟢 OK | DB CPU is 94.8% of a tiny DB time (22.5 s). No `enq: TX` waits. `db file sequential read` avg 0.23 ms |
| Workload: I/O & efficiency | 🟢 OK | Buffer hit 99.75%, 0.2 physical reads/s, 704 disk reads all hour |

## Timeline

All times are UTC.

```
2026-10-20 09:24:27 | preflight/V$INSTANCE | Current instance startup (before window; not started by this review)
2026-10-20 09:24    | ADR                  | Last ORA-00800 incident (problem 1, 16 incidents since 2026-07-05). Startup side effect, before window
2026-10-20 13:00:38 | AWR                  | Snapshot 17 (begin of the pair used)
2026-10-20 13:48    | --                   | Requested window starts
2026-10-20 13:48-14:48 | alert log         | 1 line in CDB$ROOT, not an error/warning/lifecycle message (filtered out by alert_errors)
2026-10-20 14:00:40 | AWR                  | Snapshot 18 (end of the pair used). Last AWR snapshot available
2026-10-20 14:05    | traces               | 1 trace file from a W00n space-management slave written. No serious signatures
2026-10-20 14:48    | --                   | Requested window ends (= time of this review)
2026-10-20 15:00    | AWR (due)            | Next automatic snapshot. Would give pair 18–19 covering 14:00–15:00
```

## Findings

### 🔵 INFO: AWR covers only the first 12 minutes of the requested window
- **Evidence:** `awr_window_pairs` returned a single row: 17→18 (13:00 → 14:00 UTC), `PARTIAL`.
  `awr_snapshots` shows snap 18 at 14:00 UTC as the newest. The window ends at 14:48 UTC, which is
  when this review ran, so the 15:00 snapshot doesn't exist yet.
- **What it means:** AWR stores cumulative counters at each snapshot, and a report is the
  difference between two snapshots. Activity between 14:00 and 14:48 UTC is still only in the live
  counters, so no report can isolate it yet. The 13:00–14:00 pair is 80% outside the requested
  window, so treat its figures as context for the hour around the window, not a measurement of
  it. The alert log, incident and trace checks *did* cover the full window and found nothing, so
  nothing serious happened in the uncovered 48 minutes.
- **Recommendation (not executed):** Re-run `/db-diag-review from=2026-10-20T13:48 to=2026-10-20T14:48`
  after 15:00 UTC (16:00 BST) to get pair 18→19 as well. For an on-demand window you can also take manual
  snapshots with `scripts/awr-report.sh --snap` before and after a workload. This review didn't
  take any.

### 🔵 INFO: Background ADR problem "ORA 800" (known, kept for demo)
- **Evidence:** `adr_problems`: problem 1, key `ORA 800`, 16 incidents between 2026-07-05 21:57 and
  2026-10-20 09:24 UTC, **0 in window**.
- **What it means:** At each startup Oracle tries to raise VKTM (timekeeper) and LGWR (log writer)
  to real-time priority. The container lacks `CAP_SYS_NICE`, so the OS refuses and Oracle logs a
  "soft external error" incident. It's harmless for this demo. It isn't in the window, so it
  doesn't affect the rating here.
- **Recommendation (not executed):** Recreate the container with `--cap-add=SYS_NICE`. This is known
  and kept for the demo.

### 🔵 INFO: Workload in the overlapping hour is Oracle housekeeping only
- **Evidence:** AWR 17–18 top SQL: `dbms_autotask_prvt.run_autotask` (1.3 s, FREEPDB1),
  `prvt_hdm.execute_slave_actions` (ADDM, 1.1 s), the `wrh$_mvparameter` insert (AWR snapshot itself,
  0.8 s) and `SYS_AUTO_STS_MODULE` / auto-index capture. No application SQL. Captured SQL is only 18%
  of DB time, which is normal when DB time is tiny (22.5 s).
- **What it means:** No user workload (no `scripts/demo-diag-load.sh` run, no HR activity) took
  place in this hour. Execute-to-parse is low (30.8%), but that comes from recursive dictionary SQL,
  not from an application.
- **Recommendation:** None.

## Workload profile (AWR snaps 17–18, 13:00:38 → 14:00:40 UTC)

- **Header:** elapsed 60.04 min, DB time 22.5 s (0.38 min), DB CPU 21.3 s, average active
  sessions ≈ 0.006. 89 sessions. Background CPU 82.3 s (more than foreground, as expected on an idle box).
- **Top foreground events**

| Event | Waits | Time (s) | Avg | % DB time |
|---|---|---|---|---|
| DB CPU | | 21.3 | | 94.8 |
| log file sync | 201 | 0.3 | 1.66 ms | 1.5 |
| direct path write | 83 | 0.1 | 1.22 ms | 0.4 |
| db file sequential read | 223 | 0.1 | 0.23 ms | 0.2 |
| latch: shared pool | 22 | 0.0 | 1.25 ms | 0.1 |

- **Load profile:** redo 4.6 KB/s, logical reads 77 blocks/s, physical reads 0.2/s, executes 16.1/s,
  parses 11.2/s (hard 0.3/s), user calls 0.5/s, logons 0.1/s, ≈ 0.025 transactions/s.
- **Efficiency:** buffer hit 99.75%, soft parse 97.27%, library hit 95.12%, execute to parse 30.76%,
  in-memory sort 100%, latch hit 99.96%.
- **Top SQL** (all Oracle internals, listed for completeness):

| sql_id | Module / PDB | Execs | Elapsed (s) | Text |
|---|---|---|---|---|
| b39m8n96gxk7c | DBMS_SCHEDULER / FREEPDB1 | 15 | 1.3 | `call dbms_autotask_prvt.run_autotask` |
| a95n8p4vpxmps | CDB$ROOT | 2 | 1.1 | `begin prvt_hdm.execute_slave_actions; end;` (ADDM) |
| 2pkpuk0vd342z | CDB$ROOT | 1 | 0.8 | `insert into wrh$_mvparameter ...` (AWR snapshot) |
| ampw9ddqufjd3 | DBMS_SCHEDULER / FREEPDB1 | 4 | 0.6 | `dbms_auto_index_internal.capture_sts` |
| 9bd61v53p81sk | FREEPDB1 | 1 | 0.5 | `prvt_hdm.auto_execute` (ADDM) |

- **Where did the time go?** Almost nowhere. Over an hour the database spent 22 s in user calls,
  nearly all of it on CPU in scheduler and advisor jobs. Waits were negligible and fast (commits
  under 2 ms, single-block reads under 0.3 ms). The host had 14 CPUs and was 99% idle.

## Trace excerpts

None taken. `trace_signatures` found no serious signature in the window. The only trace file
written since 13:48 UTC was from a `W00n` process (a background space-management slave), last
modified 14:05 UTC. It held none of the searched signatures, so it wasn't read.

## Method

- MCP mode: read-only queries from `.claude/skills/db-diag-review/queries.sql` via SQLcl MCP
  `sql_run` on `demo_dbmon_cdb` (10 checks: `alert_overview`, `alert_errors`, `alert_lifecycle`,
  `adr_problems`, `adr_incidents`, `trace_inventory`, `trace_signatures`, `edition_gate`,
  `awr_snapshots`, `awr_window_pairs`). The window was substituted as
  `timestamp '2026-10-20 13:48:00 +00:00'` → `timestamp '2026-10-20 14:48:00 +00:00'`.
- Preflight (`scripts/db-preflight.sh`): container already running and healthy. **The DB was not
  started by this review** (`started_by_preflight=no`). There were 5 AWR snapshots since the 09:24 UTC startup.
- Workload source: AWR report `reports/awr/awr_17_18.txt`, generated by `scripts/awr-report.sh 17 18`
  and parsed with `extract_report.py`. AWR is allowed because `edition_gate` returned
  `is_free = Y` (Oracle Database Free includes the Diagnostics Pack; see `LICENSING.md`). No ASH,
  ADDM queries or Tuning Pack were used. No AWR snapshot was taken.
- **Choices made without asking:** (1) `awr_window_pairs` offered only the PARTIAL pair 17–18, so I
  used it and stated that it covers 12 of the 60 requested minutes. I didn't swap in a pair from
  outside the window. (2) I didn't run Statspack, because AWR was available and no Statspack pair
  was requested.
- Caveats: hourly AWR granularity, so the pair is mostly outside the requested window. The window
  ends at the review time, so the last 48 minutes have no snapshot yet. The alert log, incident
  and trace checks are exact to the window.
- Audit: MCP sessions are tagged `SQLcl-MCP` in `V$SESSION`. `DBTOOLS$MCP_LOG` isn't written for the
  read-only `dbmon` users.
