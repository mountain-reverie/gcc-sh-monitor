#!/usr/bin/env python3
"""Read a dejagnu gcc.sum and emit benchmark-action customSmallerIsBetter JSON.

Output schema (one entry per metric):
  [{"name": "...", "unit": "tests", "value": N}, ...]

Counts the literal occurrences of "^FAIL:" and "^UNRESOLVED:" lines. We
intentionally do NOT use the dejagnu Summary section — it can disagree
with the line counts when tests are filtered out, and the line counts
are what the dashboard's regression detection actually needs.
"""
import json
import re
import sys
from pathlib import Path

PATTERNS = {
    "dejagnu_fail_count":       re.compile(r"^FAIL:", re.MULTILINE),
    "dejagnu_unresolved_count": re.compile(r"^UNRESOLVED:", re.MULTILINE),
}

def parse(sum_path: Path) -> list[dict]:
    text = sum_path.read_text()
    return [
        {"name": name, "unit": "tests", "value": len(pat.findall(text))}
        for name, pat in PATTERNS.items()
    ]

def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <gcc.sum>", file=sys.stderr)
        return 2
    json.dump(parse(Path(argv[1])), sys.stdout, indent=2)
    print()  # trailing newline
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
