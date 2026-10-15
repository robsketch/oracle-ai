# Oracle Health Check: {cdb_name} / {connected_container}

| | |
|---|---|
| **Overall status** | 🟢 OK / 🟡 WARN / 🔴 CRIT (the worst area rating) |
| **Run at** | {YYYY-MM-DD HH:MM} (DB time) |
| **Connection** | `{connection}` → `{user}@{connect string}` |
| **Database** | {banner}, instance `{instance_name}` on `{host_name}` |
| **Up since** | {startup_time} ({uptime_days} days) |
| **Mode** | {log_mode}, {open_mode}, {database_role} |

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Instance & PDBs | 🟢 | … |
| Storage (tablespaces, Free cap) | | |
| Recovery (FRA, archiving, backups) | | |
| Redo | | |
| Memory & limits | | |
| Sessions & blocking | | |
| Workload (top SQL, waits) | | |
| Objects & statistics | | |
| Alert log & jobs | | |
| Accounts | | |
| Configuration / licensing | | |

## Findings

Ordered CRIT → WARN → INFO. One subsection per finding:

### 🔴/🟡/🔵 {short title}
- **Evidence:** the values from the query, with the check id
- **Why it matters:** one or two sentences
- **Recommendation (not executed):** what to do, with example SQL/commands where useful

## Detail by check

For each check id, in order: a compact table of the result (trimmed to the useful columns and
rows) or "No rows: {what that means}". Add a one-line interpretation under each.

## Method

- Read-only queries from `.claude/skills/db-health-check/queries.sql` ({n} checks), run via the
  SQLcl MCP server `sql_run` tool.
- Standard `V$`/`DBA_` views only. No AWR/ASH/ADDM or SQL Monitor (Diagnostics/Tuning Pack
  not used).
- Scope caveats (PDB vs CDB, cumulative-since-startup stats).
- Audit: statements logged to `DBTOOLS$MCP_LOG`; sessions visible in `V$SESSION` as program
  `SQLcl-MCP`.
- Any checks that errored, and their error text.
