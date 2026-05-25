#!/usr/bin/env python3
"""Extract FAIL and UNRESOLVED lines from a dejagnu gcc.sum into JSON.

Output:
  {
    "commit": "<upstream-sha>",
    "date":   "<run-time, ISO8601 UTC with Z>",
    "fail":       [{"path": "...", "detail": "..."}, ...],
    "unresolved": [{"path": "...", "detail": "..."}, ...]
  }

Each entry's "path" is the first whitespace-separated token after the
"<STATUS>: " prefix; "detail" is everything after that (the failure
reason or assertion name).
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

def extract(sum_path: Path, commit: str) -> dict:
    text = sum_path.read_text()
    return {
        "commit": commit,
        "date":   dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "fail":       [{"path": p, "detail": d} for p, d in LINE_RE["fail"].findall(text)],
        "unresolved": [{"path": p, "detail": d} for p, d in LINE_RE["unresolved"].findall(text)],
    }

def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} <gcc.sum> <commit-sha>", file=sys.stderr)
        return 2
    json.dump(extract(Path(argv[1]), argv[2]), sys.stdout, indent=2)
    print()
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
