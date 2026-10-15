# Oracle AI-for-DBA PoC (Version 1)

## Goal
Proof of concept for Version 1: Claude Code acting as an Oracle DBA assistant.
- Claude Code connects to a local Oracle AI Database 26ai Free instance through the
  **SQLcl MCP server** (`sql -mcp`).
- A `/db-health-check` skill runs standard diagnostic queries and produces a formatted report.
- **Licensing (changed 2026-10-07, see `LICENSING.md`):** AWR (`DBA_HIST_*`,
  `DBMS_WORKLOAD_REPOSITORY`) is **allowed on Oracle Database Free only**, because Free includes
  the Diagnostics Pack. It's gated: check `V$VERSION`/`V$INSTANCE.EDITION` says Free first
  (`edition_gate` check, `scripts/awr-report.sh`). On any other edition, AWR/ASH/ADDM is a paid
  option (EE) or unavailable (SE2), so use only standard `V$`/`DBA_`/`GV$` views and Statspack
  unless someone confirms the licence. `/db-health-check` stays base-views-only. No Tuning Pack
  (`DBMS_SQLTUNE`, SQL Monitor) anywhere.
- Demo is Friday 2026-10-09.

The developer is a kdb+/q engineer, strong on Linux/Docker/shell but new to Oracle. Explain
Oracle-specific concepts briefly when they come up.

## Environment (set up 2026-10-06)
Runs on **WSL2 Ubuntu 24.04** (not macOS), with Docker via snap.

