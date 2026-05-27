#!/usr/bin/env bash
# Cross-compile BusyBox statically linked against an our-built musl (not
# Debian's prebuilt glibc), per arch. Smoke-test under qemu-<arch>-static
# and measure section sizes. Emits /tmp/metrics/busybox-musl-${ARCH}.json
# with five entries.
#
# Build failure → all metrics emit as 0 (script returns 0 so CI proceeds).
#
# Environment:
#   TARGET         GNU triple: sh4-linux-gnu (default) | arm-linux-gnueabihf
#                  | i686-linux-gnu
#   GCC_PREFIX     install dir of the candidate GCC (default: /tmp/gcc-install)
#   MUSL_DIR       vendored musl source (default: $PWD/musl)
#   BUSYBOX_DIR    vendored busybox source (default: $PWD/busybox)
#   OUT_FILE       output JSON (default: /tmp/metrics/busybox-musl-${ARCH}.json)
#   JOBS           parallel build jobs (default: $(nproc))

set -euo pipefail

GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
MUSL_DIR="${MUSL_DIR:-$PWD/musl}"
BUSYBOX_DIR="${BUSYBOX_DIR:-$PWD/busybox}"
JOBS="${JOBS:-$(nproc)}"

TARGET="${TARGET:-sh4-linux-gnu}"
case "$TARGET" in
  sh4-linux-gnu)
    ARCH=sh4
    QEMU=qemu-sh4-static
    BB_ARCH=sh
    MUSL_TARGET=sh4-linux-musleabi
    ;;
  arm-linux-gnueabihf)
    ARCH=arm
    QEMU=qemu-arm-static
    BB_ARCH=arm
    MUSL_TARGET=arm-linux-musleabihf
    ;;
  i686-linux-gnu)
    ARCH=x86
    QEMU=qemu-i386-static
    BB_ARCH=x86
    MUSL_TARGET=i486-linux-musl
    ;;
  *)
    echo "run-busybox-musl: unsupported TARGET=$TARGET" >&2
    exit 2
    ;;
esac
OUT_FILE="${OUT_FILE:-/tmp/metrics/busybox-musl-${ARCH}.json}"

CC_RAW="$GCC_PREFIX/bin/${TARGET}-gcc"
SIZE="${SH4_SIZE:-/usr/bin/${TARGET}-size}"

emit_zero() {
  local reason="$1"
  echo "run-busybox-musl: $reason — emitting zero metrics" >&2
  mkdir -p "$(dirname "$OUT_FILE")"
  cat > "$OUT_FILE" <<EOF
[
  {"name": "busybox_musl_text_bytes_${ARCH}",   "unit": "bytes",   "value": 0},
  {"name": "busybox_musl_rodata_bytes_${ARCH}", "unit": "bytes",   "value": 0},
  {"name": "busybox_musl_total_bytes_${ARCH}",  "unit": "bytes",   "value": 0},
  {"name": "busybox_musl_smoke_pass_${ARCH}",   "unit": "applets", "value": 0},
  {"name": "busybox_musl_smoke_total_${ARCH}",  "unit": "applets", "value": 10}
]
EOF
}

if [ ! -x "$CC_RAW" ];    then emit_zero "missing $CC_RAW";    exit 0; fi
if [ ! -d "$MUSL_DIR" ];   then emit_zero "missing $MUSL_DIR";   exit 0; fi
if [ ! -d "$BUSYBOX_DIR" ];then emit_zero "missing $BUSYBOX_DIR";exit 0; fi
if [ ! -x "$SIZE" ];       then emit_zero "missing $SIZE";       exit 0; fi
if ! command -v "$QEMU" >/dev/null; then emit_zero "missing $QEMU"; exit 0; fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

# Phase 1: build musl into $workdir/musl-install
echo "run-busybox-musl: building musl..."
musl_src="$workdir/musl-src"
musl_install="$workdir/musl-install"
mkdir -p "$musl_src" "$musl_install"
cp -a "$MUSL_DIR"/. "$musl_src"/
cd "$musl_src"

if ! ./configure \
       --target="$MUSL_TARGET" \
       --prefix="$musl_install" \
       CC="$CC_RAW -B/usr/bin/${TARGET}-" \
       CROSS_COMPILE=/usr/bin/${TARGET}- \
       >"$workdir/musl-configure.out" 2>&1; then
  echo "run-busybox-musl: musl configure failed. Output:" >&2
  tail -30 "$workdir/musl-configure.out" >&2
  emit_zero "musl configure failed"
  exit 0
fi

if ! make -j"$JOBS" >"$workdir/musl-build.out" 2>&1; then
  echo "run-busybox-musl: musl build failed. Output:" >&2
  tail -30 "$workdir/musl-build.out" >&2
  emit_zero "musl build failed"
  exit 0
fi

if ! make install >"$workdir/musl-install.out" 2>&1; then
  echo "run-busybox-musl: musl install failed. Output:" >&2
  tail -20 "$workdir/musl-install.out" >&2
  emit_zero "musl install failed"
  exit 0
fi

echo "run-busybox-musl: musl installed at $musl_install"

# Phase 2: wrapper-CC script
wrapper="$workdir/cc-musl"
cat > "$wrapper" <<EOF
#!/bin/sh
# Wrapper CC: invoke real gcc with musl as libc.
# Only inject crt1/crti/crtn on a FINAL static link — not on compile (-c),
# preprocess (-E/-M/-MM), assemble (-S), partial link (-r), or shared (-shared).
# BusyBox builds intermediate "built-in.o" files via "gcc -r"; those must
# not get crt1.o injected or we'd see multiple-definition errors on _start.
linking=true
for a in "\$@"; do
  case "\$a" in
    -c|-E|-S|-M|-MM|-r|-shared|-nostartfiles|-nostdlib) linking=false; break ;;
  esac
