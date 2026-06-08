#!/usr/bin/env python3
"""Format raw SH code-density measurements into benchmark-action metrics.

Input (file arg or stdin) is a JSON object:
  {
    "density": { "<corpus>": {"m2": int, "m2a": int, "m4": int, "common": int}, ... },
    "busybox": {"m2": int, "m4": int, "common": int}
  }

The "density" corpora (CSiBE, CoreMark) are compiled BIG-ENDIAN and compared
three-way (m2/m2a/m4): GCC has no little-endian SH-2A, and .text *size* is
endian-invariant so the byte counts still answer the density question for
little-endian J-Core. "busybox" is compiled LITTLE-ENDIAN and compared
m2-vs-m4 only — its kbuild can't produce big-endian (hence no SH-2A) objects —
and is kept OUT of the density totals/deltas.

Output (stdout): a JSON array of {name, unit, value} (the repo's metric
convention; see scripts/merge-metrics.py). Deltas are percent, positive =
first-named ISA is smaller (denser).
"""
import json
import sys
from pathlib import Path

DENSITY_ISAS = ("m2", "m2a", "m4")


def pct(reference, candidate):
    """Percent that `candidate` is smaller than `reference` (>0 == smaller)."""
    if reference == 0:
        return 0.0
    return round((reference - candidate) / reference * 100.0, 3)


def build_metrics(raw):
    metrics = []

    # Density comparison: CSiBE + CoreMark, three-way (big-endian).
    density = raw.get("density", {})
    totals = {isa: 0 for isa in DENSITY_ISAS}
    for corpus in sorted(density):
        c = density[corpus]
        for isa in DENSITY_ISAS:
            v = int(c.get(isa, 0))
            totals[isa] += v
            metrics.append({"name": f"sh_density_{corpus}_text_bytes_{isa}",
                            "unit": "bytes", "value": v})
        metrics.append({"name": f"sh_density_{corpus}_objects_common",
                        "unit": "count", "value": int(c.get("common", 0))})
    for isa in DENSITY_ISAS:
        metrics.append({"name": f"sh_density_total_text_bytes_{isa}",
                        "unit": "bytes", "value": totals[isa]})
    metrics.append({"name": "sh_density_total_m2a_vs_m2_pct",
                    "unit": "percent", "value": pct(totals["m2"], totals["m2a"])})
    metrics.append({"name": "sh_density_total_m2_vs_m4_pct",
                    "unit": "percent", "value": pct(totals["m4"], totals["m2"])})
    metrics.append({"name": "sh_density_total_m2a_vs_m4_pct",
                    "unit": "percent", "value": pct(totals["m4"], totals["m2a"])})

    # BusyBox: little-endian, m2-vs-m4 only, separate from the density totals.
    bb = raw.get("busybox", {})
    bb_m2 = int(bb.get("m2", 0))
    bb_m4 = int(bb.get("m4", 0))
    metrics.append({"name": "sh_density_busybox_text_bytes_m2",
                    "unit": "bytes", "value": bb_m2})
    metrics.append({"name": "sh_density_busybox_text_bytes_m4",
                    "unit": "bytes", "value": bb_m4})
    metrics.append({"name": "sh_density_busybox_objects_common",
                    "unit": "count", "value": int(bb.get("common", 0))})
    metrics.append({"name": "sh_density_busybox_m2_vs_m4_pct",
                    "unit": "percent", "value": pct(bb_m4, bb_m2)})
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
