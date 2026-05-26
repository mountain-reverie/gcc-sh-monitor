"""Tests for extract-failures.py."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
FIXTURE = HERE.parent / "tests" / "fixtures" / "sample.sum"
SCRIPT = HERE / "extract-failures.py"
COMMIT = "abc123def4567890abc123def4567890abc12345"

def run(sum_path: Path, commit: str = COMMIT, stale_path: Path | None = None) -> dict:
    cmd = [sys.executable, str(SCRIPT), str(sum_path), commit]
    if stale_path is not None:
        cmd.append(str(stale_path))
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return json.loads(result.stdout)

def test_emits_commit_date_fail_unresolved_fields():
    out = run(FIXTURE)
    assert set(out.keys()) >= {"commit", "date", "fail", "fail_stale", "unresolved", "unresolved_stale"}, out

def test_commit_passed_through():
    out = run(FIXTURE)
    assert out["commit"] == COMMIT

def test_fail_list_contains_failing_test_paths_and_details():
    out = run(FIXTURE)
    # sample.sum has two FAIL lines for pr55212-01.c
    assert len(out["fail"]) == 2
    for entry in out["fail"]:
        assert set(entry.keys()) == {"path", "detail"}
        assert entry["path"] == "gcc.target/sh/pr55212-01.c"
    # Each FAIL should have a non-empty detail
    details = sorted(e["detail"] for e in out["fail"])
    assert "(internal compiler error)" in details
    assert "(test for excess errors)" in details

def test_unresolved_list_includes_unresolved_lines():
    out = run(FIXTURE)
    assert len(out["unresolved"]) == 1
    e = out["unresolved"][0]
    assert e["path"] == "gcc.target/sh/pr67890.c"
    assert "compilation failed" in e["detail"]

def test_date_is_iso8601_z():
    out = run(FIXTURE)
    # YYYY-MM-DDTHH:MM:SSZ
    import re
    assert re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", out["date"]), out["date"]

def test_handles_no_failures():
    with tempfile.NamedTemporaryFile("w", suffix=".sum", delete=False) as f:
        f.write("PASS: foo (test)\nUNSUPPORTED: bar\n")
        path = Path(f.name)
    out = run(path)
    assert out["fail"] == []
    assert out["unresolved"] == []
    assert out["fail_stale"] == []
    assert out["unresolved_stale"] == []

def test_partitions_known_stale_failures():
    # Synthetic sum: one stale FAIL, one active FAIL, one stale UNRESOLVED,
    # one active UNRESOLVED.
    sum_text = (
        "FAIL: gcc.target/sh/stalefail.c scan-assembler-times foo 1\n"
        "FAIL: gcc.target/sh/activefail.c (internal compiler error)\n"
        "UNRESOLVED: gcc.target/sh/staleun.c whatever\n"
        "UNRESOLVED: gcc.target/sh/activeun.c compilation failed\n"
    )
    stale_json = {
        "description": "test",
        "stale": [
            {"fail_signature": "gcc.target/sh/stalefail.c scan-assembler-times foo 1",
             "reason": "x", "first_seen": "2026-05-26"},
            {"fail_signature": "gcc.target/sh/staleun.c whatever",
             "reason": "y", "first_seen": "2026-05-26"},
        ],
    }
    with tempfile.NamedTemporaryFile("w", suffix=".sum", delete=False) as f:
        f.write(sum_text)
        sum_path = Path(f.name)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(stale_json, f)
        stale_path = Path(f.name)
    out = run(sum_path, stale_path=stale_path)
    assert len(out["fail"]) == 1 and out["fail"][0]["path"] == "gcc.target/sh/activefail.c", out
    assert len(out["fail_stale"]) == 1 and out["fail_stale"][0]["path"] == "gcc.target/sh/stalefail.c", out
    assert len(out["unresolved"]) == 1 and out["unresolved"][0]["path"] == "gcc.target/sh/activeun.c", out
    assert len(out["unresolved_stale"]) == 1 and out["unresolved_stale"][0]["path"] == "gcc.target/sh/staleun.c", out

def test_no_annotation_means_empty_stale_arrays():
    out = run(FIXTURE)
    assert out["fail_stale"] == []
    assert out["unresolved_stale"] == []

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
