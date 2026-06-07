"""Tests for sh-file-issue.py."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
SCRIPT = HERE / "sh-file-issue.py"

def run(result, what):
    f = Path(tempfile.mkstemp(suffix=".json")[1])
    f.write_text(json.dumps(result))
    r = subprocess.run(
        [sys.executable, str(SCRIPT), what, "--result", str(f)],
        capture_output=True, text=True,
    )
    assert r.returncode == 0, r.stderr
    return r.stdout

BASE = {
    "failure_type": "build",
    "failed_step": "Build cross GCC",
    "regressed_tests": [],
    "good_commit": "a" * 40,
    "bad_commit": "b" * 40,
    "run_url": "https://github.com/o/r/actions/runs/99",
    "culprit": "c" * 40,
    "culprit_author": "Jane Dev",
    "culprit_subject": "sh: break the world",
    "bisected": True,
    "exhausted": False,
    "log_excerpt": "internal compiler error: in foo",
}

def test_title_names_culprit_short_sha():
    title = run(BASE, "--title").strip()
    assert "SH CI regression" in title
    assert ("c" * 12) in title
    assert "Build cross GCC" in title

def test_body_has_commit_and_compare_links_and_log():
    body = run(BASE, "--body")
    assert f"gcc-mirror/gcc/commit/{'c'*40}" in body
    assert f"compare/{'a'*40}...{'b'*40}" in body
    assert "Jane Dev" in body
    assert "sh: break the world" in body
    assert "https://github.com/o/r/actions/runs/99" in body
    assert "internal compiler error" in body

def test_dejagnu_title_uses_test_name():
    r = dict(BASE, failure_type="dejagnu", failed_step="Run dejagnu sh.exp",
             regressed_tests=["gcc.target/sh/pr1.c (test for excess errors)"])
    title = run(r, "--title").strip()
    assert "gcc.target/sh/pr1.c" in title

def test_exhausted_reports_subrange_not_single_culprit():
    r = dict(BASE, culprit=None, bisected=True, exhausted=True,
             narrowed_good="d" * 40, narrowed_bad="e" * 40)
    title = run(r, "--title").strip()
    body = run(r, "--body")
    assert ("d" * 12) in title and ("e" * 12) in title
    assert "could not be fully bisected" in body.lower() or "incomplete" in body.lower()

def test_no_bound_notes_bisect_skipped():
    r = dict(BASE, good_commit=None, culprit=None, bisected=False, exhausted=False)
    body = run(r, "--body")
    assert "last-green" in body.lower() or "could not establish" in body.lower()

if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t(); print(f"PASS {t.__name__}")
        except AssertionError as e:
            print(f"FAIL {t.__name__}: {e}"); failed += 1
    sys.exit(failed)
