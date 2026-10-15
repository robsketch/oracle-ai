# Oracle Health Check: FREE / FREEPDB1

| | |
|---|---|
| **Overall status** | 🟡 WARN |
| **Run at** | 2026-10-07 07:56 (DB time, UTC; 08:56 BST) |
| **Connection** | `demo_system` → `system@localhost:1521/FREEPDB1` |
| **Database** | Oracle AI Database 26ai Free Release 23.26.3.0.0, instance `FREE` on `9c6b064276dd` (Docker container) |
| **Up since** | 2026-10-07 07:35 (0 days, about 21 minutes) |
| **Mode** | ARCHIVELOG, READ WRITE, PRIMARY (force logging YES, flashback NO) |

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Instance & PDBs | 🟢 | Instance OPEN/ACTIVE; FREEPDB1 READ WRITE, not restricted |
| Storage (tablespaces, Free cap) | 🟢 | All tablespaces 0% of max; user data 72 MB of the 12 GB Free cap |
| Recovery (FRA, archiving, backups) | 🟡 | ARCHIVELOG with no FRA; archiving to `$ORACLE_HOME/dbs/arch` (container layer); no RMAN backups in 7 days |
| Redo | 🟢 | 3 × 200 MB groups; 1 switch in 24h, peak 1/hour |
| Memory & limits | 🟢 | SGA 1529 MB; PGA 40 MB (max 240), 0 over-allocations; processes 99/200 (50%), sessions 95/322 (30%) |
| Sessions & blocking | 🟢 | 7 user sessions, none active > 60 s; no blocking |
| Workload (top SQL, waits) | 🟢 | Light load; `db file sequential read` 0.1 ms, `log file sync` 1.87 ms |
| Objects & statistics | 🟢 | No invalid objects; HR stats fresh (07:35); only the MCP log table is unanalyzed |
| Alert log & jobs | 🟢 | No alert-log errors and no failed scheduler jobs in 24h |
| Accounts | 🟢 | No locked, expired or soon-expiring application accounts |
| Configuration / licensing | 🔵 | `control_management_pack_access` = DIAGNOSTIC+TUNING (informational on Free) |

## Findings

### 🟡 Archived redo goes to the container layer, with no FRA and no backups
- **Evidence:** `instance`: `log_mode` ARCHIVELOG. `fra`: no rows, so no fast recovery area
  is configured (`db_recovery_file_dest` empty, size 0). `archiving`: `LOG_ARCHIVE_DEST_1`
  VALID → `/opt/oracle/product/26ai/dbhomeFree/dbs/arch`, 1 log / 62 MB in 24h.
  `backups`: no RMAN jobs in 7 days.
- **Why it matters:**
  - That path is inside `$ORACLE_HOME`, in the container's writable layer, not on the
    `oracle-free-data` volume. Archived logs are therefore lost on `docker rm`.
  - Without an FRA, Oracle never manages or deletes them, so they grow without limit and
    can eventually fill the disk. A full archive destination stops the database.
  - With no backups, the archived logs give no recovery benefit anyway.
  - The risk is low today (62 MB/day), but this is the most serious finding. Rated WARN
    rather than CRIT because this is a demo box.
- **Recommendation (not executed):**
  - On a demo/dev box, either switch to NOARCHIVELOG, or keep ARCHIVELOG and configure an FRA
    on the volume:
    ```sql
    -- as SYS in CDB root (FREE)
    alter system set db_recovery_file_dest_size = 10G scope=both;
    alter system set db_recovery_file_dest = '/opt/oracle/oradata/fra' scope=both;
    alter system set log_archive_dest_1 = 'LOCATION=USE_DB_RECOVERY_FILE_DEST' scope=both;
    ```
  - Then schedule RMAN backups (e.g. `backup database plus archivelog delete input;`).
  - Known and deliberately left unfixed for the demo (see CLAUDE.md).

### 🔵 Diagnostics/Tuning Pack access enabled (licensing awareness)
- **Evidence:** `parameters`: `control_management_pack_access` = `DIAGNOSTIC+TUNING`
  (default).
