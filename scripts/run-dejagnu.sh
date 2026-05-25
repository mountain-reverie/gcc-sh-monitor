#!/usr/bin/env bash
# Run the gcc.target/sh test suite under qemu-sh4 and emit sum/log paths.
#
# Prereq: scripts/build-gcc.sh has populated /tmp/gcc-install AND the
# corresponding /tmp/gcc-build still exists (make check-gcc needs the
# build tree, not just the install).
#
# Outputs:
#   /tmp/dejagnu-out/gcc.sum
#   /tmp/dejagnu-out/gcc.log.gz
#
# Environment:
#   GCC_BUILD_DIR  build tree (default: /tmp/gcc-build)
#   GCC_PREFIX     install dir (default: /tmp/gcc-install)
#   BOARDS_DIR     repo-relative path to boards/ (default: $PWD/boards)
#   OUT_DIR        output directory (default: /tmp/dejagnu-out)
#   JOBS           parallel test jobs (default: $(nproc))

set -euo pipefail

GCC_BUILD_DIR="${GCC_BUILD_DIR:-/tmp/gcc-build}"
GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
BOARDS_DIR="${BOARDS_DIR:-$PWD/boards}"
OUT_DIR="${OUT_DIR:-/tmp/dejagnu-out}"
JOBS="${JOBS:-$(nproc)}"

if [ ! -x "$GCC_PREFIX/bin/sh4-linux-gnu-gcc" ]; then
  echo "run-dejagnu: missing $GCC_PREFIX/bin/sh4-linux-gnu-gcc — run build-gcc.sh first" >&2
  exit 1
fi
if [ ! -d "$GCC_BUILD_DIR/gcc" ]; then
  echo "run-dejagnu: missing $GCC_BUILD_DIR/gcc — build tree was discarded" >&2
  exit 1
fi

export PATH="$GCC_PREFIX/bin:$PATH"
export DEJAGNU="$BOARDS_DIR/site.exp"

mkdir -p "$OUT_DIR"

cd "$GCC_BUILD_DIR"
# sh.exp picks up gcc.target/sh tests specifically. Smaller than gcc.dg
# and matches Increment 2 scope per spec §6.
make -j"$JOBS" check-gcc \
  RUNTESTFLAGS="--target_board=qemu-sh4 sh.exp" \
  || true   # dejagnu returns nonzero when any test fails; that's expected.

cp "$GCC_BUILD_DIR/gcc/testsuite/gcc/gcc.sum" "$OUT_DIR/gcc.sum"
gzip -c "$GCC_BUILD_DIR/gcc/testsuite/gcc/gcc.log" > "$OUT_DIR/gcc.log.gz"

echo "run-dejagnu: results in $OUT_DIR"
grep -c "^PASS:" "$OUT_DIR/gcc.sum" | xargs -I{} echo "  PASS: {}"
grep -c "^FAIL:" "$OUT_DIR/gcc.sum" | xargs -I{} echo "  FAIL: {}"
grep -c "^UNRESOLVED:" "$OUT_DIR/gcc.sum" | xargs -I{} echo "  UNRESOLVED: {}"
grep -c "^UNSUPPORTED:" "$OUT_DIR/gcc.sum" | xargs -I{} echo "  UNSUPPORTED: {}"
