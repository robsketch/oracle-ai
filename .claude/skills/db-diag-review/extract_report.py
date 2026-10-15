#!/usr/bin/env python3
"""Condense an Oracle diagnostic file into the parts worth reading.

Used by /db-diag-review in file mode, for files someone hands you rather than ones fetched
over MCP. Detects the file type and prints a bounded plain-text extract:

  awr-html / awr-text / statspack  -> header plus key sections (load profile, top events,
                                      time model, top SQL, tablespace I/O, ...)
  alert-log                        -> error / warning / lifecycle lines (+ context), last N days
  trace                            -> file header plus a window around each serious signature

Reading an AWR report someone else generated needs no Diagnostics Pack licence on our side;
this script never connects to a database. Standard library only.
Run with: python3 -I extract_report.py <file> [--days N] [--max-lines N]
"""
import argparse
import html
import re
import sys
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser

END_RULE = re.compile(r"^\s*-{40,}\s*$")          # section terminator in AWR/Statspack text
PAGE_HDR = re.compile(r"DB/Inst:|^\s*AWR\b.*Report", re.I)

# Section headings to keep, with a per-section line cap. Names differ slightly between
# AWR text, AWR HTML and Statspack, so match on prefixes.
SECTIONS = [
    (r"Load Profile", 40),
    (r"Instance Efficiency (Percentages|Indicators)", 25),
    (r"Top \d+ (Timed|Foreground)", 30),
    (r"Top Timed Events|Top \d+ Timed", 30),
    (r"Wait Classes by Total Wait Time", 20),
    (r"Host CPU", 12),
    (r"Instance CPU", 12),
    (r"Time Model (System )?Stat", 30),
    (r"Foreground Wait Events", 40),
    (r"SQL ordered by Elapsed", 70),
    (r"SQL ordered by CPU", 70),
    (r"SQL ordered by User I/O", 50),
    (r"SQL ordered by Gets", 60),
    (r"SQL ordered by Reads", 50),
    (r"SQL ordered by Parse Calls", 40),
    (r"Tablespace IO Stats", 30),
    (r"Segments by Row Lock Waits", 25),
    (r"Enqueue Activity", 25),
    (r"Undo Segment Summary", 20),
    (r"Instance Recovery Stats", 15),
    (r"Shared Pool Advisory", 25),
    (r"Complete List of SQL Text(?! for Replication)", 80),
]
SECTION_RES = [(re.compile(r"^\s*" + p, re.I), cap) for p, cap in SECTIONS]

ALERT_PAT = re.compile(
    r"ORA-|TNS-|deadlock|checkpoint not complete|cannot allocate new log|archiver|corrupt|"
    r"terminating the instance|instance terminated|longer than expected|cannot be elevated|"
    r"persistent data failure|WARNING|Errors in file|incident=", re.I)
LIFECYCLE_PAT = re.compile(
    r"Starting ORACLE instance|Shutting down ORACLE instance|Instance shutdown complete|"
    r"Beginning crash recovery|Crash Recovery|Shutting down instance \(abort\)|"
    r"Completed: ALTER DATABASE OPEN", re.I)
TRACE_PAT = re.compile(
    r"ORA-0*600[^0-9]|ORA-0*7445|ORA-0*4031|ORA-0*1578|ORA-0*1110|Corrupt block|"
    r"DEADLOCK DETECTED|ORA-00800|ORA-0*1555|ORA-0*165[234]|ORA-0*1688", re.I)
ISO_TS = re.compile(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})")


