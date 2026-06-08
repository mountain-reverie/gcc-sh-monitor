#!/usr/bin/env python3
"""Format raw per-corpus per-ISA .text totals into benchmark-action metrics.

Input (file arg or stdin) is a JSON object:
    { "<corpus>": {"m2": int, "m2a": int, "m4": int, "common": int}, ... }

Output (stdout) is a JSON array of {name, unit, value}, matching the repo's
metric convention (see scripts/merge-metrics.py). Emits per-corpus .text byte
totals + common-object counts, grand totals per ISA, and the three headline
density deltas (percent, positive = first-named ISA is smaller).
"""
import json
import sys
from pathlib import Path

ISAS = ("m2", "m2a", "m4")


def pct(reference, candidate):
    """Percent that `candidate` is smaller than `reference` (>0 == smaller)."""
    if reference == 0:
        return 0.0
    return round((reference - candidate) / reference * 100.0, 3)


def build_metrics(raw):
    metrics = []
    totals = {isa: 0 for isa in ISAS}
    for corpus in sorted(raw):
        c = raw[corpus]
        for isa in ISAS:
            v = int(c.get(isa, 0))
            totals[isa] += v
            metrics.append({"name": f"sh_density_{corpus}_text_bytes_{isa}",
                            "unit": "bytes", "value": v})
        metrics.append({"name": f"sh_density_{corpus}_objects_common",
                        "unit": "count", "value": int(c.get("common", 0))})
    for isa in ISAS:
        metrics.append({"name": f"sh_density_total_text_bytes_{isa}",
                        "unit": "bytes", "value": totals[isa]})
    metrics.append({"name": "sh_density_total_m2a_vs_m2_pct",
                    "unit": "percent", "value": pct(totals["m2"], totals["m2a"])})
    metrics.append({"name": "sh_density_total_m2_vs_m4_pct",
                    "unit": "percent", "value": pct(totals["m4"], totals["m2"])})
    metrics.append({"name": "sh_density_total_m2a_vs_m4_pct",
                    "unit": "percent", "value": pct(totals["m4"], totals["m2a"])})
    return metrics


def main(argv):
    if len(argv) > 1:
        raw = json.loads(Path(argv[1]).read_text())
    else:
        raw = json.loads(sys.stdin.read())
    json.dump(build_metrics(raw), sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
