# Oracle Health Check: FREE / FREEPDB1

| | |
|---|---|
| **Overall status** | 🔴 CRIT (driven by optimizer stats on a freshly installed HR schema; see finding 1) |
| **Run at** | 2026-10-06 14:46 (host time, BST) |
| **Connection** | `demo_system` → `system@localhost:1521/FREEPDB1` |
| **Database** | Oracle AI Database 26ai Free Release 23.26.3.0.0, instance `FREE` on `9c6b064276dd` (Docker container) |
| **Up since** | 2026-10-06 13:29 (0 days, i.e. started today) |
| **Mode** | ARCHIVELOG, READ WRITE, PRIMARY (force logging YES, flashback NO) |

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Instance & PDBs | 🟡 WARN | OPEN / ACTIVE, FREEPDB1 READ WRITE, not restricted; but uptime 0 days, so cumulative stats are thin |
| Storage (tablespaces, Free cap) | 🟢 OK | All tablespaces ~0% of max; user datafiles 72 MB of the 12 GB Free cap |
| Recovery (FRA, archiving, backups) | 🟡 WARN | ARCHIVELOG with **no FRA**; archive dest inside `$ORACLE_HOME` (container writable layer); no RMAN backups in 7 days |
| Redo | 🟢 OK | 3 × 200 MB groups, 0 switches in 24h |
| Memory & limits | 🟢 OK | SGA 1529 MB; PGA 6 MB (max 11 MB), 0 over-allocations; processes 91/200 (46%), sessions 87/322 (27%) |
| Sessions & blocking | 🟢 OK | 1 active user session (this check), no long-running calls, no blocking |
| Workload (top SQL, waits) | 🟢 OK | Top SQL is all SQLcl / MCP tooling; `db file sequential read` 0.16 ms, `log file sync` 2.91 ms |
| Objects & statistics | 🔴 CRIT | No invalid objects; but HR has 7/7 tables never analyzed (100%) |
| Alert log & jobs | 🟢 OK | No matching alert-log errors in 24h (PDB-scoped view); no failed scheduler runs |
| Accounts | 🟢 OK | No locked/expired/expiring non-Oracle accounts |
| Configuration / licensing | 🔵 INFO | `control_management_pack_access` = DIAGNOSTIC+TUNING (default; informational on Free) |

## Findings

### 🔴 HR schema has no optimizer statistics
- **Evidence (`stats`):** HR has `never_analyzed` = 7 of `total_tables` = 7 (100%), above the 50% CRIT threshold.
- **Why it matters:** Without table statistics the optimizer falls back to dynamic sampling and
  guesses, which can give poor execution plans. In practice this is expected right after
  installing a sample schema. The automatic stats job only gathers during the nightly
  maintenance window, and the instance was started today. For a 107-row schema the real-world
  risk is low. The rating follows the threshold rule, so read it with that context.
- **Recommendation (not executed):**
  ```sql
  exec dbms_stats.gather_schema_stats(ownname => 'HR');
  ```
  (`DBMS_STATS` is standard and needs no pack licence.)

### 🟡 ARCHIVELOG mode with no FRA, archiving into the container's writable layer
- **Evidence (`instance`, `fra`, `archiving`, `parameters`):** `log_mode` = ARCHIVELOG; `v$recovery_file_dest`
  returned no rows; `db_recovery_file_dest` empty / size 0; `LOG_ARCHIVE_DEST_1` = VALID,
  `/opt/oracle/product/26ai/dbhomeFree/dbs/arch`. 0 logs archived in the last 24h.
- **Why it matters:** Nothing manages or deletes archived logs. They grow without limit, and if
  the destination fills, the database stops processing transactions. The path is inside
  `$ORACLE_HOME`, which lives in the container's writable layer, **not** the `oracle-free-data`
  volume, so archived logs disappear on `docker rm` and can't be used for recovery.
- **Recommendation (not executed):** either set an FRA on the data volume:
  ```sql
  -- run in CDB root (service FREE) as SYSDBA
  alter system set db_recovery_file_dest_size = 10G scope=both;
  alter system set db_recovery_file_dest = '/opt/oracle/oradata/fra' scope=both;
  alter system set log_archive_dest_1 = 'LOCATION=USE_DB_RECOVERY_FILE_DEST' scope=both;
  ```
  or, for a pure demo/dev box, switch to NOARCHIVELOG (`shutdown immediate; startup mount;
  alter database noarchivelog; alter database open;`).

