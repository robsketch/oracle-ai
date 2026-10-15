# Setup Runbook: Oracle AI-for-DBA PoC

Repeatable steps to build the local environment: Oracle AI Database 26ai Free in Docker, SQLcl,
the HR sample schema, read-only monitoring users, Statspack, saved connections, and the SQLcl
MCP server registered with Claude Code.

This is a living document. Each change to the environment gets appended as a new dated section
at the end, under the Change log.

## Start here

**New user:** get a copy of the project folder, `cd` into it, start Claude Code with `claude`,
and type:

```
read setup.md
```

The agent asks where your project folder is, checks what's already installed, and then takes
you through each remaining step, explaining as it goes. It stops and hands over to you when a
step needs you: anything that needs `sudo`, approving the MCP server, and restarting Claude
Code. If you stop part-way through, type `read setup.md` again later. It re-checks what's done
and carries on from there.

**You need first:**
- Linux or WSL2 (built on WSL2 Ubuntu 24.04), x86_64 or arm64
- Docker installed, running, and usable **without sudo** (`docker info` works)
- `curl`, `unzip`, `git` and `tar`, plus Claude Code itself
- About 15 GB of free disk and 4 GB of RAM. The first run downloads about 11 GB and takes
  roughly 20 to 30 minutes in total.

Apart from installing Docker, no step needs sudo. Everything installs under `$HOME`, in a
Docker volume, or in the project folder.

