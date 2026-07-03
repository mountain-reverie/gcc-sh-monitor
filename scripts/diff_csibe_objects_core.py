"""Pure parsing + delta helpers for the CSiBE object size analyzer.

No I/O and no subprocess here so the logic is unit-testable in isolation;
scripts/diff-csibe-objects.py drives the actual binutils calls and file walk.
"""

CODE_SECTIONS = (".text", ".rodata", ".data")


def parse_size_sysv(text):
    """Parse `size --format=sysv` output into {section: bytes}."""
    out = {}
    for line in text.splitlines():
        parts = line.split()
        # Section rows look like: "<name> <size> <addr>"; the name starts with '.'
        if len(parts) >= 2 and parts[0].startswith(".") and parts[1].isdigit():
            out[parts[0]] = int(parts[1])
    return out


def code_bytes(sections):
    """Sum the size-relevant sections (.text + .rodata + .data)."""
    return sum(sections.get(s, 0) for s in CODE_SECTIONS)


def parse_nm_sizes(text):
    """Parse `nm --print-size --size-sort` output into {symbol: size}.

    Sized lines: "<addr> <size> <type> <name>" or "<blank> <size> <type> <name>".
    Lines without a size field (only "<addr> <type> <name>") are skipped.
    """
    out = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        # Determine whether a size column is present. With --print-size a sized
        # symbol has two leading hex columns (addr, size) OR a blank addr then
        # size; sizeless symbols have a single leading hex column then type.
        # Detect: parts[-2] is a 1-char type code, parts[-1] is the name.
        type_code, name = parts[-2], parts[-1]
        if len(type_code) != 1:
            continue
        try:
            if len(parts) >= 4:
                # Common case: "addr size type name". This is width-independent
                # since size is always the 2nd whitespace-delimited field,
                # regardless of hex column width (e.g. real sh4-linux-gnu-nm
                # output). Only the rarer 3-token blank-addr case below needs
                # leading-whitespace disambiguation.
                size = int(parts[1], 16)  # addr, size, type, name
            elif len(parts) == 3:
                # Ambiguous: could be "<size> <type> <name>" (blank addr
                # collapsed by split()) or "<addr> <type> <name>" (sizeless).
                # Disambiguate using the raw line: a blank addr column means
                # the line starts with whitespace before the size field.
                if line[:1].isspace():
                    size = int(parts[0], 16)  # blank addr, size, type, name
                else:
                    continue  # addr, type, name — no size column
            else:
                continue
        except ValueError:
            continue
        if size > 0 or name not in out:
            out[name] = size
    return out


def diff_totals(trunk, lra):
    """Return [(key, delta, trunk_val, lra_val)] sorted by delta desc.

    Keys present in either dict are included; a missing side counts as 0.
    """
    keys = set(trunk) | set(lra)
    rows = []
    for k in keys:
        tv, lv = trunk.get(k, 0), lra.get(k, 0)
        rows.append((k, lv - tv, tv, lv))
    rows.sort(key=lambda r: r[1], reverse=True)
    return rows
