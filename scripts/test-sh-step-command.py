"""Tests for sh-step-command.py."""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
SCRIPT = HERE / "sh-step-command.py"

def run(step):
    return subprocess.run(
        [sys.executable, str(SCRIPT), step],
        capture_output=True, text=True,
    )

def test_known_script_step_maps_to_command():
    r = run("Run BusyBox+musl FDPIC build + smoke + size")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "ABI=fdpic scripts/run-busybox-musl.sh"

def test_plain_busybox_step():
    r = run("Run BusyBox build + smoke + size")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "scripts/run-busybox.sh"

def test_lto_fdpic_step():
    r = run("Run BusyBox+musl FDPIC+LTO build + smoke + size")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "LTO=1 ABI=fdpic scripts/run-busybox-musl.sh"

def test_unknown_step_exits_2_and_prints_nothing():
    r = run("Build cross GCC")  # build step is NOT a reproducible script step
    assert r.returncode == 2
    assert r.stdout.strip() == ""

if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t(); print(f"PASS {t.__name__}")
        except AssertionError as e:
            print(f"FAIL {t.__name__}: {e}"); failed += 1
    sys.exit(failed)