### 🟡 No RMAN backups in the last 7 days
- **Evidence (`backups`):** `v$rman_backup_job_details` returned no rows for the last 7 days.
- **Why it matters:** There is no recovery point if a datafile is lost or corrupted. Rated WARN,
  not CRIT, because this is a disposable demo container whose HR data can be reinstalled from
  `db-sample-schemas`.
- **Recommendation (not executed):** once an FRA exists, `rman target /` →
  `backup database plus archivelog;`, and schedule it if the box becomes long-lived.

### 🟡 Instance up less than a day
- **Evidence (`instance`):** started 2026-10-06 13:29, `uptime_days` = 0.
- **Why it matters:** `V$SQL`, `V$SYSTEM_EVENT` and the PGA high-water marks are cumulative since
  startup. The workload numbers in this report reflect only minutes of light activity.
- **Recommendation:** re-run the health check after a representative workload or a day's uptime.

### 🔵 `control_management_pack_access` = DIAGNOSTIC+TUNING
- **Evidence (`parameters`):** value `DIAGNOSTIC+TUNING`, `isdefault` = TRUE.
- **Why it matters:** On a licensed Enterprise Edition without the Diagnostics/Tuning Packs this
  default allows accidental use of AWR/ASH (licence exposure). On Oracle Free it is
  informational. This health check didn't touch any pack features.
- **Recommendation (not executed):** on unlicensed EE systems, `alter system set
  control_management_pack_access = 'NONE' scope=both;`.

### 🔵 `audit_trail` = NONE
- **Evidence (`parameters`):** `audit_trail` NONE (default).
- **Why it matters:** In 23ai/26ai traditional auditing is desupported and **unified auditing**
  is used instead, so this parameter doesn't mean "no auditing". Informational only.

## Detail by check

**instance**

| instance | host | version | status | db_status | startup | uptime_days | cdb | container | log_mode | open_mode | role |
|---|---|---|---|---|---|---|---|---|---|---|---|
| FREE | 9c6b064276dd | 23.26.3.0.0 | OPEN | ACTIVE | 2026-10-06 13:29 | 0 | FREE | FREEPDB1 | ARCHIVELOG | READ WRITE | PRIMARY |

Healthy and open. The host name is a container ID. Uptime under a day.

**pdbs**

| con_id | name | open_mode | restricted | size_mb |
|---|---|---|---|---|
| 3 | FREEPDB1 | READ WRITE | NO | 902 |

Only FREEPDB1 is visible because the connection is to the PDB. It is open read/write and not restricted.

**capacity**

| datafile_mb | user_datafile_mb | tempfile_mb |
|---|---|---|
| 882 | 72 | 20 |

72 MB user data, far below the 9 GB WARN / 12 GB Free cap.

**tablespaces**

| tablespace | contents | used_mb | alloc_mb | max_mb | used_pct_of_max |
|---|---|---|---|---|---|
| SYSAUX | PERMANENT | 401 | 420 | 937098 | 0 |
| SYSTEM | PERMANENT | 289 | 290 | 936968 | 0 |
| USERS | PERMANENT | 8 | 72 | 936750 | 0 |
| UNDOTBS1 | UNDO | 8 | 100 | 33554432 | 0 |
| TEMP | TEMPORARY | 0 | 20 | 32768 | 0 |

Bigfile autoextend tablespaces have a huge theoretical max. The real limit is the Free cap and disk space.

**fra**: No rows. No fast recovery area configured.

**archiving**

| dest_id | dest_name | status | destination | error | logs_24h | mb_24h |
|---|---|---|---|---|---|---|
| 1 | LOG_ARCHIVE_DEST_1 | VALID | /opt/oracle/product/26ai/dbhomeFree/dbs/arch | | 0 | — |

The destination is valid but sits inside `$ORACLE_HOME` (not the data volume). No archiving activity yet.

**redo**

| group# | thread# | members | size_mb | status | archived | switches_24h | peak/hour |
|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 200 | INACTIVE | YES | 0 | — |
| 2 | 1 | 1 | 200 | CURRENT | NO | 0 | — |
| 3 | 1 | 1 | 200 | UNUSED | YES | 0 | — |

No log switches in 24h. There is one member per group (no multiplexing), which is normal for Free/dev.

**memory**

| metric | value |
|---|---|
| SGA total (MB) | 1529 |
| PGA allocated / max (MB) | 6 / 11 |
| PGA over-allocation count | 0 |
| sga_max_size / sga_target / memory_target | 1536M / 0 / 0 |
| pga_aggregate_target / limit | 512M / 2G |

SGA is near the Free edition's ~1.5 GB SGA ceiling, which is expected. PGA use is minimal.

**limits**

| resource | current | limit | % |
|---|---|---|---|
| processes | 91 | 200 | 46% |
| sessions | 87 | 322 | 27% |

