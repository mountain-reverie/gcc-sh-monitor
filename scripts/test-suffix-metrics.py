import json, subprocess, sys, pathlib

SCRIPT = pathlib.Path(__file__).with_name("suffix-metrics.py")

def run(suffix, data):
    p = subprocess.run([sys.executable, str(SCRIPT), suffix],
                       input=json.dumps(data), capture_output=True, text=True)
    assert p.returncode == 0, p.stderr
    return json.loads(p.stdout)

def test_appends_suffix_to_each_name():
    out = run("__lra", [
        {"name": "csibe_total_os_bytes_sh4", "unit": "bytes", "value": 10},
        {"name": "sh_density_total_text_bytes_m4", "unit": "bytes", "value": 5},
    ])
    assert [e["name"] for e in out] == [
        "csibe_total_os_bytes_sh4__lra",
        "sh_density_total_text_bytes_m4__lra",
    ]
    assert out[0]["value"] == 10 and out[0]["unit"] == "bytes"

def test_entry_without_name_passes_through():
    out = run("__lra", [{"unit": "bytes", "value": 1}])
    assert out == [{"unit": "bytes", "value": 1}]

if __name__ == "__main__":
    test_appends_suffix_to_each_name()
    test_entry_without_name_passes_through()
    print("ok")