- **Why it matters:** this has no licensing impact on Oracle Free. On a licensed Enterprise
  Edition without the packs, this setting allows accidental use of AWR/ASH, which creates
  licence exposure.
- **Recommendation (not executed):** on unlicensed EE systems, set it to `NONE`
  (`alter system set control_management_pack_access = 'NONE' scope=both;`).

### 🔵 One table without optimizer statistics: `HR.DBTOOLS$MCP_LOG`
- **Evidence:** `stats`: HR has 0 stale and 1 never-analyzed of 8 tables. A follow-up query on
  `DBA_TAB_STATISTICS` (outside `queries.sql`) shows it is `DBTOOLS$MCP_LOG`. The 7 HR
  sample tables were analyzed at 07:35.
- **Why it matters:** the SQLcl MCP server created this audit table in HR's schema after the
  last statistics run. It only receives small inserts, so missing statistics are harmless.
  The nightly maintenance window will gather them.
- **Recommendation (not executed):** none needed. If wanted:
  `exec dbms_stats.gather_table_stats('HR', 'DBTOOLS$MCP_LOG');`

## Detail by check

**instance:** FREE on `9c6b064276dd`, 23.26.3.0.0, OPEN/ACTIVE, started 2026-10-07 07:35
(0 days), CDB FREE, connected to FREEPDB1, ARCHIVELOG, READ WRITE, PRIMARY, force logging
YES, flashback NO.
The instance is healthy. Very short uptime limits the cumulative stats (see Method).

**pdbs:**

| con_id | name | open_mode | restricted | size_mb |
|---|---|---|---|---|
| 3 | FREEPDB1 | READ WRITE | NO | 932 |

Only the PDB itself is visible from inside it.

**capacity:** datafiles 912 MB, user datafiles 72 MB, tempfiles 20 MB.
That's far below the Free edition's 12 GB user-data cap.

**tablespaces:**

| tablespace | contents | used_mb | alloc_mb | max_mb | used % of max |
|---|---|---|---|---|---|
| SYSAUX | PERMANENT | 417 | 440 | 936,304 | 0 |
| SYSTEM | PERMANENT | 295 | 300 | 936,164 | 0 |
| USERS | PERMANENT | 8 | 72 | 935,936 | 0 |
| UNDOTBS1 | UNDO | 44 | 100 | 33,554,432 | 0 |
| TEMP | TEMPORARY | 0 | 20 | 32,768 | 0 |

The bigfile tablespaces can autoextend to very large theoretical maximums. In practice the
Free cap and disk space are the real limits.

**fra:** No rows, so no fast recovery area is configured.

**archiving:**

| dest | status | destination | logs 24h | MB 24h |
|---|---|---|---|---|
| LOG_ARCHIVE_DEST_1 | VALID | /opt/oracle/product/26ai/dbhomeFree/dbs/arch | 1 | 62 |

The destination is healthy, but it's in the container layer (see Findings).

**redo:** 3 groups × 200 MB, 1 member each. Statuses are INACTIVE, INACTIVE and CURRENT.
1 switch in 24h, peak 1/hour.
The logs are well sized for this load. Single-member groups are normal for a dev box; on
production you would multiplex them.

**memory:** SGA 1529 MB (`sga_max_size` 1536M, `sga_target` 0). PGA allocated 40 MB, max
240 MB, 0 over-allocations (`pga_aggregate_target` 512M, `pga_aggregate_limit` 2G).
`memory_target` 0.
There's no memory pressure.

**limits:** processes 99/200 (50%), sessions 95/322 (30%).
Both are below the 70% threshold.

**sessions:**

| type | status | sessions | user active > 5 min |
|---|---|---|---|
| BACKGROUND | ACTIVE | 88 | 0 |
| USER | ACTIVE | 1 | 0 |
| USER | INACTIVE | 6 | 0 |

The one active user session is this health check.

**blocking:** No rows, so there is no blocking.

**long_running:** No rows, so no user calls have been active longer than 60 s.

**top_sql** (cumulative, very short uptime):

