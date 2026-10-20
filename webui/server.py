#!/usr/bin/env python3
"""Local demo front end for the awr-analyst agent (.claude/agents/awr-analyst.md).

Runs the agent headless (`claude -p --agent awr-analyst --output-format stream-json`) in the
project directory, so it gets the same skill, SQLcl MCP server and guard hook as the CLI, and
streams its progress to the browser over Server-Sent Events. Standard library only.

    python3 webui/server.py            # then open http://localhost:8765
    PORT=9000 python3 webui/server.py

Binds to 127.0.0.1 only. One agent run at a time.
"""
import json
import os
import re
import shutil
import subprocess
import threading
import time
import uuid
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PROJECT = Path(__file__).resolve().parent.parent
WEBUI = Path(__file__).resolve().parent
REPORTS = PROJECT / "reports"
UPLOADS = REPORTS / "uploads"
PORT = int(os.environ.get("PORT", "8765"))
CLAUDE = shutil.which("claude")
AGENT = "awr-analyst"
MAX_UPLOAD = 60 * 1024 * 1024
UPLOAD_EXT = {".txt", ".html", ".htm", ".log", ".xml", ".trc", ".lst"}
STATIC = {"/": ("index.html", "text/html; charset=utf-8")}
STATIC_TYPES = {".js": "text/javascript", ".woff2": "font/woff2"}
for _p in (WEBUI / "static").iterdir():
    if _p.suffix in STATIC_TYPES:
        STATIC[f"/static/{_p.name}"] = (f"static/{_p.name}", STATIC_TYPES[_p.suffix])
REPORT_RE = re.compile(r"reports/(db-(?:diag|health)-[\w.-]+\.md)")
WINDOW_FMT = "%Y-%m-%dT%H:%M"  # from/to as sent by the UI and passed to the agent, UTC
MAX_WINDOW_DAYS = 31

# AWR coverage for the timeframe picker. AWR is Diagnostics Pack, so DBA_HIST_* is queried only
# after the edition check says Free (LICENSING.md). Same read-only connection as the agent.
SQL_CONN = "demo_dbmon_cdb"
SQL_ENV = dict(os.environ, JAVA_HOME=os.path.expanduser("~/.local/opt/java"))
SQL_ENV["PATH"] = os.path.expanduser("~/.local/opt/sqlcl/bin:~/.local/opt/java/bin:") + SQL_ENV["PATH"]
EDITION_SQL = """set heading off feedback off
set sqlformat default
select /* db-diag-review */ edition from v$instance;
"""
COVERAGE_SQL = """set feedback off
set sqlformat csv
select /* db-diag-review */
       to_char(startup_time, 'YYYY-MM-DD"T"HH24:MI:SS') as startup_utc,
       to_char(end_interval_time, 'YYYY-MM-DD"T"HH24:MI:SS') as snap_utc
from dba_hist_snapshot
where dbid = (select dbid from v$database)
  and instance_number = (select instance_number from v$instance)
order by snap_id;
"""
COVERAGE_TTL = 120
_coverage = {"at": 0, "data": None}


class Job:
    def __init__(self, prompt, label):
        self.id = uuid.uuid4().hex[:12]
        self.prompt = prompt
        self.label = label
        self.started = time.time()
        self.events = []
        self.done = False
        self.cond = threading.Condition()
        self.proc = None
        self.stderr = []

    def emit(self, **ev):
        ev["t"] = round(time.time() - self.started, 1)
        with self.cond:
            self.events.append(ev)
            self.cond.notify_all()

    def finish(self):
        with self.cond:
            self.done = True
            self.cond.notify_all()


current = None
lock = threading.Lock()


# ---------- helpers ----------

def list_reports():
    out = []
    for p in REPORTS.glob("db-*.md"):
        status = ""
        try:
            with p.open(encoding="utf-8", errors="replace") as f:
                for _, line in zip(range(15), f):
                    if "Overall status" in line:
                        m = re.search(r"(🟢|🟡|🟠|🔴)\s*(\w+)", line)
                        status = f"{m.group(1)} {m.group(2)}" if m else ""
                        break
        except OSError:
            pass
        out.append({"name": p.name, "mtime": p.stat().st_mtime, "status": status,
                    "kind": "diag" if p.name.startswith("db-diag") else "health"})
    return sorted(out, key=lambda r: r["mtime"], reverse=True)


