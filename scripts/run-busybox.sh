#!/usr/bin/env bash
# Cross-compile BusyBox with the sh4-linux-gnu cross compiler, smoke-test
# the result under qemu-sh4-static, and measure section sizes. Emits
# /tmp/metrics/busybox.json with five entries.
#
# Build failure → all metrics emit as 0 (script returns 0 so CI proceeds).
# Build succeeds, smoke partially passes → size metrics ship, smoke_pass
#                                          reflects actual count.
#
# Environment:
#   GCC_PREFIX     install dir of the candidate GCC (default: /tmp/gcc-install)
#   BUSYBOX_DIR    vendored source (default: $PWD/busybox)
#   OUT_FILE       output JSON (default: /tmp/metrics/busybox.json)
#   JOBS           parallel build jobs (default: $(nproc))

set -euo pipefail

GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
BUSYBOX_DIR="${BUSYBOX_DIR:-$PWD/busybox}"
OUT_FILE="${OUT_FILE:-/tmp/metrics/busybox.json}"
JOBS="${JOBS:-$(nproc)}"

# Custom GCC ships no binutils; -B steers it at Debian's sh4 binutils.
# Without this, gcc calls the host x86 'as', which rejects '-little'.
CC_RAW="$GCC_PREFIX/bin/sh4-linux-gnu-gcc"
CC="$CC_RAW -B/usr/bin/sh4-linux-gnu-"
SIZE="${SH4_SIZE:-/usr/bin/sh4-linux-gnu-size}"
QEMU="qemu-sh4-static"
SYSROOT="/usr/sh4-linux-gnu"

emit_zero() {
  local reason="$1"
  echo "run-busybox: $reason — emitting zero metrics" >&2
  mkdir -p "$(dirname "$OUT_FILE")"
  cat > "$OUT_FILE" <<EOF
[
  {"name": "busybox_text_bytes",   "unit": "bytes",   "value": 0},
  {"name": "busybox_rodata_bytes", "unit": "bytes",   "value": 0},
  {"name": "busybox_total_bytes",  "unit": "bytes",   "value": 0},
  {"name": "busybox_smoke_pass",   "unit": "applets", "value": 0},
  {"name": "busybox_smoke_total",  "unit": "applets", "value": 10}
]
EOF
}

if [ ! -x "$CC_RAW" ]; then
  emit_zero "missing $CC_RAW"
  exit 0
fi
if [ ! -d "$BUSYBOX_DIR" ]; then
  emit_zero "missing $BUSYBOX_DIR"
  exit 0
fi
if [ ! -x "$SIZE" ]; then
  emit_zero "missing $SIZE"
  exit 0
fi
if ! command -v "$QEMU" >/dev/null; then
  emit_zero "missing $QEMU"
  exit 0
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cp -r "$BUSYBOX_DIR"/* "$workdir"/
cd "$workdir"

echo "run-busybox: configuring..."
export ARCH=sh
# CROSS_COMPILE points to Debian's binutils (our custom GCC install ships
# none — no as/ld/ar). CC is overridden to the candidate compiler.
export CROSS_COMPILE="/usr/bin/sh4-linux-gnu-"

if ! make defconfig CC="$CC" >/dev/null 2>&1; then
  emit_zero "defconfig failed"
  exit 0
fi

# Force static link.
sed -i 's|^# CONFIG_STATIC is not set|CONFIG_STATIC=y|; s|^CONFIG_STATIC=.*|CONFIG_STATIC=y|' .config
if ! grep -q '^CONFIG_STATIC=y' .config; then
  echo "CONFIG_STATIC=y" >> .config
fi

# Disable applets that don't cross-compile cleanly for sh4:
#   TC                — uses struct tc_cbq_wrropt absent from kernel headers
#   FEATURE_TC        — same family
#   SHA1_HWACCEL      — references x86 SHA-NI intrinsics unconditionally
#   SHA256_HWACCEL    — same
#   FEATURE_USE_CNG_API — Windows-only; safety
for opt in TC FEATURE_TC SHA1_HWACCEL SHA256_HWACCEL; do
  sed -i "s|^CONFIG_${opt}=.*|# CONFIG_${opt} is not set|" .config
done

make oldconfig CC="$CC" >/dev/null 2>&1 || true

echo "run-busybox: building..."
if ! make -j"$JOBS" \
       CC="$CC" \
       CROSS_COMPILE="$CROSS_COMPILE" \
       KBUILD_CFLAGS_EXTRA="-B/usr/bin/sh4-linux-gnu- --sysroot=$SYSROOT" \
       2> "$workdir/build.err"; then
  echo "run-busybox: build failed. Tail of build.err:" >&2
  tail -30 "$workdir/build.err" >&2
  emit_zero "build failed"
  exit 0
fi

if [ ! -f busybox ]; then
  emit_zero "build succeeded but no busybox binary produced"
  exit 0
fi

echo "run-busybox: build OK. Binary size: $(stat -c %s busybox) bytes"
file busybox | head -1

# Section sizes.
text=0; rodata=0
while read -r section size addr; do
  case "$section" in
    .text)   text=$size ;;
    .rodata) rodata=$size ;;
  esac
done < <("$SIZE" --format=sysv busybox | tail -n +3 | head -n -2)

total=$(stat -c %s busybox)
echo "run-busybox: text=$text rodata=$rodata total=$total"

cat > /tmp/input <<'EOF'
hello sh4
world
hello world
EOF

# Smoke check is exit-code only — catches "applet broken by cross-compile".
# A future enhancement can add stdout sha256 comparison.
pass=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  case "$i" in
    1)  set -- ./busybox --help ;;
    2)  set -- ./busybox echo hello sh4 ;;
    3)  set -- ./busybox true ;;
    4)  set -- ./busybox sh -c 'echo $((2+3))' ;;
    5)  set -- ./busybox cat /tmp/input ;;
    6)  set -- ./busybox md5sum /tmp/input ;;
    7)  set -- ./busybox grep -c hello /tmp/input ;;
    8)  set -- ./busybox sort /tmp/input ;;
    9)  set -- ./busybox wc -l /tmp/input ;;
    10) set -- ./busybox awk '{print $1}' /tmp/input ;;
  esac
  if "$QEMU" -L "$SYSROOT" "$@" >/tmp/smoke.out 2>&1; then
    pass=$((pass+1))
    echo "run-busybox: smoke #$i ($*) PASS"
  else
    echo "run-busybox: smoke #$i ($*) FAIL — output:" >&2
    head -5 /tmp/smoke.out >&2
  fi
done

echo "run-busybox: smoke $pass/10 PASS"

mkdir -p "$(dirname "$OUT_FILE")"
cat > "$OUT_FILE" <<EOF
[
  {"name": "busybox_text_bytes",   "unit": "bytes",   "value": $text},
  {"name": "busybox_rodata_bytes", "unit": "bytes",   "value": $rodata},
  {"name": "busybox_total_bytes",  "unit": "bytes",   "value": $total},
  {"name": "busybox_smoke_pass",   "unit": "applets", "value": $pass},
  {"name": "busybox_smoke_total",  "unit": "applets", "value": 10}
]
EOF

echo "run-busybox: wrote $OUT_FILE"
