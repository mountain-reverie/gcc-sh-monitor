#!/usr/bin/env bash
# Build each CSiBE subproject under csibe/src/ at -Os and -O2 with the
# sh4-linux-gnu cross compiler, then sum (.text + .rodata + .data)
# bytes of all output objects. Emit one JSON entry per (project, opt)
# plus an aggregate per opt level.
#
# Failures in any one subproject are logged but do not abort the run
# (its metrics are simply omitted from this run's JSON).
#
# Outputs: /tmp/metrics/csibe.json
#
# Environment:
#   GCC_PREFIX     install dir (default: /tmp/gcc-install)
#   CSIBE_DIR      vendored corpus subdir (default: $PWD/csibe/src)
#   OUT_FILE       output JSON (default: /tmp/metrics/csibe.json)

set -euo pipefail

GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
CSIBE_DIR="${CSIBE_DIR:-$PWD/csibe/src}"
OUT_FILE="${OUT_FILE:-/tmp/metrics/csibe.json}"

if [ ! -x "$GCC_PREFIX/bin/sh4-linux-gnu-gcc" ]; then
  echo "run-csibe: missing $GCC_PREFIX/bin/sh4-linux-gnu-gcc" >&2
  exit 1
fi
if [ ! -d "$CSIBE_DIR" ]; then
  echo "run-csibe: missing corpus dir $CSIBE_DIR" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")"

CC="$GCC_PREFIX/bin/sh4-linux-gnu-gcc"
# Our built GCC ships no binutils; use the Debian cross binutils' size.
SIZE="${SH4_SIZE:-/usr/bin/sh4-linux-gnu-size}"
if [ ! -x "$SIZE" ]; then
  echo "run-csibe: missing $SIZE" >&2
  exit 1
fi
# -B... uses Debian's cross binutils (our built GCC ships none).
# -c produces .o files (no link, no libc needed).
# -w suppresses warnings (we measure size, not test cleanliness).
# -DHAVE_CONFIG_H enables config.h paths in projects shipping one (e.g. flex).
# -Wno-error=* keeps GCC 14+ from refusing K&R-era code (e.g. compiler subproject).
CFLAGS_BASE=(
  -B/usr/bin/sh4-linux-gnu-
  -c
  -w
  -std=gnu11
  -DHAVE_CONFIG_H
  -Wno-error=implicit-function-declaration
  -Wno-error=implicit-int
  -Wno-error=int-conversion
)

# Sum .text + .rodata + .data across all .o files in $1.
size_of_objects() {
  local dir="$1"
  local total=0
  local obj
  while IFS= read -r -d '' obj; do
    while read -r section size addr; do
      case "$section" in
        .text|.rodata|.data)
          total=$((total + size))
          ;;
      esac
    done < <("$SIZE" --format=sysv "$obj" 2>/dev/null | tail -n +3 | head -n -2)
  done < <(find "$dir" -name '*.o' -print0)
  echo "$total"
}

entries=()
total_os=0
total_o2=0

# Declared once; reset to empty at the top of each inner iteration.
# Avoids relying on per-iteration `declare -A`/`unset`, which is brittle
# across bash versions.
declare -A include_set

for project_dir in "$CSIBE_DIR"/*/; do
  [ -d "$project_dir" ] || continue
  project=$(basename "$project_dir")

  for opt in Os O2; do
    workdir=$(mktemp -d)
    cp -r "$project_dir"/* "$workdir"/ 2>/dev/null || true

    # Build the -I list: $workdir itself, every dir containing a .h, AND every
    # ancestor of those dirs up to $workdir. Some projects do
    # `#include <subdir/foo.h>` where the header sits in $workdir/<...>/subdir/;
    # the include flag needs to point at the parent dir, not the dir itself.
    include_set=()
    include_set["$workdir"]=1
    while IFS= read -r -d '' hdr_dir; do
      # Walk from hdr_dir up to workdir.
      d="$hdr_dir"
      while [ "$d" != "$workdir" ] && [ "$d" != "/" ]; do
        include_set["$d"]=1
        d=$(dirname "$d")
      done
    done < <(find "$workdir" -name '*.h' -printf '%h\0' | sort -uz)

    include_flags=()
    for d in "${!include_set[@]}"; do
      include_flags+=("-I$d")
    done

    # Special-case: libpng needs zlib headers from a sibling subproject.
    if [ "$project" = "libpng-1.2.5" ] && [ -d "$CSIBE_DIR/zlib-1.1.4" ]; then
      include_flags+=("-I$CSIBE_DIR/zlib-1.1.4")
    fi

    # Find all .c files (recursively in case of nested layouts), compile each
    # individually to .o using our cross compiler. We deliberately ignore
    # any upstream Makefiles — they often use $(CC) defaults that don't
    # work for cross-compilation, and we only care about .o sizes anyway.
    build_ok=true
    found_src=false
    while IFS= read -r -d '' src; do
      found_src=true
      # Strip whatever the extension is (.c or .i) to derive the .o path.
      obj="${src%.*}.o"
      "$CC" "${CFLAGS_BASE[@]}" "${include_flags[@]}" "-${opt}" "$src" -o "$obj" 2>/dev/null || build_ok=false
    done < <(find "$workdir" \( -name '*.c' -o -name '*.i' \) -print0)

    if ! $found_src; then
      rm -rf "$workdir"
      continue
    fi

    if ! $build_ok; then
      # Some .c files may have failed but others might have produced .o files.
      # If anything compiled at all, count what we got and log a warning.
      n_o=$(find "$workdir" -name '*.o' | wc -l)
      if [ "$n_o" -eq 0 ]; then
        echo "run-csibe: $project at -$opt — all .c files failed to compile (skipping)" >&2
        rm -rf "$workdir"
        continue
      else
        echo "run-csibe: $project at -$opt — partial build ($n_o .o files; some failed)" >&2
      fi
    fi

    bytes=$(size_of_objects "$workdir")
    if [ "$bytes" -eq 0 ]; then
      echo "run-csibe: $project at -$opt produced no measurable output (skipping)" >&2
      rm -rf "$workdir"
      continue
    fi

    name="csibe_${project//[^a-zA-Z0-9_]/_}_${opt,,}_bytes"
    entries+=("{\"name\":\"$name\",\"unit\":\"bytes\",\"value\":$bytes}")
    echo "run-csibe: $project -$opt = $bytes bytes"

    if [ "$opt" = "Os" ]; then
      total_os=$((total_os + bytes))
    else
      total_o2=$((total_o2 + bytes))
    fi

    rm -rf "$workdir"
  done
done

entries+=("{\"name\":\"csibe_total_os_bytes\",\"unit\":\"bytes\",\"value\":$total_os}")
entries+=("{\"name\":\"csibe_total_o2_bytes\",\"unit\":\"bytes\",\"value\":$total_o2}")

printf '[%s]\n' "$(IFS=,; echo "${entries[*]}")" | python3 -m json.tool > "$OUT_FILE"
echo "run-csibe: wrote $OUT_FILE ($(jq length "$OUT_FILE") entries; totals Os=$total_os O2=$total_o2)"
