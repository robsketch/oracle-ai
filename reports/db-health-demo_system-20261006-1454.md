# Oracle Health Check: FREE / FREEPDB1

| | |
|---|---|
| **Overall status** | 🟡 WARN |
| **Run at** | 2026-10-06 14:54 (host `date`) |
| **Connection** | `demo_system` → `system@localhost:1521/FREEPDB1` |
| **Database** | Oracle AI Database 26ai Free Release 23.26.3.0.0, instance `FREE` on `9c6b064276dd` (container) |
| **Up since** | 2026-10-06 13:29 (0 days, about 1.5 h) |
| **Mode** | ARCHIVELOG, READ WRITE, PRIMARY (force logging YES, flashback NO) |

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Instance & PDBs | 🟢 OK | Instance `OPEN`/`ACTIVE`; FREEPDB1 `READ WRITE`, restricted `NO` |
| Storage (tablespaces, Free cap) | 🟢 OK | All tablespaces 0% of max; user datafiles 72 MB of the 12 GB Free cap |
| Recovery (FRA, archiving, backups) | 🟡 WARN | ARCHIVELOG with **no FRA**; archiving to `$ORACLE_HOME/dbs/arch`; no RMAN backups in 7 days |
| Redo | 🟢 OK | 3 × 200 MB groups; 0 switches in 24 h |
| Memory & limits | 🟢 OK | SGA 1529 MB; PGA 5 MB (max 11 MB), 0 over-allocations; processes 90/200 (45%), sessions 86/322 (27%) |
| Sessions & blocking | 🟢 OK | 1 active user session (this check); no blocking; no long-running calls |
| Workload (top SQL, waits) | 🟢 OK | Top SQL is all SQLcl/MCP tooling; `log file sync` 3.59 ms, `db file sequential read` 0.16 ms |
| Objects & statistics | 🟡 WARN | No invalid objects; HR: 7 of 7 tables never analyzed (expected, schema just installed) |
| Alert log & jobs | 🟢 OK | No alert-log errors in 24 h; no failed scheduler jobs |
| Accounts | 🟢 OK | No locked, expired or expiring application accounts |
| Configuration / licensing | 🔵 INFO | `control_management_pack_access` = `DIAGNOSTIC+TUNING` (default; informational on Free) |

## Findings

### 🟡 ARCHIVELOG with no fast recovery area; archive logs in the container's writable layer
- **Evidence:** `instance`: `log_mode = ARCHIVELOG`. `fra`: no rows (no FRA configured);
  `parameters`: `db_recovery_file_dest` empty, `db_recovery_file_dest_size = 0`. `archiving`:
  `LOG_ARCHIVE_DEST_1` = `/opt/oracle/product/26ai/dbhomeFree/dbs/arch`, status `VALID`, 0 logs
  archived in 24 h.
- **Why it matters:** In ARCHIVELOG mode, every filled online redo log is copied to the archive
  destination. With no FRA, Oracle doesn't manage or purge that space, and without backups nothing
  deletes the logs either, so they grow without limit. If the destination fills, archiving stops
  and the database hangs on the next log switch. Because the path is under `$ORACLE_HOME`, it sits
  in the container's writable layer, not the `oracle-free-data` volume, so the logs are lost on
  `docker rm` and also bloat the container filesystem.
- **Recommendation (not executed):** Either point archiving at an FRA on the data volume:
  ```sql
  -- in CDB root (service FREE), as SYSDBA
  alter system set db_recovery_file_dest_size = 10G scope=both;
  alter system set db_recovery_file_dest = '/opt/oracle/oradata/FRA' scope=both;
  alter system set log_archive_dest_1 = 'LOCATION=USE_DB_RECOVERY_FILE_DEST' scope=both;
  ```
  or, for a pure dev/demo box with no recovery requirement, switch to NOARCHIVELOG
  (`shutdown immediate; startup mount; alter database noarchivelog; alter database open;`).
  This is a known finding, deliberately left unfixed for the demo.

### 🟡 No RMAN backups in the last 7 days
- **Evidence:** `backups`: no rows in `V$RMAN_BACKUP_JOB_DETAILS` for the last 7 days.
- **Why it matters:** With no backup, there's no recovery from media loss or user error. That
  would be CRIT on a real system. Rated WARN here because this is a freshly built demo box.
- **Recommendation (not executed):** After configuring an FRA, take a baseline backup and let
  RMAN purge obsolete archive logs:
  ```
  rman target /
  RMAN> backup database plus archivelog delete input;
  RMAN> configure retention policy to redundancy 1;
  ```

