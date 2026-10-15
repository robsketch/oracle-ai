# Oracle Diagnostic Review: FREE (CDB `FREE` + PDB `FREEPDB1`)

| | |
|---|---|
| **Overall status** | 🟡 WARN |
| **Run at** | 2026-10-07 09:26 BST (database timestamps below are UTC; 08:17 UTC = 09:17 BST) |
| **Sources** | MCP: `demo_dbmon_cdb` (alert log, traces, incidents), `demo_dbmon` (Statspack) |
| **Window** | alert log / traces: last 7 days (data exists from 2026-10-06) · workload: Statspack snaps 13–21 (2026-10-07 08:16:36 → 08:17:11 UTC, **35 s**) |
| **Database** | 23.26.3 (Oracle AI Database 26ai Free), instance `FREE` on container host `9c6b064276dd`, 16 CPUs, 7.7 GB RAM |

## Summary

There are no critical errors: no ORA-600/7445/4031 and no corruption. The database has
**not been shut down cleanly** before either of the last two startups (6 Oct and 7 Oct), and
it ran crash recovery each time. That is almost certainly `docker stop` killing Oracle after
its default 10-second timeout. Two **ORA-00060 deadlocks** (08:15 and 08:17 UTC today) come
from the same pair of HR updates touching rows 1 and 2 of `DIAG_DEMO` in opposite order.
In the latest 35-second Statspack window, a **hard-parse storm** (soft parse 43%, 254 hard
parses/s from a literal-SQL loop) and one **Cartesian-join query** using 58% of DB time stand
out. Fix the shutdown first (`docker stop -t 120`). The rest are application patterns, and
here they were injected by `scripts/demo-diag-load.sh`.

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Critical errors (ORA-600/7445/4031/corruption) | 🟢 OK | none in alert log or trace signatures |
| ADR incidents | 🟡 WARN | 4 in window, all `ORA-00800 [Set Priority Failed]` (VKTM, LGWR), a known-benign container cause |
| Instance lifecycle (restarts, crash recovery) | 🟡 WARN | crash recovery at 2026-10-06 13:29 and 2026-10-07 07:35, with no "Instance shutdown complete" before either |
| Application errors (deadlocks, 1555, space) | 🟡 WARN | 2 × ORA-00060 in FREEPDB1 (08:15, 08:17), same SQL pair |
| Redo / log writer | 🟡 WARN (low) | one "redo writes taking longer than expected" (737 ms write, 6 Oct 13:58); `log file sync` avg 0.76 ms now |
| Workload: CPU | 🟡 WARN | DB CPU 80% of DB time; one SQL (`35ajv8tsat198`) = 58% of DB time; host only 17% busy |
| Workload: parsing | 🟡 WARN (CRIT on a sustained window) | soft parse **42.9%**, 254 hard parses/s, execute-to-parse 28% |
| Workload: waits & locking | 🟡 WARN | `enq: TX - row lock contention` 2 waits, avg **2.85 s**, 15.4% of DB time |
| Workload: I/O & efficiency | 🟢 OK | buffer hit 100%, 2 physical reads, no disk sorts |

Ratings for the workload rows are softened because the window is 35 seconds. It's evidence,
not a trend.

## Timeline

All times UTC (database clock).

```
2026-10-06 13:29:16 | alert     | Starting ORACLE instance, no clean shutdown logged before it
2026-10-06 13:29:17 | ADR       | incidents 8051 (VKTM), 8171 (LGWR): ORA-00800 Set Priority Failed
2026-10-06 13:29:18 | alert     | Beginning crash recovery of 1 threads
2026-10-06 13:29:20 | alert     | FREEPDB1 opened read write; ALTER DATABASE OPEN completed
2026-10-06 13:58:49 | alert+trc | redo writes taking longer than expected (FREE_lgwr_89.trc: 737 ms for 1 KB)
              ...   | (instance stopped uncleanly some time before the next startup)
2026-10-07 07:35:08 | alert     | Starting ORACLE instance, no clean shutdown logged before it
2026-10-07 07:35:10 | ADR       | incidents 9653 (VKTM), 9773 (LGWR): ORA-00800 Set Priority Failed
2026-10-07 07:35:10 | alert     | Beginning crash recovery of 1 threads
2026-10-07 07:35:13 | alert     | FREEPDB1 opened read write
2026-10-07 08:13:54 | statspack | snap 1  "baseline"
2026-10-07 08:14:45 | statspack | snap 11 "demo begin"
2026-10-07 08:15:06 | alert+trc | ORA-00060 deadlock, FREE_ora_3455.trc (HR, SQLcl), inside snaps 11–12
2026-10-07 08:15:11 | statspack | snap 12 "demo end"
2026-10-07 08:16:36 | statspack | snap 13 "demo begin"  ← analysed window starts
2026-10-07 08:17:07 | alert+trc | ORA-00060 deadlock, FREE_ora_3613.trc (HR, SQLcl), inside snaps 13–21
2026-10-07 08:17:11 | statspack | snap 21 "demo end"    ← analysed window ends
```

