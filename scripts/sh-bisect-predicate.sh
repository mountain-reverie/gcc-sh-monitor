#!/usr/bin/env bash
# git-bisect-run predicate for SH regressions. Run from the gcc-mirror bisect
# checkout (HEAD = commit under test). Exit codes follow git bisect run:
#   0   good  — commit does NOT exhibit the failure
#   1   bad   — commit exhibits the failure
#   125 skip  — cannot test this commit (build broke for a non-build failure)
#
# Usage:
#   sh-bisect-predicate.sh build
#   sh-bisect-predicate.sh script  '<reproduce command>'
#   sh-bisect-predicate.sh dejagnu '<regressed-tests-file>'   # one "path detail" per line
#   sh-bisect-predicate.sh sh-sim  '<regressed-tests-file>'   # one "isa:path detail" per line
#   sh-bisect-predicate.sh metric --script <path> --key <name> \
#                                 --threshold <number> --direction below|above
#
# Environment:
#   MONITOR_DIR  path to the gcc-sh-monitor checkout (scripts/ + boards/)
#   OUT_DIR      output dir (default: /tmp/dejagnu-out); dejagnu gcc.sum and sh-sim {execute,ieee}-<isa>.sum are read from here
set -uo pipefail

TYPE="${1:?usage: sh-bisect-predicate.sh <build|script|dejagnu|sh-sim|metric> [arg]}"
ARG="${2:-}"
MONITOR_DIR="${MONITOR_DIR:?MONITOR_DIR must point at the gcc-sh-monitor checkout}"
OUT_DIR="${OUT_DIR:-/tmp/dejagnu-out}"
export OUT_DIR

sha="$(git rev-parse HEAD 2>/dev/null)" || sha=""
if [ -z "$sha" ]; then
  echo "bisect: git rev-parse HEAD failed or returned empty -- cannot identify commit under test (infra fault, not a verdict)" >&2
  exit 125
fi
BISECT_SRC="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Build the candidate GCC, or restore it from the per-SHA cache when
# BISECT_CACHE_DIR is set. The cache exists so a second bisect over the same
# commit range costs no rebuilds — a GCC build is ~40 min, unpacking is seconds.
# Returns: 0 = success, 1 = genuine build failure (a fact about the commit),
# 2 = cache-restore failure (a fact about our infra, never the commit) — every
# call site must map 2 to skip(125), never to bad(1).
build() {
  local prefix="${GCC_PREFIX:-/tmp/gcc-install}"
  local cache="${BISECT_CACHE_DIR:-}"
  # gzip, not zstd: the CI image (ghcr.io/mountain-reverie/gcc-sh-base) does
  # not ship a zstd binary, so every `tar --zstd` pack silently failed
  # (non-fatally) during the real Aug 4 run, leaving the cache empty for the
  # whole run and forcing bisect 2 to rebuild everything from scratch. gzip
  # is present in the image (verified) and universally available.
  local tarball="$cache/$sha.tar.gz"

  if [ -n "$cache" ] && [ -f "$tarball" ]; then
    echo "bisect: cache hit for $sha" >&2
    rm -rf "$prefix"; mkdir -p "$prefix"
    if ! tar -xzf "$tarball" -C "$prefix"; then
      echo "bisect: cache restore failed for $sha, clearing prefix" >&2
      rm -rf "$prefix"
      return 2
    fi
    return 0
  fi

  rm -rf "$prefix"
  ( cd "$MONITOR_DIR" && GCC_PREFIX="$prefix" scripts/build-gcc.sh "$sha" sh4-linux-gnu ) \
    || return 1

  if [ -n "$cache" ]; then
    mkdir -p "$cache"
    if tar -czf "$tarball.tmp" -C "$prefix" . ; then
      mv "$tarball.tmp" "$tarball"
      echo "bisect: cached $sha ($(du -sh "$tarball" | cut -f1))" >&2
    else
      rm -f "$tarball.tmp"
      echo "bisect: caching failed for $sha (continuing)" >&2
    fi
  fi
  return 0
}

