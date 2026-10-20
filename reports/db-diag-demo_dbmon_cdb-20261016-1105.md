# Oracle Diagnostic Review: FREE (whole instance: CDB$ROOT + FREEPDB1)

| | |
|---|---|
| **Overall status** | 🟡 WARN |
| **Run at** | 2026-10-16 10:05 UTC (11:05 BST host time) |
| **Sources** | MCP: `demo_dbmon_cdb` (alert log, traces, incidents), `demo_dbmon` (Statspack) |
| **Window** | alert log / traces / incidents: last 7 days (since 2026-10-09 10:05 UTC) · workload: **Statspack requested, but no snapshots exist, so this section was skipped** |
| **Database** | Oracle AI Database 26ai Free 23.26.3.0.0, instance `FREE` in container `oracle-free`. The DB was already running (started 2026-10-15 20:02:46 UTC); this review didn't start it |

## Summary

No critical errors were found: no ORA-600/7445/4031, no corruption and no deadlocks in the last 7 days. The only incidents are the two
known ORA-00800 "Set Priority Failed" incidents (VKTM, LGWR) logged when the instance started at 2026-10-15 20:02 UTC. That startup
also needed crash recovery, because the previous stop was unclean. Both are known and kept for the demo. The new item is LGWR
taking **3.5 s and 2.0 s to write 1 KB of redo** at 08:05 and 08:07 UTC today, which caused an alert-log warning about slow redo
log writes. That points to a host or disk stall, not to database load. There is no workload section: `workload=statspack` was
requested and `PERFSTAT.STATS$SNAPSHOT` is empty. Run `scripts/demo-diag-load.sh` to create a Statspack pair, or re-run with
`workload=awr`, since 5 AWR snapshots exist since startup.

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Critical errors (ORA-600/7445/4031/corruption) | 🟢 OK | None in alert log (`alert_errors`) or traces (`trace_signatures`) |
| ADR incidents | 🟡 WARN | 2 incidents, ORA-00800 Set Priority Failed (VKTM 8051, LGWR 8171), 2026-10-15 20:02 UTC. Known cause, kept for demo |
| Instance lifecycle (restarts, crash recovery) | 🟡 WARN | 1 startup at 2026-10-15 20:02:46 with crash recovery; no "Instance shutdown complete" before it. Known cause (`docker stop` 10 s timeout), kept for demo |
| Application errors (deadlocks, 1555, space) | 🟢 OK | No ORA-00060/01555/0165x in alert log or traces in the window |
| Redo / log writer | 🟡 WARN | "online redo log writes … taking longer than expected" at 2026-10-16 08:05; LGWR trace: 3480 ms and 2012 ms for 1 KB writes |
| Workload: CPU | ⚪ n/a | No Statspack snapshots |
| Workload: parsing | ⚪ n/a | No Statspack snapshots |
| Workload: waits & locking | ⚪ n/a | No Statspack snapshots |
| Workload: I/O & efficiency | ⚪ n/a | No Statspack snapshots |

## Timeline (UTC)

| Time | Source | Event |
|---|---|---|
| before 2026-10-15 20:02 | (inferred) | Previous instance stopped uncleanly. There's no shutdown line in the 7-day window and no alert lines at all between 2026-10-09 and 2026-10-15, so the container was probably stopped for that time |
| 2026-10-15 20:02:46 | alert log | `Starting ORACLE instance (normal)`. Startup was **not** caused by this review (`started_by_preflight=no`) |
| 2026-10-15 20:02:47 | ADR | Incident 8051: ORA-00800 [Set Priority Failed] [VKTM] |
| 2026-10-15 20:02:48 | ADR / trace | Incident 8171: ORA-00800 [Set Priority Failed] [LGWR]; `FREE_lgwr_89.trc` also logs "WARNING: Failed to disable OOMK" |
| 2026-10-15 20:02:48 | alert log | `Beginning crash recovery of 1 threads` ("excluding pdb 2", i.e. PDB$SEED, which was cleanly closed) |
| 2026-10-15 20:02:52 | alert log | FREEPDB1 opened read write; `ALTER DATABASE OPEN` completed |
| ~2026-10-15 20:12 → 2026-10-16 10:00 | AWR | 5 automatic AWR snapshots (latest snap 5 at 10:00). Not used, because Statspack was requested |
| 2026-10-16 08:05:36 | alert log + LGWR trace | "online redo log writes … taking longer than expected"; `log write elapsed time 3480ms, size 1KB` |
| 2026-10-16 08:05–08:07 | trace inventory | `cjq`, `mz`, `j` (job) and `lgwr` traces all written in this two-minute burst |
| 2026-10-16 08:07:30 | LGWR trace | `log write elapsed time 2012ms, size 1KB` |
| 2026-10-16 10:05 | this review | Run start |

