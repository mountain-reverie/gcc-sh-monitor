#!/usr/bin/env python3
"""Append _sh4 to historical sh4-only metric names in benchmark-data.json.

Rewrites the file in place. Idempotent — names already ending in
_sh4/_arm/_x86 are left untouched. Names of the dejagnu_* / lra_*
families are sh4-only by design and never get a suffix.

Usage:
  migrate-benchmark-data.py <path-to-benchmark-data.json>

Exits 0 on success, nonzero if the file is missing or malformed.
"""
import json
import sys
from pathlib import Path

SUFFIX_PREFIXES = ("csibe_", "coremark_", "busybox_", "musl_")
KNOWN_ARCH_SUFFIXES = ("_sh4", "_arm", "_x86", "_riscv32")


def maybe_rename(name: str) -> str:
    # Repair: riscv32 was once missing from KNOWN_ARCH_SUFFIXES, so
    # busybox_*_riscv32 metrics wrongly received a second _sh4 suffix
    # (..._riscv32_sh4). Strip it back. Idempotent once names are clean.
    if name.endswith("_riscv32_sh4"):
        return name[: -len("_sh4")]
    if not name.startswith(SUFFIX_PREFIXES):
        return name
    if name.endswith(KNOWN_ARCH_SUFFIXES):
        return name
    return name + "_sh4"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <benchmark-data.json>", file=sys.stderr)
        return 2
    path = Path(argv[1])
    data = json.loads(path.read_text())
    for suite_runs in (data.get("entries") or {}).values():
        for run in suite_runs:
            for bench in run.get("benches", []):
                bench["name"] = maybe_rename(bench["name"])
    path.write_text(json.dumps(data, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"migrate-benchmark-data: {e}", file=sys.stderr)
        sys.exit(1)