done
if \$linking; then
  exec "$CC_RAW" \\
    -B/usr/bin/${TARGET}- \\
    -nostdinc \\
    -isystem "$musl_install/include" \\
    -isystem /usr/${TARGET}/include \\
    -nostdlib -static \\
    "$musl_install/lib/crt1.o" "$musl_install/lib/crti.o" \\
    "\$@" \\
    -L"$musl_install/lib" -lc -lgcc \\
    "$musl_install/lib/crtn.o"
else
  exec "$CC_RAW" \\
    -B/usr/bin/${TARGET}- \\
    -nostdinc \\
    -isystem "$musl_install/include" \\
    -isystem /usr/${TARGET}/include \\
    "\$@"
fi
EOF
chmod +x "$wrapper"

# Sanity check
echo "int main(void) { return 0; }" > "$workdir/sanity.c"
if ! "$wrapper" "$workdir/sanity.c" -o "$workdir/sanity" 2>"$workdir/wrapper-test.out"; then
  echo "run-busybox-musl: wrapper-CC sanity check failed. Output:" >&2
  cat "$workdir/wrapper-test.out" >&2
  emit_zero "wrapper-cc sanity failed"
  exit 0
fi
echo "run-busybox-musl: wrapper-cc sanity PASS ($(file "$workdir/sanity" | head -1))"

# Phase 3: BusyBox build using wrapper-CC
echo "run-busybox-musl: building BusyBox..."
bb_dir="$workdir/bb"
mkdir -p "$bb_dir"
cp -a "$BUSYBOX_DIR"/. "$bb_dir"/
cd "$bb_dir"

if [ ! -f Config.in ]; then
  echo "run-busybox-musl: BusyBox workdir broken (Config.in missing)" >&2
  emit_zero "bb workdir copy incomplete"
  exit 0
fi

export CROSS_COMPILE="/usr/bin/${TARGET}-"

if ! make defconfig ARCH=$BB_ARCH CC="$wrapper" >"$workdir/bb-defconfig.out" 2>&1; then
  echo "run-busybox-musl: BusyBox defconfig failed. Output:" >&2
  tail -30 "$workdir/bb-defconfig.out" >&2
  emit_zero "bb defconfig failed"
  exit 0
fi

sed -i 's|^# CONFIG_STATIC is not set|CONFIG_STATIC=y|; s|^CONFIG_STATIC=.*|CONFIG_STATIC=y|' .config
if ! grep -q '^CONFIG_STATIC=y' .config; then
  echo "CONFIG_STATIC=y" >> .config
fi

for opt in TC FEATURE_TC SHA1_HWACCEL SHA256_HWACCEL; do
  sed -i "s|^CONFIG_${opt}=.*|# CONFIG_${opt} is not set|" .config
done

make oldconfig ARCH=$BB_ARCH CC="$wrapper" >/dev/null 2>&1 || true

if ! make -j"$JOBS" \
       ARCH=$BB_ARCH \
       CC="$wrapper" \
       CROSS_COMPILE="$CROSS_COMPILE" \
       2>"$workdir/bb-build.err"; then
  echo "run-busybox-musl: BusyBox build failed. Tail of build.err:" >&2
  tail -40 "$workdir/bb-build.err" >&2
  emit_zero "bb build failed"
  exit 0
fi

if [ ! -f busybox ]; then
  emit_zero "build succeeded but no busybox binary produced"
  exit 0
fi

echo "run-busybox-musl: build OK. Binary size: $(stat -c %s busybox) bytes"
file busybox | head -1

# Phase 4: measure + smoke
text=0; rodata=0
while read -r section size addr; do
  case "$section" in
    .text)   text=$size ;;
    .rodata) rodata=$size ;;
  esac
done < <("$SIZE" --format=sysv busybox | tail -n +3 | head -n -2)

total=$(stat -c %s busybox)
echo "run-busybox-musl: text=$text rodata=$rodata total=$total"

cat > /tmp/input <<'EOF'
hello sh4
world
hello world
EOF

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
  if "$QEMU" "$@" >/tmp/smoke.out 2>&1; then
    pass=$((pass+1))
    echo "run-busybox-musl: smoke #$i ($*) PASS"
  else
    echo "run-busybox-musl: smoke #$i ($*) FAIL — output:" >&2
    head -5 /tmp/smoke.out >&2
  fi
done

echo "run-busybox-musl: smoke $pass/10 PASS"

# Phase 5: emit
mkdir -p "$(dirname "$OUT_FILE")"
cat > "$OUT_FILE" <<EOF
[
  {"name": "busybox_musl_text_bytes_${ARCH}",   "unit": "bytes",   "value": $text},
  {"name": "busybox_musl_rodata_bytes_${ARCH}", "unit": "bytes",   "value": $rodata},
  {"name": "busybox_musl_total_bytes_${ARCH}",  "unit": "bytes",   "value": $total},
  {"name": "busybox_musl_smoke_pass_${ARCH}",   "unit": "applets", "value": $pass},
  {"name": "busybox_musl_smoke_total_${ARCH}",  "unit": "applets", "value": 10}
]
EOF

echo "run-busybox-musl: wrote $OUT_FILE"
