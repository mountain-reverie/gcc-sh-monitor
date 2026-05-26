#!/usr/bin/env python3
"""Extract FAIL and UNRESOLVED lines from a dejagnu gcc.sum into JSON.

Output:
  {
    "commit": "<upstream-sha>",
    "date":   "<run-time, ISO8601 UTC with Z>",
    "fail":             [{"path": "...", "detail": "..."}, ...],
    "fail_stale":       [{"path": "...", "detail": "..."}, ...],
    "unresolved":       [{"path": "...", "detail": "..."}, ...],
    "unresolved_stale": [{"path": "...", "detail": "..."}, ...]
  }

Each entry's "path" is the first whitespace-separated token after the
"<STATUS>: " prefix; "detail" is everything after that (the failure
reason or assertion name).

If an optional known-stale annotation file is provided, entries whose
"<path> <detail>" signature appears in its "stale" list are routed
into the "*_stale" arrays instead of the active arrays.
"""
import datetime as dt
import json
import re
import sys
from pathlib import Path

LINE_RE = {
    "fail":       re.compile(r"^FAIL:\s+(\S+)\s*(.*)$", re.MULTILINE),
    "unresolved": re.compile(r"^UNRESOLVED:\s+(\S+)\s*(.*)$", re.MULTILINE),
}

def load_stale_signatures(path: Path) -> set[str]:
    data = json.loads(path.read_text())
    return {entry["fail_signature"] for entry in data.get("stale", [])}

def partition(entries: list[dict], stale: set[str]) -> tuple[list[dict], list[dict]]:
    active, drifted = [], []
    for e in entries:
        sig = f"{e['path']} {e['detail']}"
        (drifted if sig in stale else active).append(e)
    return active, drifted

def extract(sum_path: Path, commit: str, stale: set[str] | None = None) -> dict:
    text = sum_path.read_text()
    stale = stale or set()
    fail_all       = [{"path": p, "detail": d} for p, d in LINE_RE["fail"].findall(text)]
    unresolved_all = [{"path": p, "detail": d} for p, d in LINE_RE["unresolved"].findall(text)]
    fail, fail_stale             = partition(fail_all, stale)
    unresolved, unresolved_stale = partition(unresolved_all, stale)
    return {
        "commit": commit,
        "date":   dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "fail":             fail,
        "fail_stale":       fail_stale,
        "unresolved":       unresolved,
        "unresolved_stale": unresolved_stale,
    }

def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        print(f"usage: {argv[0]} <gcc.sum> <commit-sha> [<known-stale.json>]", file=sys.stderr)
        return 2
    stale = load_stale_signatures(Path(argv[3])) if len(argv) == 4 else None
    json.dump(extract(Path(argv[1]), argv[2], stale), sys.stdout, indent=2)
    print()
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
