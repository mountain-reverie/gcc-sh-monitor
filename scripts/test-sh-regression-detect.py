"""Tests for sh-regression-detect.py."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
SCRIPT = HERE / "sh-regression-detect.py"

def run(build_result, failed_step, failures=None):
    cmd = [sys.executable, str(SCRIPT), build_result, failed_step]
    if failures is not None:
        f = Path(tempfile.mkstemp(suffix=".json")[1])
        f.write_text(json.dumps(failures))
        cmd.append(str(f))
    r = subprocess.run(cmd, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)

def test_build_step_failure_is_build_type():
    out = run("failure", "Build cross GCC")
    assert out["failure_type"] == "build"
    assert out["failed_step"] == "Build cross GCC"
    assert out["regressed_tests"] == []

def test_script_step_failure_is_script_type():
    out = run("failure", "Run BusyBox+musl FDPIC build + smoke + size")
    assert out["failure_type"] == "script"
    assert out["failed_step"] == "Run BusyBox+musl FDPIC build + smoke + size"

def test_dejagnu_regression_when_success_with_new_fails():
    failures = {"fail": [
        {"path": "gcc.target/sh/pr12345.c", "detail": "(test for excess errors)"},
    ], "fail_stale": []}
    out = run("success", "", failures)
    assert out["failure_type"] == "dejagnu"
    assert out["failed_step"] == "Run dejagnu sh.exp"
    assert out["regressed_tests"] == ["gcc.target/sh/pr12345.c (test for excess errors)"]

def test_success_with_empty_fail_is_none():
    out = run("success", "", {"fail": [], "fail_stale": []})
    assert out["failure_type"] == "none"

def test_success_with_no_failures_file_is_none():
    out = run("success", "")
    assert out["failure_type"] == "none"

def test_cancelled_is_none():
    out = run("cancelled", "")
    assert out["failure_type"] == "none"

def test_failure_does_not_read_failures_file():
    # A failure result must ignore the failures file entirely (no crash on a bogus path).
    r = subprocess.run(
        [sys.executable, str(SCRIPT), "failure", "Run musl build + smoke + size", "/nonexistent/x.json"],
        capture_output=True, text=True,
    )
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["failure_type"] == "script"

if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t(); print(f"PASS {t.__name__}")
        except AssertionError as e:
            print(f"FAIL {t.__name__}: {e}"); failed += 1
    sys.exit(failed)
