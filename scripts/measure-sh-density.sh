#!/usr/bin/env bash
# Measure SH code-density: compile BusyBox + CSiBE + CoreMark to objects under
# -m2, -m2a and -m4 with the SAME sh4 compiler, then sum .text over the set of
# translation units that produced an object under ALL THREE ISAs (apples-to-
# apples). Emits /tmp/metrics/sh-density.json via scripts/sh_density_metrics.py.
#
# Compile-to-object only: no link, no libgcc, no qemu. -mN are ISA-selection
# flags accepted by any SH gcc; SH binutils assembles every SH ISA. Run
# scripts/check-sh-isa-flags.sh first. Any TU that fails identically across all
# three ISAs simply drops out of the intersection (and out of *_objects_common),
# so partial corpora skew nothing.
#
# Environment:
#   TARGET        GNU triple for as/size (default: sh4-linux-gnu)
#   GCC_PREFIX    install dir of the candidate gcc (default: /tmp/gcc-install)
#   GCC           compiler (default: $GCC_PREFIX/bin/${TARGET}-gcc)
#   SIZE          size tool (default: /usr/bin/${TARGET}-size, Debian cross binutils)
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
[ -x "$GCC" ]  || { echo "measure-sh-density: missing compiler $GCC" >&2; exit 1; }
[ -x "$SIZE" ] || { echo "measure-sh-density: missing size tool $SIZE" >&2; exit 1; }

# Per-corpus temp trees are registered here and removed on ANY exit (including
# interrupt), so a SIGINT mid-build doesn't leak hundreds of MB of object trees.
CLEANUP_DIRS=()
cleanup() { [ "${#CLEANUP_DIRS[@]}" -gt 0 ] && rm -rf "${CLEANUP_DIRS[@]}"; return 0; }
trap cleanup EXIT

# .text bytes of one object (0 if unreadable).
text_of() { "$SIZE" --format=sysv "$1" 2>/dev/null | awk '$1==".text"{s+=$2} END{print s+0}' || true; }

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
    "$GCC" -"$isa" -"$OPT" -B/usr/bin/"${TARGET}"- -c -w -std=gnu11 -DHAVE_CONFIG_H \
      -Wno-error=implicit-function-declaration -Wno-error=implicit-int \
      -Wno-error=int-conversion "${iflags[@]}" "$src_c" -o "$obj" 2>/dev/null || true
  done < <(find "$out" \( -name '*.c' -o -name '*.i' \) -print0)
}

# BusyBox via its own kbuild (needs generated headers). -k keeps going past a
# failed TU; objects land at deterministic relative paths, so the cross-ISA
# intersection still lines up. NOTE: this relies on kbuild leaving per-TU .o
# files on disk (it does — they coexist with the built-in.a archives), which is
# what measure_common reads.
compile_busybox() {
  local isa="$1" out="$2"
  rm -rf "$out"; mkdir -p "$out"; cp -a "$BUSYBOX_DIR"/. "$out"/
  ( cd "$out"
    export CROSS_COMPILE="/usr/bin/${TARGET}-"
    local cc="$GCC -$isa -B/usr/bin/${TARGET}-"
    make defconfig ARCH=sh CC="$cc" >/dev/null 2>&1 || true
    for o in TC FEATURE_TC SHA1_HWACCEL SHA256_HWACCEL; do
      sed -i "s|^CONFIG_${o}=.*|# CONFIG_${o} is not set|" .config 2>/dev/null || true
    done
    make oldconfig ARCH=sh CC="$cc" >/dev/null 2>&1 || true
    make -k -j"$JOBS" ARCH=sh CC="$cc" CROSS_COMPILE="/usr/bin/${TARGET}-" \
      KBUILD_CFLAGS_EXTRA="-$OPT -B/usr/bin/${TARGET}- --sysroot=$SYSROOT" \
      >/dev/null 2>&1 || true
  )
}

declare -A RAW

measure_busybox() {
  if [ ! -d "$BUSYBOX_DIR" ]; then
    echo "measure-sh-density: skip busybox (no $BUSYBOX_DIR)" >&2
    RAW[busybox]="0 0 0 0"; return
  fi
  local work; work=$(mktemp -d); CLEANUP_DIRS+=("$work")
  for isa in "${ISAS[@]}"; do
    echo "measure-sh-density: busybox -$isa ..." >&2
    compile_busybox "$isa" "$work/$isa"
  done
  RAW[busybox]=$(measure_common "$work/m2" "$work/m2a" "$work/m4")
  rm -rf "$work"
}

measure_coremark() {
  if [ ! -d "$COREMARK_DIR" ]; then
    echo "measure-sh-density: skip coremark (no $COREMARK_DIR)" >&2
    RAW[coremark]="0 0 0 0"; return
  fi
  local work; work=$(mktemp -d); CLEANUP_DIRS+=("$work")
  for isa in "${ISAS[@]}"; do
    echo "measure-sh-density: coremark -$isa ..." >&2
    compile_tree_perfile "$COREMARK_DIR" "$isa" "$work/$isa"
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

read -r s2_bb s2a_bb s4_bb n_bb <<< "${RAW[busybox]}"
read -r s2_cs s2a_cs s4_cs n_cs <<< "${RAW[csibe]}"
read -r s2_cm s2a_cm s4_cm n_cm <<< "${RAW[coremark]}"

python3 "$SCRIPT_DIR/sh_density_metrics.py" > "$OUT_FILE" <<JSON
{
  "busybox":  {"m2": $s2_bb, "m2a": $s2a_bb, "m4": $s4_bb, "common": $n_bb},
  "csibe":    {"m2": $s2_cs, "m2a": $s2a_cs, "m4": $s4_cs, "common": $n_cs},
  "coremark": {"m2": $s2_cm, "m2a": $s2a_cm, "m4": $s4_cm, "common": $n_cm}
}
JSON

echo "measure-sh-density: wrote $OUT_FILE"
cat "$OUT_FILE"