| sql_id | schema | module | execs | elapsed_s | avg_ms | sql_text (abridged) |
|---|---|---|---|---|---|---|
| dwdphdbzv36cf | HR | Oracle SQL Developer for VS Code/26.3.0 | 1 | 0.3 | 268.3 | object-browser query on `ALL_OBJECTS` |
| gmsat725pn3ch | HR | SQLcl-MCP | 43 | 0.1 | 3.4 | MCP log-table existence check |
| 0ksjuubjvu2tp | HR | claude-opus-5-5 | 43 | 0.1 | 2.7 | MCP log-table setup block |

The rest are MCP housekeeping (log inserts, NLS lookups).
Nothing is expensive. The top statement is the VS Code SQL Developer extension browsing HR's
objects, at 0.3 s.

**waits:**

| event | class | waits | time_s | avg_ms |
|---|---|---|---|---|
| external table read | User I/O | 2 | 2.2 | 1085.05 |
| db file sequential read | User I/O | 14,570 | 1.5 | 0.1 |
| enq: CR - block range reuse ckpt | Other | 99 | 0.3 | 2.85 |
| direct path read | User I/O | 1,255 | 0.3 | 0.2 |
| enq: KO - fast object checkpoint | Application | 54 | 0.2 | 3.8 |
| latch: shared pool | Concurrency | 661 | 0.2 | 0.23 |
| log file sync | Commit | 66 | 0.1 | 1.87 |

Total wait time is tiny. The `external table read` waits are almost certainly reads of the
alert log: `V$DIAG_ALERT_EXT` reads the XML log file as an external table, and the
`alert_log` check does exactly that. Single-block reads (0.1 ms) and commits (1.87 ms) are
well within thresholds.

**invalid_objects:** No rows, so there are no invalid objects.

**alert_log:** No rows, so there were no errors in the last 24h.

**backups:** No rows, so there were no RMAN backups in 7 days (see Findings).

**jobs:** No rows, so no scheduler jobs failed in 24h.

**users:** No rows, so no application accounts are locked, expired or expiring within 14
days. `DBMON` expires 2027-04-05.

**stats:**

| owner | stale | never analyzed | total |
|---|---|---|---|
| HR | 0 | 1 | 8 |

The unanalyzed table is `DBTOOLS$MCP_LOG` (see Findings).

**parameters:**

| name | value | default |
|---|---|---|
| audit_trail | NONE | yes |
| compatible | 23.6.0 | no |
| control_management_pack_access | DIAGNOSTIC+TUNING | yes |
| db_recovery_file_dest | (empty) | yes |
| db_recovery_file_dest_size | 0 | yes |
| open_cursors | 300 | no |
| optimizer_features_enable | 23.1.0 | yes |
| processes | 200 | no |
| sessions | 322 | yes |
| statistics_level | TYPICAL | yes |
| undo_retention | 900 | yes |

`audit_trail` = NONE turns off only the legacy traditional audit. 23ai uses unified
auditing, which this parameter doesn't control.

## Method

- Read-only queries from `.claude/skills/db-health-check/queries.sql` (21 checks), run via
  the SQLcl MCP server `sql_run` tool. All 21 ran without errors.
- One supplementary read-only query on standard view `DBA_TAB_STATISTICS`, to identify the
  unanalyzed HR table.
- Standard `V$`/`DBA_` views only. No AWR/ASH/ADDM or SQL Monitor (Diagnostics/Tuning Pack
  not used).
- **Scope:** connected to PDB `FREEPDB1`. Most `V$` views show this container only.
  `V$SGA`, `V$LOG`, `V$ARCHIVE_DEST` and the parameters reflect the whole CDB `FREE`. The CDB
  root itself wasn't checked.
- **Uptime caveat (INFO):** the instance started about 21 minutes before the check, so
  `V$SQL` and `V$SYSTEM_EVENT` contain very little history and the 24h redo/archive counts
  cover only part of a day.
- **Audit:** statements logged to `SYSTEM.DBTOOLS$MCP_LOG`. The session is visible in
  `V$SESSION` as program `SQLcl-MCP`, module `claude-opus-5-5`.
