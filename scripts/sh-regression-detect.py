#!/usr/bin/env python3
"""Classify an SH-lane CI outcome into a regression type for the auto-bisect.

Usage:
  sh-regression-detect.py <build_result> <failed_step> [<failures.json>]

Emits JSON:
  {"failure_type": "build|script|dejagnu|none",
   "failed_step": "<step name or ''>",
   "regressed_tests": ["<path> <detail>", ...]}

- build:   the GCC build step failed.
- script:  some other build-and-test step exited non-zero (smoke/size script).
- dejagnu: the job succeeded but extract-failures.py reports new (non-stale)
           FAILs — a test regression that does not fail the job.
- none:    SH is green (or run was cancelled/skipped).
"""
import json
import sys
from pathlib import Path

BUILD_STEP = "Build cross GCC"
DEJAGNU_STEP = "Run dejagnu sh.exp"

def classify(build_result: str, failed_step: str, failures: dict | None) -> dict:
    if build_result == "failure":
        if failed_step == BUILD_STEP:
            return {"failure_type": "build", "failed_step": failed_step, "regressed_tests": []}
        return {"failure_type": "script", "failed_step": failed_step or "", "regressed_tests": []}
    if build_result == "success":
        fails = (failures or {}).get("fail", [])
        if fails:
            tests = [f"{e['path']} {e['detail']}".strip() for e in fails]
            return {"failure_type": "dejagnu", "failed_step": DEJAGNU_STEP, "regressed_tests": tests}
    return {"failure_type": "none", "failed_step": "", "regressed_tests": []}

def main(argv):
    if len(argv) not in (3, 4):
        print("usage: sh-regression-detect.py <build_result> <failed_step> [failures.json]",
              file=sys.stderr)
        return 2
    build_result, failed_step = argv[1], argv[2]
    failures = None
    if len(argv) == 4:
        failures = json.loads(Path(argv[3]).read_text())
    print(json.dumps(classify(build_result, failed_step, failures)))
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
