# Oracle Diagnostic Review: FREE (whole instance, CDB root)

| | |
|---|---|
| **Overall status** | 🔴 CRIT (instance lifecycle: two unclean restarts on 2026-10-07; cause known, see below) |
| **Run at** | 2026-10-08 12:58 local (11:58 UTC). All event times below are UTC, as the database logs them |
| **Sources** | MCP: `demo_dbmon_cdb` (alert log, traces, ADR incidents, AWR). Workload: AWR report `reports/awr/awr_4_5.txt` |
| **Window** | alert log / traces: last 7 days (2026-10-06 → 2026-10-08) · workload: AWR snaps 4–5 (2026-10-07 07:45:52 → 09:00:46, 74.9 min) |
| **Database** | Oracle AI Database 26ai Free 23.26.3.0.0, instance `FREE` on `9c6b064276dd` (Docker container), 16 CPUs / 8 cores, 7.7 GB RAM |

## Summary

The database is healthy in use, but it **never gets shut down cleanly**. It has started 4 times
in 3 days, needed crash recovery every time, and did so twice on 2026-10-07. That's the CRIT
rating. The cause is known: `docker stop` (10 s timeout) or a WSL shutdown kills Oracle before it
can close the database. The workload window (AWR, 75 min) holds the two **ORA-00060 deadlocks**
from the demo workload. They show up as 5 `enq: TX - row lock contention` waits averaging 2.3 s,
and **soft parse is only 80.6%** (literal SQL). Otherwise the instance was almost idle: 0.04
average active sessions, host 98% idle, buffer hit 99.99%. Fix first: stop the container with
`docker stop -t 120 oracle-free`, and add `--cap-add=SYS_NICE` the next time the container is
recreated.

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Critical errors (ORA-600/7445/4031/corruption) | 🟢 OK | None in the alert log or trace signatures |
| ADR incidents | 🟡 WARN | 8 incidents in window, all problem `ORA 800` "Set Priority Failed" (VKTM, LGWR), 2 per startup. Known benign container cause |
| Instance lifecycle (restarts, crash recovery) | 🔴 CRIT | Crash recovery at all 4 startups: 10-06 13:29, **10-07 07:35 and 11:01** (twice in one day), 10-08 11:56. No "Instance shutdown complete" anywhere |
| Application errors (deadlocks, 1555, space) | 🟡 WARN | 2 × ORA-00060 in FREEPDB1 at 10-07 08:15 and 08:17 (HR, module SQLcl, table `DIAG_DEMO`). No ORA-01555 (AWR undo STO = 0) or space errors |
| Redo / log writer | 🟡 WARN | "online redo log writes … taking longer than expected" at 10-06 13:58 and 10-07 09:13. But `log file sync` avg 1.08 ms over 3,815 waits in the AWR window |
| Workload: CPU | 🟢 OK | DB CPU 93.1% of DB time, but DB time only 2.83 min in 74.9 min; host 97.9% idle |
| Workload: parsing | 🟡 WARN | Soft parse 80.57%, hard parses 6.4/s, hard-parse time 12.6% of DB time, execute-to-parse 56.45% |
| Workload: waits & locking | 🟡 WARN | `enq: TX - row lock contention` 5 waits, avg 2,312 ms, 6.8% of DB time |
| Workload: I/O & efficiency | 🟢 OK | Buffer hit 99.99%, 0.6 physical reads/s, `db file sequential read` avg 0.17 ms |

## Timeline

```
2026-10-06 13:29:16 | alert   | Instance start → crash recovery (no clean shutdown before it)
2026-10-06 13:29:17 | ADR     | ORA-00800 Set Priority Failed: VKTM (inc 8051), LGWR (inc 8171)
2026-10-06 13:58    | alert   | Online redo log writes taking longer than expected
2026-10-07 07:35:08 | alert   | Instance start → crash recovery; ORA-00800 VKTM/LGWR (inc 9653/9773)
2026-10-07 07:45:52 | AWR     | Snapshot 4 (begin of analysed window)
2026-10-07 08:15    | alert   | ORA-00060 deadlock, FREEPDB1 (FREE_ora_3455.trc)
2026-10-07 08:16:36 | Statspk | Statspack demo window 13–21 begins (35 s; earlier report)
2026-10-07 08:17:07 | alert   | ORA-00060 deadlock, FREEPDB1 (FREE_ora_3613.trc), HR / SQLcl
2026-10-07 08:17:11 | Statspk | Statspack demo window ends
2026-10-07 09:00:46 | AWR     | Snapshot 5 (end of analysed window)
2026-10-07 09:13    | alert   | Online redo log writes taking longer than expected
2026-10-07 11:00:58 | alert   | Instance start → crash recovery (2nd of the day); ORA-00800 (inc 11255/11375)
2026-10-07 13:00    | AWR     | Snapshot 9, the last one. No snapshot 10, so the instance died 13:00–14:00
2026-10-08 11:56:43 | alert   | Instance start → crash recovery (container found exited, code 255;
                    |         | started for this review); ORA-00800 (inc 12857/12977)
```

