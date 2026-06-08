#!/usr/bin/env bash
# Measure SH code-density by compiling corpora to objects and summing .text over
# the translation units that built under every compared ISA. Two parts:
#   * DENSITY comparison (CSiBE + CoreMark): three-way -m2/-m2a/-m4, BIG-ENDIAN.
#   * BusyBox: -m2 vs -m4 only, LITTLE-ENDIAN, kept SEPARATE from the density
#     totals — its kbuild can't build big-endian (so no SH-2A).
# Emits /tmp/metrics/sh-density.json via scripts/sh_density_metrics.py.
#
# Compile-to-object only: no link, no libgcc, no qemu. Needs the MULTILIB SH gcc
# (scripts/build-gcc-sh-multilib.sh) — the main --disable-multilib sh4 gcc
# rejects -m2/-m2a ("not supported by this configuration"). All three ISAs are
# compiled BIG-ENDIAN (-mb): GCC has no little-endian SH-2A (sh.h: "SH2a does
# not support little-endian"), and .text *size* is endian-invariant, so the
# big-endian byte counts still answer the density question for little-endian
# J-Core. Run scripts/check-sh-isa-flags.sh first. Any TU that fails identically
# across all three ISAs simply drops out of the intersection (and out of
# *_objects_common), so partial corpora skew nothing.
#
# Environment:
#   TARGET        GNU triple for as/size (default: sh4-linux-gnu)
#   GCC_PREFIX    install dir of the candidate gcc (default: /tmp/gcc-install)
#   GCC           compiler (default: $GCC_PREFIX/bin/${TARGET}-gcc)
#   SIZE          size tool (default: /usr/bin/${TARGET}-size, Debian cross binutils)
#   ENDIAN        endian flag for all ISAs (default: -mb — SH-2A is big-endian-only)
#   OPT           optimization level (default: Os — the density-relevant setting)
#   BUSYBOX_DIR   default: $PWD/busybox
#   CSIBE_DIR     default: $PWD/csibe/src
#   COREMARK_DIR  default: $PWD/coremark
#   OUT_FILE      metrics JSON (default: /tmp/metrics/sh-density.json)
#   JOBS          parallelism for the busybox build (default: nproc)
set -euo pipefail

TARGET="${TARGET:-sh4-linux-gnu}"
GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
GCC="${GCC:-$GCC_PREFIX/bin/${TARGET}-gcc}"
SIZE="${SIZE:-/usr/bin/${TARGET}-size}"
ENDIAN="${ENDIAN:--mb}"   # big-endian: GCC has no little-endian SH-2A
OPT="${OPT:-Os}"
BUSYBOX_DIR="${BUSYBOX_DIR:-$PWD/busybox}"
CSIBE_DIR="${CSIBE_DIR:-$PWD/csibe/src}"
COREMARK_DIR="${COREMARK_DIR:-$PWD/coremark}"
OUT_FILE="${OUT_FILE:-/tmp/metrics/sh-density.json}"
JOBS="${JOBS:-$(nproc)}"
SYSROOT="/usr/${TARGET}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISAS=(m2 m2a m4)

mkdir -p "$(dirname "$OUT_FILE")"
# Fail-safe: if the (multilib) compiler or size tool is missing, emit an
# all-zero metrics file and exit 0. This keeps a build failure of the separate
# multilib compiler from breaking the all-or-nothing metrics merge — which would
# otherwise take down the ENTIRE sh4 metrics artifact, not just this lane.
emit_zero() {
  echo "measure-sh-density: $1 — emitting zero metrics" >&2
  python3 "$SCRIPT_DIR/sh_density_metrics.py" > "$OUT_FILE" <<'JSON'
{
  "density": {
    "csibe":    {"m2": 0, "m2a": 0, "m4": 0, "common": 0},
    "coremark": {"m2": 0, "m2a": 0, "m4": 0, "common": 0}
  },
  "busybox": {"m2": 0, "m4": 0, "common": 0}
}
JSON
}
[ -x "$GCC" ]  || { emit_zero "missing compiler $GCC"; exit 0; }
[ -x "$SIZE" ] || { emit_zero "missing size tool $SIZE"; exit 0; }

# Per-corpus temp trees are registered here and removed on ANY exit (including
# interrupt), so a SIGINT mid-build doesn't leak hundreds of MB of object trees.
CLEANUP_DIRS=()
cleanup() { [ "${#CLEANUP_DIRS[@]}" -gt 0 ] && rm -rf "${CLEANUP_DIRS[@]}"; return 0; }
trap cleanup EXIT

# .text bytes of one object (0 if unreadable). Match the .text PREFIX so
# -ffunction-sections output (.text.<fn>, as BusyBox's --gc-sections build emits)
# is counted, not just a single ".text" section.
text_of() { "$SIZE" --format=sysv "$1" 2>/dev/null | awk '$1 ~ /^\.text/{s+=$2} END{print s+0}' || true; }

