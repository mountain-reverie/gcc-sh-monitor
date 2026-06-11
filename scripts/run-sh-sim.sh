#!/usr/bin/env bash
# Run gcc.c-torture execution tests on the SH instruction-set simulator
# (sh-elf-run) via boards/sh-sim.exp, once per ISA (-m2/-m2a/-m4), for both the
# integer torture suite (execute.exp) and the floating-point suite (ieee.exp).
# Copies the per-(isa,suite) gcc.sum files to OUT_DIR for parse-sh-sim.py.
#
# Prereq: scripts/build-sh-elf-gcc.sh has installed the tested-commit sh-elf gcc
# into /opt/sh-elf (alongside the baked binutils+sim+newlib) and left its build
# tree at GCC_BUILD_DIR.
#
# Degraded mode: if the toolchain or build tree is absent (base/trunk build
# failed), this skips cleanly with exit 0 and no sums — parse-sh-sim.py then emits
# zero metrics. This step is continue-on-error in CI either way.
#
# Env overrides:
#   PREFIX        sh-elf toolchain prefix  (default /opt/sh-elf)
#   GCC_BUILD_DIR sh-elf gcc build tree    (default /tmp/sh-elf-gcc-build)
#   BOARDS_DIR    repo boards/ dir         (default $PWD/boards)
#   OUT_DIR       sums output dir          (default /tmp/sh-sim-out)
#   ISAS          ISAs to run              (default "m2 m2a m4")
#   GLOB          restrict integer suite to execute.exp=<glob> (default: full suite)
#   JOBS          parallel test jobs       (default nproc)

set -euo pipefail

PREFIX="${PREFIX:-/opt/sh-elf}"
GCC_BUILD_DIR="${GCC_BUILD_DIR:-/tmp/sh-elf-gcc-build}"
BOARDS_DIR="${BOARDS_DIR:-$PWD/boards}"
OUT_DIR="${OUT_DIR:-/tmp/sh-sim-out}"
ISAS="${ISAS:-m2 m2a m4}"
GLOB="${GLOB:-}"
JOBS="${JOBS:-$(nproc)}"
TARGET=sh-elf

mkdir -p "$OUT_DIR"

if [ ! -x "$PREFIX/bin/${TARGET}-gcc" ] || [ ! -x "$PREFIX/bin/${TARGET}-run" ] || [ ! -d "$GCC_BUILD_DIR/gcc" ]; then
  echo "run-sh-sim: toolchain or build tree missing — skipping (zero metrics)" >&2
  echo "  ${TARGET}-gcc: $([ -x "$PREFIX/bin/${TARGET}-gcc" ] && echo ok || echo MISSING)" >&2
  echo "  ${TARGET}-run: $([ -x "$PREFIX/bin/${TARGET}-run" ] && echo ok || echo MISSING)" >&2
  echo "  build tree:    $([ -d "$GCC_BUILD_DIR/gcc" ] && echo ok || echo MISSING)" >&2
  exit 0
fi

export PATH="$PREFIX/bin:$PATH"
export DEJAGNU="$BOARDS_DIR/site.exp"

cd "$GCC_BUILD_DIR"
echo "run-sh-sim: $("${TARGET}-gcc" --version | head -1)"

sum="$GCC_BUILD_DIR/gcc/testsuite/gcc/gcc.sum"
log="$GCC_BUILD_DIR/gcc/testsuite/gcc/gcc.log"

# suite name -> .exp selector. GLOB (if set) narrows the integer torture suite;
# ieee is small, so it always runs in full.
declare -A EXP=( [execute]="execute.exp${GLOB:+=$GLOB}" [ieee]="ieee.exp" )

for isa in $ISAS; do
  for suite in execute ieee; do
    echo "===== -$isa / $suite ====="
    # dejagnu returns nonzero on any FAIL; expected.
    make -j"$JOBS" check-gcc \
      RUNTESTFLAGS="--target_board=sh-sim/-$isa ${EXP[$suite]}" \
      >/dev/null 2>&1 || true
    if [ -f "$sum" ]; then
      cp "$sum" "$OUT_DIR/${suite}-${isa}.sum"
      gzip -cf "$log" > "$OUT_DIR/${suite}-${isa}.log.gz" 2>/dev/null || true
      printf '  PASS(exec)=%s FAIL(exec)=%s\n' \
        "$(grep -E '^PASS:.* execution( test|,)' "$OUT_DIR/${suite}-${isa}.sum" | wc -l)" \
        "$(grep -E '^FAIL:.* execution( test|,)' "$OUT_DIR/${suite}-${isa}.sum" | wc -l)"
    else
      echo "  (no gcc.sum — runtest/board error)"
    fi
  done
done

echo "run-sh-sim: sums in $OUT_DIR"
