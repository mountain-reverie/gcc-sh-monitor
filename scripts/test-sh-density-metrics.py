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
            "busybox":  {"m2": 100, "m2a": 90,  "m4": 110, "common": 7},
            "csibe":    {"m2": 200, "m2a": 180, "m4": 220, "common": 50},
            "coremark": {"m2": 10,  "m2a": 9,   "m4": 11,  "common": 3},
        }
        self.byname = {d["name"]: d for d in m.build_metrics(self.raw)}

    def test_per_corpus_names_present(self):
        for c in ("busybox", "csibe", "coremark"):
            for isa in ("m2", "m2a", "m4"):
                self.assertIn(f"sh_density_{c}_text_bytes_{isa}", self.byname)
            self.assertIn(f"sh_density_{c}_objects_common", self.byname)

    def test_totals_are_summed(self):
        self.assertEqual(self.byname["sh_density_total_text_bytes_m2"]["value"], 310)
        self.assertEqual(self.byname["sh_density_total_text_bytes_m2a"]["value"], 279)
        self.assertEqual(self.byname["sh_density_total_text_bytes_m4"]["value"], 341)

    def test_delta_values_and_signs(self):
        self.assertAlmostEqual(
            self.byname["sh_density_total_m2a_vs_m2_pct"]["value"],
            round((310 - 279) / 310 * 100, 3),
        )
        # m2a smaller than m2, and m2 smaller than m4 -> both positive.
        self.assertGreater(self.byname["sh_density_total_m2a_vs_m2_pct"]["value"], 0)
        self.assertGreater(self.byname["sh_density_total_m2_vs_m4_pct"]["value"], 0)
        self.assertGreater(self.byname["sh_density_total_m2a_vs_m4_pct"]["value"], 0)

    def test_units(self):
        self.assertEqual(self.byname["sh_density_busybox_text_bytes_m2"]["unit"], "bytes")
        self.assertEqual(self.byname["sh_density_busybox_objects_common"]["unit"], "count")
        self.assertEqual(self.byname["sh_density_total_m2a_vs_m2_pct"]["unit"], "percent")

    def test_common_count_passthrough(self):
        self.assertEqual(self.byname["sh_density_csibe_objects_common"]["value"], 50)


class TestCLI(unittest.TestCase):
    def test_reads_stdin_and_emits_array(self):
        raw = {
            "busybox":  {"m2": 1, "m2a": 1, "m4": 1, "common": 1},
            "csibe":    {"m2": 0, "m2a": 0, "m4": 0, "common": 0},
            "coremark": {"m2": 0, "m2a": 0, "m4": 0, "common": 0},
        }
        out = subprocess.run(
            [sys.executable, str(HERE / "sh_density_metrics.py")],
            input=json.dumps(raw), capture_output=True, text=True, check=True,
        )
        arr = json.loads(out.stdout)
        self.assertTrue(any(d["name"] == "sh_density_total_text_bytes_m2" for d in arr))

    def test_reads_file_argument_and_full_shape(self):
        import os
        import tempfile
        raw = {
            "busybox":  {"m2": 5, "m2a": 4, "m4": 6, "common": 2},
            "csibe":    {"m2": 0, "m2a": 0, "m4": 0, "common": 0},
            "coremark": {"m2": 0, "m2a": 0, "m4": 0, "common": 0},
        }
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(raw, f)
            path = f.name
        try:
            out = subprocess.run(
                [sys.executable, str(HERE / "sh_density_metrics.py"), path],
                capture_output=True, text=True, check=True,
            )
        finally:
            os.unlink(path)
        arr = json.loads(out.stdout)
        byname = {d["name"]: d["value"] for d in arr}
        self.assertEqual(byname["sh_density_total_text_bytes_m2"], 5)
        self.assertEqual(len(arr), 18)


if __name__ == "__main__":
    unittest.main()
