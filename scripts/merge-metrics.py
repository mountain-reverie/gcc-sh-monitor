#!/usr/bin/env python3
"""Concatenate per-tool benchmark-action metrics JSONs into one flat array.

Each input file must be a JSON array of {name, unit, value} objects.
Output to stdout. Order preserved: file-by-file, then within each file.
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
    out: list = []
    for arg in argv[1:]:
        out.extend(load_array(Path(arg)))
    json.dump(out, sys.stdout, indent=2)
    print()
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as e:
        print(f"merge-metrics: {e}", file=sys.stderr)
        sys.exit(1)