# Sorted relative paths of all .o under a dir (for `comm`).
rel_objects() { ( cd "$1" 2>/dev/null && find . -name '*.o' | sort ) || true; }

# Given a corpus's three per-ISA object dirs, print "<m2> <m2a> <m4> <common>",
# summing .text over only the objects present under ALL three ISAs.
measure_common() {
  local d2="$1" d2a="$2" d4="$3"
  local common n=0 s2=0 s2a=0 s4=0 rel
  common=$(comm -12 <(rel_objects "$d2") <(comm -12 <(rel_objects "$d2a") <(rel_objects "$d4")))
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    n=$((n + 1))
    s2=$((  s2  + $(text_of "$d2/$rel")  ))
    s2a=$(( s2a + $(text_of "$d2a/$rel") ))
    s4=$((  s4  + $(text_of "$d4/$rel")  ))
  done <<< "$common"
  echo "$s2 $s2a $s4 $n"
}

# Two-ISA variant for BusyBox (m2 vs m4 only): print "<m2> <m4> <common>".
measure_common2() {
  local d2="$1" d4="$2"
  local common n=0 s2=0 s4=0 rel
  common=$(comm -12 <(rel_objects "$d2") <(rel_objects "$d4"))
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    n=$((n + 1))
    s2=$(( s2 + $(text_of "$d2/$rel") ))
    s4=$(( s4 + $(text_of "$d4/$rel") ))
  done <<< "$common"
  echo "$s2 $s4 $n"
}

# Per-file compiler for self-contained C trees (CSiBE projects, CoreMark).
# Mirrors scripts/run-csibe.sh: ignore upstream Makefiles, scan for -I dirs,
# compile every .c to a sibling .o. Failures are tolerated (the TU drops out).
compile_tree_perfile() {
  local src="$1" isa="$2" out="$3"
  rm -rf "$out"; mkdir -p "$out"; cp -r "$src"/. "$out"/ 2>/dev/null || true
  local -A inc=(); inc["$out"]=1
  local hdr d
  while IFS= read -r -d '' hdr; do
    d="$hdr"
    while [ "$d" != "$out" ] && [ "$d" != "/" ]; do inc["$d"]=1; d=$(dirname "$d"); done
  done < <(find "$out" -name '*.h' -printf '%h\0' | sort -uz)
  local iflags=(); for d in "${!inc[@]}"; do iflags+=("-I$d"); done
  local src_c obj
  while IFS= read -r -d '' src_c; do
    obj="${src_c%.*}.o"
    "$GCC" -"$isa" $ENDIAN -"$OPT" -B/usr/bin/"${TARGET}"- -c -w -std=gnu11 -DHAVE_CONFIG_H \
      -Wno-error=implicit-function-declaration -Wno-error=implicit-int \
      -Wno-error=int-conversion "${iflags[@]}" "$src_c" -o "$obj" 2>/dev/null || true
  done < <(find "$out" \( -name '*.c' -o -name '*.i' \) -print0)
}

# BusyBox via its own kbuild. LITTLE-ENDIAN only (no $ENDIAN): BusyBox can't
# build SH-2A (big-endian), so it's measured m2-vs-m4 — both little-endian, which
# is J-Core-native. Mirrors run-busybox.sh's working config (CONFIG_STATIC=y,
# host HOSTCC) so applets actually compile; the final link may fail for -m2 (no
# m2 libc in the sh4 sysroot), but -k leaves the per-TU .o we measure. The
# generated headers come from defconfig/oldconfig built with the host compiler.
compile_busybox() {
  local isa="$1" out="$2"
  rm -rf "$out"; mkdir -p "$out"; cp -a "$BUSYBOX_DIR"/. "$out"/
  ( cd "$out"
    export CROSS_COMPILE="/usr/bin/${TARGET}-"
    local cc="$GCC -$isa -B/usr/bin/${TARGET}-"   # little-endian (no -mb)
    make defconfig ARCH=sh CC="$cc" HOSTCC=gcc >defconfig.log 2>&1 || true
    sed -i 's|^# CONFIG_STATIC is not set|CONFIG_STATIC=y|; s|^CONFIG_STATIC=.*|CONFIG_STATIC=y|' .config 2>/dev/null || true
    grep -q '^CONFIG_STATIC=y' .config || echo "CONFIG_STATIC=y" >> .config
    for o in TC FEATURE_TC SHA1_HWACCEL SHA256_HWACCEL; do
      sed -i "s|^CONFIG_${o}=.*|# CONFIG_${o} is not set|" .config 2>/dev/null || true
    done
    make oldconfig ARCH=sh CC="$cc" HOSTCC=gcc >oldconfig.log 2>&1 || true
    make -k -j"$JOBS" ARCH=sh CC="$cc" HOSTCC=gcc CROSS_COMPILE="/usr/bin/${TARGET}-" \
      KBUILD_CFLAGS_EXTRA="-$OPT -B/usr/bin/${TARGET}- --sysroot=$SYSROOT" \
      >build.log 2>&1 || true
  )
  # Diagnostic: report objects produced; if suspiciously low, surface the first
  # errors (kbuild swallows them) so a broken build is visible in the CI log.
  local n; n=$(find "$out" -name '*.o' | wc -l)
  echo "measure-sh-density: busybox -$isa produced $n .o" >&2
  if [ "$n" -lt 20 ]; then
    echo "measure-sh-density: busybox -$isa first errors:" >&2
    grep -iE 'error:|#error|fatal' "$out/build.log" 2>/dev/null | head -8 >&2 || true
  fi
}

