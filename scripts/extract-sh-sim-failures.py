#!/usr/bin/env python3
"""Extract regression-candidate execution FAILs from sh-sim torture sums.

Reads <sums-dir>/{execute,ieee}-{m2,m2a,m4}.sum (written by run-sh-sim.sh) and
emits the EXECUTION FAILs with the ISA folded into the path, so the generic
sh-dejagnu-delta.py can key on (path, detail):

  {"commit": "...", "date": "...Z",
   "fail":       [{"path": "<isa>:<testpath>", "detail": "<rest>"}, ...],
   "fail_xfail": [ ...known compare-fp sim gaps, never counted... ]}

Only execution results count (compile/"excess errors" lines are ignored):
torture lines end "... execution test"; ieee lines contain "... execution,".
The known SH-sim FP gaps (compare-fp-1/4.c, NaN/unordered fcmp) go to fail_xfail
and never to fail. Keep KNOWN_FP_XFAIL in sync with parse-sh-sim.py.
"""
import datetime as dt
import json
import re
import sys
from pathlib import Path

ISAS = ("m2", "m2a", "m4")
SUITES = ("execute", "ieee")
KNOWN_FP_XFAIL = ("compare-fp-1.c", "compare-fp-4.c")   # sync w/ parse-sh-sim.py
FAIL_LINE = re.compile(r"^FAIL: (\S+)\s*(.*?)\s*$", re.MULTILINE)
EXEC_RE = re.compile(r"\bexecution\b")


def is_known_fp_xfail(test_path: str) -> bool:
    return any(test_path.endswith(n) for n in KNOWN_FP_XFAIL)


def extract(sums_dir: Path, commit: str) -> dict:
    fail, fail_xfail = [], []
    for isa in ISAS:
        for suite in SUITES:
            p = sums_dir / f"{suite}-{isa}.sum"
            if not p.is_file():
                continue
            for m in FAIL_LINE.finditer(p.read_text(errors="replace")):
                path, detail = m.group(1), m.group(2)
                if not EXEC_RE.search(detail):   # execution fails only, not compile
                    continue
                entry = {"path": f"{isa}:{path}", "detail": detail}
                (fail_xfail if is_known_fp_xfail(path) else fail).append(entry)
    return {
        "commit": commit,
        "date": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "fail": fail,
        "fail_xfail": fail_xfail,
    }


def main(argv):
    if len(argv) != 3:
        print(f"usage: {argv[0]} <sh-sim-out-dir> <commit-sha>", file=sys.stderr)
        return 2
    json.dump(extract(Path(argv[1]), argv[2]), sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