def list_input_files():
    files = []
    for d in (REPORTS / "awr", UPLOADS):
        if d.is_dir():
            for p in d.iterdir():
                if p.is_file() and p.suffix.lower() in UPLOAD_EXT:
                    files.append({"path": str(p.relative_to(PROJECT)), "size": p.stat().st_size,
                                  "mtime": p.stat().st_mtime})
    return sorted(files, key=lambda f: f["mtime"], reverse=True)


def db_status():
    try:
        r = subprocess.run(
            ["docker", "inspect", "-f", "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}",
             "oracle-free"], capture_output=True, text=True, timeout=5)
        if r.returncode != 0:
            return {"state": "unknown", "detail": (r.stderr.strip() or "docker inspect failed")[:200]}
        parts = r.stdout.split()
        return {"state": parts[0] if parts else "unknown", "health": parts[1] if len(parts) > 1 else ""}
    except (OSError, subprocess.TimeoutExpired) as e:
        return {"state": "unknown", "detail": str(e)[:200]}


def run_sql(script):
    r = subprocess.run(["sql", "-S", "-name", SQL_CONN], input=script, capture_output=True,
                       text=True, timeout=60, env=SQL_ENV, cwd=PROJECT)
    out = r.stdout.strip()
    if r.returncode != 0 or re.search(r"ORA-\d{5}|SP2-\d{4}|Connection failed", out):
        m = re.search(r"(?:ORA|SP2)-\d+.*", out + "\n" + r.stderr)
        raise RuntimeError(m.group(0)[:200] if m else f"sql exited {r.returncode}")
    return out


def awr_coverage(force=False):
    """AWR snapshot ranges, one per instance startup, so the user can pick a window with data."""
    if not force and _coverage["data"] and time.time() - _coverage["at"] < COVERAGE_TTL:
        return _coverage["data"]
    db = db_status()
    if db.get("state") != "running" or db.get("health") not in ("healthy", ""):
        return {"available": False, "reason": "database not running, so AWR coverage is unknown "
                "until the agent starts it"}
    try:
        edition = run_sql(EDITION_SQL).split()[-1]
        if edition != "FREE":
            data = {"available": False, "edition": edition,
                    "reason": f"edition {edition}: AWR needs the Diagnostics Pack, so the agent uses Statspack"}
        else:
            segs = {}
            for ln in run_sql(COVERAGE_SQL).splitlines()[1:]:
                if ln.strip():
                    startup, snap = ln.replace('"', "").split(",")
                    segs.setdefault(startup, []).append(snap)
            data = {"available": True, "edition": edition,
                    "segments": [{"startup": k, "first": v[0], "last": v[-1], "snaps": len(v), "times": v}
                                 for k, v in segs.items()]}
    except (RuntimeError, OSError, subprocess.TimeoutExpired, ValueError) as e:
        return {"available": False, "reason": f"could not read AWR coverage: {e}"}
    _coverage.update(at=time.time(), data=data)
    return data


def parse_window(body):
    """from/to (UTC, YYYY-MM-DDTHH:MM) -> validated datetimes."""
    try:
        frm = datetime.strptime(str(body.get("from", "")), WINDOW_FMT)
        to = datetime.strptime(str(body.get("to", "")), WINDOW_FMT)
    except ValueError:
        raise ValueError("from/to must be YYYY-MM-DDTHH:MM (UTC)")
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    if frm >= to:
        raise ValueError("the timeframe must end after it starts")
    if frm > now:
        raise ValueError("the timeframe starts in the future")
    if to - frm > timedelta(days=MAX_WINDOW_DAYS):
        raise ValueError(f"the timeframe can be at most {MAX_WINDOW_DAYS} days")
    return frm, min(to, now + timedelta(minutes=1))


def summarise_tool(name, inp):
    short = name.replace("mcp__sqlcl__", "sqlcl.")
    if name == "Bash":
        return short, inp.get("command", "")
    if name in ("Read", "Write"):
        p = inp.get("file_path", "")
        return short, p.replace(str(PROJECT) + "/", "")
    if name == "mcp__sqlcl__connect":
        return short, inp.get("connection_name", "")
    if name == "mcp__sqlcl__sql_run":
        sql = " ".join(inp.get("sql", "").split())
        sql = sql.replace("/* db-diag-review */", "").strip()
        return short, sql[:160] + ("…" if len(sql) > 160 else "")
    return short, json.dumps(inp)[:160]