## Findings

### 🔴 Unclean shutdowns: crash recovery at every startup, twice on 2026-10-07
- **Evidence:** `alert_lifecycle`: "Beginning crash recovery of 1 threads" at 10-06 13:29:18,
  10-07 07:35:10, 10-07 11:01:00 and 10-08 11:56:44. No "Instance shutdown complete" or
  "Shutting down ORACLE instance" line anywhere in the 7 days. The AWR snapshots stop at snap
  9 (10-07 13:00), so the last instance died between 13:00 and 14:00. This morning the container
  was in `Exited (255)` state.
- **What it means:** Oracle writes changes to the redo log first and to the datafiles later. If
  it's killed instead of shut down, the next startup has to replay redo to make the datafiles
  consistent ("crash recovery"). It worked every time and took about 2 s here, so no data was
  lost. But every kill is a gamble on storage behaving, and on a real system repeated unclean
  restarts usually mean something (OOM killer, host reboots, a wrapper script) is killing it.
- **Why CRIT:** the rating guide treats repeated crash restarts within a day as CRIT. On this
  dev box the cause is known and harmless in practice: `docker stop` sends SIGKILL after 10 s,
  before `shutdown immediate` finishes, and shutting down WSL kills the container outright.
- **Recommendation (not executed):** stop the DB with `docker stop -t 120 oracle-free`. Before
  `wsl --shutdown` or closing the laptop, stop the container first. Optionally recreate the
  container with `--stop-timeout 120` so a plain `docker stop` is safe.

### 🟡 ORA-00060 deadlocks in FREEPDB1 (demo workload)
- **Evidence:** `alert_errors`: ORA-00060 at 10-07 08:15 and 08:17 in FREEPDB1. The
  `FREE_ora_3613.trc` deadlock graph shows two HR sessions from SQLcl on `sketchPC`. Session 22
  holds the row lock for `id = 1` and waits on `update diag_demo set pad = 'A' where id = 2`.
  Session 58 holds `id = 2` and waits on `update diag_demo set pad = 'B' where id = 1`. AWR
  window 4–5: `enq: TX - row lock contention` 5 waits, 11.6 s, avg 2.31 s, 6.8% of DB time.
  "Segments by Row Lock Waits" shows 2 waits each on objects 73436 and 73438 in USERS
  (FREEPDB1), listed as `** MISSING **` because the table has since been dropped. Two object
  ids means two incarnations of `HR.DIAG_DEMO`, one per demo run.
- **What it means:** each session holds a row the other wants. Oracle detects the cycle after
  about 3 s and rolls back one *statement* (not the whole transaction) with ORA-00060. Oracle
  regards this as an application design problem, not a database fault. It's exactly what
  `scripts/demo-diag-load.sh` provokes on purpose.
- **Recommendation (not executed):** in real code, lock rows in a consistent order (for
  example, always by ascending `id`, or `SELECT … FOR UPDATE` both rows first), and commit
  sooner. Here: expected demo behaviour, so no action needed.

### 🟡 Literal SQL: soft parse 80.6%, hard parse 12.6% of DB time
- **Evidence:** AWR Instance Efficiency: Soft Parse 80.57%, Library Hit 85.82%, Execute to
  Parse 56.45%. Load profile: 6.4 hard parses/s. Time model: hard parse elapsed 21.4 s (12.6% of
  DB time), parse time 23.3 s. Captured SQL accounts for only **5.0% of DB time**.
- **What it means:** a "hard parse" means Oracle compiles a brand-new statement (syntax check,
  security check, optimiser) instead of reusing a cached cursor. SQL built by gluing values into
  the text (`… where id = 4711`) is a different statement every time, so it's always
  hard-parsed and floods the shared pool. That's the demo's 5,000-statement literal loop.
  Correlation: the demo's CPU-heavy join on `employees` dominated the 35-second Statspack window
  (76.6% of DB CPU) but **doesn't appear in AWR's top SQL at all**. Most likely the
  thousands of one-off cursors pushed it out of the shared pool before snapshot 5 at 09:00.
  So literal SQL costs CPU and also hides other SQL from performance tools. This is an
  inference, not checked against the shared pool history.
