# Oracle Health Check: (unknown) / FREEPDB1 (expected)

| | |
|---|---|
| **Overall status** | ⚪ NOT ASSESSED (0 of 21 checks returned data) |
| **Run at** | 2026-10-07 08:47 BST (client time; the database time comes from the `instance` check, which failed) |
| **Connection** | `demo_hr` → `hr@localhost:1521/FREEPDB1` |
| **Database** | Oracle 23.26.3.0.0 (reported by the MCP `connect` call). Instance and host unknown |
| **Up since** | unknown |
| **Mode** | unknown |

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Instance & PDBs | ⚪ | `instance`, `pdbs`: ORA-00942 |
| Storage (tablespaces, Free cap) | ⚪ | `capacity`, `tablespaces`: ORA-00942 |
| Recovery (FRA, archiving, backups) | ⚪ | `fra`, `archiving`, `backups`: ORA-00942 |
| Redo | ⚪ | `redo`: ORA-00942 |
| Memory & limits | ⚪ | `memory`, `limits`: ORA-00942 |
| Sessions & blocking | ⚪ | `sessions`, `blocking`, `long_running`: ORA-00942 |
| Workload (top SQL, waits) | ⚪ | `top_sql`, `waits`: ORA-00942 |
| Objects & statistics | ⚪ | `invalid_objects`, `stats`: ORA-00942 |
| Alert log & jobs | ⚪ | `alert_log`, `jobs`: ORA-00942 |
| Accounts | ⚪ | `users`: ORA-00942 |
| Configuration / licensing | ⚪ | `parameters`: ORA-00942 |

⚪ means not assessed. It does **not** mean healthy. No conclusion about the database's
health can be drawn from this run.

## Findings

### 🟡 Connection lacks privileges for a health check
- **Evidence:** every check failed with `ORA-00942: table or view "SYS"."<view>" does not exist`
  (e.g. `V_$DATABASE`, `V_$SESSION`, `V_$PARAMETER`, `DBA_DATA_FILES`, `DBA_USERS`). The
  database reports the views as non-existent because `hr` has no privilege on them. Oracle
  answers that way so that it doesn't reveal objects a user can't access.
- **Why it matters:** `HR` is an application schema owner. It can query its own tables but
  not the data dictionary (`DBA_*`) or the dynamic performance views (`V$*`). This is correct,
  least-privilege behaviour for an application account, not a fault in the database.
- **Recommendation (not executed):**
  1. Re-run with the DBA connection: `/db-health-check demo_system`.
  2. For a dedicated, least-privilege monitoring account instead of SYSTEM (run as a DBA):
     ```sql
     create user dbmon identified by "<from .env>";
     grant create session, select_catalog_role to dbmon;
     -- then in SQLcl: conn -save demo_dbmon -savepwd dbmon@localhost:1521/FREEPDB1
     ```
     `SELECT_CATALOG_ROLE` gives read access to the `V$`/`DBA_` views with no ability to
     change anything. Don't grant it to `HR`, because application accounts should stay
     narrow.

## Detail by check

| # | Check | Result |
|---|---|---|
| 1 | instance | ORA-00942 `V_$DATABASE` |
| 2 | pdbs | ORA-00942 `V_$PDBS` |
| 3 | capacity | ORA-00942 `DBA_DATA_FILES` |
| 4 | tablespaces | ORA-00942 `DBA_DATA_FILES` |
| 5 | fra | ORA-00942 `V_$RECOVERY_FILE_DEST` |
| 6 | archiving | ORA-00942 `V_$ARCHIVED_LOG` |
| 7 | redo | ORA-00942 `V_$LOG_HISTORY` |
| 8 | memory | ORA-00942 `V_$SGA` |
| 9 | limits | ORA-00942 `V_$PROCESS` |
| 10 | sessions | ORA-00942 `V_$SESSION` |
| 11 | blocking | ORA-00942 `V_$SESSION` |
| 12 | long_running | ORA-00942 `V_$SESSION` |
| 13 | top_sql | ORA-00942 `V_$SQL` |
| 14 | waits | ORA-00942 `V_$SYSTEM_EVENT` |
| 15 | invalid_objects | ORA-00942 `DBA_USERS` |
| 16 | alert_log | ORA-00942 `V_$DIAG_ALERT_EXT` |
| 17 | backups | ORA-00942 `V_$RMAN_BACKUP_JOB_DETAILS` |
| 18 | jobs | ORA-00942 `DBA_SCHEDULER_JOB_RUN_DETAILS` |
| 19 | users | ORA-00942 `DBA_USERS` |
| 20 | stats | ORA-00942 `DBA_USERS` |
| 21 | parameters | ORA-00942 `V_$PARAMETER` |

The error names the first inaccessible object Oracle hit in each statement. Others in the
same statement may also be inaccessible.

## Method

- Read-only queries from `.claude/skills/db-health-check/queries.sql` (21 checks), sent
  verbatim via the SQLcl MCP server `sql_run` tool. SQLcl prefixes each with
  `/* LLM in use is claude-opus-5-5 */`.
- Standard `V$`/`DBA_` views only. No AWR/ASH/ADDM or SQL Monitor (Diagnostics/Tuning Pack
  not used). No supplementary queries were run.
- Skill argument was `localhost:1521/FREEPDB1 demo_hr`. It was resolved to saved connection
  `demo_hr`, whose connect string is `localhost:1521/FREEPDB1`.
- Scope: intended container FREEPDB1, but not confirmed, because `sys_context('USERENV',
  'CON_NAME')` was in the failed `instance` check.
- Audit: statements logged to `HR.DBTOOLS$MCP_LOG`; the session is visible in `V$SESSION`
  as program `SQLcl-MCP`.
- Errored checks: all 21 (see table above).
