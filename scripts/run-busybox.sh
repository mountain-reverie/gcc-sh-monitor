#!/usr/bin/env bash
# Cross-compile BusyBox with a TARGET-tuple cross compiler, smoke-test the
# result under the matching qemu-user-static binary, and measure section
# sizes. Emits /tmp/metrics/busybox-${ARCH}.json with five entries.
#
# Build failure → all metrics emit as 0 (script returns 0 so CI proceeds).
# Build succeeds, smoke partially passes → size metrics ship, smoke_pass
#                                          reflects actual count.
#
# Environment:
#   TARGET         GNU triple: sh4-linux-gnu (default) | arm-linux-gnueabihf
#                  | i686-linux-gnu
#   GCC_PREFIX     install dir of the candidate GCC (default: /tmp/gcc-install)
#   BUSYBOX_DIR    vendored source (default: $PWD/busybox)
#   OUT_FILE       output JSON (default: /tmp/metrics/busybox-${ARCH}.json)
#   JOBS           parallel build jobs (default: $(nproc))

set -euo pipefail

GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
BUSYBOX_DIR="${BUSYBOX_DIR:-$PWD/busybox}"
JOBS="${JOBS:-$(nproc)}"

TARGET="${TARGET:-sh4-linux-gnu}"
case "$TARGET" in
  sh4-linux-gnu)
    ARCH=sh4
    QEMU=qemu-sh4-static
    BB_ARCH=sh
    SYSROOT=/usr/sh4-linux-gnu
    ;;
  arm-linux-gnueabihf)
    ARCH=arm
    QEMU=qemu-arm-static
    BB_ARCH=arm
    SYSROOT=/usr/arm-linux-gnueabihf
    ;;
  i686-linux-gnu)
    ARCH=x86
    QEMU=qemu-i386-static
    BB_ARCH=x86
    SYSROOT=/usr/i686-linux-gnu
    ;;
  *)
    echo "run-busybox: unsupported TARGET=$TARGET" >&2
    exit 2
    ;;
esac
OUT_FILE="${OUT_FILE:-/tmp/metrics/busybox-${ARCH}.json}"

# Custom GCC ships no binutils; -B steers it at Debian's cross binutils.
# Without this, gcc calls the host x86 'as', which rejects '-little' (sh4).
CC_RAW="$GCC_PREFIX/bin/${TARGET}-gcc"
CC="$CC_RAW -B/usr/bin/${TARGET}-"
SIZE="${SH4_SIZE:-/usr/bin/${TARGET}-size}"

emit_zero() {
  local reason="$1"
  echo "run-busybox: $reason — emitting zero metrics" >&2
  mkdir -p "$(dirname "$OUT_FILE")"
  cat > "$OUT_FILE" <<EOF
[
  {"name": "busybox_text_bytes_${ARCH}",   "unit": "bytes",   "value": 0},
  {"name": "busybox_rodata_bytes_${ARCH}", "unit": "bytes",   "value": 0},
  {"name": "busybox_total_bytes_${ARCH}",  "unit": "bytes",   "value": 0},
  {"name": "busybox_smoke_pass_${ARCH}",   "unit": "applets", "value": 0},
  {"name": "busybox_smoke_total_${ARCH}",  "unit": "applets", "value": 10}
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
# `cp -a SRC/. DST/` copies everything including dotfiles, preserves perms,
# and avoids shell-glob argv overflow when BUSYBOX_DIR has thousands of files
# (which is the case — ~6k files for BusyBox 1.37).
cp -a "$BUSYBOX_DIR"/. "$workdir"/
cd "$workdir"

if [ ! -f Config.in ]; then
  echo "run-busybox: workdir layout broken (Config.in missing). Listing:" >&2
  ls -la "$workdir" >&2 | head -30
  emit_zero "workdir copy incomplete"
  exit 0
fi

echo "run-busybox: configuring..."
# CROSS_COMPILE points to Debian's binutils (our custom GCC install ships
# none — no as/ld/ar). CC is overridden to the candidate compiler.
# Pass ARCH=$BB_ARCH directly to make so we don't clobber our shell-level
# $ARCH (sh4/arm/x86 shortname used for metric suffixing).
export CROSS_COMPILE="/usr/bin/${TARGET}-"

if ! make defconfig ARCH=$BB_ARCH CC="$CC" >"$workdir/defconfig.out" 2>&1; then
  echo "run-busybox: defconfig failed. Output:" >&2
  tail -30 "$workdir/defconfig.out" >&2
  emit_zero "defconfig failed"
  exit 0
fi

# Force static link.
sed -i 's|^# CONFIG_STATIC is not set|CONFIG_STATIC=y|; s|^CONFIG_STATIC=.*|CONFIG_STATIC=y|' .config
if ! grep -q '^CONFIG_STATIC=y' .config; then
  echo "CONFIG_STATIC=y" >> .config
fi

# Cross-build applet/feature disables (apply to all arches):
#   TC / FEATURE_TC   — uses struct tc_cbq_wrropt absent from the kernel
#                       headers shipped in Debian's cross sysroots (all arches).
#   SHA1_HWACCEL      — references x86 SHA-NI intrinsics unconditionally; the
#                       code doesn't compile for sh4 or arm, and our i686 target
#                       lacks SHA-NI by default. Safer to disable everywhere.
#   SHA256_HWACCEL    — same.
for opt in TC FEATURE_TC SHA1_HWACCEL SHA256_HWACCEL; do
  sed -i "s|^CONFIG_${opt}=.*|# CONFIG_${opt} is not set|" .config
done

make oldconfig ARCH=$BB_ARCH CC="$CC" >/dev/null 2>&1 || true

echo "run-busybox: building..."
if ! make -j"$JOBS" \
       ARCH=$BB_ARCH \
       CC="$CC" \
       CROSS_COMPILE="$CROSS_COMPILE" \
       KBUILD_CFLAGS_EXTRA="-B/usr/bin/${TARGET}- --sysroot=$SYSROOT" \
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
  {"name": "busybox_text_bytes_${ARCH}",   "unit": "bytes",   "value": $text},
  {"name": "busybox_rodata_bytes_${ARCH}", "unit": "bytes",   "value": $rodata},
  {"name": "busybox_total_bytes_${ARCH}",  "unit": "bytes",   "value": $total},
  {"name": "busybox_smoke_pass_${ARCH}",   "unit": "applets", "value": $pass},
  {"name": "busybox_smoke_total_${ARCH}",  "unit": "applets", "value": 10}
]
EOF

echo "run-busybox: wrote $OUT_FILE"
