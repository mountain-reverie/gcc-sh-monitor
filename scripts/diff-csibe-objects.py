#!/usr/bin/env python3
"""Diff two CSiBE object trees (trunk vs sh-lra) into a markdown report.

Trees are laid out as <root>/<project>/<opt>/<src-rel>.o (see run-csibe.sh
KEEP_OBJECTS_DIR). Uses the cross binutils size/nm/objdump to attribute the
size difference down to sections, symbols, and disassembly.

Usage:
  diff-csibe-objects.py TRUNK_DIR LRA_DIR [--opt Os|O2] [--top N]
                        [--project NAME] [--tool-prefix PFX] [--out DIR]
"""
import argparse, subprocess, sys, pathlib
from collections import defaultdict
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from diff_csibe_objects_core import (
    parse_size_sysv, code_bytes, parse_nm_sizes, diff_totals,
)


def run(tool_prefix, tool, *args):
    """Run <prefix><tool> <args...> and return stdout (empty string on failure)."""
    try:
        return subprocess.run([f"{tool_prefix}{tool}", *args],
                              capture_output=True, text=True, check=False).stdout
    except FileNotFoundError:
        sys.exit(f"error: {tool_prefix}{tool} not found (set --tool-prefix)")


def objects_for(root, opt):
    """Return {project: {rel_path: abs_path}} for a given opt under root."""
    root = pathlib.Path(root)
    out = defaultdict(dict)
    if not root.is_dir():
        sys.exit(f"error: not a directory: {root}")
    for obj in root.glob(f"*/{opt}/**/*.o"):
        project = obj.relative_to(root).parts[0]
        rel = obj.relative_to(root / project / opt).as_posix()
        out[project][rel] = str(obj)
    return out


def project_code_bytes(prefix, objs):
    """Sum code bytes across a {rel: abs} object map."""
    total = 0
    for abs_path in objs.values():
        total += code_bytes(parse_size_sysv(run(prefix, "size", "--format=sysv", abs_path)))
    return total


def symbol_sizes(prefix, objs):
    """Merge {symbol: size} across all objects of a project (summing dups)."""
    merged = defaultdict(int)
    for abs_path in objs.values():
        for sym, sz in parse_nm_sizes(
                run(prefix, "nm", "--print-size", "--size-sort", abs_path)).items():
            merged[sym] += sz
    return dict(merged)


def disasm_symbol(prefix, abs_path, sym):
    """Return objdump -d disassembly restricted to one symbol."""
    return run(prefix, "objdump", "-d", f"--disassemble={sym}", "-l", abs_path)


def find_object_with_symbol(prefix, objs, sym):
    """Return the abs path of the object defining `sym`, or None."""
    for abs_path in objs.values():
        if sym in parse_nm_sizes(
                run(prefix, "nm", "--print-size", "--size-sort", abs_path)):
            return abs_path
    return None


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("trunk_dir")
    ap.add_argument("lra_dir")
    ap.add_argument("--opt", default="Os", choices=["Os", "O2"])
    ap.add_argument("--top", type=int, default=10)
    ap.add_argument("--project", default=None)
    ap.add_argument("--tool-prefix", default="sh4-linux-gnu-")
    ap.add_argument("--out", default="csibe-size-report")
    a = ap.parse_args(argv)
    pfx = a.tool_prefix
    out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)

    trunk = objects_for(a.trunk_dir, a.opt)
    lra = objects_for(a.lra_dir, a.opt)

    # Per-project code-byte totals + ranked deltas.
    t_tot = {p: project_code_bytes(pfx, o) for p, o in trunk.items()}
    l_tot = {p: project_code_bytes(pfx, o) for p, o in lra.items()}
    ranked = diff_totals(t_tot, l_tot)

    projects = [a.project] if a.project else [p for p, d, *_ in ranked if d != 0][:a.top]

    # summary.md
    lines = [f"# CSiBE size diff (trunk vs sh-lra), -{a.opt}", "",
             f"Total code bytes: trunk={sum(t_tot.values())} "
             f"sh-lra={sum(l_tot.values())} "
             f"Δ={sum(l_tot.values())-sum(t_tot.values()):+}", "",
             "| project | trunk | sh-lra | Δ | report |",
             "|---|--:|--:|--:|---|"]
    for p, d, tv, lv in ranked:
        if d == 0:
            continue
        link = f"[{p}]({p}/report.md)" if p in projects else p
        lines.append(f"| {link} | {tv} | {lv} | {d:+} |  |")
    (out / "summary.md").write_text("\n".join(lines) + "\n")

    # Per-project drill-down.
    for p in projects:
        t_objs, l_objs = trunk.get(p, {}), lra.get(p, {})
        t_syms, l_syms = symbol_sizes(pfx, t_objs), symbol_sizes(pfx, l_objs)
        sym_rows = [r for r in diff_totals(t_syms, l_syms) if r[1] != 0]
        rep = [f"# {p} — symbol size diff (-{a.opt})", "",
               "| symbol | trunk | sh-lra | Δ |", "|---|--:|--:|--:|"]
        for sym, d, tv, lv in sym_rows[:a.top]:
            rep.append(f"| `{sym}` | {tv} | {lv} | {d:+} |")
        rep.append("")
        # Disassembly of the top movers, both sides.
        for sym, d, tv, lv in sym_rows[:a.top]:
            if d <= 0:
                continue
            rep += [f"## `{sym}` (Δ{d:+})", "", "### trunk", "```",
                    (disasm_symbol(pfx, find_object_with_symbol(pfx, t_objs, sym) or "", sym)
                     if find_object_with_symbol(pfx, t_objs, sym) else "(absent)").rstrip(),
                    "```", "### sh-lra", "```",
                    (disasm_symbol(pfx, find_object_with_symbol(pfx, l_objs, sym) or "", sym)
                     if find_object_with_symbol(pfx, l_objs, sym) else "(absent)").rstrip(),
                    "```", ""]
        (out / p).mkdir(parents=True, exist_ok=True)
        (out / p / "report.md").write_text("\n".join(rep) + "\n")

    print(f"wrote {out}/summary.md and {len(projects)} project report(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
