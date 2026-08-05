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
#   sh-bisect-predicate.sh metric --script <path> --key <name> \
#                                 --threshold <number> --direction below|above
#
# Environment:
#   MONITOR_DIR  path to the gcc-sh-monitor checkout (scripts/ + boards/)
#   OUT_DIR      output dir (default: /tmp/dejagnu-out); dejagnu gcc.sum and sh-sim {execute,ieee}-<isa>.sum are read from here
set -uo pipefail

TYPE="${1:?usage: sh-bisect-predicate.sh <build|script|dejagnu> [arg]}"
ARG="${2:-}"
MONITOR_DIR="${MONITOR_DIR:?MONITOR_DIR must point at the gcc-sh-monitor checkout}"
OUT_DIR="${OUT_DIR:-/tmp/dejagnu-out}"
export OUT_DIR

sha="$(git rev-parse HEAD)"
BISECT_SRC="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

build() { ( cd "$MONITOR_DIR" && scripts/build-gcc.sh "$sha" sh4-linux-gnu ); }

case "$TYPE" in
  build)
    if build; then exit 0; else exit 1; fi
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
