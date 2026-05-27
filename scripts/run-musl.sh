#!/usr/bin/env bash
# Cross-compile musl with a TARGET-tuple cross compiler, smoke-test the
# resulting libc by static-linking a hello-world and running under the
# matching qemu-user-static binary, and measure libc.so section sizes.
# Emits /tmp/metrics/musl-${ARCH}.json with four entries.
#
# Build failure → all metrics emit as 0 (script returns 0 so CI proceeds).
# Build OK + smoke fails → size ships, smoke_pass=0.
#
# Environment:
#   TARGET         GNU triple: sh4-linux-gnu (default) | arm-linux-gnueabihf
#                  | i686-linux-gnu
#   GCC_PREFIX     install dir of the candidate GCC (default: /tmp/gcc-install)
#   MUSL_DIR       vendored source (default: $PWD/musl)
#   OUT_FILE       output JSON (default: /tmp/metrics/musl-${ARCH}.json)
#   JOBS           parallel build jobs (default: $(nproc))

set -euo pipefail

GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
MUSL_DIR="${MUSL_DIR:-$PWD/musl}"
JOBS="${JOBS:-$(nproc)}"

TARGET="${TARGET:-sh4-linux-gnu}"
case "$TARGET" in
  sh4-linux-gnu)
    ARCH=sh4
    QEMU=qemu-sh4-static
    MUSL_TARGET=sh4-linux-musleabi
    ;;
  arm-linux-gnueabihf)
    ARCH=arm
    QEMU=qemu-arm-static
    MUSL_TARGET=arm-linux-musleabihf
    ;;
  i686-linux-gnu)
    ARCH=x86
    QEMU=qemu-i386-static
    MUSL_TARGET=i486-linux-musl
    ;;
  *)
    echo "run-musl: unsupported TARGET=$TARGET" >&2
    exit 2
    ;;
esac
OUT_FILE="${OUT_FILE:-/tmp/metrics/musl-${ARCH}.json}"

CC_RAW="$GCC_PREFIX/bin/${TARGET}-gcc"
CC="$CC_RAW -B/usr/bin/${TARGET}-"
SIZE="${SH4_SIZE:-/usr/bin/${TARGET}-size}"

emit_zero() {
  local reason="$1"
  echo "run-musl: $reason — emitting zero metrics" >&2
  mkdir -p "$(dirname "$OUT_FILE")"
  cat > "$OUT_FILE" <<EOF
[
  {"name": "musl_libc_text_bytes_${ARCH}",  "unit": "bytes", "value": 0},
  {"name": "musl_libc_total_bytes_${ARCH}", "unit": "bytes", "value": 0},
  {"name": "musl_smoke_pass_${ARCH}",       "unit": "runs",  "value": 0},
  {"name": "musl_smoke_total_${ARCH}",      "unit": "runs",  "value": 1}
]
EOF
}

if [ ! -x "$CC_RAW" ];   then emit_zero "missing $CC_RAW";   exit 0; fi
if [ ! -d "$MUSL_DIR" ]; then emit_zero "missing $MUSL_DIR"; exit 0; fi
if [ ! -x "$SIZE" ];     then emit_zero "missing $SIZE";     exit 0; fi
if ! command -v "$QEMU" >/dev/null; then emit_zero "missing $QEMU"; exit 0; fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cp -a "$MUSL_DIR"/. "$workdir"/src/
install_dir="$workdir/install"
mkdir -p "$install_dir"

cd "$workdir/src"

echo "run-musl: configuring..."
# CC: candidate GCC, configured to find Debian's cross binutils via -B.
# CROSS_COMPILE: prefix for ar/ranlib/strip that musl invokes directly.
if ! ./configure \
       --target="$MUSL_TARGET" \
       --prefix="$install_dir" \
       CC="$CC" \
       CROSS_COMPILE=/usr/bin/${TARGET}- \
       >"$workdir/configure.out" 2>&1; then
  echo "run-musl: configure failed. Output:" >&2
  tail -30 "$workdir/configure.out" >&2
  emit_zero "configure failed"
  exit 0