class HtmlToText(HTMLParser):
    """Flatten an AWR HTML report: headings on their own line, table rows joined with ' | ',
    and a dash rule after each table so the text section logic applies unchanged.
    Table-of-contents entries (an <li> that is nothing but an in-page link) are dropped,
    otherwise they look like section headings."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.lines, self.buf, self.row = [], [], None
        self.skip = 0
        self.in_li, self.link_buf = False, None

    def _flush(self):
        text = re.sub(r"\s+", " ", "".join(self.buf)).strip()
        if text:
            self.lines.append(text)
        self.buf = []

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self.skip += 1
        elif tag in ("h1", "h2", "h3", "h4", "p", "br", "li", "table"):
            self._flush()
            if tag == "li":
                self.in_li, self.link_buf = True, None
        elif tag == "a" and self.in_li and dict(attrs).get("href", "").startswith("#"):
            self.link_buf = []
        elif tag == "tr":
            self._flush()
            self.row = []
        elif tag in ("td", "th") and self.row is not None:
            self.buf = []

    def handle_endtag(self, tag):
        if tag in ("script", "style"):
            self.skip -= 1
        elif tag in ("td", "th") and self.row is not None:
            self.row.append(re.sub(r"\s+", " ", "".join(self.buf)).strip())
            self.buf = []
        elif tag == "tr" and self.row is not None:
            if any(self.row):
                self.lines.append(" | ".join(self.row))
            self.row = None
        elif tag == "table":
            self._flush()
            self.lines.append("-" * 60)
        elif tag == "li":
            text = re.sub(r"\s+", " ", "".join(self.buf)).strip()
            link = re.sub(r"\s+", " ", "".join(self.link_buf or [])).strip()
            if link and link == text:      # TOC entry
                self.buf = []
            self._flush()
            self.in_li, self.link_buf = False, None
        elif tag in ("h1", "h2", "h3", "h4", "p"):
            self._flush()

    def handle_data(self, data):
        if not self.skip:
            self.buf.append(data)
            if self.link_buf is not None:
                self.link_buf.append(data)


def detect(text):
    head = text[:20000]
    if re.search(r"<html|<!DOCTYPE html", head, re.I):
        return "awr-html" if re.search(r"WORKLOAD REPOSITORY|AWR Report", head, re.I) else "html"
    if "WORKLOAD REPOSITORY report for" in head or "WORKLOAD REPOSITORY REPORT" in head:
        return "awr-text"
    if "STATSPACK report for" in head:
        return "statspack"
    if head.startswith("Trace file ") or re.search(r"^Trace file /", head, re.M):
        return "trace"
    if "<msg " in head and "org_id=" in head:
        return "alert-xml"
    if ISO_TS.search(head) or re.search(r"^\w{3} \w{3} \d{1,2} \d{2}:\d{2}:\d{2} \d{4}$", head, re.M):
        return "alert-log"
    return "unknown"


def extract_sections(lines, max_lines):
    out = ["### header"]
    for ln in lines[:40]:
        if SECTION_RES[0][0].match(ln):
            break
        out.append(ln)
    found = []
    i = 0
    while i < len(lines):
        ln = lines[i]
        hit = next(((rx, cap) for rx, cap in SECTION_RES if rx.match(ln)), None)
        if not hit:
            i += 1
            continue
        title = re.sub(r"\s+DB/Inst:.*", "", ln).strip()
        cont = " (continued)" if found and found[-1] == title else ""   # AWR text page break
        found.append(title)
        out.append(f"\n### {title}{cont}")
        out.append(ln)
        n, j = 0, i + 1
        while j < len(lines) and n < hit[1]:
            if END_RULE.match(lines[j]):
                break
            if j > i + 2 and any(rx.match(lines[j]) for rx, _ in SECTION_RES):
                break
            out.append(lines[j])
            n += 1
            j += 1
        if n >= hit[1]:
            out.append(f"... [section truncated at {hit[1]} lines]")
        i = j
    missing = [p for p, _ in SECTIONS if not any(re.match(p, t, re.I) for t in found)]
    out.append(f"\n### extractor notes\nsections found: {len(found)}; "
               f"patterns with no match: {', '.join(missing) or 'none'}")
    return out[:max_lines]


def extract_alert(lines, days, max_lines):
    """Plain-text alert log: each record starts with an ISO timestamp line."""
    records, cur_ts, cur = [], None, []
    for ln in lines:
        m = ISO_TS.match(ln)
        if m:
            if cur:
                records.append((cur_ts, cur))
            cur_ts, cur = m.group(1), []
        else:
            cur.append(ln)
    if cur:
        records.append((cur_ts, cur))
    if not records or records[-1][0] is None:
        return ["### alert log", "(no ISO-8601 timestamps found; old-style alert log?)"] + lines[-200:]
    newest = datetime.fromisoformat(records[-1][0])
    cutoff = newest - timedelta(days=days)
    out = [f"### alert log: {len(records)} records, newest {records[-1][0]}, window {days} days"]
    kept = 0
    for ts, body in records:
        if ts is None or datetime.fromisoformat(ts) < cutoff:
            continue
        text = " ".join(body)
        if ALERT_PAT.search(text) or LIFECYCLE_PAT.search(text):
            if re.match(r"^\s*Resize operation completed", text) or re.match(r"^\s*[A-Za-z_]+\s*=\s*\S*\s*$", text):
                continue
            out.append(f"{ts}  " + " | ".join(b.strip() for b in body if b.strip())[:400])
            kept += 1
    out.append(f"### {kept} matching records in window")
    return out[:max_lines]


def extract_trace(lines, max_lines):
    out = ["### trace header"] + lines[:40]
    hits = [i for i, ln in enumerate(lines) if TRACE_PAT.search(ln)]
    out.append(f"\n### {len(hits)} signature lines; showing windows around the first 5")
    shown_to = -1
    for i in hits[:5]:
        lo, hi = max(i - 15, shown_to + 1), min(i + 120, len(lines))
        if lo >= hi:
            continue
        out.append(f"\n### lines {lo + 1}-{hi}")
        out.extend(lines[lo:hi])
        shown_to = hi - 1
    return out[:max_lines]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("path")
    ap.add_argument("--days", type=int, default=7, help="alert-log window (default 7)")
    ap.add_argument("--max-lines", type=int, default=1500)
    a = ap.parse_args()
    with open(a.path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    kind = detect(text)
    print(f"### file: {a.path}\n### detected type: {kind}\n### size: {len(text):,} chars")
    if kind in ("awr-html", "html"):
        p = HtmlToText()
        p.feed(text)
        lines = p.lines
    elif kind == "alert-xml":
        msgs = re.findall(r"<msg time='([^']+)'.*?<txt>(.*?)</txt>", text, re.S)
        lines = []
        for ts, body in msgs:
            lines.append(ts[:19])
            lines.extend(html.unescape(body).splitlines())
        kind = "alert-log"
    else:
        lines = text.splitlines()

    if kind in ("awr-html", "awr-text", "statspack", "html"):
        out = extract_sections(lines, a.max_lines)
    elif kind == "alert-log":
        out = extract_alert(lines, a.days, a.max_lines)
    elif kind == "trace":
        out = extract_trace(lines, a.max_lines)
    else:
        out = ["### unknown type: first 100 lines"] + lines[:100]
    print("\n".join(out))
    if len(out) >= a.max_lines:
        print(f"### output capped at {a.max_lines} lines")


if __name__ == "__main__":
    sys.exit(main())
