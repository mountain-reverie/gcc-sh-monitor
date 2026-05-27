#!/usr/bin/env bash
# Build CoreMark with the $TARGET cross compiler at the published-
# score flags (-O2 -funroll-loops) and measure the resulting binary's
# section sizes. Emits /tmp/metrics/coremark-${ARCH}.json. Metric names
# are suffixed with the short arch name (sh4/arm/x86).
#
# Environment:
#   TARGET         GNU triple (default: sh4-linux-gnu; also arm-linux-gnueabihf, i686-linux-gnu)
#   GCC_PREFIX     install dir (default: /tmp/gcc-install)
#   COREMARK_DIR   vendored corpus (default: $PWD/coremark)
#   OUT_FILE       output JSON (default: /tmp/metrics/coremark-${ARCH}.json)
#   PORT_DIR       CoreMark port subdir (default: simple)

set -euo pipefail

GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
COREMARK_DIR="${COREMARK_DIR:-$PWD/coremark}"
PORT_DIR="${PORT_DIR:-simple}"
TARGET="${TARGET:-sh4-linux-gnu}"
case "$TARGET" in
  sh4-linux-gnu)       ARCH=sh4 ;;
  arm-linux-gnueabihf) ARCH=arm ;;
  i686-linux-gnu)      ARCH=x86 ;;
  *) echo "run-coremark-size: unsupported TARGET=$TARGET" >&2; exit 2 ;;
esac
OUT_FILE="${OUT_FILE:-/tmp/metrics/coremark-${ARCH}.json}"

if [ ! -x "$GCC_PREFIX/bin/${TARGET}-gcc" ]; then
  echo "run-coremark-size: missing $GCC_PREFIX/bin/${TARGET}-gcc" >&2
  exit 1
fi
if [ ! -d "$COREMARK_DIR" ]; then
  echo "run-coremark-size: missing corpus dir $COREMARK_DIR" >&2
  exit 1
fi

# Debian's cross binutils' size tool (our built GCC ships no binutils).
SIZE="${SH4_SIZE:-/usr/bin/${TARGET}-size}"

mkdir -p "$(dirname "$OUT_FILE")"

# Build in a tmpdir to keep the vendored tree pristine.
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cp -r "$COREMARK_DIR"/* "$workdir"/

if [ ! -d "$workdir/$PORT_DIR" ]; then
  echo "run-coremark-size: port '$PORT_DIR' not found. Available:" >&2
  (cd "$workdir" && ls -d */) >&2
  exit 1
fi

cd "$workdir"
CC="$GCC_PREFIX/bin/${TARGET}-gcc"
# -B/usr/bin/${TARGET}- uses Debian's cross binutils (our build ships none).
# -static avoids dynamic-linker issues when ld looks for /lib/ld-linux.so.2.
XCFLAGS="-O2 -funroll-loops -B/usr/bin/${TARGET}- -static"

make PORT_DIR="$PORT_DIR" CC="$CC" XCFLAGS="$XCFLAGS" compile

# Locate the produced binary. The upstream Makefile usually produces
# ./coremark.exe (the .exe suffix is a CoreMark convention, not a Windows thing).
binary=""
for cand in coremark.exe coremark.elf coremark; do
  if [ -f "$cand" ]; then binary="$cand"; break; fi
done
if [ -z "$binary" ]; then
  echo "run-coremark-size: no coremark binary produced" >&2
  ls -la
  exit 1
fi

# `$SIZE --format=sysv` output:
#   <path> :
#   section    size    addr
#   .text      12345   8192
#   ...
#   Total      99999
#
# Skip the first 2 lines and the last 2 (blank + Total).
text=0; rodata=0
while read -r section size addr; do
  case "$section" in
    .text)   text=$size ;;
    .rodata) rodata=$size ;;
  esac
done < <("$SIZE" --format=sysv "$binary" | tail -n +3 | head -n -2)

# Total binary file size on disk.
total=$(stat -c %s "$binary")

cat > "$OUT_FILE" <<EOF
[
  {"name": "coremark_text_bytes_${ARCH}",   "unit": "bytes", "value": $text},
  {"name": "coremark_rodata_bytes_${ARCH}", "unit": "bytes", "value": $rodata},
  {"name": "coremark_total_bytes_${ARCH}",  "unit": "bytes", "value": $total}
]
EOF

echo "run-coremark-size: text=$text rodata=$rodata total=$total"
echo "run-coremark-size: wrote $OUT_FILE"