case "$TYPE" in
  build)
    build; rc=$?
    case "$rc" in
      0) exit 0 ;;
      2) exit 125 ;;   # cache-restore failure: infra fact, not a verdict on this commit
      *) exit 1 ;;
    esac
    ;;
  script)
    build || exit 125
    if ( cd "$MONITOR_DIR" && eval "$ARG" ); then exit 0; else exit 1; fi
    ;;
  dejagnu)
    [ -f "$ARG" ] || { echo "regressed-tests file not found: $ARG" >&2; exit 125; }
    build || exit 125
    ( cd "$MONITOR_DIR" && scripts/run-dejagnu.sh ) || true
    sum="$OUT_DIR/gcc.sum"
    [ -f "$sum" ] || { echo "gcc.sum missing after dejagnu run: $sum" >&2; exit 125; }
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      if grep -qF "FAIL: $t" "$sum"; then exit 1; fi
    done < "$ARG"
    exit 0
    ;;
  sh-sim)
    [ -f "$ARG" ] || { echo "regressed-tests file not found: $ARG" >&2; exit 125; }
    # Build the sh-elf gcc at this commit into the baked /opt/sh-elf. Source is the
    # bisect checkout (already at HEAD=$sha); build failure => skip.
    ( cd "$MONITOR_DIR" && GCC_SRC_DIR="$BISECT_SRC" scripts/build-sh-elf-gcc.sh "$sha" ) || exit 125
    rm -f "$OUT_DIR"/execute-*.sum "$OUT_DIR"/ieee-*.sum
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      tag="${line%% *}"          # "<isa>:<testpath>"
      isa="${tag%%:*}"
      tpath="${tag#*:}"
      ( cd "$MONITOR_DIR" && ISAS="$isa" GLOB="${tpath##*/}" OUT_DIR="$OUT_DIR" \
          scripts/run-sh-sim.sh ) || true
      if grep -qF "FAIL: $tpath" "$OUT_DIR/execute-$isa.sum" 2>/dev/null \
         || grep -qF "FAIL: $tpath" "$OUT_DIR/ieee-$isa.sum" 2>/dev/null; then
        exit 1
      fi
    done < "$ARG"
    exit 0
    ;;
  metric)
    # Bisect a continuous metric against a threshold.
    #   metric --script <path> --key <name> --threshold <n> --direction below|above
    m_script=""; m_key=""; m_threshold=""; m_direction=""
    shift   # drop the leading "metric"
    while [ $# -gt 0 ]; do
      case "$1" in
        --script|--key|--threshold|--direction)
          [ $# -ge 2 ] || { echo "metric: $1 requires a value" >&2; exit 125; }
          ;;
      esac
      case "$1" in
        --script)    m_script="$2";    shift 2 ;;
        --key)       m_key="$2";       shift 2 ;;
        --threshold) m_threshold="$2"; shift 2 ;;
        --direction) m_direction="$2"; shift 2 ;;
        *) echo "metric: unknown option $1" >&2; exit 125 ;;
      esac
    done
    for v in m_script m_key m_threshold m_direction; do
      [ -n "${!v}" ] || { echo "metric: --${v#m_} is required" >&2; exit 125; }
    done
    case "$m_direction" in
      below|above) ;;
      *) echo "metric: --direction must be below or above" >&2; exit 125 ;;
    esac

    build || exit 125

    metric_out="$OUT_DIR/metric.json"
    rm -f "$metric_out"
    mkdir -p "$OUT_DIR"
    ( cd "$MONITOR_DIR" && OUT_FILE="$metric_out" "$m_script" ) || exit 125
    [ -f "$metric_out" ] || { echo "metric: $m_script wrote no $metric_out" >&2; exit 125; }

    value=$(jq -r --arg k "$m_key" \
              'map(select(.name == $k)) | if length == 0 then "" else .[0].value end' \
              "$metric_out" 2>/dev/null)
    [ -n "$value" ] && [ "$value" != "null" ] \
      || { echo "metric: key $m_key absent from $metric_out" >&2; exit 125; }

    # A zero-valued metric is never a legitimate measurement here -- it is
    # the signature of a skip_zero path (missing toolchain/corpus/qemu) or
    # a compile failure that slipped through, not a fact about the commit.
    # Treating it as real would make "0 < threshold" true for every commit
    # and converge the bisect on the first one tested, with nothing
    # surfaced. Distinguish this from the absent-key case above (both exit
    # 125, but for different, clearly stated reasons).
    if awk -v v="$value" 'BEGIN { exit !(v == 0) }'; then
      echo "metric: key $m_key = 0 in $metric_out -- treating as untestable (zero metric, not an absent key)" >&2
      exit 125
    fi

    echo "metric: $m_key = $value (threshold $m_threshold, bad if $m_direction)" >&2
    if awk -v v="$value" -v t="$m_threshold" -v d="$m_direction" \
         'BEGIN { exit !((d == "below" && v < t) || (d == "above" && v > t)) }'; then
      exit 1   # bad
    fi
    exit 0     # good
    ;;
  *)
    echo "unknown predicate type: $TYPE" >&2
    exit 125
    ;;
esac