- **Rating:** WARN (80–95% band). Averaged over 75 minutes, it hides a much worse burst: the
  Statspack window showed 42.9% soft parse and 254 hard parses/s.
- **Recommendation (not executed):** use bind variables (`… where id = :id`).
  `cursor_sharing = FORCE` is only a stop-gap.

### 🟡 ORA-00800 "Set Priority Failed" for VKTM and LGWR (8 ADR incidents)
- **Evidence:** `adr_incidents`: 8 incidents in window, two per startup (VKTM and LGWR), all ADR
  problem 1 `ORA 800` (18 incidents since 2026-07-05). `FREE_lgwr_88.trc` line 37:
  `ORA-00800: soft external error, arguments: [Set Priority Failed], [LGWR], …`. The alert log
  shows "Failed to elevate LGWR's priority from 0 to 1 … ErrMsg(Operation not permitted)".
- **What it means:** Oracle tries to run its timekeeper (VKTM) and log writer (LGWR) at
  real-time OS priority. The container isn't allowed to (no `CAP_SYS_NICE`), so they run at
  normal priority. It's not a crash. Under heavy commit load LGWR could be slower, which shows
  as `log file sync`.
- **Recommendation (not executed):** next time the container is recreated, add
  `--cap-add=SYS_NICE`. Kept unfixed for the demo.

### 🟡 Redo log writes "taking longer than expected" (twice)
- **Evidence:** `alert_errors`: 10-06 13:58 and 10-07 09:13. The 09:13 event falls just after
  the AWR window. Inside the window `log file sync` was 3,815 waits at avg 1.08 ms (threshold
  10 ms), and the System I/O wait class averaged 2.12 ms.
- **What it means:** LGWR saw an occasional slow write to the online redo logs. On WSL2 with a
  Docker volume on a laptop disk, short latency spikes are normal, and normal-priority LGWR
  (finding above) doesn't help. There's no sustained impact in the workload data.
- **Recommendation (not executed):** none for the PoC. On a real system, check storage latency
  for the redo log disks and keep redo off shared/slow volumes.

### 🔵 Rest of the workload is idle Oracle housekeeping
- **Evidence:** DB time 169.8 s in 4,494 s, so about 0.04 average active sessions. Host
  97.9% idle, instance used 0.3% of total CPU. Top SQL by elapsed is
  `dbms_auto_report_internal.i_save_report` (6.1 s, 15 execs), then `DBMS_REPORT`, ADDM
  (`prvt_hdm`), AWR's own `wrh$_*` inserts and `DBMS_SCHEDULER`, all Oracle's own maintenance
  jobs. Undo: 0 snapshot-too-old, 0 out-of-space. Estimated MTTR 3–4 s.
- **What it means:** nothing in the steady-state workload needs attention.

## Workload profile (AWR snaps 4–5)

- **Window:** 2026-10-07 07:45:52 → 09:00:46 UTC (74.9 min), same startup (07:35), so the deltas are valid.
  Chosen over the newest pair (8–9, an idle hour) because it covers both deadlocks and the demo workload.
- **DB time** 169.8 s · **DB CPU** 158.1 s · **average active sessions** ≈ 0.04 · 5.3 transactions/s

**Top foreground events**

| Event | Waits | Time (s) | Avg | % DB time |
|---|---:|---:|---:|---:|
| DB CPU | | 158.1 | | 93.1 |
| enq: TX - row lock contention | 5 | 11.6 | 2,312 ms | 6.8 |
| log file sync | 3,815 | 4.1 | 1.08 ms | 2.4 |
| direct path sync | 3 | 0.3 | 92.9 ms | 0.2 |
| db file sequential read | 658 | 0.1 | 0.17 ms | 0.1 |

**Load profile (per second):** redo 15.4 KB · logical reads 4,383 blocks · physical reads 0.6 ·
user calls 6.3 · parses 32.7 · **hard parses 6.4** · executes 75.0 · transactions 5.3

**Efficiency:** buffer hit 99.99% · soft parse **80.57%** · library hit 85.82% ·
execute-to-parse 56.45% · in-memory sort 100%

**Top SQL** (only 5% of DB time captured, so all of it is Oracle housekeeping):

