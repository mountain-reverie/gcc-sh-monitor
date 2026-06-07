#!/usr/bin/env python3
"""Compute NEW dejagnu failures: those present now but not at the last-green baseline.

The SH lane carries a stable baseline of FAIL lines (e.g. the pr51244 missed-
optimization family) that are deliberately NOT in state/dejagnu-known-stale.json.
extract-failures.py's `.fail` therefore stays non-empty even on a perfectly
green run, so "`.fail` is non-empty" is the wrong regression signal. The real
signal is the *delta* against the previous green run: a test that fails now and
did not fail then.

Usage:
  sh-dejagnu-delta.py <current.json> <baseline.json>

Both inputs are extract-failures.py output objects (with a `.fail` array of
{path, detail}). Emits JSON `{"fail": [ ...current fails absent from baseline ]}`
on stdout. Identity is the (path, detail) pair.
"""
import json
import sys
from pathlib import Path


def delta(current: dict, baseline: dict) -> dict:
    base_sigs = {(e["path"], e["detail"]) for e in baseline.get("fail", [])}
    new = [e for e in current.get("fail", []) if (e["path"], e["detail"]) not in base_sigs]
    return {"fail": new}


def main(argv):
    if len(argv) != 3:
        print("usage: sh-dejagnu-delta.py <current.json> <baseline.json>", file=sys.stderr)
        return 2
    current = json.loads(Path(argv[1]).read_text())
    baseline = json.loads(Path(argv[2]).read_text())
    print(json.dumps(delta(current, baseline)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