declare -A RAW

# BusyBox: little-endian, m2 vs m4 only (separate from the density comparison).
measure_busybox() {
  if [ ! -d "$BUSYBOX_DIR" ]; then
    echo "measure-sh-density: skip busybox (no $BUSYBOX_DIR)" >&2
    RAW[busybox]="0 0 0"; return
  fi
  local work; work=$(mktemp -d); CLEANUP_DIRS+=("$work")
  for isa in m2 m4; do
    echo "measure-sh-density: busybox -$isa (little-endian) ..." >&2
    compile_busybox "$isa" "$work/$isa"
  done
  RAW[busybox]=$(measure_common2 "$work/m2" "$work/m4")
  rm -rf "$work"
}

measure_coremark() {
  if [ ! -d "$COREMARK_DIR" ]; then
    echo "measure-sh-density: skip coremark (no $COREMARK_DIR)" >&2
    RAW[coremark]="0 0 0 0"; return
  fi
  local work; work=$(mktemp -d); CLEANUP_DIRS+=("$work")
  # CoreMark ships many ports (simple/posix/barebones/rtems/zephyr/...), several
  # defining the same core_portme symbols/headers. Compiling them all makes the
  # -I scan pick up conflicting core_portme.h and pulls in RTOS-only ports that
  # cannot compile, so almost nothing survives the intersection. Restrict to the
  # canonical 'simple' port (matches run-coremark-size.sh): the top-level
  # core_*.c + coremark.h plus simple/.
  local src="$work/src"
  mkdir -p "$src/simple"
  cp "$COREMARK_DIR"/*.c "$COREMARK_DIR"/*.h "$src"/ 2>/dev/null || true
  cp "$COREMARK_DIR"/simple/*.c "$COREMARK_DIR"/simple/*.h "$src/simple"/ 2>/dev/null || true
  for isa in "${ISAS[@]}"; do
    echo "measure-sh-density: coremark -$isa ..." >&2
    compile_tree_perfile "$src" "$isa" "$work/$isa"
  done
  RAW[coremark]=$(measure_common "$work/m2" "$work/m2a" "$work/m4")
  rm -rf "$work"
}

measure_csibe() {
  if [ ! -d "$CSIBE_DIR" ]; then
    echo "measure-sh-density: skip csibe (no $CSIBE_DIR)" >&2
    RAW[csibe]="0 0 0 0"; return
  fi
  local work; work=$(mktemp -d); CLEANUP_DIRS+=("$work")
  for isa in "${ISAS[@]}"; do
    echo "measure-sh-density: csibe -$isa ..." >&2
    mkdir -p "$work/$isa"
    local proj
    for proj in "$CSIBE_DIR"/*/; do
      [ -d "$proj" ] || continue
      compile_tree_perfile "$proj" "$isa" "$work/$isa/$(basename "$proj")"
    done
  done
  RAW[csibe]=$(measure_common "$work/m2" "$work/m2a" "$work/m4")
  rm -rf "$work"
}

measure_busybox
measure_csibe
measure_coremark

# Density corpora (CSiBE + CoreMark): three-way m2/m2a/m4 (big-endian).
read -r s2_cs s2a_cs s4_cs n_cs <<< "${RAW[csibe]}"
read -r s2_cm s2a_cm s4_cm n_cm <<< "${RAW[coremark]}"
# BusyBox: m2 vs m4 only (little-endian), separate from the density comparison.
read -r s2_bb s4_bb n_bb <<< "${RAW[busybox]}"

python3 "$SCRIPT_DIR/sh_density_metrics.py" > "$OUT_FILE" <<JSON
{
  "density": {
    "csibe":    {"m2": $s2_cs, "m2a": $s2a_cs, "m4": $s4_cs, "common": $n_cs},
    "coremark": {"m2": $s2_cm, "m2a": $s2a_cm, "m4": $s4_cm, "common": $n_cm}
  },
  "busybox": {"m2": $s2_bb, "m4": $s4_bb, "common": $n_bb}
}
JSON

echo "measure-sh-density: wrote $OUT_FILE"
cat "$OUT_FILE"