### 🟡 HR tables have never had optimizer statistics gathered
- **Evidence:** `stats`: owner `HR`, 7 of 7 tables `never_analyzed`, 0 stale.
- **Why it matters:** Without statistics, the optimizer falls back to dynamic sampling and
  guesses, which can produce poor execution plans. This is **expected** here: HR was installed
  today, after the last automatic stats maintenance window, which will pick it up overnight.
- **Recommendation (not executed):** `exec dbms_stats.gather_schema_stats('HR');`, or wait for
  the nightly auto-stats job.

### 🔵 Management pack access left at default `DIAGNOSTIC+TUNING`
- **Evidence:** `parameters`: `control_management_pack_access = DIAGNOSTIC+TUNING` (isdefault
  `TRUE`).
- **Why it matters:** On a licensed Enterprise Edition without the Diagnostics/Tuning Packs, this
  default lets tools (and people) use AWR/ASH by accident, which creates licence exposure. On
  Oracle Free it's informational only.
- **Recommendation (not executed):** On production EE without pack licences:
  `alter system set control_management_pack_access = 'NONE' scope=both;`

### 🔵 Short uptime: cumulative stats carry little weight
- **Evidence:** `instance`: started 2026-10-06 13:29, `uptime_days = 0`.
- **Why it matters:** `V$SQL`, `V$SYSTEM_EVENT` and `V$LOG_HISTORY` are cumulative since startup,
  so workload, wait and redo-rate figures reflect about 1.5 hours of mostly idle time.

## Detail by check

**instance**

| instance | host | version | status | db status | log mode | open mode | role | force logging | flashback |
|---|---|---|---|---|---|---|---|---|---|
| FREE | 9c6b064276dd | 23.26.3.0.0 | OPEN | ACTIVE | ARCHIVELOG | READ WRITE | PRIMARY | YES | NO |

Healthy. Host name is a container ID, as expected for the Docker image.

**pdbs**

| con_id | name | open_mode | restricted | size_mb |
|---|---|---|---|---|
| 3 | FREEPDB1 | READ WRITE | NO | 912 |

Only the connected PDB is visible from inside it. It's open read-write, unrestricted.

**capacity**

| datafile_mb | user_datafile_mb | tempfile_mb |
|---|---|---|
| 892 | 72 | 20 |

72 MB of user data against the 12 GB Free edition cap.

**tablespaces**

| tablespace | contents | used_mb | alloc_mb | max_mb | used_pct_of_max |
|---|---|---|---|---|---|
| SYSAUX | PERMANENT | 402 | 430 | 937359 | 0 |
| SYSTEM | PERMANENT | 289 | 290 | 937219 | 0 |
| USERS | PERMANENT | 8 | 72 | 937001 | 0 |
| UNDOTBS1 | UNDO | 8 | 100 | 33554432 | 0 |
| TEMP | TEMPORARY | 0 | 20 | 32768 | 0 |

Bigfile tablespaces with autoextend, so the theoretical maximums are huge. The Free 12 GB cap
(see `capacity`) is the real ceiling.

**fra**: No rows: no fast recovery area configured.

**archiving**

| dest | status | destination | error | logs_24h | mb_24h |
|---|---|---|---|---|---|
| LOG_ARCHIVE_DEST_1 | VALID | /opt/oracle/product/26ai/dbhomeFree/dbs/arch | – | 0 | – |

Destination is valid but sits inside `$ORACLE_HOME` (container layer). See findings.

**redo**

| group | members | size_mb | status | archived | switches_24h | peak/hour |
|---|---|---|---|---|---|---|
| 1 | 1 | 200 | INACTIVE | YES | 0 | – |
| 2 | 1 | 200 | CURRENT | NO | 0 | – |
| 3 | 1 | 200 | UNUSED | YES | 0 | – |

No log switches in 24 h. 200 MB logs are ample for this load. Single-member groups (no
multiplexing) are normal for Free/dev.

**memory**

| metric | value |
|---|---|
| SGA total | 1529 MB |
| PGA allocated / max | 5 MB / 11 MB |
| PGA over-allocation count | 0 |
| sga_max_size / sga_target / memory_target | 1536M / 0 / 0 |
| pga_aggregate_target / limit | 512M / 2G |

No memory pressure. (`sga_target`/`memory_target` = 0 as seen from the PDB. SGA sizing is set
at CDB level.)