fi

echo "run-musl: building..."
if ! make -j"$JOBS" >"$workdir/build.out" 2>&1; then
  echo "run-musl: build failed. Tail of build.out:" >&2
  tail -30 "$workdir/build.out" >&2
  emit_zero "build failed"
  exit 0
fi

if ! make install >"$workdir/install.out" 2>&1; then
  echo "run-musl: install failed. Output:" >&2
  tail -20 "$workdir/install.out" >&2
  emit_zero "install failed"
  exit 0
fi

# Locate the libc.so ELF object (not the linker script). musl typically
# installs libc.so as the linker script and lib/libc.so.<ver> as the ELF.
# Detect via `file`.
libc_elf=""
for cand in "$install_dir"/lib/libc.so.* "$install_dir"/lib/libc.so; do
  if [ -f "$cand" ] && file "$cand" | grep -q "ELF.*shared object"; then
    libc_elf="$cand"
    break
  fi
done
if [ -z "$libc_elf" ]; then
  echo "run-musl: cannot locate libc.so ELF in $install_dir/lib:" >&2
  ls -la "$install_dir/lib" >&2
  emit_zero "libc.so ELF missing"
  exit 0
fi
echo "run-musl: libc.so ELF: $libc_elf"

# Section sizes.
text=0; rodata=0
while read -r section size addr; do
  case "$section" in
    .text)   text=$size ;;
    .rodata) rodata=$size ;;
  esac
done < <("$SIZE" --format=sysv "$libc_elf" | tail -n +3 | head -n -2)

total=$(stat -c %s "$libc_elf")
echo "run-musl: text=$text rodata=$rodata total=$total"

# Smoke: build a static hello-world against the new musl, run under qemu.
cat > "$workdir/hello.c" <<'EOF'
#include <unistd.h>
int main(void) {
    const char msg[] = "hello musl\n";
    write(1, msg, sizeof msg - 1);
    return 0;
}
EOF

smoke_pass=0
if $CC_RAW \
      -B/usr/bin/${TARGET}- \
      -nostdinc -isystem "$install_dir/include" \
      -nostdlib -static \
      "$install_dir/lib/crt1.o" \
      "$install_dir/lib/crti.o" \
      "$workdir/hello.c" \
      -L"$install_dir/lib" -lc \
      "$install_dir/lib/crtn.o" \
      -o "$workdir/hello-musl" \
      >"$workdir/link.out" 2>&1; then
  echo "run-musl: hello-world linked OK"
  if "$QEMU" "$workdir/hello-musl" >"$workdir/run.out" 2>&1; then
    if grep -q '^hello musl$' "$workdir/run.out"; then
      smoke_pass=1
      echo "run-musl: smoke PASS"
    else
      echo "run-musl: smoke FAIL — unexpected output:" >&2
      head -5 "$workdir/run.out" >&2
    fi
  else
    echo "run-musl: smoke FAIL — hello exit nonzero. Output:" >&2
    head -5 "$workdir/run.out" >&2
  fi
else
  echo "run-musl: smoke FAIL — link error. Tail:" >&2
  tail -20 "$workdir/link.out" >&2
fi

mkdir -p "$(dirname "$OUT_FILE")"
cat > "$OUT_FILE" <<EOF
[
  {"name": "musl_libc_text_bytes_${ARCH}",  "unit": "bytes", "value": $text},
  {"name": "musl_libc_total_bytes_${ARCH}", "unit": "bytes", "value": $total},
  {"name": "musl_smoke_pass_${ARCH}",       "unit": "runs",  "value": $smoke_pass},
  {"name": "musl_smoke_total_${ARCH}",      "unit": "runs",  "value": 1}
]
EOF

echo "run-musl: wrote $OUT_FILE"
