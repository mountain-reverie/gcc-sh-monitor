#!/usr/bin/env python3
"""Summarise sh-sim torture-execution sums into benchmark-action metrics JSON.

Input: a directory containing per-(suite,ISA) gcc.sum files written by
run-sh-sim.sh, named "<suite>-<isa>.sum" where suite in {execute, ieee} and
isa in {m2, m2a, m4}. Missing/empty directory => all-zero metrics (the lane
ran in degraded mode because the toolchain build failed).

Output schema (one entry per metric):
  [{"name": "...", "unit": "tests", "value": N}, ...]

Only EXECUTION results are counted (compile/"excess errors" lines are ignored):
torture execute lines end in "execution test"; ieee lines contain "execution,".

Known simulator FP limitation: the binutils-gdb SH sim mishandles NaN/unordered
fcmp, so ieee/compare-fp-1.c and compare-fp-4.c fail on the hardware-FPU
multilibs. These are recorded (sh_sim_known_fp_xfail_count) but EXCLUDED from the
regression-signal fail count, so the badge stays green for them.
"""
import json
import re
import sys
from pathlib import Path

ISAS = ("m2", "m2a", "m4")
SUITES = ("execute", "ieee")
KNOWN_FP_XFAIL = ("compare-fp-1.c", "compare-fp-4.c")

# PASS/FAIL execution lines, capturing the test path (the first token after the
# result). The optimization flags sit AFTER the path in the torture format
# ("<path>  -O2  execution test") but BEFORE "execution" in the ieee format
# ("<path>  execution,  -O1"), so allow anything between path and "execution".
# Compile checks ("(test for excess errors)") lack the word and are excluded.
LINE = re.compile(r"^(PASS|FAIL): (\S+).*\bexecution\b", re.MULTILINE)


def is_known_fp_xfail(test_path: str) -> bool:
    return any(test_path.endswith(name) for name in KNOWN_FP_XFAIL)


def count(sum_path: Path):
    """Return (pass, fail, known_fp_xfail) execution counts for one sum file."""
    if not sum_path.is_file():
        return 0, 0, 0
    text = sum_path.read_text(errors="replace")
    npass = nfail = nxfail = 0
    for m in LINE.finditer(text):
        result, path = m.group(1), m.group(2)
        if result == "PASS":
            npass += 1
        else:  # FAIL
            if is_known_fp_xfail(path):
                nxfail += 1          # known sim gap: not a regression
            else:
                nfail += 1
    return npass, nfail, nxfail


def parse(out_dir: Path) -> list:
    metrics: list = []
    total_pass = total_fail = total_xfail = 0
    # Per-ISA integer counts (the primary execution-coverage signal).
    for isa in ISAS:
        ip, ifail, _ = count(out_dir / f"execute-{isa}.sum")
        metrics.append({"name": f"sh_sim_int_pass_{isa}", "unit": "tests", "value": ip})
        metrics.append({"name": f"sh_sim_int_fail_{isa}", "unit": "tests", "value": ifail})
        total_pass += ip
        total_fail += ifail
    # FP suite folded into the totals (fails minus known sim XFAILs).
    for isa in ISAS:
        fp, ffail, fxfail = count(out_dir / f"ieee-{isa}.sum")
        total_pass += fp
        total_fail += ffail
        total_xfail += fxfail
    # Headline metrics (smaller-is-better): fail count drives the badge.
    metrics.insert(0, {"name": "sh_sim_fail_count", "unit": "tests", "value": total_fail})
    metrics.insert(1, {"name": "sh_sim_pass_count", "unit": "tests", "value": total_pass})
    metrics.insert(2, {"name": "sh_sim_known_fp_xfail_count", "unit": "tests", "value": total_xfail})
    return metrics


def main(argv: list) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <sh-sim-out-dir>", file=sys.stderr)
        return 2
    json.dump(parse(Path(argv[1])), sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