**Running it by hand instead:** run the [preamble](#preamble) once in your terminal, then the
steps in the order given in playbook C.3. Every block is safe to re-run.

- **Host:** WSL2 Ubuntu 24.04, Docker 29.8 (snap).
- **Project folder:** `<PROJECT_DIR>` (written as `$PROJ` below; set per user, see the playbook)
- **Secrets:** generated into `$PROJ/.env` (mode 600, gitignored). Never put passwords on a
  command line, because they're visible in `ps` and shell history.

---

## Agent playbook

**If you are a coding agent and the user asked you to read this file, or to set up this
project, you are the onboarding guide. Follow this playbook.** The user may be new to Oracle,
so explain Oracle terms briefly when they first come up (CDB/PDB, schema, tablespace, common
user, Statspack and so on; the notes under each step help).

### A. Get the project path (always first)

1. If the `PROJ=` line in the [preamble](#preamble) still reads `PROJ=<PROJECT_DIR>`, **ask
   the user** for the absolute path of the project folder, i.e. the folder that holds this
   `setup.md`, `CLAUDE.md` and `.claude/`. Suggest the current working directory as the
   default. Don't guess, and don't reuse a path from another machine.
2. Check the answer: expand `~` and `$HOME` to a real absolute path, remove any trailing `/`,
   and confirm the folder exists and contains this `setup.md`. Confirm the final path with the
   user before going on.
3. Edit this file so it records where this machine's project lives. Replace `<PROJECT_DIR>`
   with that path on just two lines: the **Project folder** bullet in "Start here" and the
   `PROJ=` line in the preamble. Leave the placeholder in these instructions and in the change
   log alone.
4. If the `PROJ=` line already holds a real path, ask the user whether it's still right before
   using it. The file may have been copied from someone else's machine.

### B. How to run the commands

- **Start every command block with the preamble.** Each shell command you run may be a fresh
  shell: variables don't carry over, and `~/.bashrc` isn't read by non-interactive shells, so
  without the preamble `sql` and `java` won't be found and the passwords in `.env` won't be
  set.
- **Run the blocks as written.** Every setup block skips work that's already done, so
  re-running is safe. If a step only works after you change it, fix the step in this file and
  add a Change log entry. A routine onboarding run doesn't get a Change log entry.
- **Long-running commands:** the image pull in step 1 (about 10 GB, 5 to 20 minutes) and the
  wait for the database to become healthy. Give them a long timeout (10 minutes) or run them in
  the background and poll. Tell the user what's happening while they wait.
- **Secrets:** never print `.env` or any password, never `cat .env`, and never put a password
  on a command line. Refer to passwords by variable name (`ORACLE_PWD`, `HR_PWD`,
  `DBMON_PWD`, `CDBMON_PWD`, `PERFSTAT_PWD`).
- **Never invent a new password for an existing database.** If `.env` and the database
  disagree, follow "Passwords don't match" in [Troubleshooting](#troubleshooting).
- **Setup only.** Testing sections ("Test the queries…", "9d. Testing", headless `claude -p`
  runs, which cost money) and the demo workload (9c) aren't part of onboarding. Offer them at
  the end and don't run them unless the user asks.

### C. Take the user through it

1. **Overview.** In a few lines, tell the user what will be installed and where (Java and
   SQLcl in `~/.local/opt`, the database in Docker volume `oracle-free-data`, saved connections
   in `~/.dbtools`), the download size, and roughly how long it takes. Then do A.
2. **Status.** Run the [status check](#status-check) and show the result as a short table.
   Say which steps are left, then ask once: "OK to go ahead?" After that, run routine steps
   without asking again each time.
3. **Order:** 0, 1, 2, 3, 4, 4a, 4b, 5, 6, 9a, then 7 (which needs a restart), then 8. Step 9a
   runs before 7 so that everything that needs a shell is done before the restart.
4. **Each remaining step:** say in one or two sentences what it does and why, run its blocks,
   then run its **Done when** check and report pass or fail in one line. Skip steps that are
   already done.
5. **On failure:** stop. Show the relevant error lines (never secrets), work out the cause from
   the step's notes and [Troubleshooting](#troubleshooting), and suggest a fix. Don't go on to
   the next step until the check passes.
6. **Ask before:** editing `~/.bashrc` (optional, step 2), overwriting any existing file
   (`.env`, `.mcp.json`, `.gitignore`), dropping or re-creating a database user, resetting a
   password, any `docker rm` or `docker volume rm`, and anything under Teardown.
7. **Steps only the user can do.** Explain what's needed and give the exact command,
   suggesting they type it with a `!` prefix so it runs in this session:
   - installing Docker or getting `docker` to work without sudo (needs sudo)
   - approving the `sqlcl` MCP server and restarting Claude Code (step 7)
8. **Restart handoff (step 7).** Claude Code only loads MCP servers when it starts. Ask the
   user to exit (`/exit`), run `claude` again in the project folder, approve `sqlcl` if asked,
   and type `read setup.md` again. When you resume, the status check shows everything done;
   step 7 is finished when you have `mcp__sqlcl__*` tools available.
9. **Finish with step 8**, the end-to-end check through MCP. Then give a short summary: what's
   installed, that passwords are in `.env`, the day-to-day commands, and where Teardown is.
   Offer a first real use: `/db-health-check demo_dbmon`, or `scripts/demo-diag-load.sh`
   followed by `/db-diag-review`.

### Preamble

Start every command block with this:

```bash
PROJ=<PROJECT_DIR>     # replaced with the user's project path by the onboarding agent
cd "$PROJ"
export JAVA_HOME="$HOME/.local/opt/java"
export PATH="$HOME/.local/opt/sqlcl/bin:$JAVA_HOME/bin:$PATH"
[ -f .env ] && { set -a; . ./.env; set +a; }
```

### Status check

This only reads, so it's safe to run at any time. Run it after the preamble. Each line says
`done` or `TODO`, and it takes about 15 seconds.

```bash
sysdba() { docker exec -i oracle-free sqlplus -S / as sysdba 2>/dev/null; }
probe()  { echo "select 'PROBE'||'_OK' from ${2:-dual};" | sql -S -name "$1" 2>/dev/null | grep -q PROBE_OK; }
st()     { if eval "$2" >/dev/null 2>&1; then s=done; else s=TODO; fi; printf '%-5s %s\n' "$s" "$1"; }
st "0  Docker usable without sudo"         'docker info'
st "1  .env has ORACLE_PWD"                'grep -q "^ORACLE_PWD=" .env'
st "1  container oracle-free healthy"      '[ "$(docker inspect -f "{{.State.Health.Status}}" oracle-free)" = healthy ]'
st "2  Java 21"                            'java -version 2>&1 | grep -qE "version .21"'
st "2  SQLcl"                              'sql -V'
st "3  sample schemas cloned"              '[ -f db-sample-schemas/human_resources/hr_install.sql ]'
st "3  HR schema installed (107 rows)"     'printf "set heading off feedback off\nalter session set container=FREEPDB1;\nselect count(*) from hr.employees;\n" | sysdba | grep -qw 107'
st "4  connection demo_hr"                 'probe demo_hr'
st "4  connection demo_system"             'probe demo_system'
st "4a connection demo_dbmon + alert log"  'probe demo_dbmon "(select count(*) from v\$diag_alert_ext where rownum = 1)"'
st "4b connection demo_dbmon_cdb + traces" 'probe demo_dbmon_cdb "(select count(*) from v\$diag_trace_file where rownum = 1)"'
st "6  .gitignore covers .env"             'grep -qxF .env .gitignore'
st "9a Statspack readable by dbmon"        'probe demo_dbmon "(select count(*) from perfstat.stats\$snapshot)"'
st "9e AWR report grant for c##dbmon"      'probe demo_dbmon_cdb "(select 1 from all_procedures where object_name = '"'"'DBMS_WORKLOAD_REPOSITORY'"'"' and rownum = 1)"'
st "7  .mcp.json defines sqlcl"            'grep -q "\"sqlcl\"" .mcp.json'
st "8  skills present"                     '[ -f .claude/skills/db-health-check/queries.sql ] && [ -f .claude/skills/db-diag-review/queries.sql ]'
st "9f awr-analyst agent + preflight"     '[ -f .claude/agents/awr-analyst.md ] && [ -x scripts/db-preflight.sh ] && [ -f scripts/agent-guard.py ]'
echo "7  MCP tools loaded? Check inside Claude Code: /mcp, or the agent has mcp__sqlcl__* tools"
```

---

## 0. Pre-flight checks

Check what's already installed before installing anything.

```bash
uname -m                                    # x86_64 or aarch64
for c in docker curl unzip git tar; do command -v "$c" >/dev/null || echo "MISSING: $c"; done
docker info --format 'docker {{.ServerVersion}} mem={{.MemTotal}} cpus={{.NCPU}}' \
  || echo "Docker not usable without sudo: see Troubleshooting"
docker ps -a --format '{{.Names}}  {{.Status}}'; docker volume ls -q
ss -ltn | grep -q ':1521 ' && echo "port 1521 IN USE" || echo "port 1521 free"
free -h; df -h ~ "$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)"
```

**Done when:** nothing is reported missing, `docker info` works without sudo, port 1521 is
free (or already used by an `oracle-free` container from an earlier run), and there's at least
15 GB free for the Docker root and `~`.

Oracle Free caps itself at 2 GB RAM (SGA+PGA) and the image is about 10 GB on disk.

---

## 1. Run the database container

**1a. Safety check.** Run this first and stop if it prints `STOP`:

```bash
if docker volume inspect oracle-free-data >/dev/null 2>&1 && ! grep -q '^ORACLE_PWD=' .env 2>/dev/null; then
  echo "STOP: volume oracle-free-data already holds a database but .env has no ORACLE_PWD."
  echo "      A new password wouldn't match it. See 'Passwords don't match' in Troubleshooting."
else
  echo "OK to continue"
fi
```

**1b. Password and image.** The pull is about 10 GB, so it's long-running:

```bash
# SYS/SYSTEM/PDBADMIN password into .env, only if there isn't one already. Starting with a
# letter and using only alphanumerics avoids quoting problems.
umask 077; touch .env; chmod 600 .env
grep -q '^ORACLE_PWD=' .env || printf 'ORACLE_PWD=Ora%s1\n' "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)" >> .env

IMG=container-registry.oracle.com/database/free:latest
docker image inspect "$IMG" >/dev/null 2>&1 || docker pull "$IMG"
```

**1c. Volume and container, then wait until healthy:**

```bash
IMG=container-registry.oracle.com/database/free:latest
docker volume inspect oracle-free-data >/dev/null 2>&1 || docker volume create oracle-free-data
docker inspect oracle-free >/dev/null 2>&1 || docker run -d --name oracle-free \
  -p 1521:1521 \
  --env-file .env \
  -v oracle-free-data:/opt/oracle/oradata \
  "$IMG"
docker start oracle-free >/dev/null      # no-op if it's already running

# About 1 to 2 minutes on first boot (the image ships with pre-built datafiles)
timeout 600 bash -c 'until [ "$(docker inspect -f "{{.State.Health.Status}}" oracle-free)" = healthy ]; do sleep 5; done'
docker inspect -f '{{.State.Health.Status}}' oracle-free     # → healthy
```

**Done when:** the container reports `healthy`.

**Notes**
- The image label says `23.26.x`, which is Oracle's internal version number for **26ai**.
- **CDB vs PDB:** the instance is a container database (CDB, service `FREE`) that holds the
  shared processes, memory, redo and dictionary root. User data lives in a pluggable database
  (PDB). The image creates **`FREEPDB1`**, so connect to service `FREEPDB1` for application
  work.
- `ORACLE_PWD` only takes effect when the database is first created. Changing `.env` later
  doesn't change the database password.
- The named volume keeps the datafiles across `docker rm`. Running `docker volume rm
  oracle-free-data` destroys the database.

---

## 2. Install Java 21 and SQLcl (user-local)

SQLcl needs Java 17 or later. The MCP server (`sql -mcp`) needs SQLcl 25.2 or later.

```bash
mkdir -p ~/.local/opt && cd ~/.local/opt
case "$(uname -m)" in x86_64) JARCH=x64 ;; aarch64|arm64) JARCH=aarch64 ;; *) echo "unsupported CPU: $(uname -m)" ;; esac

# Eclipse Temurin JDK 21 (skipped if already installed)
if [ ! -x ~/.local/opt/java/bin/java ]; then
  curl -fsSL -o jdk.tgz "https://api.adoptium.net/v3/binary/latest/21/ga/linux/${JARCH}/jdk/hotspot/normal/eclipse"
  tar xzf jdk.tgz && rm jdk.tgz
  ln -sfn "$(ls -d ~/.local/opt/jdk-21* | head -1)" ~/.local/opt/java
fi

# SQLcl, latest (skipped if already installed)
if [ ! -x ~/.local/opt/sqlcl/bin/sql ]; then
  curl -fsSL -o sqlcl.zip "https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip"
  unzip -q sqlcl.zip && rm sqlcl.zip
fi

cd "$PROJ"
java -version      # openjdk 21.x
sql -V             # SQLcl 25.2 or later (26.3.0.0 as of 2026-10-06)
```

**Done when:** `java -version` shows 21 and `sql -V` shows 25.2 or later.

**Optional, so `sql` works in your own terminals** (agents: ask the user before running this,
because it edits `~/.bashrc`; the marked block makes it easy to remove later):

```bash
grep -q 'oracle-ai PoC' ~/.bashrc || cat >> ~/.bashrc <<'EOF'

# >>> oracle-ai PoC: Java + SQLcl (user-local) >>>
export JAVA_HOME="$HOME/.local/opt/java"
export PATH="$HOME/.local/opt/sqlcl/bin:$JAVA_HOME/bin:$PATH"
# <<< oracle-ai PoC <<<
EOF
```

It takes effect in new terminals, or after `source ~/.bashrc`.

**Gotcha:** Ubuntu's `~/.bashrc` returns early for non-interactive shells, so scripts, cron
jobs, `bash -c` and coding agents won't see this PATH. That's why every block here starts with
the preamble, and why the MCP registration in step 7 uses absolute paths.

On macOS (not tested with this runbook), use `brew install --cask temurin@21` instead of the
tarball. The SQLcl zip is the same on both.

---

## 3. Install the HR sample schema into FREEPDB1

```bash
[ -d db-sample-schemas ] || git clone --depth 1 https://github.com/oracle-samples/db-sample-schemas.git

# HR password into .env, only if there isn't one already
grep -q '^HR_PWD=' .env || printf 'HR_PWD=Hr%s9\n' "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 14)" >> .env
set -a; . ./.env; set +a
```

**Gotcha:** `hr_install.sql` asks three questions with `ACCEPT`, and the password prompt uses
`HIDE`. SQLcl can't read a hidden prompt from piped stdin, so a scripted install fails with
`ORA-20999: the HR password is mandatory`. It fails before creating anything, so it's harmless.

**Workaround:** pre-define the three variables and run a copy of the installer with the
`ACCEPT` lines removed. Skipped if HR is already installed:

```bash
if printf 'set heading off feedback off\nalter session set container=FREEPDB1;\nselect count(*) from hr.employees;\n' \
     | docker exec -i oracle-free sqlplus -S / as sysdba 2>/dev/null | grep -qw 107; then
  echo "HR already installed, skipping"
else
  cd "$PROJ/db-sample-schemas/human_resources"
  grep -v '^ACCEPT ' hr_install.sql > hr_install_noprompt.sql
  printf 'connect system/"%s"@localhost:1521/FREEPDB1
DEFINE pass = "%s"
DEFINE tbs = USERS
DEFINE overwrite_schema = no
@hr_install_noprompt.sql
' "$ORACLE_PWD" "$HR_PWD" | sql -S /nolog
  rm -f hr_install_noprompt.sql
  cd "$PROJ"
fi
```

**Done when:** the installer's verification shows regions 5, countries 25, departments 27,
locations 23, **employees 107**, jobs 19, job_history 10 (or it printed "already installed").
A log is written to `db-sample-schemas/human_resources/hr_install.log`.

**Notes**
- **Schema = user:** in Oracle, creating user `HR` creates the `HR` schema.
- **Tablespace:** a logical storage container backed by datafiles. `USERS` is the standard
  default for application data.
- `overwrite_schema = no` means a re-run won't drop an existing HR schema. To reinstall, run
  `hr_uninstall.sql` as SYSTEM first.
- The `docker exec ... sqlplus / as sysdba` check logs in as SYS using OS authentication
  inside the container, so it needs no password.

---

## 4. Save named SQLcl connections

`-replace` overwrites a saved connection of the same name, so this is safe to re-run.

```bash
printf 'conn -save demo_hr -savepwd -replace hr/"%s"@localhost:1521/FREEPDB1
conn -save demo_system -savepwd -replace system/"%s"@localhost:1521/FREEPDB1
connmgr list
exit
' "$HR_PWD" "$ORACLE_PWD" | sql -S /nolog
```

**Done when:** both connections work:

```bash
echo "select count(*) from employees;" | sql -S -name demo_hr                 # 107
echo "select name, open_mode from v\$pdbs;" | sql -S -name demo_system      # FREEPDB1 READ WRITE
```

| Name | User | Connect string | Purpose |
|---|---|---|---|
| `demo_hr` | hr | `localhost:1521/FREEPDB1` | Sample application schema |
| `demo_system` | system | `localhost:1521/FREEPDB1` | DBA-level account inside the PDB |
| `demo_dbmon` | dbmon | `localhost:1521/FREEPDB1` | Read-only monitoring account for health checks and Statspack (steps 4a, 9a) |
| `demo_dbmon_cdb` | c##dbmon | `localhost:1521/FREE` | Read-only common user in the CDB root for alert log and traces (step 4b) |

- Connections are stored in `~/.dbtools/connections/` with saved passwords. The MCP server
  looks them up by name, and names are case-sensitive.
- `demo_system` is scoped to the PDB. `demo_dbmon_cdb` connects to the root (service `FREE`).

### 4a. Read-only monitoring user `dbmon`

A least-privilege account for health checks. It can read the data dictionary and `V$` views
but can't change anything, so the database itself enforces read-only access rather than the
skill's rules alone.

```bash
# 1. Password into .env (only if not already there)
grep -q '^DBMON_PWD=' .env || echo "DBMON_PWD=Mon_$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)9" >> .env
set -a; . ./.env; set +a

# 2. Create the user as SYSTEM in FREEPDB1 (skipped if it already exists)
if echo "select 'DBMON'||'_EXISTS' from dba_users where username = 'DBMON';" \
     | sql -S -name demo_system | grep -q DBMON_EXISTS; then
  echo "dbmon already exists, skipping create"
else
  sql -S -name demo_system <<EOF
create user dbmon identified by "${DBMON_PWD}";
grant create session to dbmon;
grant select_catalog_role to dbmon;
EOF
fi

# 3. The alert-log view isn't in SELECT_CATALOG_ROLE, and only SYS can grant it.
#    "/ as sysdba" uses OS authentication inside the container, so no password is needed.
#    Re-granting is harmless.
docker exec -i oracle-free sqlplus -S / as sysdba <<'EOF'
alter session set container = FREEPDB1;
grant select on sys.v_$diag_alert_ext to dbmon;
EOF

# 4. Save the connection
printf 'conn -save demo_dbmon -savepwd -replace dbmon/"%s"@localhost:1521/FREEPDB1\nexit\n' "$DBMON_PWD" | sql -S /nolog
```

**Done when:** all 21 checks run (expect `errors: 0  result sets: 21`) and writes are refused
(expect ORA-01031 / ORA-00942):

```bash
{ echo "set feedback on"; cat .claude/skills/db-health-check/queries.sql; echo exit; } \
  | sql -S -name demo_dbmon > /tmp/dbmon_test.txt 2>&1
echo "errors: $(grep -c 'ORA-' /tmp/dbmon_test.txt)  result sets: $(grep -cE 'rows? selected' /tmp/dbmon_test.txt)"
printf 'create table t (x number);\nupdate hr.employees set salary = salary where rownum = 1;\n' \
  | sql -S -name demo_dbmon | grep ORA-
```

Notes:
- **MCP audit trade-off:** SQLcl MCP logs statements to `DBTOOLS$MCP_LOG` in the connected
  user's schema. `dbmon` can't create tables, so that log isn't written for `dbmon` (the
  `HR` and `SYSTEM` schemas have one). Sessions are still tagged `SQLcl-MCP` in `V$SESSION`.
- The `DEFAULT` profile expires the password after 180 days from creation.
- Remove with: `echo "drop user dbmon;" | sql -S -name demo_system` and
  `connmgr delete -conn demo_dbmon` in SQLcl.

### 4b. Read-only CDB-root monitoring user `c##dbmon`

From inside a PDB, the `V$DIAG_*` views only show that PDB's own entries: about 70 alert-log
lines and 20 trace files here, versus about 1,300 lines and all the instance's trace files from
the root. Instance-level problems (background process errors, crash recovery, ORA-00800)
are logged at root level. So `/db-diag-review` reads the alert log and traces through a
**common user** (a user that exists in the root and every PDB, so its name needs the `C##`
prefix).

```bash
# 1. Password into .env (only if not already there)
grep -q '^CDBMON_PWD=' .env || echo "CDBMON_PWD=Mon_$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)9" >> .env
set -a; . ./.env; set +a

# 2. Create the common user in the root (skipped if it already exists)
if printf "set heading off feedback off\nselect 'C##DBMON'||'_EXISTS' from dba_users where username = 'C##DBMON';\n" \
     | docker exec -i oracle-free sqlplus -S / as sysdba | grep -q 'C##DBMON_EXISTS'; then
  echo "c##dbmon already exists, skipping create"
else
  docker exec -i oracle-free sqlplus -S / as sysdba <<EOF
create user c##dbmon identified by "${CDBMON_PWD}" container = all;
EOF
fi

# 3. Grants (re-granting is harmless)
docker exec -i oracle-free sqlplus -S / as sysdba <<'EOF'
grant create session, select_catalog_role to c##dbmon container = all;
grant select on sys.v_$diag_alert_ext to c##dbmon container = all;
grant select on sys.v_$diag_trace_file to c##dbmon container = all;
grant select on sys.v_$diag_trace_file_contents to c##dbmon container = all;
grant select on sys.v_$diag_incident to c##dbmon container = all;
grant select on sys.v_$diag_problem to c##dbmon container = all;
-- AWR reports (scripts/awr-report.sh). Free only: Diagnostics Pack is included in Free, a
-- paid option elsewhere. See LICENSING.md. Also lets the user take/drop AWR snapshots.
grant execute on sys.dbms_workload_repository to c##dbmon container = all;
-- without this, a common user sees only root rows in V$ views
alter user c##dbmon set container_data = all container = current;
EOF

# 4. Save the connection (to the root: service FREE)
printf 'conn -save demo_dbmon_cdb -savepwd -replace c##dbmon/"%s"@localhost:1521/FREE\nexit\n' "$CDBMON_PWD" | sql -S /nolog
```

**Done when:** you get rows for con_id 1, 2 and 3, then ORA-01031 for the create:

```bash
printf 'select con_id, count(*) from v$diag_alert_ext group by con_id;\ncreate table t (x number);\n' \
  | sql -S -name demo_dbmon_cdb
```

---

## 5. Verify

```bash
docker inspect -f '{{.State.Health.Status}}' oracle-free                  # healthy
echo "select count(*) from employees;" | sql -S -name demo_hr             # 107
echo "select banner_full from v\$version;
select name, open_mode from v\$pdbs;" | sql -S -name demo_system          # 26ai banner, FREEPDB1 READ WRITE
```

**Done when:** all three show the expected output. The [status check](#status-check) should
now show steps 0 to 4b as `done`.

---

## 6. Project files

```bash
touch .gitignore
for p in .env '*.log'; do grep -qxF "$p" .gitignore || echo "$p" >> .gitignore; done
```

**Done when:** `.gitignore` lists `.env` and `*.log`.

- `CLAUDE.md` holds project context for future Claude Code sessions: goal, licensing rule,
  environment, connections and gotchas.
- `setup.md` is this runbook.

---

## 7. Register the SQLcl MCP server with Claude Code

The server is defined at **project scope** in `.mcp.json` in the project root, so the config
lives with the project and can be shown in the demo. The file has no user paths or secrets,
so a copied project usually has it already. Create it only if it's missing:

```bash
[ -f .mcp.json ] && echo ".mcp.json already exists, leaving it" || cat > .mcp.json <<'EOF'
{
  "mcpServers": {
    "sqlcl": {
      "type": "stdio",
      "command": "${HOME}/.local/opt/sqlcl/bin/sql",
      "args": ["-mcp"],
      "env": {
        "JAVA_HOME": "${HOME}/.local/opt/java"
      }
    }
  }
}
EOF
claude mcp get sqlcl      # Scope: Project config; "Pending approval" until first approved
```

**Then the user restarts Claude Code** (an agent can't do this itself; see playbook C.8):
1. Exit Claude Code (`/exit`).
2. Run `claude` again in the project folder.
3. Accept the prompt to trust the project's MCP servers, or approve `sqlcl` under `/mcp`.
4. Type `read setup.md` to carry on.

**Done when:** `claude mcp get sqlcl` shows `✔ Connected`, and inside Claude Code `/mcp`
lists `sqlcl` with its tools.

- **Why `${HOME}` paths and an explicit `JAVA_HOME`:** Claude Code starts MCP servers directly,
  without sourcing `~/.bashrc`. It expands `${VAR}` inside `.mcp.json`, so the file has no
  hard-coded user paths.
- **No secrets in `.mcp.json`:** credentials stay in the saved SQLcl connections
  (`~/.dbtools/connections`), so the file is safe to show or commit.
- **Scopes:** `project` writes `.mcp.json`, `local` writes to `~/.claude.json` (private to this
  folder), and `user` applies to all projects. If the same name exists in more than one scope,
  `local` wins, so don't keep a local `sqlcl` as well.
- If the copied project includes `.claude/settings.local.json` with
  `"enabledMcpjsonServers": ["sqlcl"]`, the server is already approved and there's no prompt.
  It still needs a restart if Claude Code started before SQLcl was installed.

**Optional: test with the raw protocol, without Claude.** This sends the handshake that Claude
Code does and should print a list of the saved connections:

```bash
{ printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"connections_list","arguments":{}}}'
  sleep 12; } | timeout 30 sql -mcp 2>/dev/null | grep '"id":2'
```

Tools exposed by SQLcl 26.3: `connections_list`, `connect`, `disconnect`, `sql_run`,
`sqlcl_run`, `schema_information`, `context_retrieve`, `request_status`,
`annotation_generate`, `skills_sync`. Tool names change between releases (older versions used
`list-connections`), so check with `tools/list` rather than assuming.

---

## 8. End-to-end check and the `/db-health-check` skill

**End-to-end check through MCP** (agents: do this after the restart in step 7):
1. Call `connections_list`. Expect `demo_dbmon`, `demo_dbmon_cdb`, `demo_hr` and
   `demo_system` in the list.
2. Call `connect` with `demo_dbmon`.
3. Call `sql_run` with `select banner_full from v$version`. Expect the 26ai banner.

**Done when:** all three work. Setup is complete.

A project skill lives in `.claude/skills/db-health-check/`. Claude Code finds it automatically
when started in this folder.

| File | Purpose |
|---|---|
| `SKILL.md` | Workflow, hard rules (read-only, no Diagnostics/Tuning Pack views), RAG thresholds, interpretation notes |
| `queries.sql` | 21 read-only checks, each starting with a `-- @check: <id> \| <title>` line and tagged `/* db-health-check */` |
| `report-template.md` | Report layout: header, scorecard, findings (CRIT → WARN → INFO), detail by check, method |

**Usage** (inside Claude Code in this folder):
```
/db-health-check                 # defaults to demo_system
/db-health-check demo_dbmon      # any saved connection name; demo_dbmon is read-only
```
It connects through the `sqlcl` MCP server, runs each check with `sql_run`, and writes
`reports/db-health-<connection>-<YYYYMMDD-HHMM>.md`, then summarises the result in chat.

**Checks:** instance, pdbs, capacity (Free 12 GB cap), tablespaces, fra, archiving, redo,
memory, limits, sessions, blocking, long_running, top_sql, waits, invalid_objects, alert_log,
backups, jobs, users, stats, parameters.

**Test the queries without Claude** (splits the file and runs each check through SQLcl):
```bash
mkdir -p /tmp/hc && rm -f /tmp/hc/*
awk -v d=/tmp/hc '/^-- @check:/{split($0,a,/: | \| /); f=sprintf("%s/%02d_%s.sql",d,++n,a[2])} f{print > f}' \
  .claude/skills/db-health-check/queries.sql
{ echo "set sqlformat csv"; for f in /tmp/hc/*.sql; do echo "prompt ### $(basename $f .sql)"; cat $f; done; } \
  | sql -S -name demo_system
```

**Test the skill headless** (restricted to the MCP query tools and file writes):
```bash
claude -p "/db-health-check demo_system" \
  --allowedTools "mcp__sqlcl__connect" "mcp__sqlcl__connections_list" "mcp__sqlcl__sql_run" \
                 "Read" "Write" "Bash(mkdir:*)" "Bash(date:*)" "Bash(ls:*)"
```
This takes about 2 minutes and about $0.65 per run.

**Things learned while building it**
- `V$RESOURCE_LIMIT` is **empty when connected to a PDB**. The `limits` check counts
  `V$PROCESS` and `V$SESSION` against their parameters instead.
- The MCP server rewrites each statement to add `/* LLM in use is <model> */` and logs it to
  `<user>.DBTOOLS$MCP_LOG` (created automatically, here in SYSTEM). Sessions show in
  `V$SESSION` as program `SQLcl-MCP`, module = model, action = tool name. This is a useful
  audit-trail point for the demo.
- `sql_run` returns CSV, and trailing semicolons are fine.
- `V$SQL_MONITOR` is excluded as well as AWR/ASH, because it needs the Tuning Pack.
- **Default image finding:** the DB runs in ARCHIVELOG mode with **no FRA**, and the archive
  destination is `$ORACLE_HOME/dbs/arch`, inside the container's writable layer rather than
  the data volume. Left as-is for now because it's a good real finding for the demo.

---

## 9. The `/db-diag-review` skill (alert log, traces, Statspack/AWR)

Reads the database's diagnostic evidence and writes a RAG-rated report that explains the
problems it finds. It has two modes:
- **MCP (default):** pulls the alert log, ADR incidents and trace files from `V$DIAG_*` as
  `demo_dbmon_cdb`. Workload history comes from **AWR** (`demo_dbmon_cdb`) when the database
  is Oracle Database Free, otherwise from Statspack as `demo_dbmon`.
- **File:** accepts an AWR (HTML/text) or Statspack report, an alert log or a trace file
  that someone hands over.

**AWR vs Statspack:** an AWR report is a before/after comparison of hourly performance
snapshots (top waits, top SQL, load profile). AWR is part of the Diagnostics Pack, which is
**included in Oracle Database Free** but is a paid option on Enterprise Edition and
unavailable on SE2. So the skill uses AWR only after an edition check (step 9e, and costs in
`LICENSING.md`). Statspack is Oracle's free predecessor with almost the same report sections,
and it's the fallback on every other edition. It's supported inside a PDB but **not** in
`CDB$ROOT`.

### 9a. Install Statspack into FREEPDB1

Part of setup. Agents run this before step 7 (see playbook C.3).

```bash
grep -q '^PERFSTAT_PWD=' .env || echo "PERFSTAT_PWD=Perf_$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)9" >> .env
set -a; . ./.env; set +a

# Create the PERFSTAT schema (skipped if it already exists). spcreate echoes the password once,
# so discard its console output and check the .lis files instead.
if printf "set heading off feedback off\nalter session set container = FREEPDB1;\nselect 'PERFSTAT'||'_EXISTS' from dba_users where username = 'PERFSTAT';\n" \
     | docker exec -i oracle-free sqlplus -S / as sysdba | grep -q PERFSTAT_EXISTS; then
  echo "Statspack already installed, skipping spcreate"
else
  docker exec -i oracle-free bash -c 'cd /tmp && sqlplus -S / as sysdba' <<EOF >/dev/null 2>&1
alter session set container = FREEPDB1;
define perfstat_password = "${PERFSTAT_PWD}"
define default_tablespace = SYSAUX
define temporary_tablespace = TEMP
@?/rdbms/admin/spcreate
EOF
  docker exec oracle-free bash -c 'grep -c "ORA-" /tmp/sp*.lis; rm -f /tmp/sp*.lis'   # expect 0s
fi

# Let dbmon read the Statspack tables (73 tables; re-granting is harmless)
docker exec -i oracle-free sqlplus -S / as sysdba <<'EOF'
alter session set container = FREEPDB1;
begin
  for t in (select table_name from dba_tables where owner = 'PERFSTAT' and table_name like 'STATS$%') loop
    execute immediate 'grant select on perfstat."' || t.table_name || '" to dbmon';
  end loop;
end;
/
EOF
```

**Done when:** the `.lis` error counts are all 0 (or it printed "already installed"), and
`dbmon` can read the snapshot table:

```bash
echo 'select count(*) from perfstat.stats$snapshot;' | sql -S -name demo_dbmon    # a number, no ORA- error
```

Take a snapshot by hand (level 7 includes segment stats and SQL plans):
```bash
printf "alter session set container = FREEPDB1;\nexec perfstat.statspack.snap(i_snap_level => 7);\n" \
  | docker exec -i oracle-free sqlplus -S / as sysdba
```
Hourly snapshots (`spauto.sql`) are **not** scheduled. Snapshots are taken around the demo load
instead. Remove Statspack with `@?/rdbms/admin/spdrop` in FREEPDB1.

### 9b. Skill files

`.claude/skills/db-diag-review/`:

| File | Purpose |
|---|---|
| `SKILL.md` | Modes, hard rules (read-only, AWR only on Free, bounded trace reads), workflow, rating guide, known-pattern table (ORA-00800, crash recovery, ORA-00060, ORA-600...) |
| `queries.sql` | 19 read-only checks tagged `/* db-diag-review */`, each marked `-- @check: <id> \| <cdb\|pdb> \| <title>`, with `{{days}}`, `{{begin_snap}}`/`{{end_snap}}` and `{{trace_file}}`/`{{line_from}}`/`{{line_to}}` placeholders |
| `extract_report.py` | File mode. Detects AWR HTML/text, Statspack, alert log (text or `log.xml`) and trace files, and prints a bounded extract. Standard library only, run with `python3 -I` |
| `report-template.md` | Summary, scorecard, cross-source timeline, findings, workload profile, trace excerpts, method |

Checks: alert_overview, alert_errors, alert_lifecycle, adr_problems, adr_incidents,
trace_inventory, trace_signatures, trace_excerpt, edition_gate, awr_snapshots (cdb); sp_snapshots, sp_header,
sp_load_profile, sp_efficiency, sp_top_events, sp_time_model, sp_top_sql, sp_file_io,
sp_host_cpu (pdb).

**Usage** (inside Claude Code in this folder):
```
/db-diag-review                          # MCP, last 7 days, newest AWR pair (Free) or Statspack pair
/db-diag-review workload=statspack       # force Statspack, e.g. to demo the any-edition path
/db-diag-review days=2 snaps=13-21       # explicit window / snapshot pair
/db-diag-review samples/statspack_13_21.txt   # file mode (AWR/Statspack/alert/trace)
```
Output goes to `reports/db-diag-<connection or file>-<YYYYMMDD-HHMM>.md`.

### 9c. Demo workload: `scripts/demo-diag-load.sh`

Not part of setup. It runs a workload against the database, so agents should only run it when
the user asks.

Takes a Statspack snapshot, runs about 35 s of workload as HR, and takes another. The workload
is a Cartesian-join CPU hog, 3,000 client-side commits (`log file sync`), 5,000 literal SQLs
(hard parses), and a **two-session deadlock** that writes ORA-00060 to the alert log plus
a trace file. Everything happens in a scratch table `HR.DIAG_DEMO`, which is dropped at the end.
`--no-deadlock` skips the deadlock.

```bash
scripts/demo-diag-load.sh && claude    # then: /db-diag-review
```

`samples/` holds files for file mode: `statspack_13_21.txt` (from `spreport.sql`),
`alert_FREE.log` and the deadlock trace `FREE_ora_3613.trc` (`docker cp` from
`/opt/oracle/diag/rdbms/free/FREE/trace/`). For AWR samples, run `scripts/awr-report.sh`
(step 9e).

### 9e. AWR reports (Oracle Database Free only)

Part of setup: the grant is in step 4b. AWR is on by default in Free
(`control_management_pack_access = DIAGNOSTIC+TUNING`) and takes an automatic snapshot every
hour, kept for 8 days. Snapshots live in the CDB root and cover the whole instance. Snapshots
are lost while the container is stopped, and no delta can span a restart.

```bash
scripts/awr-report.sh                 # newest valid pair -> reports/awr/awr_<b>_<e>.txt
scripts/awr-report.sh 5 6             # explicit pair
scripts/awr-report.sh --html 5 6      # HTML version
scripts/awr-report.sh --snap          # take a manual snapshot first (e.g. after a demo load)
```
The script connects as `demo_dbmon_cdb` (override with `AWR_CONN`) and **refuses** unless
`V$VERSION` says Free, or `AWR_LICENSED=1` is set by someone who has confirmed the target has
the Diagnostics Pack. To get an AWR window around the demo workload:
`scripts/awr-report.sh --snap; scripts/demo-diag-load.sh; scripts/awr-report.sh --snap`.

**Done when:** `scripts/awr-report.sh` prints `AWR report snaps B-E -> reports/awr/...`, and
`python3 -I .claude/skills/db-diag-review/extract_report.py reports/awr/awr_<b>_<e>.txt`
shows `detected type: awr-text` with Load Profile and Top 10 Foreground Events sections. On a
fresh container, wait for two hourly snapshots, or take two with `--snap`.

### 9d. Testing

Run every check through SQLcl without Claude (substitutes placeholders with test values;
adjust the snapshot ids to a valid pair from `sp_snapshots`):
```bash
T=$(mktemp -d)
awk -v d=$T '/^-- @check:/{split($0,a,"|"); id=a[1]; sub(/^-- @check: */,"",id); gsub(/ /,"",id); r=a[2]; gsub(/ /,"",r); f=d"/"r"__"id".sql"} f{print > f}' \
  .claude/skills/db-diag-review/queries.sql
for f in $T/*.sql; do b=$(basename $f .sql); c=demo_dbmon_cdb; [[ $b == pdb__* ]] && c=demo_dbmon
  { echo "set feedback on"; sed 's/{{days}}/7/g; s/{{begin_snap}}/13/g; s/{{end_snap}}/21/g; s/{{trace_file}}/FREE_ora_3613.trc/; s/{{line_from}}/24/; s/{{line_to}}/60/' $f; echo exit; } \
    | sql -S -name $c > $T/$b.out 2>&1
  printf '%-28s %s %s\n' $b "$(grep -m1 -oE '[0-9]+ rows? selected|no rows selected' $T/$b.out)" \
    "$(grep -m1 -oE 'SQL Error: ORA-[0-9]+' $T/$b.out)"; done   # expect a row count, no SQL Error
```

Headless end-to-end runs:
```bash
claude -p "/db-diag-review" --allowedTools "mcp__sqlcl__connect" "mcp__sqlcl__disconnect" \
  "mcp__sqlcl__connections_list" "mcp__sqlcl__sql_run" "Read" "Write" "Bash(mkdir:*)" "Bash(date:*)" "Bash(ls:*)"
claude -p "/db-diag-review samples/statspack_13_21.txt" --allowedTools "Read" "Write" \
  "Bash(python3 -I .claude/skills/db-diag-review/extract_report.py:*)" "Bash(mkdir:*)" "Bash(date:*)" "Bash(ls:*)"
```
MCP mode takes about 3 minutes and file mode about 1 minute.

**Things learned while building it**
- `V$DIAG_ALERT_EXT.message_type` and `message_level` don't indicate severity reliably:
  ORA-00060 is logged as type 1 (unknown) and routine datafile resizes as type 3. So the
  queries classify on the message text.
- `V$DIAG_TRACE_FILE_CONTENTS.line_number` is the line in the file, so a bounded window can be
  pulled. The deadlock trace is 30,900 lines (1.9 MB), mostly state dumps.
- Trace files sit at `con_id` 1 even for PDB sessions. Use `container_name` per line.
- PL/SQL loops with `commit` barely wait on `log file sync` (PL/SQL commit optimisation), so
  the demo commits from the client.
- Statspack snapshot ids have gaps (cached sequence). This is normal.
- Statspack figures from the SQL checks match `spreport.sql` exactly (soft parse 42.91%, 3,013
  `log file sync` waits), which cross-checks the delta queries.
- AWR parsing was first tested against real reports from this instance on 2026-10-07. The
  HTML report's table of contents (`<li><a href="#...">`) used to be taken for section
  headings, and text reports repeat a heading after each page break (now marked
  "(continued)").
- **Real findings in this environment:** every startup does crash recovery, because
  `docker stop` kills Oracle after 10 s (use `docker stop -t 120`). ORA-00800
  "Set Priority Failed" for LGWR/VKTM appears because the container lacks `CAP_SYS_NICE`
  (`--cap-add=SYS_NICE`). Both are left unfixed for the demo.

### 9f. The `awr-analyst` agent

A Claude Code subagent that runs `/db-diag-review` in its own context and returns only the
scorecard, the top findings and the report path. It works this way:
- **The skill stays portable.** The agent preloads it with `skills: [db-diag-review]`.
- **The agent holds this machine's gotchas:** WSL/Docker, UTC vs local time, AWR snapshot
  pairing after restarts, and which findings are kept for the demo.
- **`scripts/db-preflight.sh` starts the DB.** It runs `docker start oracle-free` if the
  container isn't running, waits until it's healthy, checks the `demo_dbmon_cdb` connection
  and prints `key=value` facts (edition, startup time, AWR snapshots since startup).
- **`scripts/agent-guard.py` enforces read-only.** It's a PreToolUse hook scoped to the agent.
  It allows only:
  - Bash: the preflight, `awr-report.sh` (no `--snap`), the extractor, `docker ps/inspect/logs`, `date`, `ls`
  - Write: `reports/*.md`
  - MCP: connections `demo_dbmon`/`demo_dbmon_cdb`, and `sql_run` with tagged `SELECT`/`WITH` statements

  It **approves** what it lets through, so the agent runs without permission prompts. Because
  the approval lives in the agent's hook, the main session gets no wider permissions.

Files: `.claude/agents/awr-analyst.md`, `scripts/db-preflight.sh`, `scripts/agent-guard.py`.
New agent files are only picked up when a session starts, so restart Claude Code (or use
`/agents`) after adding them. The guard needs `python3` on PATH (no `jq` required).

```bash
scripts/db-preflight.sh                       # exit 0 = ready; 1 Docker down, 2 no container, 3 unhealthy, 4 connection
claude -p "Use the awr-analyst agent to run a diagnostic review of the database, then relay its result verbatim." \
  --allowedTools "Agent"                      # headless end-to-end test, about 5 min
```
In an interactive session, just ask: "use the awr-analyst agent to analyse AWR".

**Done when:** `scripts/db-preflight.sh` prints `health=healthy` and `cdb_connection=ok`, and
the headless run returns a scorecard and a new `reports/db-diag-*.md`. The guard can be tested
alone with
`echo '{"tool_name":"Bash","tool_input":{"command":"scripts/awr-report.sh --snap"}}' | CLAUDE_PROJECT_DIR=$PWD python3 -I scripts/agent-guard.py`.
This must exit 2.

### 9g. Web front end for the agent (`webui/`)

A local browser UI for the demo. It runs the agent headless
(`claude -p --agent awr-analyst --output-format stream-json`) in the project folder, so it
gets the same skill, SQLcl MCP server and guard hook as the CLI, and streams each step to the
page. Standard-library Python with nothing to install. `marked` and `DOMPurify` are vendored
in `webui/static/`, so it works offline.

- **Live database:** look-back window, workload source (auto/AWR/Statspack), optional focus
  note. The preflight starts `oracle-free` if it's down.
- **Analyse a report file:** pick a file in `reports/awr/` or upload one. Uploads go to
  `reports/uploads/` (`.txt .html .htm .log .xml .trc .lst`, 60 MB max).
- The right pane shows the agent's summary and the full RAG report. The report list shows every
  `reports/db-*.md`.
- Binds to `127.0.0.1` only. One run at a time. Each run is billed like any Claude Code
  session: about $0.50 for file mode, more for live mode.

```bash
python3 webui/server.py            # http://localhost:8765 (PORT=9000 to change)
```
From Windows, open `http://localhost:8765` in a browser (WSL2 forwards localhost).

**Done when:** the page shows the `oracle-free` status pill, and a file-mode run on
`reports/awr/awr_4_5.txt` ends with "Finished" and opens a new `reports/db-diag-awr_4_5-*.md`.

---

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `permission denied ... docker.sock` | Your user can't use Docker without sudo. The user runs: `sudo groupadd -f docker && sudo usermod -aG docker "$USER"`. For snap Docker, also `sudo snap disable docker && sudo snap enable docker`. Then log out and back in (on WSL: `wsl --shutdown` from Windows, then reopen). |
| `sql: command not found` or `java: command not found` | The preamble wasn't run in this shell, or step 2 isn't done. |
| Port 1521 already in use | Another database or container is using it. Find it with `docker ps` or `ss -ltnp`. Ask the user before stopping anything. |
| Container `unhealthy` or exits | Run `docker logs --tail 50 oracle-free`. It's usually memory: the database needs about 2 GB. On WSL, raise `memory=` in `%UserProfile%\.wslconfig`. |
| Image pull fails or is very slow | Retry `docker pull`, which resumes finished layers. Check disk space with `docker system df`. |
| **Passwords don't match** (`ORA-01017: invalid username/password`) | `.env` doesn't match the database, for example a volume left over from an earlier install. Don't generate new passwords or delete the volume without asking. With the user's OK, reset the database to match `.env` as SYS. The passwords go through stdin, not the command line: see the block below the table. |
| `ORA-20999: the HR password is mandatory` | The `ACCEPT` workaround in step 3 wasn't used. |
| MCP server not connected | Run `claude mcp get sqlcl`. Check that `~/.local/opt/sqlcl/bin/sql` and `~/.local/opt/java/bin/java` exist and that there's no `local`-scope `sqlcl` overriding the project one (`claude mcp list`). Restart Claude Code after fixing. |
| Shell blocks foreground `sleep` | Run the step 1c wait (or the raw MCP test) in the background and poll it. |

Resetting passwords to match `.env` (ask the user first):

```bash
docker exec -i oracle-free sqlplus -S / as sysdba <<EOF
alter user system identified by "${ORACLE_PWD}" container=all;
alter session set container = FREEPDB1;
alter user hr identified by "${HR_PWD}";
EOF
```

For any other users that exist, run the matching statement the same way:
`alter user dbmon identified by "${DBMON_PWD}";` and
`alter user perfstat identified by "${PERFSTAT_PWD}";` in FREEPDB1, and
`alter user c##dbmon identified by "${CDBMON_PWD}" container=all;` in the root. Then re-run
the connection-saving lines of steps 4, 4a and 4b so the saved connections pick up the
passwords.

---

## Day-to-day operations

```bash
docker stop oracle-free        # stop (data kept). Kills Oracle after 10 s, so crash recovery at next start
# docker stop -t 120 oracle-free   # clean shutdown, no crash recovery (verified 2026-10-08)
docker start oracle-free       # start again; wait for healthy
docker logs -f oracle-free     # alert log / startup output
sql -name demo_system          # interactive DBA session
```

## Teardown (destructive, so confirm before running)

```bash
rm .mcp.json                                           # project-scope MCP server
docker rm -f oracle-free
docker volume rm oracle-free-data                      # deletes the database
rm -rf ~/.dbtools/connections                          # saved connections (check for others first)
rm -rf ~/.local/opt/java ~/.local/opt/jdk-21* ~/.local/opt/sqlcl
# then delete the "oracle-ai PoC" block from ~/.bashrc
```

---

## Change log

### 2026-10-06: Initial environment build
- Steps 0–7 above completed and verified: container healthy, `sql -name demo_hr` returns 107
  employees, MCP server connected and lists both saved connections.
- Versions: Oracle AI Database 26ai Free 23.26.3.0.0, SQLcl 26.3.0.0, Temurin JDK 21.0.12.1.

### 2026-10-06: Created setup.md
- Wrote this runbook from the session history. Re-ran the step 7 raw-protocol MCP check and
  confirmed it returns `demo_hr,demo_system`. Documented the non-interactive-shell PATH gotcha
  (step 2).

### 2026-10-06: Built /db-health-check skill (step 8)
- Wrote `queries.sql` (21 checks) and tested every check against `demo_system`, then fixed
  issues found in testing: PDB-empty `V$RESOURCE_LIMIT`, background sessions counted as
  long-running, the health check's own SQL showing in top SQL, and the alert-log filter
  matching harmless resize messages.
- Added `archiving` and `capacity` checks after finding that archived redo goes to the
  container layer.
- Tested end-to-end with headless `claude -p`: 21/21 checks ran, no errors, no off-list SQL.
  The first run rated the DB CRIT because of missing HR stats, so the thresholds were
  recalibrated (stats max WARN, uptime is a caveat not a finding) and the test re-run.

### 2026-10-07: Moved the MCP server to project scope
- Replaced the `--scope local` entry in `~/.claude.json` with a project `.mcp.json` (step 7),
  using `${HOME}` paths. Removed the local entry with `claude mcp remove sqlcl -s local`. The
  server needs a one-time approval in Claude Code.

### 2026-10-07: Added read-only monitoring user `dbmon` (step 4a)
- Created `dbmon` in FREEPDB1 with `CREATE SESSION`, `SELECT_CATALOG_ROLE`, and (as SYS)
  `SELECT` on `V_$DIAG_ALERT_EXT`. Saved connection `demo_dbmon`; password in `.env` as
  `DBMON_PWD`.
- Verified: all 21 health checks run as `dbmon` with no errors, including via the MCP
  server, and create/update/alter system attempts fail with ORA-01031/ORA-00942.
- Trade-off: no `DBTOOLS$MCP_LOG` audit table for `dbmon`, because it can't create tables.

### 2026-10-07: Made the project path portable
- Replaced the hard-coded project path with a `<PROJECT_DIR>` placeholder. Added instructions
  at the top telling a coding agent to ask the user for their project path, check it, and fill
  in the placeholder before running any step. Every other command already used `$PROJ` or
  `$HOME`, so nothing else changed.

### 2026-10-07: Built /db-diag-review skill (steps 4b, 9)
- Added read-only common user `C##DBMON` in the CDB root (`CREATE SESSION`,
  `SELECT_CATALOG_ROLE`, `V_$DIAG_*` grants, `CONTAINER_DATA=ALL`) and saved connection
  `demo_dbmon_cdb` (service `FREE`). Password in `.env` as `CDBMON_PWD`.
- Installed Statspack (schema `PERFSTAT`, tablespace SYSAUX) in FREEPDB1. Password in `.env` as
  `PERFSTAT_PWD`. Granted `dbmon` SELECT on the 73 `PERFSTAT.STATS$*` tables.
- Wrote the skill (17 checks plus `extract_report.py` for file mode), `scripts/demo-diag-load.sh`
  and the `samples/` files.
- Tested: all 17 checks run as the dbmon users. Headless MCP run 17/17 with no errors, and
  every model-issued statement carried the tag. File-mode run on the Statspack sample was
  correct. Not tested: AWR HTML/text parsing (no licensed AWR report available).

### 2026-10-07: Made the runbook agent-driven ("read setup.md")
- Added "Start here" (prerequisites, one-line start) and an Agent playbook: ask for the path,
  a preamble at the start of every block (non-interactive shells don't read `~/.bashrc`), a
  read-only status check so a run can resume after the Claude Code restart, a **Done when**
  check per step, an explicit step order (9a before the step 7 restart), when to ask the user,
  and a restart handoff at step 7. Testing sections and the demo workload are marked as not
  part of onboarding.
- Made every setup step safe to re-run: `.env` passwords are only generated if missing, and
  the pull, volume, container, JDK, SQLcl, clone, HR install, `dbmon`/`c##dbmon` create,
  Statspack install, `.gitignore` and `.mcp.json` are all skipped when already present.
  Connections are saved with `-replace`. Step 1a stops if a database volume exists but `.env`
  has no password.
- JDK download picks x64 or aarch64 from `uname -m`. The `~/.bashrc` PATH block is now
  optional and needs the user's OK.
- Added an end-to-end MCP check (step 8) and a Troubleshooting table, including how to reset
  passwords to match `.env`.
- Tested on this machine: the status check reports every step `done` (negative probes report
  `TODO`), `conn -save ... -replace` works when run twice, the `c##dbmon` grants re-run
  cleanly, and the `dbmon`/`c##dbmon`/`PERFSTAT` existence guards detect existing users.

### 2026-10-07: Enabled AWR for the PoC (Free only; step 9e, LICENSING.md)
- Confirmed in Oracle's 26ai *Licensing Information User Manual* that Diagnostics and Tuning
  Packs are included in Oracle AI Database Free. AWR was already active (hourly snapshots).
- Granted `EXECUTE ON DBMS_WORKLOAD_REPOSITORY` to `C##DBMON` (step 4b), added a status-check
  line, and added `scripts/awr-report.sh` (edition-gated, writes `reports/awr/`).
- `/db-diag-review` now runs `edition_gate`, uses AWR on Free and Statspack elsewhere. Added
  checks `edition_gate` and `awr_snapshots` (19 checks in total). `/db-health-check` is
  unchanged (base views only).
- Fixed `extract_report.py` for real AWR reports (HTML table of contents, text page breaks).
  Tested on AWR snaps 5-6 in text and HTML.
- Added `LICENSING.md`: what AWR would cost on a licensed estate, how Oracle detects use, and
  an onboarding checklist.

### 2026-10-08: Added the `awr-analyst` agent (step 9f)
- Ran the first full `/db-diag-review` on the AWR path: edition gate, then `awr_snapshots`,
  then `scripts/awr-report.sh 4 5`, then the extractor. Report:
  `reports/db-diag-demo_dbmon_cdb-20261008-1258.md`. The container had exited overnight (WSL)
  and was started by hand.
- Added `scripts/db-preflight.sh`, `scripts/agent-guard.py` (agent-scoped PreToolUse
  hook: allowlist plus auto-approve) and `.claude/agents/awr-analyst.md`, which preloads the
  skill. Added a status-check line.
- `scripts/awr-report.sh` now sets `JAVA_HOME`/`PATH` and `cd`s to the project root itself, so
  it runs from a non-interactive shell with nothing in front of it.
- Learned: AWR's `DBA_HIST_SNAPSHOT.startup_time` is about 3 s later than
  `V$INSTANCE.startup_time`, so don't join them with `=`. `docker stop -t 120` gives a clean
  shutdown with no crash recovery at the next start (tested at 12:08 UTC).

### 2026-10-15: Added a web front end for the agent (step 9g)
- `webui/server.py` (stdlib HTTP + SSE) and `webui/index.html`. It runs
  `claude -p --agent awr-analyst --output-format stream-json --verbose`. Headless check: the
  agent-scoped guard hook still auto-approves, `sqlcl` connects and the tool list is limited to
  the agent's 7 tools, so no `--dangerously-skip-permissions` is needed.
- Tested file mode on `reports/awr/awr_4_5.txt` (83 s, $0.51) and live mode with the container
  stopped: the preflight started it, then 23 turns, 184 s, $0.88, report
  `reports/db-diag-demo_dbmon_cdb-20261015-1550.md`. No guard blocks.

### 2026-10-15: Git repo and GitHub remote
- Project is now a git repo, pushed to private `github.com/robsketch/oracle-ai` (branch `main`).
- `.gitignore` excludes `.env`, `db-sample-schemas/` (re-clone it per step 6),
  `.claude/settings.local.json`, `__pycache__/` and `reports/uploads/`.
