#!/usr/bin/env bash
# Verify the density compiler can compile-to-object for -m2, -m2a and -m4, and
# that the cross 'size' tool can read each object. Gates measure-sh-density.sh.
#
# Uses the MULTILIB SH gcc (the main --disable-multilib sh4 gcc rejects
# -m2/-m2a), and BIG-ENDIAN (-mb): GCC has no little-endian SH-2A. Exits
# non-zero if any ISA fails.
set -euo pipefail

TARGET="${TARGET:-sh4-linux-gnu}"
GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
GCC="${GCC:-$GCC_PREFIX/bin/${TARGET}-gcc}"
SIZE="${SIZE:-/usr/bin/${TARGET}-size}"
ENDIAN="${ENDIAN:--mb}"   # big-endian: GCC has no little-endian SH-2A

[ -x "$GCC" ]  || { echo "check-sh-isa-flags: missing compiler $GCC" >&2; exit 1; }
[ -x "$SIZE" ] || { echo "check-sh-isa-flags: missing size tool $SIZE" >&2; exit 1; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo 'int f(int x){return x*3+1;}' > "$tmp/t.c"

rc=0
for isa in m2 m2a m4; do
  if ! "$GCC" -"$isa" $ENDIAN -Os -B/usr/bin/"${TARGET}"- -c "$tmp/t.c" -o "$tmp/t-$isa.o" 2>"$tmp/err-$isa"; then
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
