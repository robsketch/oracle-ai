# Oracle Health Check: FREE / FREEPDB1

| | |
|---|---|
| **Overall status** | 🟡 WARN |
| **Run at** | 2026-10-06 14:49 (host time, BST) |
| **Connection** | `demo_system` → `system@localhost:1521/FREEPDB1` |
| **Database** | Oracle AI Database 26ai Free Release 23.26.3.0.0, instance `FREE` on `9c6b064276dd` (container) |
| **Up since** | 2026-10-06 13:29 (0 days, under a day) |
| **Mode** | ARCHIVELOG, READ WRITE, PRIMARY (force logging YES, flashback NO) |

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Instance & PDBs | 🟢 OK | Instance `OPEN` / `ACTIVE`; FREEPDB1 `READ WRITE`, restricted `NO`, 902 MB |
| Storage (tablespaces, Free cap) | 🟢 OK | All tablespaces ≈0% of max; user datafiles 72 MB of the 12 GB Free cap |
| Recovery (FRA, archiving, backups) | 🟡 WARN | ARCHIVELOG with **no FRA**; archive dest `$ORACLE_HOME/dbs/arch` (container layer); **no RMAN backups** in 7 days |
| Redo | 🟢 OK | 3 × 200 MB groups; 0 switches in the last 24h (uptime < 1 day); 1 member per group (INFO) |
| Memory & limits | 🟢 OK | SGA 1529 MB, PGA 5 MB (max 11), 0 over-allocations; processes 91/200 (46%), sessions 87/322 (27%) |
| Sessions & blocking | 🟢 OK | 1 active user session, none > 5 min; no blocking; no long-running calls |
| Workload (top SQL, waits) | 🟢 OK | Top SQL is SQLcl/MCP tooling only (≤ 1 s total); `db file sequential read` 0.16 ms, `log file sync` 3.52 ms |
| Objects & statistics | 🟡 WARN | No invalid objects; HR: 7 of 7 tables never analyzed (schema installed today, expected) |
| Alert log & jobs | 🟢 OK | No alert-log errors in 24h; no failed scheduler runs |
| Accounts | 🟢 OK | No locked, expired or soon-to-expire non-Oracle accounts |
| Configuration / licensing | 🔵 INFO | `control_management_pack_access` = `DIAGNOSTIC+TUNING` (default; informational on Free) |

## Findings

### 🟡 Archived redo has no space management and is lost if the container is removed
- **Evidence:** `instance`: log_mode = ARCHIVELOG. `fra`: no rows, so no FRA is configured
  (`parameters`: `db_recovery_file_dest` empty, size 0). `archiving`: LOG_ARCHIVE_DEST_1 VALID →
  `/opt/oracle/product/26ai/dbhomeFree/dbs/arch`, which is inside `$ORACLE_HOME`.
