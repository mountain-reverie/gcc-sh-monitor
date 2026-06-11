#!/usr/bin/env bash
# Build the TESTED-COMMIT sh-elf gcc and install it into the baked /opt/sh-elf
# prefix (which already holds sh-elf binutils + the SH simulator + newlib from the
# base image). This is the per-commit half of the sh-sim lane: it makes the
# simulator execute the exact trunk codegen under test for SH-2/SH-2A/SH-4.
#
# Prereq: scripts/build-gcc.sh has already checked out $GCC_SRC_DIR to the tested
# commit (same reuse pattern as build-gcc-sh-multilib.sh) and the base image
# provides /opt/sh-elf with sh-elf-as/ld + newlib.
#
# Non-fatal by design: on any build failure it exits non-zero WITHOUT leaving a
# half-installed gcc that could masquerade as the trunk compiler — the CI step is
# continue-on-error and the run step then degrades to zero metrics.
#
# Env overrides:
#   GCC_SRC_DIR   gcc checkout (default /tmp/gcc-src — populated by build-gcc.sh)
#   PREFIX        sh-elf toolchain prefix (default /opt/sh-elf)
#   GCC_BUILD_DIR build tree (default /tmp/sh-elf-gcc-build)
#   MULTILIB_LIST SH multilib list (default m2,m2a,m4 — must match baked newlib)
#   CCACHE_DIR    ccache dir (default /tmp/.ccache — shared with the sh4 build)
#   JOBS          parallelism (default nproc)

set -euo pipefail

COMMIT="${1:-}"   # informational only; the source is the existing $GCC_SRC_DIR checkout
GCC_SRC_DIR="${GCC_SRC_DIR:-/tmp/gcc-src}"
PREFIX="${PREFIX:-/opt/sh-elf}"
GCC_BUILD_DIR="${GCC_BUILD_DIR:-/tmp/sh-elf-gcc-build}"
MULTILIB_LIST="${MULTILIB_LIST:-m2,m2a,m4}"
CCACHE_DIR="${CCACHE_DIR:-/tmp/.ccache}"
JOBS="${JOBS:-$(nproc)}"
TARGET=sh-elf

[ -d "$GCC_SRC_DIR/.git" ] || { echo "build-sh-elf-gcc: GCC_SRC_DIR=$GCC_SRC_DIR not a checkout (run build-gcc.sh first)" >&2; exit 1; }
[ -x "$PREFIX/bin/${TARGET}-as" ] || { echo "build-sh-elf-gcc: baked sh-elf binutils missing at $PREFIX (stale base image?)" >&2; exit 1; }
[ -f "$PREFIX/$TARGET/lib/libc.a" ] || { echo "build-sh-elf-gcc: baked newlib missing at $PREFIX (stale base image?)" >&2; exit 1; }

export CCACHE_DIR
export PATH="/usr/lib/ccache:$PREFIX/bin:$PATH"   # ccache for host g++; PREFIX for sh-elf-as/ld
ccache --max-size=3G >/dev/null 2>&1 || true
git config --global --add safe.directory "$GCC_SRC_DIR" || true
git config --global --add safe.directory "$GCC_BUILD_DIR" || true

echo "build-sh-elf-gcc: TARGET=$TARGET multilib=$MULTILIB_LIST prefix=$PREFIX commit=${COMMIT:-<checkout>}"
"${TARGET}-as" --version | head -1

rm -rf "$GCC_BUILD_DIR"; mkdir -p "$GCC_BUILD_DIR"; cd "$GCC_BUILD_DIR"
"$GCC_SRC_DIR/configure" \
  --target="$TARGET" --prefix="$PREFIX" \
  --enable-languages=c --with-newlib \
  --enable-multilib --with-multilib-list="$MULTILIB_LIST" \
  --disable-libssp --disable-shared --disable-threads \
  --disable-nls --disable-bootstrap --enable-checking=release --disable-werror

# all-gcc = driver + cc1; all-target-libgcc links against the baked newlib headers.
make -j"$JOBS" all-gcc all-target-libgcc
make install-gcc install-target-libgcc

GCC="$PREFIX/bin/${TARGET}-gcc"
echo "build-sh-elf-gcc: installed $GCC"
"$GCC" --version | head -1
echo "build-sh-elf-gcc: multilibs: $("$GCC" -print-multi-lib | tr '\n' ' ')"

# Smoke: each ISA must compile, link against newlib, and run on the simulator.
echo 'int main(void){ return 42; }' > "$GCC_BUILD_DIR/smoke.c"
rc=0
for isa in m2 m2a m4; do
  out="$GCC_BUILD_DIR/smoke-$isa.elf"
  if "$GCC" -"$isa" -O2 "$GCC_BUILD_DIR/smoke.c" -o "$out" 2>/dev/null \
     && [ "$("${TARGET}-run" "$out" >/dev/null 2>&1; echo $?)" = 42 ]; then
    echo "build-sh-elf-gcc: -$isa smoke PASS (sim exit 42)"
  else
    echo "build-sh-elf-gcc: -$isa smoke FAIL" >&2; rc=1
  fi
done
[ "$rc" = 0 ] || { echo "build-sh-elf-gcc: smoke failed; treating build as unusable" >&2; exit 1; }
echo "build-sh-elf-gcc: done"
