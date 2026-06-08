#!/usr/bin/env bash
# Verify the candidate sh4 GCC can compile-to-object for -m2, -m2a and -m4,
# and that the cross 'size' tool can read each object. Gates
# measure-sh-density.sh: the single-compiler density lane assumes any SH gcc
# emits objects for every SH ISA (compile-to-object needs no libgcc/startfiles).
# Exits non-zero if any ISA fails.
set -euo pipefail

TARGET="${TARGET:-sh4-linux-gnu}"
GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
GCC="${GCC:-$GCC_PREFIX/bin/${TARGET}-gcc}"
SIZE="${SIZE:-/usr/bin/${TARGET}-size}"

[ -x "$GCC" ]  || { echo "check-sh-isa-flags: missing compiler $GCC" >&2; exit 1; }
[ -x "$SIZE" ] || { echo "check-sh-isa-flags: missing size tool $SIZE" >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo 'int f(int x){return x*3+1;}' > "$tmp/t.c"

rc=0
for isa in m2 m2a m4; do
  if ! "$GCC" -"$isa" -Os -B/usr/bin/"${TARGET}"- -c "$tmp/t.c" -o "$tmp/t-$isa.o" 2>"$tmp/err-$isa"; then
    echo "check-sh-isa-flags: -$isa FAILED (compile):" >&2
    cat "$tmp/err-$isa" >&2
    rc=1
  elif ! sysv=$("$SIZE" --format=sysv "$tmp/t-$isa.o" 2>"$tmp/size-err-$isa"); then
    echo "check-sh-isa-flags: -$isa FAILED (size could not read object):" >&2
    cat "$tmp/size-err-$isa" >&2
    rc=1
  else
    bytes=$(printf '%s\n' "$sysv" | awk '$1==".text"{print $2}')
    echo "check-sh-isa-flags: -$isa OK (.text=${bytes:-unknown} bytes)"
  fi
done
exit "$rc"
