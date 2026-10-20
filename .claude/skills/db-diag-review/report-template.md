# Oracle Diagnostic Review: {db_name} ({scope})

| | |
|---|---|
| **Overall status** | 🟢 OK / 🟡 WARN / 🔴 CRIT (the worst area rating) |
| **Run at** | {YYYY-MM-DD HH:MM} |
| **Sources** | MCP: `{cdb connection}` (alert log, traces, incidents, AWR on Free), `{pdb connection}` (Statspack). Or file: `{path}` ({detected type}) |
| **Window** | requested: {from} → {to} UTC (or "last {days} days") · alert log / incidents / traces: that window · workload: {AWR|Statspack} snaps {begin}–{end} ({begin_time} → {end_time} UTC, {elapsed}; FULL/PARTIAL cover), one entry per pair |
| **Database** | {version}, instance `{instance_name}` on `{host_name}`, {num_cpus} CPUs |

## Summary

Three to five sentences in plain English: what's wrong, how serious it is, and what to do
first. Write for a DBA who has 30 seconds.

## Scorecard

| Area | Status | Key evidence |
|---|---|---|
| Critical errors (ORA-600/7445/4031/corruption) | | |
| ADR incidents | | |
| Instance lifecycle (restarts, crash recovery) | | |
| Application errors (deadlocks, 1555, space) | | |
| Redo / log writer | | |
| Workload: CPU | | |
| Workload: parsing | | |
| Workload: waits & locking | | |
| Workload: I/O & efficiency | | |

## Timeline

Merged, time-ordered view of the notable events across sources (restarts, incidents,
errors, the Statspack window). One line each: `time | source | event`.

## Findings

Ordered CRIT → WARN → INFO. One subsection per finding:

### 🔴/🟡/🔵 {short title}
- **Evidence:** values, message text, trace file name + excerpt lines, check ids
- **What it means:** plain-English explanation (Oracle concepts explained briefly)
- **Recommendation (not executed):** concrete next steps / commands

## Workload profile (Statspack / AWR)

- Header: window, DB time, DB CPU, average active sessions
- Top timed events table (event, waits, time, avg ms, % DB time)
- Load profile highlights (per second / per transaction)
- Efficiency ratios
- Top SQL (sql_id, module, execs, elapsed, CPU, short text), noise filtered out
- One paragraph: "where did the time go?"

## Trace excerpts

For each trace examined: file, process type, container, signature, and the 5–15 most telling
lines in a code block, with a short interpretation.

## Method

- MCP mode: read-only queries from `.claude/skills/db-diag-review/queries.sql` via SQLcl MCP
  `sql_run` ({n} checks), with trace excerpts bounded to line windows.
  File mode: `extract_report.py` extract of `{path}`.
- Workload source: AWR report `reports/awr/awr_{begin}_{end}.txt` (allowed because the edition
  gate found Oracle Database **Free**, where the Diagnostics Pack is included; see
  `LICENSING.md`), **or** Statspack (free on every edition). Say which, and why. No ASH/ADDM
  or Tuning Pack. Alert/trace data from `V$DIAG_*`.
- Caveats: short Statspack window / hourly AWR window, PDB vs CDB scope, checks that errored or were skipped.
- Audit: sessions tagged `SQLcl-MCP` in `V$SESSION`. `DBTOOLS$MCP_LOG` isn't written for the
  read-only `dbmon` users.
