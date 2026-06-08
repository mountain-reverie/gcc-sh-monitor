#!/usr/bin/env python3
"""Unit tests for sh_density_metrics (pure formatter; no toolchain needed)."""
import json
import subprocess
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import sh_density_metrics as m  # noqa: E402


class TestPct(unittest.TestCase):
    def test_smaller_candidate_is_positive(self):
        self.assertAlmostEqual(m.pct(1000, 900), 10.0)

    def test_larger_candidate_is_negative(self):
        self.assertAlmostEqual(m.pct(1000, 1100), -10.0)

    def test_zero_reference_does_not_crash(self):
        self.assertEqual(m.pct(0, 0), 0.0)
        self.assertEqual(m.pct(0, 5), 0.0)


class TestBuildMetrics(unittest.TestCase):
    def setUp(self):
        self.raw = {
            "density": {
                "csibe":    {"m2": 200, "m2a": 180, "m4": 220, "common": 50},
                "coremark": {"m2": 10,  "m2a": 9,   "m4": 11,  "common": 3},
            },
            "busybox": {"m2": 100, "m4": 90, "common": 7},
        }
        self.byname = {d["name"]: d for d in m.build_metrics(self.raw)}

    def test_density_per_corpus_names_present(self):
        for c in ("csibe", "coremark"):
            for isa in ("m2", "m2a", "m4"):
                self.assertIn(f"sh_density_{c}_text_bytes_{isa}", self.byname)
            self.assertIn(f"sh_density_{c}_objects_common", self.byname)

    def test_density_totals_exclude_busybox(self):
        # Totals are CSiBE + CoreMark only; busybox (100/90) must not be added.
        self.assertEqual(self.byname["sh_density_total_text_bytes_m2"]["value"], 210)
        self.assertEqual(self.byname["sh_density_total_text_bytes_m2a"]["value"], 189)
        self.assertEqual(self.byname["sh_density_total_text_bytes_m4"]["value"], 231)

    def test_density_delta_signs(self):
        self.assertAlmostEqual(
            self.byname["sh_density_total_m2a_vs_m2_pct"]["value"],
            round((210 - 189) / 210 * 100, 3),
        )
        self.assertGreater(self.byname["sh_density_total_m2a_vs_m2_pct"]["value"], 0)
        self.assertGreater(self.byname["sh_density_total_m2_vs_m4_pct"]["value"], 0)
        self.assertGreater(self.byname["sh_density_total_m2a_vs_m4_pct"]["value"], 0)

    def test_busybox_is_separate_m2_vs_m4(self):
        self.assertEqual(self.byname["sh_density_busybox_text_bytes_m2"]["value"], 100)
        self.assertEqual(self.byname["sh_density_busybox_text_bytes_m4"]["value"], 90)
        self.assertEqual(self.byname["sh_density_busybox_objects_common"]["value"], 7)
        # m4 (90) smaller than m2 (100): m2_vs_m4 is negative (m2 is bigger).
        self.assertAlmostEqual(
            self.byname["sh_density_busybox_m2_vs_m4_pct"]["value"],
            round((90 - 100) / 90 * 100, 3),
        )
        # BusyBox must NOT have an m2a metric.
        self.assertNotIn("sh_density_busybox_text_bytes_m2a", self.byname)

    def test_units(self):
        self.assertEqual(self.byname["sh_density_csibe_text_bytes_m2"]["unit"], "bytes")
        self.assertEqual(self.byname["sh_density_csibe_objects_common"]["unit"], "count")
        self.assertEqual(self.byname["sh_density_total_m2a_vs_m2_pct"]["unit"], "percent")
        self.assertEqual(self.byname["sh_density_busybox_m2_vs_m4_pct"]["unit"], "percent")


class TestRobustness(unittest.TestCase):
    def test_empty_input_does_not_crash(self):
        byname = {d["name"]: d["value"] for d in m.build_metrics({})}
        # Totals present and zero; busybox present and zero; deltas zero.
        self.assertEqual(byname["sh_density_total_text_bytes_m2"], 0)
        self.assertEqual(byname["sh_density_busybox_text_bytes_m4"], 0)
        self.assertEqual(byname["sh_density_total_m2a_vs_m2_pct"], 0.0)


class TestCLI(unittest.TestCase):
    RAW = {
        "density": {
            "csibe":    {"m2": 5, "m2a": 4, "m4": 6, "common": 2},
            "coremark": {"m2": 0, "m2a": 0, "m4": 0, "common": 0},
        },
        "busybox": {"m2": 1, "m4": 1, "common": 1},
    }

    def test_reads_stdin_and_emits_array(self):
        out = subprocess.run(
            [sys.executable, str(HERE / "sh_density_metrics.py")],
            input=json.dumps(self.RAW), capture_output=True, text=True, check=True,
        )
        arr = json.loads(out.stdout)
        self.assertTrue(any(d["name"] == "sh_density_total_text_bytes_m2" for d in arr))

    def test_reads_file_argument(self):
        import os
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(self.RAW, f)
            path = f.name
        try:
            out = subprocess.run(
                [sys.executable, str(HERE / "sh_density_metrics.py"), path],
                capture_output=True, text=True, check=True,
            )
        finally:
            os.unlink(path)
        byname = {d["name"]: d["value"] for d in json.loads(out.stdout)}
        self.assertEqual(byname["sh_density_total_text_bytes_m2"], 5)
        self.assertEqual(byname["sh_density_busybox_text_bytes_m2"], 1)


if __name__ == "__main__":
    unittest.main()