## Findings

### 🟡 Slow redo log writes at 08:05–08:07 UTC today
- **Evidence:** alert log 2026-10-16 08:05: "The system is observing online redo log writes that are taking longer than expected to
  complete" (`alert_errors`). `FREE_lgwr_89.trc` lines 60–71: `Warning: log write elapsed time 3480ms, size 1KB` (08:05:36) and
  `… 2012ms, size 1KB` (08:07:30). Several other background processes (`cjq`, `mz`, `j`) also wrote traces between 08:05 and 08:07
  (`trace_inventory`).
- **What it means:** LGWR (the log writer) has to write redo to disk before any commit can return. Writing 1 KB should take well
  under 10 ms; 2–3.5 s means the write was stalled, not that it was large. The tiny size and the burst of other traces at the same
  minute point to a pause on the host, such as WSL2 or the laptop resuming from sleep or the virtual disk stalling, and not to
  database load. This is general guidance, not confirmed against host logs. Commits during those seconds would have hung
  (`log file sync`).
- **Recommendation (not executed):** Check whether the laptop slept or resumed around 09:05 BST. If the warning recurs while the
  laptop is awake, look at disk latency for the WSL2 VHDX (`iostat -x` inside WSL) and keep redo off slow or shared storage. To
  measure it, run a Statspack or AWR window across an active period and check `log file sync` / `log file parallel write` average ms.

### 🟡 Crash recovery at the 2026-10-15 20:02 startup (known, kept for demo)
- **Evidence:** `alert_lifecycle`: `Starting ORACLE instance` 20:02:46, then `Crash Recovery excluding pdb 2 which was cleanly closed`
  and `Beginning crash recovery of 1 threads` at 20:02:48. No `Instance shutdown complete` in the window.
- **What it means:** Oracle had to replay redo at startup because the previous instance was killed, not shut down. Recovery
  succeeded in under 4 s. The cause is known: `docker stop` (10 s timeout) or a WSL shutdown kills Oracle before
  `shutdown immediate` finishes.
- **Recommendation (not executed):** Stop the container with `docker stop -t 120 oracle-free`. This was verified clean on
  2026-10-08. Only one restart happened in the window, so this stays WARN, not CRIT.

### 🟡 ORA-00800 Set Priority Failed for VKTM and LGWR (known, kept for demo)
- **Evidence:** `adr_incidents` 8051 (VKTM) and 8171 (LGWR), 2026-10-15 20:02, both `ORA-00800 [Set Priority Failed]`. ADR problem 1
  (`ORA 800`) has 12 incidents since 2026-07-05, 2 of them in this window. Alert log: "Failed to elevate LGWR's priority from 0 to 1 …
  ErrMsg(Operation not permitted)".
- **What it means:** Oracle tries to run its timekeeper (VKTM) and log writer (LGWR) at real-time priority. The container lacks the
  `CAP_SYS_NICE` capability, so the OS refused. This isn't a crash, but LGWR at normal priority competes with everything else for
  CPU, which could make stalls like the 08:05 one slightly worse under load.
- **Recommendation (not executed):** Recreate the container with `--cap-add=SYS_NICE`. It's kept unfixed for the demo.

