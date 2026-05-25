#!/usr/bin/env bash
# Build CoreMark with the sh4-linux-gnu cross compiler at the published-
# score flags (-O2 -funroll-loops) and measure the resulting binary's
# section sizes. Emits /tmp/metrics/coremark.json.
#
# Environment:
#   GCC_PREFIX     install dir (default: /tmp/gcc-install)
#   COREMARK_DIR   vendored corpus (default: $PWD/coremark)
#   OUT_FILE       output JSON (default: /tmp/metrics/coremark.json)
#   PORT_DIR       CoreMark port subdir (default: simple)

set -euo pipefail

GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
COREMARK_DIR="${COREMARK_DIR:-$PWD/coremark}"
OUT_FILE="${OUT_FILE:-/tmp/metrics/coremark.json}"
PORT_DIR="${PORT_DIR:-simple}"

if [ ! -x "$GCC_PREFIX/bin/sh4-linux-gnu-gcc" ]; then
  echo "run-coremark-size: missing $GCC_PREFIX/bin/sh4-linux-gnu-gcc" >&2
  exit 1
fi
if [ ! -d "$COREMARK_DIR" ]; then
  echo "run-coremark-size: missing corpus dir $COREMARK_DIR" >&2
  exit 1
fi

# Debian's cross binutils' size tool (our built GCC ships no binutils).
SIZE="${SH4_SIZE:-/usr/bin/sh4-linux-gnu-size}"

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
CC="$GCC_PREFIX/bin/sh4-linux-gnu-gcc"
# -B/usr/bin/sh4-linux-gnu- uses Debian's cross binutils (our build ships none).
# -static avoids dynamic-linker issues when ld looks for /lib/ld-linux.so.2.
XCFLAGS="-O2 -funroll-loops -B/usr/bin/sh4-linux-gnu- -static"

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
  {"name": "coremark_text_bytes",   "unit": "bytes", "value": $text},
  {"name": "coremark_rodata_bytes", "unit": "bytes", "value": $rodata},
  {"name": "coremark_total_bytes",  "unit": "bytes", "value": $total}
]
EOF

echo "run-coremark-size: text=$text rodata=$rodata total=$total"
echo "run-coremark-size: wrote $OUT_FILE"