| Component | Detail |
|---|---|
| Database | Container `oracle-free`, image `container-registry.oracle.com/database/free:latest` (26ai, 23.26.3) |
| Port | `localhost:1521` |
| Data volume | Docker named volume `oracle-free-data` → `/opt/oracle/oradata` |
| CDB / PDB | CDB `FREE` (service `FREE`); application PDB **`FREEPDB1`** (service `FREEPDB1`) |
| Passwords | `./.env` (mode 600): `ORACLE_PWD` (SYS/SYSTEM/PDBADMIN), `HR_PWD`, `DBMON_PWD`, `CDBMON_PWD` (C##DBMON) and `PERFSTAT_PWD` (Statspack). Never print or commit them. |
| Java | Temurin 21, user-local at `~/.local/opt/java` (no sudo needed) |
| SQLcl | 26.3 at `~/.local/opt/sqlcl` (MCP needs 25.2 or later) |
| PATH | Marked block `oracle-ai PoC` in `~/.bashrc` sets `JAVA_HOME` and PATH |
| Sample schemas | `./db-sample-schemas` (clone of oracle-samples/db-sample-schemas); HR installed into FREEPDB1 |

## Saved SQLcl connections
Stored in `~/.dbtools/connections` (passwords saved, so no prompt):
- **`demo_hr`**: `hr@localhost:1521/FREEPDB1`, HR sample schema (employees = 107 rows)
- **`demo_system`**: `system@localhost:1521/FREEPDB1`, DBA-level account inside the PDB
- **`demo_dbmon`**: `dbmon@localhost:1521/FREEPDB1`, read-only monitoring user
  (`SELECT_CATALOG_ROLE` + `V_$DIAG_ALERT_EXT`; password `DBMON_PWD` in `.env`). Runs all 21
  health checks and can't write. It has no `DBTOOLS$MCP_LOG` table, so the MCP audit log
  isn't written for it. See setup.md step 4a. Also has SELECT on the `PERFSTAT.STATS$*` tables.
- **`demo_dbmon_cdb`**: `c##dbmon@localhost:1521/FREE`, read-only **common user in the CDB root**
  (`CONTAINER_DATA=ALL`, `V$DIAG_*` grants, `EXECUTE ON DBMS_WORKLOAD_REPOSITORY` for AWR
  reports, which also lets it create/drop AWR snapshots), so it sees the whole instance's alert log, traces
  and incidents. From a PDB you only see that PDB's entries. See setup.md step 4b.

Usage: `sql -name demo_hr`, or `connmgr list` inside SQLcl. The MCP server refers to
connections by these names.

Note: `demo_system` connects to the **PDB**, so `V$` views are scoped to FREEPDB1. Instance-wide
views (e.g. `V$SGA`, `V$INSTANCE`) still work. For CDB-root-level reads use `demo_dbmon_cdb`.

## setup.md runbook (keep it updated)
`setup.md` is the repeatable setup runbook. **Whenever the environment changes** (new
container config, connections, MCP servers, skills, installs), update the relevant numbered
section with copy-pasteable commands **and** add a dated entry under its `## Change log`.
Never write real passwords into it; reference `.env` instead.

It's also the onboarding script: a new user types `read setup.md` and the agent follows its
**Agent playbook** (asks for the project path, runs the status check, then works through the
remaining steps). On a new machine, don't assume the environment described here exists; run
setup.md's status check first. Keep every setup block safe to re-run and add a **Done when**
check to any new step.

## Common commands
```bash
docker start oracle-free / docker stop oracle-free
docker logs -f oracle-free                    # wait for "DATABASE IS READY TO USE!"
docker inspect -f '{{.State.Health.Status}}' oracle-free
sql -name demo_hr                             # interactive
echo "select count(*) from employees;" | sql -S -name demo_hr
```

## Gotchas
- SQLcl `ACCEPT ... HIDE` prompts don't read piped stdin. To script `hr_install.sql`, `DEFINE`
  the variables (`pass`, `tbs`, `overwrite_schema`) and strip the `ACCEPT` lines.
- Pass passwords via stdin or `.env`, never on the `sql` command line (they'd show in `ps`).

## SQLcl MCP server (registered 2026-10-06, moved to project scope 2026-10-07)
Defined as **`sqlcl`** in the project's **`.mcp.json`** (project scope, shareable, no secrets):
`${HOME}/.local/opt/sqlcl/bin/sql -mcp` with `JAVA_HOME=${HOME}/.local/opt/java`.
```bash
claude mcp get sqlcl          # status; needs one-time approval in Claude Code
```
Don't also add a `--scope local` `sqlcl`, because it would override the project one.
Full `${HOME}` paths and an explicit `JAVA_HOME` are used because Claude Code doesn't source `~/.bashrc`.
Tools (SQLcl 26.3): `connections_list`, `connect` (by saved name, case-sensitive), `disconnect`,
`sql_run`, `sqlcl_run`, `schema_information`, `context_retrieve`, `request_status`,
`annotation_generate`, `skills_sync`. Typical flow: `connect` to `demo_system` → `sql_run`.
Tool names have changed between SQLcl releases (e.g. older `list-connections`). Check
`tools/list` rather than assuming.

## /db-health-check skill
`.claude/skills/db-health-check/`: `SKILL.md` (workflow, rules, thresholds), `queries.sql`
(21 tagged read-only checks), `report-template.md`. Output goes to `reports/`. See setup.md
step 8. If you edit `queries.sql`, re-test every check against `demo_system` before relying on
it. Keep checks PDB-safe (e.g. `V$RESOURCE_LIMIT` is empty in a PDB).

Known real finding, kept unfixed for the demo: ARCHIVELOG with no FRA, archiving to
`$ORACLE_HOME/dbs/arch` in the container layer.

## /db-diag-review skill
`.claude/skills/db-diag-review/`: reviews the alert log, ADR incidents and trace files (via
`demo_dbmon_cdb`) and workload snapshots: AWR on Free (via `demo_dbmon_cdb` and
`scripts/awr-report.sh` → `reports/awr/`), else Statspack (via `demo_dbmon`). Then it writes a RAG report to
`reports/db-diag-*.md`. File mode (`/db-diag-review <path>`) runs `extract_report.py` on an
AWR/Statspack report, alert log or trace file instead. See setup.md step 9.
- **Statspack** (schema `PERFSTAT` in FREEPDB1) is the free stand-in for AWR. It doesn't work in
  CDB$ROOT. Hourly snapshots aren't scheduled. `scripts/demo-diag-load.sh` takes a snapshot
  pair around a workload that includes a deliberate deadlock.
- AWR: hourly automatic snapshots, kept 8 days, in the CDB root (whole instance). Generate
  reports with `scripts/awr-report.sh [--snap] [--html] [b e]`, which refuses on non-Free unless
  `AWR_LICENSED=1`. `extract_report.py` is tested on real 26ai AWR text and HTML. Reading an
  AWR *file* someone else generated is always fine.
- Never select a whole trace file via `V$DIAG_TRACE_FILE_CONTENTS`, since some are 30k+ lines.
  Use line windows.
- Real findings kept unfixed for the demo: crash recovery at every startup (`docker stop`'s
  10 s timeout kills Oracle; the fix is `docker stop -t 120`) and ORA-00800 Set Priority Failed
  (container lacks `--cap-add=SYS_NICE`).

## awr-analyst agent (added 2026-10-08)
`.claude/agents/awr-analyst.md`: a subagent that preloads `db-diag-review`, runs
`scripts/db-preflight.sh` first (starts `oracle-free` if it's down, checks `demo_dbmon_cdb`), then
returns only the scorecard, top findings and report path. Environment gotchas live in the agent
prompt, not the skill, so keep the skill portable. `scripts/agent-guard.py` is its PreToolUse
hook. It allowlists Bash/Write/SQLcl-MCP calls (dbmon connections, tagged SELECTs only) and
auto-approves them, so the agent runs without prompts and the main session gains no
permissions. See setup.md step 9f. If you add commands the agent needs, update the guard's
allowlist and the agent prompt together.

## Web front end (added 2026-10-15)
`webui/server.py` (stdlib, `127.0.0.1:8765`) + `webui/index.html`: a browser UI that runs the
agent headless with `claude -p --agent awr-analyst --output-format stream-json` and streams
progress over SSE. Live-DB mode or file mode (uploads go to `reports/uploads/`). It depends on the
guard hook auto-approving, so if you change the agent's commands, test a headless run too. See
setup.md step 9g. Start it with `python3 webui/server.py`.

## Next steps
- Make `db-diag-review` fully portable: move `scripts/awr-report.sh` into the skill folder
  (`${CLAUDE_SKILL_DIR}`) and pass connection names in as arguments rather than defaults.
- Get a real (sanitised) AWR report from an EE system via the principal DBA, to check file-mode
  parsing beyond 26ai Free output (older releases, RAC).
- Possibly a demo script that injects problems (blocking lock, invalid object, filling
  tablespace) so the health check has something to find live.
