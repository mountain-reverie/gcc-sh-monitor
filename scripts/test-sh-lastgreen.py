"""Tests for sh-lastgreen.pick_good_run()."""
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location("sh_lastgreen", HERE / "sh-lastgreen.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
pick_good_run = mod.pick_good_run

def R(run_id, build_success, commit):
    return {"run_id": run_id, "build_success": build_success, "commit": commit}

def test_picks_newest_build_success_for_build_type():
    runs = [R(5, False, "bad"), R(4, True, "g4"), R(3, True, "g3")]
    good = pick_good_run(runs, "build", [], lambda r: True)
    assert good["run_id"] == 4
    assert good["commit"] == "g4"

def test_skips_runs_with_no_commit():
    runs = [R(5, True, None), R(4, True, "g4")]
    good = pick_good_run(runs, "build", [], lambda r: True)
    assert good["run_id"] == 4

def test_dejagnu_requires_test_passing():
    runs = [R(5, True, "g5"), R(4, True, "g4")]
    passing = lambda r: r["run_id"] == 4
    good = pick_good_run(runs, "dejagnu", ["t"], passing)
    assert good["run_id"] == 4

def test_returns_none_when_no_good_run():
    runs = [R(5, False, "bad"), R(4, False, "bad2")]
    assert pick_good_run(runs, "build", [], lambda r: True) is None

def test_sh_sim_uses_first_green_run():
    runs = [R(3, False, "c3"), R(2, True, "c2"), R(1, True, "c1")]
    good = pick_good_run(runs, "sh-sim", [], lambda r: True)
    assert good["run_id"] == 2, good

if __name__ == "__main__":
    tests = [v for k, v in globals().items() if k.startswith("test_")]
    failed = 0
    for t in tests:
        try:
            t(); print(f"PASS {t.__name__}")
        except AssertionError as e:
            print(f"FAIL {t.__name__}: {e}"); failed += 1
    sys.exit(failed)