**limits**

| resource | current | limit | % |
|---|---|---|---|
| processes | 90 | 200 | 45% |
| sessions | 86 | 322 | 27% |

Comfortably below limits. Counts are instance-wide (mostly background processes).

**sessions**

| type | status | sessions | user active > 5 min |
|---|---|---|---|
| BACKGROUND | ACTIVE | 85 | 0 |
| USER | ACTIVE | 1 | 0 |

The single user session is this health check (SQLcl-MCP).

**blocking**: No rows: no blocking or blocked sessions.

**long_running**: No rows: no user calls active for more than 60 s.

**top_sql**

| sql_id | module | execs | elapsed_s | avg_ms | text |
|---|---|---|---|---|---|
| 8mqmasy2r5sg0 | SQLcl | 952 | 1.0 | 1.1 | SQLcl internal PL/SQL helper |
| gmsat725pn3ch | SQLcl-MCP | 64 | 0.2 | 2.4 | MCP log-table existence check |
| 0ksjuubjvu2tp | claude-opus-5-5 | 64 | 0.1 | 1.6 | MCP log-table setup block |
| … | | | | | (remaining 7 rows: SQLcl/MCP plumbing, all ≤ 0.1 s) |

Top SQL is all tooling noise from SQLcl and the MCP server. There's no application workload
yet. Nothing dominates.

**waits**

| event | class | waits | time_s | avg_ms |
|---|---|---|---|---|
| log file sync | Commit | 195 | 0.7 | 3.59 |
| db file sequential read | User I/O | 3805 | 0.6 | 0.16 |
| resmgr:cpu quantum | Scheduler | 116 | 0.2 | 1.83 |
| latch: shared pool | Concurrency | 817 | 0.2 | 0.26 |
| enq: CR - block range reuse ckpt | Other | 72 | 0.1 | 1.96 |

Total non-idle wait time is under 3 s since startup. Both key latencies are well under
threshold (log file sync 3.59 < 10 ms; single-block read 0.16 < 20 ms). `resmgr:cpu quantum`
reflects Oracle Free's built-in CPU cap (2 threads), so it's not a problem.

**invalid_objects**: No rows: no invalid objects in any schema.

**alert_log**: No rows: no ORA-/TNS-/error/deadlock messages in the last 24 h.

**backups**: No rows: no RMAN backup jobs in the last 7 days.

**jobs**: No rows: no failed scheduler job runs in the last 24 h.

**users**: No rows: no locked, expired or soon-to-expire application accounts.

**stats**

| owner | stale | never_analyzed | total |
|---|---|---|---|
| HR | 0 | 7 | 7 |

Freshly installed sample schema. See findings.

**parameters**

| name | value | default? |
|---|---|---|
| audit_trail | NONE | TRUE |
| compatible | 23.6.0 | FALSE |
| control_management_pack_access | DIAGNOSTIC+TUNING | TRUE |
| db_recovery_file_dest | (empty) | TRUE |
| db_recovery_file_dest_size | 0 | TRUE |
| open_cursors | 300 | FALSE |
| optimizer_features_enable | 23.1.0 | TRUE |
| processes | 200 | FALSE |
| sessions | 322 | TRUE |
| statistics_level | TYPICAL | TRUE |
| undo_retention | 900 | TRUE |

`audit_trail = NONE` only covers legacy auditing. 23ai uses Unified Auditing, which this
parameter doesn't control.

## Method

- Read-only queries from `.claude/skills/db-health-check/queries.sql` (21 checks), run via the
  SQLcl MCP server `sql_run` tool. All 21 completed without errors.
- Standard `V$`/`DBA_` views only. No AWR/ASH/ADDM or SQL Monitor (Diagnostics/Tuning Pack
  not used). No additional digging beyond `queries.sql`.
- **Scope:** connected to PDB `FREEPDB1` as `SYSTEM`. Most `V$` views show this container only.
  `V$SGA`, `V$LOG`, `V$ARCHIVE_DEST`, `V$PROCESS` and the parameters reflect the whole CDB
  `FREE`. CDB root was not checked directly.
- **Cumulative stats:** uptime is about 1.5 h, so top SQL, waits and redo rates carry little
  weight.
- **Audit:** every statement was logged to `SYSTEM.DBTOOLS$MCP_LOG` with model
  `claude-opus-5-5`. The session is visible in `V$SESSION` as program `SQLcl-MCP`, module
  `claude-opus-5-5`.
