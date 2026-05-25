#!/usr/bin/env python3
"""Tests for parse-dejagnu.py. Run with: python3 scripts/test-parse-dejagnu.py"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
FIXTURE = HERE.parent / "tests" / "fixtures" / "sample.sum"
PARSER = HERE / "parse-dejagnu.py"

def run_parser(sum_path: Path) -> list[dict]:
    result = subprocess.run(
        [sys.executable, str(PARSER), str(sum_path)],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)

def test_emits_expected_metric_names():
    entries = run_parser(FIXTURE)
    names = {e["name"] for e in entries}
    assert names == {"dejagnu_fail_count", "dejagnu_unresolved_count"}, \
        f"unexpected names: {names}"

def test_fail_count_matches_fixture():
    entries = run_parser(FIXTURE)
    fail = next(e for e in entries if e["name"] == "dejagnu_fail_count")
    # Two FAIL lines in the fixture.
    assert fail["value"] == 2, fail
    assert fail["unit"] == "tests"

def test_unresolved_count_matches_fixture():
    entries = run_parser(FIXTURE)
    unres = next(e for e in entries if e["name"] == "dejagnu_unresolved_count")
    # One UNRESOLVED line.
    assert unres["value"] == 1, unres
    assert unres["unit"] == "tests"

def test_output_is_a_json_list():
    entries = run_parser(FIXTURE)
    assert isinstance(entries, list)
    for e in entries:
        assert set(e.keys()) >= {"name", "unit", "value"}, e

def test_handles_missing_categories():
    # Synthesise a sum with no FAIL lines at all.
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".sum", delete=False) as f:
        f.write("PASS: foo (test)\nUNSUPPORTED: bar\n")
        path = Path(f.name)
    entries = run_parser(path)
    fail = next(e for e in entries if e["name"] == "dejagnu_fail_count")
    assert fail["value"] == 0

if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t()
            print(f"PASS {t.__name__}")
        except AssertionError as e:
            print(f"FAIL {t.__name__}: {e}")
            failed += 1
    sys.exit(failed)