## Findings

### 🟡 Unclean shutdowns: crash recovery at every startup
- **Evidence:** `alert_lifecycle`: "Beginning crash recovery of 1 threads" at 2026-10-06
  13:29:18 and 2026-10-07 07:35:10, with no "Instance shutdown complete" in the 7-day window
  before either. "Crash Recovery excluding pdb 2 which was cleanly closed" (PDB$SEED is
  read-only, so it's always clean).
- **What it means:** Oracle wasn't allowed to finish `shutdown immediate`, so at startup it had
  to replay redo to make the datafiles consistent ("crash recovery", known as instance recovery).
  It worked, and on this small DB it took about 2 s. But every unclean stop is a hard kill. On
  a busy DB, recovery takes longer, and on bad storage you risk data loss.
- **Recommendation (not executed):** stop the container with `docker stop -t 120 oracle-free`,
  because the default 10-second grace period kills Oracle mid-shutdown. Check that WSL2 isn't
  being shut down (`wsl --shutdown`, Windows sleep) with the container running. Consider
  updating the `CLAUDE.md` / `setup.md` "Common commands" to use `-t 120`.

### 🟡 ORA-00060 deadlocks between two HR sessions (same pattern, twice)
- **Evidence:** `alert_errors` (FREEPDB1, 2 occurrences, 08:15 and 08:17);
  `trace_signatures` → `FREE_ora_3455.trc`, `FREE_ora_3613.trc`. Deadlock graph (3613): session
  22 holds TX `00050020…` and waits on TX `0008001E…`, which is held by session 58, which waits on
  session 22. Both sessions belong to user HR, program/module **SQLcl**, machine `sketchPC`, PDB FREEPDB1.
  - Session 22 current SQL: `update diag_demo set pad = 'A' where id = 2` (sql_id `1spp42b1cfff6`)
  - Session 58 current SQL: `update diag_demo set pad = 'B' where id = 1`
  - The 08:15 deadlock (`FREE_ora_3455.trc`, sessions 213/46) is identical.
- **What it means:** session A updated row 1 then wanted row 2, and session B updated row 2
  then wanted row 1. Neither can proceed, so after about 3 s Oracle breaks the cycle by rolling
  back *one statement* (not the whole transaction) in one session and raising ORA-00060. Oracle
  treats this as an application design problem, not a database bug. In Statspack it shows as
  `enq: TX - row lock contention` (2 waits, 5.7 s, avg 2.85 s), matching the 2 sessions × ~3 s
  detection delay.
- **Recommendation (not executed):** make every code path lock `DIAG_DEMO` rows in the same
  order (e.g. `order by id`, or `select … for update` of both rows first), or commit between
  the updates. The session that receives ORA-00060 must roll back or retry, not carry on.
  Here the cause is the injected demo load (`scripts/demo-diag-load.sh`).

### 🟡 Hard-parse storm: literal SQL instead of bind variables
- **Evidence:** `sp_efficiency`: soft parse **42.91%**, execute-to-parse 28.08%.
  `sp_load_profile`: 8,905 hard parses (254/s) out of 15,597 parses. `sp_time_model`: hard parse
  3.67 s (9.9% of DB time). `sp_top_sql`: `9wkqt88p0c6sm`, a PL/SQL loop running
  `execute immediate 'select /* diag-demo literal */ count(*) from diag_demo where id = ' || i`
  5,000 times. The individual literal statements are too cheap to clear Statspack's capture
  threshold, so they show only in the load profile.
- **What it means:** each distinct SQL text is compiled from scratch (a "hard parse": syntax,
  security and optimiser work), which burns CPU and fills the shared pool with single-use
  cursors. On a sustained window, a soft parse ratio below 80% is CRIT. A 35-second burst is
  rated WARN here.
- **Recommendation (not executed):** use binds: `execute immediate '… where id = :1' into n
  using i` (or plain static SQL in PL/SQL, which binds automatically). `cursor_sharing=FORCE`
  is only a stop-gap.

### 🟡 One Cartesian-join SQL dominates CPU
- **Evidence:** `sp_top_sql`: `35ajv8tsat198` (module SQLcl), 1 execution, 21.35 s elapsed,
  22.64 s CPU, **13.7 M buffer gets**, 0 disk reads:
  `select /* diag-demo cpu */ count(*) from employees a, employees b, employees c, (select level n from dual connect by level <= 200) d where a.salary + b.salary > c.salary - d.n`.
  That's 58% of the 36.9 s DB time. DB CPU 29.6 s = 80% of DB time. `sp_host_cpu`: host 17.1% busy, 16 CPUs.
- **What it means:** 107³ × 200 ≈ 245 M row combinations, all from cache (logical I/O), so it is
  pure CPU on one core. The host has plenty of headroom, so nothing else suffered, but one
  such query per CPU would saturate the box.
- **Recommendation (not executed):** add proper join predicates and review the plan
  (`dbms_xplan.display_cursor('35ajv8tsat198')`). In the demo it's deliberate.

### 🟡 ORA-00800 "Set Priority Failed" for VKTM and LGWR at each startup
- **Evidence:** `adr_incidents` 8051/8171 (6 Oct) and 9653/9773 (7 Oct). `adr_problems`:
  problem 1 "ORA 800", 14 incidents in total since 2026-07-05 (older ones predate this
  environment's setup on 6 Oct, probably carried in the image/volume ADR). Alert text: "Failed to
  elevate LGWR's priority … ErrMsg(Operation not permitted)". `FREE_lgwr_89.trc` also has
  "WARNING: Failed to disable OOMK".
- **What it means:** Oracle wants its timekeeper (VKTM) and log writer (LGWR) at real-time
  priority, and the container lacks `CAP_SYS_NICE`. This isn't a crash. The incidents line up
  one-for-one with the two startups (2 per startup). The "OOMK" line is related, as general
  guidance: the process couldn't exempt itself from the Linux OOM killer, also a privilege limit.
- **Recommendation (not executed):** when the container is next recreated, add
  `--cap-add=SYS_NICE` to `docker run` (and record it in `setup.md`). Low priority for a PoC.

### 🟡 One slow redo write (6 Oct)
- **Evidence:** alert "online redo log writes that are taking longer than expected" at
  2026-10-06 13:58. `FREE_lgwr_89.trc` line 65: `Warning: log write elapsed time 737ms, size 1KB`.
  In today's window, `log file sync` is 3,013 waits at an avg of **0.76 ms**, which is healthy.
- **What it means:** a single 1 KB write took about ¾ s, which points to a storage hiccup (WSL2 virtual
  disk or Windows host I/O), not to redo volume. LGWR running at normal priority (see the
  ORA-00800 finding) makes it more exposed to this. Isolated, so low concern.
- **Recommendation (not executed):** if it recurs, check host disk latency and keep the Docker
  volume on the WSL2 ext4 filesystem (not `/mnt/c`).

### 🔵 Row-by-row commits
- **Evidence:** `sp_load_profile`: 3,010 user commits (86/s), about 1 commit per transaction, 3,021
  redo synch writes, 1.8 KB redo per transaction. `log file sync` 3,013 waits at 0.76 ms.
- **What it means:** the client commits after every single row. Each commit waits for LGWR to
  write redo to disk. It's cheap here (2.3 s total), but it scales with storage latency, and
  the 737 ms write above would stall every committer.
- **Recommendation (not executed):** commit in batches (e.g. every 500–1,000 rows) or once per
  logical unit of work.

## Workload profile (Statspack)

- **Window:** snaps 13 → 21, 2026-10-07 08:16:36 → 08:17:11 UTC, **35 s**, same instance
  startup (deltas valid). Container FREEPDB1.
- **DB time** 36.9 s · **DB CPU** 29.6 s · **Average active sessions** 1.06 on 16 CPUs.

**Top timed events (foreground)**

| Event | Waits | Time (s) | Avg (ms) | % DB time |
|---|---:|---:|---:|---:|
| DB CPU | | 29.57 | | 80.0 |
| enq: TX - row lock contention | 2 | 5.70 | 2,849.46 | 15.4 |
| log file sync | 3,013 | 2.28 | 0.76 | 6.2 |
| enq: RO - fast object reuse | 2 | 0.01 | 5.20 | 0.0 |

**Load profile highlights**

| Statistic | Per second | Per txn |
|---|---:|---:|
| Logical reads | 395,280 | 4,593 |
| Physical reads | 0.1 | 0 |
| Redo size (bytes) | 157,319 | 1,828 |
| User calls | 363 | 4.2 |
| Parses (total / hard) | 446 / **254** | 5.2 / 3.0 |
| Executes | 620 | 7.2 |
| User commits | 86 | 1.0 |

**Efficiency:** buffer hit 100% · soft parse **42.9%** · execute-to-parse 28.1% · in-memory
sorts 100% · redo log space requests 0. Tablespace I/O: USERS 2 reads / 8 writes, nothing else.

**Top SQL (noise filtered)**

| sql_id | Module | Execs | Elapsed (s) | CPU (s) | Buffer gets | Text |
|---|---|---:|---:|---:|---:|---|
| `35ajv8tsat198` | SQLcl | 1 | 21.35 | 22.64 | 13,738,967 | `select /* diag-demo cpu */ count(*) from employees a, employees b, employees c, (… connect by level <= 200) d where …` |
| `9wkqt88p0c6sm` | SQLcl | 1 | 2.48 | 2.63 | 15,116 | `declare … for i in 1 .. 5000 loop execute immediate 'select /* diag-demo literal */ … where id = ' \|\| i …` |

Filtered as SQLcl-MCP / dictionary noise: `8mqmasy2r5sg0` (SQLcl `declare FUNCTION ifelse`),
plus recursive queries on `dependency$`, `aud_object_opt$`, `annotations_usage$`, `ind$`,
`histgrm$`/`hist_head$`. Together they take under 0.5 s.

**Where did the time go?** Almost all of DB time was CPU (80%), and 58% of it was one Cartesian
query reading 13.7 M cached blocks. Most of the remaining CPU went to hard-parsing about 5,000 literal
statements (hard parse 9.9% of DB time). About 15% was two sessions stuck behind each other's row locks
for about 3 s each until Oracle declared the deadlock, and about 6% was per-row commits waiting on
LGWR. There was essentially no physical I/O, and the host was mostly idle (17% busy).

## Trace excerpts

**`FREE_ora_3613.trc`**: foreground (`ora` = user session), FREEPDB1, ORA-00060 deadlock
```
38  2026-10-07 08:17:07.663025*:ksq.c@13862:ksqdld_hdr_dump():
39  DEADLOCK DETECTED ( ORA-00060 )
52  TX-00050020-000002BD-CE1992F3-00000000   72  22  X  2824    84  58     X  39177
53  TX-0008001E-000002A7-CE1992F3-00000000   84  58  X 39177    72  22     X   2824
58    sid: 22 ser: 2824 audsid: 190001 user: 136/HR
68      program: SQLcl machine: sketchPC
71    current SQL: update diag_demo set pad = 'A' where id = 2
76    sid: 58 ser: 39177 audsid: 190002 user: 136/HR
89    current SQL: update diag_demo set pad = 'B' where id = 1
```
The classic two-row, two-session cycle. Each session holds one row (X) and waits for the other's.

**`FREE_ora_3455.trc`**: foreground, FREEPDB1, ORA-00060 deadlock (08:15:06)
```
52  TX-00040021-00000275-CE1992F3-00000000   31 213  X 58643    86  46     X   2114
53  TX-00060021-00000296-CE1992F3-00000000   86  46  X  2114    31 213     X  58643
71    current SQL: update diag_demo set pad = 'A' where id = 2
89    current SQL: update diag_demo set pad = 'B' where id = 1
```
Identical SQL and pattern (sessions 213/46). It's the same bug, so it's not a separate finding.

**`FREE_lgwr_89.trc`**: background log writer, CDB$ROOT, ORA-00800 + slow write
```
34  WARNING: Failed to disable OOMK
35  Incident 8171 created, dump file: …/incdir_8171/FREE_lgwr_89_i8171.trc
37  ORA-00800: soft external error, arguments: [Set Priority Failed], [LGWR], …
51  Overlapped redo/writes by log writer are disabled (… LGWR mode=serial)
61  *** ACTION NAME:(Redo writer IO's) 2026-10-06T13:58:49
65  Warning: log write elapsed time 737ms, size 1KB
```
The priority failure appears at startup, and the single slow 1 KB write 30 minutes later matches the
alert-log warning. `FREE_lgwr_88.trc` / `FREE_vktm_46/47.trc` carry the same ORA-00800 signature
and were not excerpted separately.

## Method

- MCP mode: read-only queries from `.claude/skills/db-diag-review/queries.sql` via SQLcl MCP
  `sql_run`. 17 checks were run (7 cdb on `demo_dbmon_cdb`, 9 Statspack on `demo_dbmon`, plus
  `trace_excerpt` × 3, bounded to lines 24–159). None errored.
- No AWR/ASH/ADDM queried or generated. Workload data comes from Statspack (free), and
  alert/trace data from `V$DIAG_*`.
- Caveats: the Statspack window is **35 s**, so the workload ratings are softened and this is
  not a trend. The earlier pair 11–12 (08:14:45–08:15:11, containing the first deadlock) wasn't
  analysed, and snapshots 2–10 and 14–20 are missing from `STATS$SNAPSHOT`. The alert log only
  holds data from 2026-10-06, so the shutdown events before each startup aren't visible.
  The snapshot comments ("demo begin/end") and `/* diag-demo */` SQL tags show this load was
  injected by `scripts/demo-diag-load.sh`.
- Audit: MCP sessions are tagged `SQLcl-MCP` in `V$SESSION`. `DBTOOLS$MCP_LOG` isn't written
  for the read-only `dbmon` users.
