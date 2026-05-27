"""Tests for migrate-benchmark-data.py."""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
FIXTURE = HERE.parent / "tests" / "fixtures" / "benchmark-data-unmigrated.json"
SCRIPT = HERE / "migrate-benchmark-data.py"


def migrate_to_tmp() -> Path:
    tmp = Path(tempfile.NamedTemporaryFile(suffix=".json", delete=False).name)
    shutil.copy(FIXTURE, tmp)
    subprocess.run([sys.executable, str(SCRIPT), str(tmp)], check=True)
    return tmp


def load_names(path: Path) -> list[str]:
    data = json.loads(path.read_text())
    return [b["name"] for b in data["entries"]["Benchmark"][0]["benches"]]


def test_renames_unsuffixed_csibe():
    names = load_names(migrate_to_tmp())
    assert "csibe_total_os_bytes_sh4" in names
    assert "csibe_total_os_bytes" not in names


def test_renames_per_subproject_csibe():
    names = load_names(migrate_to_tmp())
    assert "csibe_bzip2_os_bytes_sh4" in names
    assert "csibe_bzip2_os_bytes" not in names


def test_renames_coremark():
    names = load_names(migrate_to_tmp())
    assert "coremark_text_bytes_sh4" in names


def test_renames_busybox_text_and_smoke():
    names = load_names(migrate_to_tmp())
    assert "busybox_text_bytes_sh4" in names
    assert "busybox_smoke_pass_sh4" in names


def test_renames_musl():
    names = load_names(migrate_to_tmp())
    assert "musl_libc_text_bytes_sh4" in names
    assert "musl_smoke_pass_sh4" in names


def test_leaves_dejagnu_alone():
    names = load_names(migrate_to_tmp())
    assert "dejagnu_fail_count" in names
    assert "dejagnu_fail_count_sh4" not in names


def test_leaves_lra_alone():
    names = load_names(migrate_to_tmp())
    assert "lra_diverged_count" in names
    assert "lra_diverged_count_sh4" not in names


def test_leaves_already_suffixed_alone():
    names = load_names(migrate_to_tmp())
    assert "csibe_total_o2_bytes_sh4" in names
    assert "csibe_total_o2_bytes_sh4_sh4" not in names
    assert "coremark_text_bytes_arm" in names
    assert "coremark_text_bytes_arm_sh4" not in names


def test_idempotent():
    once = migrate_to_tmp()
    once_names = sorted(load_names(once))
    subprocess.run([sys.executable, str(SCRIPT), str(once)], check=True)
    twice_names = sorted(load_names(once))
    assert once_names == twice_names


def test_missing_file_aborts_nonzero():
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "/does/not/exist.json"],
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