Both are below 70%. The counts are mostly background processes.

**sessions**

| type | status | sessions | user_active_over_5m |
|---|---|---|---|
| BACKGROUND | ACTIVE | 86 | 0 |
| USER | ACTIVE | 1 | 0 |

The single user session is this health check (SQLcl-MCP).

**blocking**: No rows. No blocking or blocked sessions.

**long_running**: No rows. No user calls active for more than 60 s.

**top_sql** (all rows are tooling noise)

| sql_id | module | execs | elapsed_s | avg_ms | text (trimmed) |
|---|---|---|---|---|---|
| 8mqmasy2r5sg0 | SQLcl | 952 | 1.0 | 1.1 | `declare FUNCTION ifelse ...` (SQLcl internal) |
| gmsat725pn3ch | SQLcl-MCP | 20 | 0.1 | 6.7 | MCP log table existence check |
| a1gd9m7g6xds8 | SQLcl | 56 | 0.1 | 1.1 | `dbms_metadata.set_transform_param` |
| 0ksjuubjvu2tp | claude-opus-5-5 | 20 | 0.1 | 2.6 | MCP log autonomous-txn block |
| … | | | | | 6 more SQLcl / MCP rows, all < 0.1 s |

There is no application workload yet. The total elapsed time across the top 10 is about 1.5 s.

**waits**

| event | class | waits | time_s | avg_ms |
|---|---|---|---|---|
| db file sequential read | User I/O | 3769 | 0.6 | 0.16 |
| log file sync | Commit | 149 | 0.4 | 2.91 |
| resmgr:cpu quantum | Scheduler | 116 | 0.2 | 1.83 |
| latch: shared pool | Concurrency | 793 | 0.2 | 0.26 |
| direct path sync | User I/O | 3 | 0.1 | 36.3 |

All are well under the thresholds. `resmgr:cpu quantum` is the Free edition's CPU cap (Resource Manager) at work. `direct path sync` has only 3 waits, so it isn't significant.

**invalid_objects**: No rows. There are no invalid objects in any schema.

**alert_log**: No rows. No ORA-/TNS-/error lines in the last 24h *as visible from FREEPDB1*. From a PDB, `V$DIAG_ALERT_EXT` may not show CDB-root messages, so confirm from a CDB-root connection.

**backups**: No rows. No RMAN backup jobs in the last 7 days.

**jobs**: No rows. No failed scheduler job runs in 24h.

**users**: No rows. No locked, expired or soon-to-expire non-Oracle accounts.

**stats**

| owner | stale | never_analyzed | total |
|---|---|---|---|
| HR | 0 | 7 | 7 |

The freshly installed HR schema hasn't been analyzed yet (see finding 1).

**parameters**

| name | value | default? |
|---|---|---|
| audit_trail | NONE | Y |
| compatible | 23.6.0 | N |
| control_management_pack_access | DIAGNOSTIC+TUNING | Y |
| db_recovery_file_dest / _size | (empty) / 0 | Y |
| open_cursors | 300 | N |
| optimizer_features_enable | 23.1.0 | Y |
| processes / sessions | 200 / 322 | N / Y |
| statistics_level | TYPICAL | Y |
| undo_retention | 900 | Y |

Sensible defaults for a dev box. The FRA is not set.

## Method

- Read-only queries from `.claude/skills/db-health-check/queries.sql` (21 checks), run one by one via
  the SQLcl MCP server `sql_run` tool. All 21 completed and none errored.
- Standard `V$`/`DBA_` views only. No AWR/ASH/ADDM or SQL Monitor (Diagnostics/Tuning Pack
  not used). No extra queries beyond `queries.sql`.
- **Scope:** connected to PDB `FREEPDB1` as SYSTEM. `V$SESSION`, `V$SQL`, `DBA_*`, `V$DIAG_ALERT_EXT`
  and `V$SYSTEM_EVENT` are scoped to FREEPDB1. `V$SGA`, `V$LOG`, `V$ARCHIVE_DEST` and `V$INSTANCE`
  reflect the whole CDB. CDB-root-level items (root tablespaces, root alert messages) were not
  checked because no connection to service `FREE` exists yet.
- **Cumulative stats:** the instance has been up less than a day, so top SQL and wait figures carry little weight.
- **Timestamp:** taken from the host clock (BST). The DB startup time is in the container's clock,
  which may be UTC.
- **Audit:** each statement was logged to `SYSTEM.DBTOOLS$MCP_LOG`. The session appears in
  `V$SESSION` as program `SQLcl-MCP` with module `claude-opus-5-5`.
