#!/usr/bin/env python3
"""PreToolUse guard for the awr-analyst agent (.claude/agents/awr-analyst.md).

Reads the hook JSON on stdin. A call that passes is approved outright, so the agent runs
without permission prompts. Exit 2 blocks the call, and the stderr message goes back to the
agent. Bash may run only the preflight, AWR and extractor commands below, with no shell
operators. Write may only create Markdown files under reports/. SQLcl MCP may connect only as
the read-only dbmon users and run only tagged SELECT/WITH statements. The approval comes from
this hook, so it applies to this agent only, not to the main session.
"""
import json
import os
import re
import sys

ALLOWED_BASH = [
    r"scripts/db-preflight\.sh",
    r"scripts/awr-report\.sh(?: --html)?(?: \d+ \d+)?",  # never --snap: it writes to the DB
    r"python3 -I \.claude/skills/db-diag-review/extract_report\.py [\w./-]+(?: --days \d+)?",
    r"docker (?:ps|inspect)(?: [\w.{}' -]+)?",
    r"docker logs --tail \d+ oracle-free",
    r"date(?: [+%\w:' -]+)?",
    r"ls(?: -l)?(?: [\w./*-]+)*",
    r"mkdir -p reports(?:/awr)?",
]
SHELL_OPERATORS = re.compile(r"[;&|`<>\n]|\$\(")
READONLY_CONNECTIONS = {"demo_dbmon_cdb", "demo_dbmon"}


def block(msg):
    print(f"awr-analyst guard: {msg}", file=sys.stderr)
    sys.exit(2)


event = json.load(sys.stdin)
tool = event.get("tool_name", "")
args = event.get("tool_input", {})
proj = os.environ.get("CLAUDE_PROJECT_DIR") or event.get("cwd", "")

if tool == "Bash":
    cmd = args.get("command", "").strip()
    if proj:
        cmd = cmd.replace(proj.rstrip("/") + "/", "")  # accept absolute paths into the project
    if SHELL_OPERATORS.search(cmd):
        block("no shell operators (; & | > < ` $( or newlines). Run one allowed command per call.")
    if not any(re.fullmatch(p, cmd) for p in ALLOWED_BASH):
        block(f"command not on the allowlist: {cmd!r}. Allowed: preflight, awr-report.sh "
              "(no --snap), extract_report.py, docker ps/inspect/logs, date, ls, mkdir -p reports.")
elif tool == "Write":
    path = os.path.realpath(args.get("file_path", ""))
    reports = os.path.realpath(os.path.join(proj, "reports")) + os.sep
    if not (path.startswith(reports) and path.endswith(".md")):
        block(f"Write is limited to Markdown files under {reports} (got {path}).")
elif tool == "mcp__sqlcl__connect":
    if args.get("connection_name") not in READONLY_CONNECTIONS:
        block(f"connect only to {sorted(READONLY_CONNECTIONS)} (the read-only monitoring users).")
elif tool == "mcp__sqlcl__sql_run":
    sql = args.get("sql", "").strip()
    if not re.match(r"(?is)(select|with)\b", sql) or "/* db-diag-review */" not in sql:
        block("sql_run accepts only SELECT/WITH statements from queries.sql carrying the "
              "/* db-diag-review */ tag.")
elif tool not in ("mcp__sqlcl__disconnect", "mcp__sqlcl__connections_list"):
    sys.exit(0)  # not ours to judge: normal permission flow

print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "awr-analyst guard: on the allowlist"}}))
sys.exit(0)
