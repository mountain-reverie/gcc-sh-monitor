import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from diff_csibe_objects_core import (
    parse_size_sysv, code_bytes, parse_nm_sizes, diff_totals,
)

SIZE_SYSV = """a.o  :
section        size   addr
.text           100      0
.rodata          20      0
.data             8      0
.bss             16      0
Total           144
"""

NM_OUT = """00000000 00000040 T func_big
00000040 00000010 t func_small
         00000004 b some_bss_no_addr_ok
00000050          T sizeless_symbol_skipped
"""

def test_parse_size_sysv():
    s = parse_size_sysv(SIZE_SYSV)
    assert s[".text"] == 100 and s[".rodata"] == 20 and s[".data"] == 8 and s[".bss"] == 16

def test_code_bytes_sums_text_rodata_data_only():
    assert code_bytes({".text":100,".rodata":20,".data":8,".bss":16}) == 128

def test_parse_nm_sizes_skips_sizeless():
    syms = parse_nm_sizes(NM_OUT)
    assert syms["func_big"] == 0x40 and syms["func_small"] == 0x10
    assert syms["some_bss_no_addr_ok"] == 0x4
    assert "sizeless_symbol_skipped" not in syms

NM_REALISTIC = """\
00001a2c 00000064 T sh_expand_prologue
00000000 000000f0 t local_helper
0000abcd          T sizeless_import
"""

def test_parse_nm_sizes_realistic_widths():
    syms = parse_nm_sizes(NM_REALISTIC)
    assert syms["sh_expand_prologue"] == 0x64
    assert syms["local_helper"] == 0xf0
    assert "sizeless_import" not in syms

def test_diff_totals_ranks_and_handles_missing():
    trunk = {"p1": 100, "p2": 50, "gone": 30}
    lra   = {"p1": 130, "p2": 50, "new": 10}
    d = diff_totals(trunk, lra)
    assert d[0] == ("p1", 30, 100, 130)          # biggest growth first
    assert ("new", 10, 0, 10) in d
    assert ("gone", -30, 30, 0) in d
    assert ("p2", 0, 50, 50) in d

def test_diff_totals_tie_break_is_deterministic():
    trunk = {"zebra": 10, "alpha": 10, "mango": 10}
    lra   = {"zebra": 15, "alpha": 15, "mango": 15}  # all Δ=+5
    d = diff_totals(trunk, lra)
    assert [r[0] for r in d] == ["alpha", "mango", "zebra"]

if __name__ == "__main__":
    test_parse_size_sysv()
    test_code_bytes_sums_text_rodata_data_only()
    test_parse_nm_sizes_skips_sizeless()
    test_parse_nm_sizes_realistic_widths()
    test_diff_totals_ranks_and_handles_missing()
    test_diff_totals_tie_break_is_deterministic()
    print("ok")
