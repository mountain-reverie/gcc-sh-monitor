#!/usr/bin/env python3
"""Concatenate per-tool benchmark-action metrics JSONs into one flat array.

Each input file must be a JSON array of {name, unit, value} objects.
Output to stdout. Order preserved: file-by-file, then within each file.

With --skip-missing, input files that don't exist are skipped (with a
warning to stderr) instead of aborting. Used for the multi-arch and
combined merges, where an architecture whose build failed contributes no
metrics file this run — its series simply gets no new point. The sh4
"Merge all metrics" step omits the flag, keeping that merge all-or-nothing.
"""
import json
import sys
from pathlib import Path

def load_array(path: Path) -> list:
    data = json.loads(path.read_text())
    if not isinstance(data, list):
        raise ValueError(f"{path}: top-level must be a JSON array, got {type(data).__name__}")
    return data

def main(argv: list[str]) -> int:
    args = argv[1:]
    skip_missing = False
    if args and args[0] == "--skip-missing":
        skip_missing = True
        args = args[1:]
    out: list = []
    for arg in args:
        path = Path(arg)
        if skip_missing and not path.exists():
            print(f"merge-metrics: skipping missing {path}", file=sys.stderr)
            continue
        out.extend(load_array(path))
    json.dump(out, sys.stdout, indent=2)
    print()
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as e:
        print(f"merge-metrics: {e}", file=sys.stderr)
        sys.exit(1)
