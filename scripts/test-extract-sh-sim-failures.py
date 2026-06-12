"""Tests for extract-sh-sim-failures.py."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
SCRIPT = HERE / "extract-sh-sim-failures.py"

def run(files: dict, commit="deadbeef"):
    d = Path(tempfile.mkdtemp())
    for name, body in files.items():
        (d / name).write_text(body)
    r = subprocess.run([sys.executable, str(SCRIPT), str(d), commit],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)

def test_integer_fail_is_captured_with_isa_in_path():
    out = run({"execute-m2a.sum":
        "PASS: gcc.c-torture/execute/foo.c   -O0  execution test\n"
        "FAIL: gcc.c-torture/execute/foo.c   -O2  execution test\n"})
    assert out["fail"] == [
        {"path": "m2a:gcc.c-torture/execute/foo.c", "detail": "-O2  execution test"}]

def test_compile_only_fail_is_ignored():
    out = run({"execute-m2.sum":
        "FAIL: gcc.c-torture/execute/bar.c   -O2  (test for excess errors)\n"})
    assert out["fail"] == []

def test_known_compare_fp_routed_to_xfail_not_fail():
    out = run({"ieee-m4.sum":
        "FAIL: gcc.c-torture/execute/ieee/compare-fp-1.c   execution,  -O1\n"
        "FAIL: gcc.c-torture/execute/ieee/compare-fp-4.c   execution,  -O2\n"
        "FAIL: gcc.c-torture/execute/ieee/mzero.c   execution,  -O1\n"})
    assert out["fail"] == [
        {"path": "m4:gcc.c-torture/execute/ieee/mzero.c", "detail": "execution,  -O1"}]
    assert len(out["fail_xfail"]) == 2
    xfail_paths = {e["path"] for e in out["fail_xfail"]}
    assert any(p.endswith("compare-fp-1.c") for p in xfail_paths)
    assert any(p.endswith("compare-fp-4.c") for p in xfail_paths)

def test_missing_sums_dir_is_empty():
    out = run({})
    assert out["fail"] == [] and out["fail_xfail"] == []
    assert out["commit"] == "deadbeef"

if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t(); print(f"PASS {t.__name__}")
        except AssertionError as e:
            print(f"FAIL {t.__name__}: {e}"); failed += 1
    sys.exit(failed)
