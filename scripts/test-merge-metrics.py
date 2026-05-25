# scripts/test-merge-metrics.py
"""Tests for merge-metrics.py."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
FIXTURES = HERE.parent / "tests" / "fixtures"
MERGER = HERE / "merge-metrics.py"

def run_merger(*paths) -> list[dict]:
    result = subprocess.run(
        [sys.executable, str(MERGER), *(str(p) for p in paths)],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)

def test_concatenates_two_files_in_order():
    out = run_merger(FIXTURES / "metrics-a.json", FIXTURES / "metrics-b.json")
    assert [e["name"] for e in out] == ["alpha", "beta", "gamma"], out

def test_single_file_passes_through():
    out = run_merger(FIXTURES / "metrics-a.json")
    assert len(out) == 1
    assert out[0]["name"] == "alpha"

def test_zero_files_emits_empty_array():
    out = run_merger()
    assert out == []

def test_missing_file_aborts_nonzero():
    result = subprocess.run(
        [sys.executable, str(MERGER), "/does/not/exist.json"],
        capture_output=True, text=True,
    )
    assert result.returncode != 0, result.stdout

def test_malformed_json_aborts_nonzero():
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        f.write("not json")
        bad = Path(f.name)
    result = subprocess.run(
        [sys.executable, str(MERGER), str(bad)],
        capture_output=True, text=True,
    )
    assert result.returncode != 0

def test_non_array_input_aborts_nonzero():
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        f.write('{"not": "an array"}')
        path = Path(f.name)
    result = subprocess.run(
        [sys.executable, str(MERGER), str(path)],
        capture_output=True, text=True,
    )
    assert result.returncode != 0

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