def result_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(c.get("text", "") for c in content if isinstance(c, dict))
    return str(content)


def run_job(job):
    before = {p.name: p.stat().st_mtime for p in REPORTS.glob("db-*.md")}
    cmd = [CLAUDE, "-p", "--agent", AGENT, "--output-format", "stream-json", "--verbose", job.prompt]
    job.emit(kind="start", label=job.label, prompt=job.prompt)
    try:
        job.proc = subprocess.Popen(cmd, cwd=PROJECT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    stdin=subprocess.DEVNULL, text=True, bufsize=1)
    except OSError as e:
        job.emit(kind="error", text=f"could not start claude: {e}")
        job.finish()
        return

    def drain_stderr():
        for line in job.proc.stderr:
            job.stderr.append(line.rstrip())
    threading.Thread(target=drain_stderr, daemon=True).start()

    tool_names = {}
    final = None
    for line in job.proc.stdout:
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        t = e.get("type")
        if t == "system" and e.get("subtype") == "init":
            mcp = {s.get("name"): s.get("status") for s in e.get("mcp_servers", [])}
            job.emit(kind="init", model=e.get("model"), sqlcl=mcp.get("sqlcl", "missing"))
        elif t == "assistant":
            for c in e.get("message", {}).get("content", []):
                if c.get("type") == "tool_use":
                    name, detail = summarise_tool(c["name"], c.get("input", {}))
                    tool_names[c["id"]] = name
                    job.emit(kind="tool", id=c["id"], name=name, detail=detail)
                elif c.get("type") == "text" and c.get("text", "").strip():
                    job.emit(kind="text", text=c["text"])
        elif t == "user":
            content = e.get("message", {}).get("content", [])
            for c in content if isinstance(content, list) else []:
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    txt = result_text(c.get("content"))
                    job.emit(kind="tool_result", id=c.get("tool_use_id"), error=bool(c.get("is_error")),
                             name=tool_names.get(c.get("tool_use_id"), ""), preview=txt[:300])
        elif t == "result":
            final = e
    job.proc.wait()

    report = None
    text = (final or {}).get("result") or ""
    for m in REPORT_RE.finditer(text):
        if (REPORTS / m.group(1)).is_file():
            report = m.group(1)
    if not report:
        new = [p for p in REPORTS.glob("db-*.md") if before.get(p.name) != p.stat().st_mtime]
        if new:
            report = max(new, key=lambda p: p.stat().st_mtime).name
    if final:
        job.emit(kind="done", ok=not final.get("is_error") and final.get("subtype") == "success",
                 subtype=final.get("subtype"), result=text, report=report,
                 cost=final.get("total_cost_usd"), turns=final.get("num_turns"),
                 duration=round((final.get("duration_ms") or 0) / 1000))
    else:
        job.emit(kind="error", text="agent exited without a result (exit code "
                 f"{job.proc.returncode}). " + " ".join(job.stderr[-5:])[:600])
    job.finish()


def build_prompt(body):
    mode = body.get("mode")
    if mode == "live":
        if body.get("from") or body.get("to"):
            frm, to = parse_window(body)
            args = [f"from={frm:{WINDOW_FMT}}", f"to={to:{WINDOW_FMT}}"]
            same_day = frm.date() == to.date()
            span = f"{frm:%d %b %H:%M}–{to:%H:%M}" if same_day else f"{frm:%d %b %H:%M} – {to:%d %b %H:%M}"
            label = f"Live review · {span} UTC"
        else:
            days = int(body.get("days", 7))
            if not 1 <= days <= 30:
                raise ValueError("days must be 1-30")
            args = [f"days={days}"]
            label = f"Live review · {days}d"
        workload = body.get("workload", "auto")
        if workload in ("awr", "statspack"):
            args.append(f"workload={workload}")
        elif workload != "auto":
            raise ValueError("bad workload")
        focus = " ".join(str(body.get("focus", "")).split())[:300]
        prompt = "Run the diag review against the local database. Arguments: " + " ".join(args) + "."
        if focus:
            prompt += f" The user would like you to pay particular attention to: {focus}"
        return prompt, f"{label} · {workload}"
    if mode == "file":
        path = body.get("path", "")
        if path not in {f["path"] for f in list_input_files()}:
            raise ValueError("unknown file")
        return f"Analyse this file (file mode): {path}", f"File · {Path(path).name}"
    raise ValueError("bad mode")