### 🔵 No Statspack snapshots, so no workload analysis
- **Evidence:** `sp_snapshots` returned no rows. `PERFSTAT.STATS$SNAPSHOT` in FREEPDB1 is empty.
- **What it means:** Statspack only records what it's told to snapshot, and no hourly job is scheduled here. Any earlier snapshots
  have been purged, or Statspack was reinstalled.
- **Recommendation (not executed):** Run `scripts/demo-diag-load.sh`, which takes a Statspack pair around a demo workload with a
  deliberate deadlock, then re-run this review. Or, because this is Free, re-run with `workload=awr`: there are 5 AWR snapshots
  since the current startup.

### 🔵 Not covered by this review
- ARCHIVELOG with no FRA (archives in the container layer) is a known finding kept for the demo. The alert log showed no archiver
  errors (`ORA-00257/19809/19815`) in the window. `arc` traces were last written at 09:12 UTC.

## Workload profile (Statspack / AWR)

Skipped. `workload=statspack` was requested and `sp_snapshots` returned no rows, so there's no snapshot pair to compare. The
remaining `sp_*` checks weren't run.

## Trace excerpts

**`FREE_lgwr_89.trc`**: log writer (background), container CDB$ROOT, signature ORA-00800 (lines 22–157 requested).
```
34  WARNING: Failed to disable OOMK
35  Incident 8171 created, dump file: .../incident/incdir_8171/FREE_lgwr_89_i8171.trc
37  ORA-00800: soft external error, arguments: [Set Priority Failed], [LGWR], [Check traces and OS configuration], ...
51  Overlapped redo/writes by log writer are disabled (size=2048, stall size=2048, poke=100%, LGWR mode=serial)
61  *** ACTION NAME:(Redo writer IO's) 2026-10-16T08:05:36
65  Warning: log write elapsed time 3480ms, size 1KB
67  *** ACTION NAME:(Redo writer IO's) 2026-10-16T08:07:30
71  Warning: log write elapsed time 2012ms, size 1KB
```
Interpretation: the ORA-00800 lines are the known startup issue. Lines 65 and 71 are the evidence for the slow-redo finding: tiny
writes taking seconds is a stall, not volume. "Failed to disable OOMK" means Oracle couldn't exempt LGWR from the Linux OOM killer.
It comes from the same missing container privileges and is general guidance. I took no excerpt from `FREE_vktm_47.trc`: it has the
same ORA-00800 signature, already covered by the incident and the alert log.

## Method

- MCP mode: read-only queries from `.claude/skills/db-diag-review/queries.sql` via SQLcl MCP `sql_run`. 10 checks ran:
  `alert_overview`, `alert_errors`, `alert_lifecycle`, `adr_problems`, `adr_incidents`, `trace_inventory`, `trace_signatures`,
  `edition_gate`, one `trace_excerpt` (lines 22–157) and `sp_snapshots`. None errored.
- Preflight (`scripts/db-preflight.sh`): container was already running and healthy, `started_by_preflight=no`, edition FREE, 5 AWR
  snapshots since the 2026-10-15 20:02:46 UTC startup.
- **Workload source: Statspack, because the caller passed `workload=statspack`.** The edition gate says Free (`is_free=Y`), so AWR
  was allowed, but I followed the explicit argument and didn't fall back to AWR when Statspack turned out to be empty. Nobody
  could be asked, and the skill's fallback only goes from AWR to Statspack. No AWR pair was used, `awr_snapshots` wasn't run and
  no AWR snapshot was taken. No ASH/ADDM or Tuning Pack.
- Caveats: the 7-day window only has alert-log activity from 2026-10-15 20:02 onwards. The container seems to have been stopped
  from about 2026-10-09 to 2026-10-15, so the demo-day (2026-10-09) deadlocks and workload aren't in this window. I didn't check
  host logs to confirm the 08:05 stall cause.
- Times: all event times are UTC (DB). The host clock is BST (UTC+1).
- Audit: sessions are tagged `SQLcl-MCP` in `V$SESSION`. `DBTOOLS$MCP_LOG` isn't written for the read-only `dbmon` users.