| SQL Id | PDB | Execs | Elapsed (s) | What |
|---|---|---:|---:|---|
| fhf8upax5cxsz | CDB$ROOT | 15 | 6.1 | `dbms_auto_report_internal.i_save_report` (automatic reports) |
| 0w26sk6t6gq98 | CDB$ROOT | 6 | 1.4 | `DBMS_REPORT.GET_REPORT_WITH_SUMMARY` |
| 8f91gw4xw0tkz | CDB$ROOT | 6 | 1.1 | Oracle's own monitoring query (`GV$` cursor) |
| 2pkpuk0vd342z | CDB$ROOT | 1 | 0.6 | `insert into wrh$_mvparameter` (AWR snapshot itself) |
| 9bd61v53p81sk | FREEPDB1 | 1 | 0.3 | `prvt_hdm.auto_execute` (ADDM) |

**Where did the time go?** Almost all DB time (93%) was CPU, nearly all of it from the
demo burst around 08:15–08:17: the Cartesian join, 3,000 client commits and 5,000 literal
statements. The SQL isn't in AWR's top list because the literal storm aged it out (see
finding). The only significant wait was the deadlock's row-lock contention (6.8%). Commits
cost 2.4% at a healthy 1 ms each. For the rest of the 75 minutes the instance was idle.

## Trace excerpts

**`FREE_ora_3613.trc`**: user session (`ora`), container FREEPDB1, signature ORA-00060 deadlock
```
39  DEADLOCK DETECTED ( ORA-00060 )
49  Deadlock graph:
52  TX-00050020-000002BD-...    72      22     X         2824      84      58           X  39177
53  TX-0008001E-000002A7-...    84      58     X        39177      72      22           X   2824
58    sid: 22 ser: 2824 audsid: 190001 user: 136/HR
68      program: SQLcl machine: sketchPC
71    current SQL: update diag_demo set pad = 'A' where id = 2
76    sid: 58 ser: 39177 audsid: 190002 user: 136/HR
89    current SQL: update diag_demo set pad = 'B' where id = 1
100 ----- Current SQL Statement for this session (sql_id=1spp42b1cfff6) -----
```
A classic two-way TX deadlock: each session holds the row the other wants. Session 22 detected
it, so its statement was rolled back. `FREE_ora_3455.trc` (08:15) has the same signature from
the first demo run and wasn't excerpted separately.

**`FREE_lgwr_88.trc`**: log writer (background), CDB$ROOT, signature ORA-00800
```
34  WARNING: Failed to disable OOMK
35  Incident 12977 created, dump file: .../incdir_12977/FREE_lgwr_88_i12977.trc
37  ORA-00800: soft external error, arguments: [Set Priority Failed], [LGWR],
    [Check traces and OS configuration], [Check Oracle document and MOS notes], []
49  Overlapped redo/writes by log writer are disabled (... LGWR mode=serial)
```
Container permission limits: LGWR can't raise its priority (no `CAP_SYS_NICE`) and Oracle can't
opt out of the OOM killer. The VKTM and older LGWR traces carry the same signature at line 37.

## Method

- MCP mode: read-only queries from `.claude/skills/db-diag-review/queries.sql` via SQLcl MCP
  `sql_run` on `demo_dbmon_cdb`: `alert_overview`, `alert_errors`, `alert_lifecycle`,
  `adr_problems`, `adr_incidents`, `trace_inventory`, `trace_signatures`, `edition_gate`,
  `awr_snapshots`, and `trace_excerpt` ×2 (bounded line windows). No check errored.
- Workload source: **AWR**, allowed because `edition_gate` returned `EDITION = FREE`,
  `is_free = Y` (Oracle AI Database 26ai Free, where the Diagnostics Pack is included; see
  `LICENSING.md`). Report produced by `scripts/awr-report.sh 4 5` (no new snapshot taken) and
  read through `extract_report.py`. No ASH, ADDM queries or Tuning Pack. The Statspack
  `sp_*` checks weren't run (AWR path). The Statspack figures quoted come from the earlier
  report `reports/db-diag-statspack_13_21-20261007-0928.md`.
- Caveats: AWR snapshots are hourly, so a 2-minute burst is averaged over 75 minutes and the
  ratios understate it. AWR here covers the whole instance (CDB$ROOT and all PDBs). No AWR
  snapshot exists yet since this morning's restart. The container was found stopped (exit 255)
  and was started with `docker start oracle-free` to run this review. That startup is the
  10-08 11:56 entry in the timeline.
- Audit: sessions are tagged `SQLcl-MCP` in `V$SESSION`. `DBTOOLS$MCP_LOG` isn't written for the
  read-only `dbmon` users. One extra no-op probe (`select 1 from dual where 1=0`) was issued at
  connect time with a mistyped tag (`db-diagkreview`).