# ---------- HTTP ----------

class Handler(BaseHTTPRequestHandler):
    server_version = "awr-analyst-ui"

    def log_message(self, fmt, *args):
        if "/events" not in self.path:
            super().log_message(fmt, *args)

    def send_json(self, obj, code=200):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def read_json(self):
        n = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(n) or b"{}") if n < 100_000 else {}

    def do_GET(self):
        u = urlparse(self.path)
        if u.path in STATIC:
            fname, ctype = STATIC[u.path]
            data = (WEBUI / fname).read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif u.path == "/api/state":
            job = current
            self.send_json({
                "db": db_status(), "agent": AGENT, "claude": bool(CLAUDE),
                "reports": list_reports(), "files": list_input_files(),
                "job": {"id": job.id, "label": job.label, "done": job.done} if job else None})
        elif u.path == "/api/coverage":
            self.send_json(awr_coverage(force="refresh" in parse_qs(u.query)))
        elif u.path == "/api/report":
            name = parse_qs(u.query).get("name", [""])[0]
            if name not in {r["name"] for r in list_reports()}:
                return self.send_json({"error": "not found"}, 404)
            self.send_json({"name": name, "markdown": (REPORTS / name).read_text(errors="replace")})
        elif m := re.fullmatch(r"/api/jobs/(\w+)/events", u.path):
            self.stream_events(m.group(1), int(parse_qs(u.query).get("from", ["0"])[0]))
        else:
            self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        global current
        u = urlparse(self.path)
        if u.path == "/api/run":
            if not CLAUDE:
                return self.send_json({"error": "claude CLI not found on PATH"}, 500)
            try:
                prompt, label = build_prompt(self.read_json())
            except (ValueError, TypeError) as e:
                return self.send_json({"error": str(e)}, 400)
            with lock:
                if current and not current.done:
                    return self.send_json({"error": "a run is already in progress"}, 409)
                current = Job(prompt, label)
                threading.Thread(target=run_job, args=(current,), daemon=True).start()
            self.send_json({"id": current.id})
        elif u.path == "/api/stop":
            job = current
            if job and job.proc and job.proc.poll() is None:
                job.proc.terminate()
                job.emit(kind="error", text="Stopped by user.")
            self.send_json({"ok": True})
        elif u.path == "/api/upload":
            name = Path(self.headers.get("X-Filename", "")).name
            name = re.sub(r"[^\w.-]", "_", name)[:100]
            n = int(self.headers.get("Content-Length", 0))
            if Path(name).suffix.lower() not in UPLOAD_EXT:
                return self.send_json({"error": f"allowed types: {', '.join(sorted(UPLOAD_EXT))}"}, 400)
            if not 0 < n <= MAX_UPLOAD:
                return self.send_json({"error": "file empty or larger than 60 MB"}, 400)
            UPLOADS.mkdir(parents=True, exist_ok=True)
            dest = UPLOADS / name
            remaining = n
            with dest.open("wb") as f:
                while remaining:
                    chunk = self.rfile.read(min(remaining, 1 << 20))
                    if not chunk:
                        break
                    f.write(chunk)
                    remaining -= len(chunk)
            self.send_json({"path": str(dest.relative_to(PROJECT))})
        else:
            self.send_json({"error": "not found"}, 404)

    def stream_events(self, job_id, idx):
        job = current
        if not job or job.id != job_id:
            return self.send_json({"error": "no such job"}, 404)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            while True:
                with job.cond:
                    while len(job.events) <= idx and not job.done:
                        if not job.cond.wait(timeout=15):
                            break
                    batch = job.events[idx:]
                    finished = job.done and len(job.events) <= idx + len(batch)
                if not batch and not finished:
                    self.wfile.write(b": keepalive\n\n")
                for ev in batch:
                    idx += 1
                    self.wfile.write(f"id: {idx}\ndata: {json.dumps(ev)}\n\n".encode())
                self.wfile.flush()
                if finished:
                    self.wfile.write(b"event: end\ndata: {}\n\n")
                    self.wfile.flush()
                    return
        except (BrokenPipeError, ConnectionResetError):
            return


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    srv.daemon_threads = True
    print(f"awr-analyst UI on http://localhost:{PORT}  (project {PROJECT})")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