- **Why it matters:** In ARCHIVELOG mode, Oracle copies every filled redo log to the archive
  destination (`archiving`). Without an FRA (Oracle's managed recovery-file area) and backups,
  nothing ever deletes those copies. If the disk fills, the archiver stops and the database
  stalls on every commit. In this container image the path is in the writable layer, not on the
  `oracle-free-data` volume, so `docker rm` also deletes the logs you'd need for recovery.
- **Recommendation (not executed):** For a dev/demo box, choose one of:
  - Put an FRA on the data volume:
    ```sql
    -- as SYS in CDB root (service FREE)
    alter system set db_recovery_file_dest_size = 10G scope=both;
    alter system set db_recovery_file_dest = '/opt/oracle/oradata/FRA' scope=both;
    alter system set log_archive_dest_1 = 'LOCATION=USE_DB_RECOVERY_FILE_DEST' scope=both;
    ```
  - Or, if point-in-time recovery isn't needed, switch to NOARCHIVELOG (`shutdown immediate;
    startup mount; alter database noarchivelog; alter database open;`).

  Kept unfixed for the demo, as noted in CLAUDE.md.

### 🟡 No RMAN backups in the last 7 days
- **Evidence:** `backups`: no rows in `V$RMAN_BACKUP_JOB_DETAILS` for the last 7 days.
- **Why it matters:** No backup means no recovery from a lost datafile or a dropped volume.
  It also means archived logs are never backed up and purged (see previous finding). Rated WARN
  rather than CRIT because this is a demo box built today.
- **Recommendation (not executed):** After configuring an FRA, take a baseline backup and purge
  backed-up logs:
  ```
  rman target /
  RMAN> backup database plus archivelog delete input;
  ```

### 🟡 HR tables have never been analyzed
- **Evidence:** `stats`: HR has 0 stale and 7 never-analyzed tables, out of 7.
- **Why it matters:** Without statistics the optimizer uses dynamic sampling and defaults, so
  execution plans can be poor. This is expected for a schema installed today, before the
  nightly maintenance window has run.
- **Recommendation (not executed):** `exec dbms_stats.gather_schema_stats('HR');`, or wait for
  the automatic stats job.

### 🔵 Redo logs are not multiplexed
- **Evidence:** `redo`: groups 1–3 each have `members` = 1 (200 MB each).
- **Why it matters:** If the one copy of the current redo log is lost, committed transactions
  are lost. That's normal for a dev container but not for production.
- **Recommendation (not executed):** In production, add a second member to each group on a
  separate disk (`alter database add logfile member '...' to group 1;`).

### 🔵 Management-pack access enabled by default
- **Evidence:** `parameters`: `control_management_pack_access` = `DIAGNOSTIC+TUNING`
  (isdefault TRUE).
- **Why it matters:** This is informational on Oracle Free. On a licensed Enterprise Edition
  without the Diagnostics/Tuning Packs, this setting lets tools use AWR/ASH by accident, which is
  a licence exposure. The health check itself used no pack features.
- **Recommendation (not executed):** On EE systems without pack licences:
  `alter system set control_management_pack_access='NONE' scope=both;`

## Detail by check

**instance**

| instance | host | version | status | db status | started | uptime_days | CDB | container | log mode | open mode | role |
|---|---|---|---|---|---|---|---|---|---|---|---|
| FREE | 9c6b064276dd | 23.26.3.0.0 | OPEN | ACTIVE | 2026-10-06 13:29 | 0 | FREE | FREEPDB1 | ARCHIVELOG | READ WRITE | PRIMARY |

The instance is healthy. It was started about 80 minutes before the check, so cumulative stats are thin.

**pdbs**

| con_id | name | open_mode | restricted | size_mb |
|---|---|---|---|---|
| 3 | FREEPDB1 | READ WRITE | NO | 902 |

Only the connected PDB is visible from inside it. It's open and unrestricted.

**capacity**

| datafile_mb | user_datafile_mb | tempfile_mb |
|---|---|---|
| 882 | 72 | 20 |

72 MB of user data, far below the 9 GB warning level and the 12 GB Free cap.

**tablespaces**

| tablespace | contents | used_mb | alloc_mb | max_mb | used % of max |
|---|---|---|---|---|---|
| SYSAUX | PERMANENT | 401 | 420 | 937,097 | 0 |
| SYSTEM | PERMANENT | 289 | 290 | 936,967 | 0 |
| USERS | PERMANENT | 8 | 72 | 936,749 | 0 |
| UNDOTBS1 | UNDO | 8 | 100 | 33,554,432 | 0 |
| TEMP | TEMPORARY | 0 | 20 | 32,768 | 0 |

Bigfile autoextend maximums are theoretical. On Free, the 12 GB cap in `capacity` is the real limit.

**fra**: No rows, so no fast recovery area is configured.

**archiving**

| dest | status | destination | error | logs 24h | MB 24h |
|---|---|---|---|---|---|
| LOG_ARCHIVE_DEST_1 | VALID | /opt/oracle/product/26ai/dbhomeFree/dbs/arch | – | 0 | – |

The destination is valid but sits under `$ORACLE_HOME` in the container layer. No logs were
archived in the 24h window. Group 1 is marked archived, so the log predates this window.

**redo**

| group | thread | members | size_mb | status | archived |
|---|---|---|---|---|---|
| 1 | 1 | 1 | 200 | INACTIVE | YES |
| 2 | 1 | 1 | 200 | CURRENT | NO |
| 3 | 1 | 1 | 200 | UNUSED | YES |

switches_24h = 0, peak/hour = none. Redo volume is low and the log size is ample for this load.

**memory**

| metric | value |
|---|---|
| SGA total | 1529 MB |
| PGA allocated / max | 5 / 11 MB |
| PGA over-allocation count | 0 |
| sga_max_size / sga_target / memory_target | 1536M / 0 / 0 |
| pga_aggregate_target / limit | 512M / 2G |

No memory pressure.

**limits**

| resource | current | limit | % |
|---|---|---|---|
| processes | 91 | 200 | 46% |
| sessions | 87 | 322 | 27% |

Both are below 70%.

**sessions**

| type | status | sessions | user active > 5 min |
|---|---|---|---|
| BACKGROUND | ACTIVE | 86 | 0 |
| USER | ACTIVE | 1 | 0 |

The only user session is this health check.

**blocking**: No rows, so there is no blocking.

**long_running**: No rows, so no user calls have run longer than 60 s.

**top_sql**

| sql_id | module | execs | elapsed_s | text (trimmed) |
|---|---|---|---|---|
| 8mqmasy2r5sg0 | SQLcl | 952 | 1.0 | `declare FUNCTION ifelse …` (SQLcl internal) |
| gmsat725pn3ch | SQLcl-MCP | 42 | 0.1 | `DECLARE table_exists …` (MCP log setup) |
| 0ksjuubjvu2tp | claude-opus-5-5 | 42 | 0.1 | `DECLARE PRAGMA AUTONOMOUS_TRANSACTION …` (MCP log) |
| a1gd9m7g6xds8 | SQLcl | 56 | 0.1 | `dbms_metadata.set_transform_param …` |
| … | | | | 6 more rows, all SQLcl / MCP tooling, ≤ 0.1 s each |

There's no application workload yet. Everything here is tooling noise.

**waits**

| event | class | waits | time_s | avg_ms |
|---|---|---|---|---|
| db file sequential read | User I/O | 3781 | 0.6 | 0.16 |
| log file sync | Commit | 172 | 0.6 | 3.52 |
| resmgr:cpu quantum | Scheduler | 116 | 0.2 | 1.83 |
| latch: shared pool | Concurrency | 793 | 0.2 | 0.26 |
| enq: CR - block range reuse ckpt | Other | 72 | 0.1 | 1.96 |
| direct path sync | User I/O | 3 | 0.1 | 36.3 |

All are under the thresholds. `direct path sync` averages 36 ms but over only 3 waits.
`resmgr:cpu quantum` is the Free edition's CPU throttling (the resource manager caps CPU use).

**invalid_objects**: No rows, so there are no invalid objects.

**alert_log**: No rows, so no errors were logged in the last 24h. From a PDB, this view mainly shows this container's messages.

**backups**: No rows, so there were no RMAN backup jobs in the last 7 days.

**jobs**: No rows, so no scheduler jobs failed in the last 24h.

**users**: No rows, so no non-Oracle accounts are locked, expired or expiring within 14 days.

**stats**

| owner | stale | never analyzed | total |
|---|---|---|---|
| HR | 0 | 7 | 7 |

The HR sample schema was installed today and hasn't been analyzed yet.

**parameters**

| name | value | default |
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

`audit_trail=NONE` covers only legacy auditing. 23ai/26ai uses Unified Auditing instead.

## Method

- Read-only queries from `.claude/skills/db-health-check/queries.sql` (21 checks), run one by
  one through the SQLcl MCP server's `sql_run` tool. None errored.
- Standard `V$`/`DBA_` views only. No AWR, ASH, ADDM or SQL Monitor, so no
  Diagnostics/Tuning Pack use.
- **Scope:** connected to PDB `FREEPDB1` in CDB `FREE`. Most `V$` views (sessions, SQL, waits,
  alert log) are scoped to this PDB. Instance-wide items (`V$SGA`, `V$LOG`, `V$ARCHIVE_DEST`,
  `V$PROCESS`) cover the whole CDB. CDB root and PDB$SEED weren't checked directly.
- **Cumulative stats:** uptime is under one day (started 13:29), so `V$SQL`, `V$SYSTEM_EVENT`
  and the 24h redo/archive counts reflect very little activity.
- **Audit:** every statement is logged to `SYSTEM.DBTOOLS$MCP_LOG`, and the session is visible
  in `V$SESSION` as program `SQLcl-MCP`, module `claude-opus-5-5`.
