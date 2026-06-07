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
#
# Environment:
#   MONITOR_DIR  path to the gcc-sh-monitor checkout (scripts/ + boards/)
#   OUT_DIR      dejagnu output dir (default: /tmp/dejagnu-out); gcc.sum read from here
set -uo pipefail

TYPE="${1:?usage: sh-bisect-predicate.sh <build|script|dejagnu> [arg]}"
ARG="${2:-}"
MONITOR_DIR="${MONITOR_DIR:?MONITOR_DIR must point at the gcc-sh-monitor checkout}"
OUT_DIR="${OUT_DIR:-/tmp/dejagnu-out}"
export OUT_DIR

sha="$(git rev-parse HEAD)"

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
    build || exit 125
    ( cd "$MONITOR_DIR" && scripts/run-dejagnu.sh ) || true
    sum="$OUT_DIR/gcc.sum"
    while IFS= read -r t; do
      [ -z "$t" ] && continue
      if grep -qF "FAIL: $t" "$sum"; then exit 1; fi
    done < "$ARG"
    exit 0
    ;;
  *)
    echo "unknown predicate type: $TYPE" >&2
    exit 125
    ;;
esac
