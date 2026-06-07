"""Tests for sh-dejagnu-delta.py."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
SCRIPT = HERE / "sh-dejagnu-delta.py"


def run(current, baseline):
    c = Path(tempfile.mkstemp(suffix=".json")[1]); c.write_text(json.dumps(current))
    b = Path(tempfile.mkstemp(suffix=".json")[1]); b.write_text(json.dumps(baseline))
    r = subprocess.run([sys.executable, str(SCRIPT), str(c), str(b)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def F(path, detail):
    return {"path": path, "detail": detail}


def test_identical_baseline_yields_no_new_failures():
    # The persistent baseline (e.g. pr51244 family) appears in both -> no regression.
    base = {"fail": [F("gcc.target/sh/pr51244-11.c", "scan-assembler-not subc|and|bra"),
                     F("gcc.target/sh/pr55212-c248.c", "(test for excess errors)")]}
    cur = {"fail": list(base["fail"])}
    assert run(cur, base) == {"fail": []}


def test_new_failure_is_reported():
    base = {"fail": [F("gcc.target/sh/pr51244-11.c", "scan-assembler-not subc|and|bra")]}
    cur = {"fail": [F("gcc.target/sh/pr51244-11.c", "scan-assembler-not subc|and|bra"),
                    F("gcc.target/sh/brandnew.c", "(internal compiler error)")]}
    out = run(cur, base)
    assert out["fail"] == [F("gcc.target/sh/brandnew.c", "(internal compiler error)")]


def test_fixed_baseline_failure_is_not_reported():
    # A test that failed at baseline but passes now must NOT appear as a regression.
    base = {"fail": [F("gcc.target/sh/oldfail.c", "x")]}
    cur = {"fail": []}
    assert run(cur, base) == {"fail": []}


def test_empty_baseline_reports_all_current():
    base = {"fail": []}
    cur = {"fail": [F("a.c", "d1"), F("b.c", "d2")]}
    assert run(cur, base)["fail"] == [F("a.c", "d1"), F("b.c", "d2")]


def test_same_path_different_detail_is_distinct():
    base = {"fail": [F("a.c", "scan-assembler-times foo 1")]}
    cur = {"fail": [F("a.c", "scan-assembler-times foo 1"),
                    F("a.c", "scan-assembler-times bar 2")]}
    assert run(cur, base)["fail"] == [F("a.c", "scan-assembler-times bar 2")]


if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t(); print(f"PASS {t.__name__}")
        except AssertionError as e:
            print(f"FAIL {t.__name__}: {e}"); failed += 1
    sys.exit(failed)
