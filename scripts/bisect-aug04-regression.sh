#!/usr/bin/env bash
# Bisects the two symptoms that appeared together in sync 6de428fe
# (2026-08-04 14:30 UTC, upstream range 672923ae05..91dda5028f):
#
#   1. a back_threader/gori ICE that zeroed every BusyBox series
#   2. a ~3% CSiBE -Os size drop
#
# Both bisects walk the same range, so bisect 2 runs entirely off bisect 1's
# build cache. They run strictly one after the other: a GCC build peaks near
# 20 GB and this is sized for a 30 GB laptop.
#
# Usage:  scripts/bisect-aug04-regression.sh
#
# Environment:
#   OUT_ROOT     results dir (default: /tmp/aug04-bisect)
#   JOBS         parallel build jobs (default: 6 — do not raise on a 30 GB box)
#   KEEP_CACHE   set to 1 to keep the per-SHA build cache after the run
#   NO_DOCKER    set to 1 to run directly on the host instead of in the image
set -euo pipefail

GOOD=672923ae05596d602c16f4bdb74
BAD=91dda5028f6a7adcb4bf8f98484

IMAGE=ghcr.io/mountain-reverie/gcc-sh-base:latest
OUT_ROOT="${OUT_ROOT:-/tmp/aug04-bisect}"
JOBS="${JOBS:-6}"
MONITOR_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# CSiBE: bad if total -Os bytes fall below the midpoint of known-good and
# known-bad. Measured on the dashboard at entries 132 and 133.
CSIBE_KEY=csibe_total_os_bytes_sh4
CSIBE_GOOD=1543331
CSIBE_BAD=1496355
CSIBE_THRESHOLD=1519843

# Re-exec inside the CI image unless we are already there (or told not to).
if [ -z "${IN_CONTAINER:-}" ] && [ "${NO_DOCKER:-0}" != 1 ]; then
  echo "=> re-executing inside $IMAGE (--memory=24g)"
  mkdir -p "$OUT_ROOT"
  exec docker run --rm -i \
    --memory=24g --memory-swap=24g \
    -e IN_CONTAINER=1 -e JOBS="$JOBS" -e OUT_ROOT=/out \
    -e KEEP_CACHE="${KEEP_CACHE:-0}" \
    -v "$MONITOR_DIR":/monitor \
    -v "$OUT_ROOT":/out \
    -w /monitor "$IMAGE" \
    /monitor/scripts/bisect-aug04-regression.sh
fi

mkdir -p "$OUT_ROOT"
CACHE_DIR="$OUT_ROOT/gcc-cache"
BISECT_SRC=/tmp/bisect-gcc

export MONITOR_DIR JOBS
export BISECT_CACHE_DIR="$CACHE_DIR"
export OUT_DIR="$OUT_ROOT/predicate-out"
export GCC_PREFIX=/tmp/gcc-install
mkdir -p "$OUT_DIR" "$CACHE_DIR"

cleanup() {
  if [ "${KEEP_CACHE:-0}" != 1 ]; then
    echo "=> pruning build cache (set KEEP_CACHE=1 to keep it)"
    rm -rf "$CACHE_DIR"
  else
    echo "=> build cache kept at $CACHE_DIR ($(du -sh "$CACHE_DIR" | cut -f1))"
  fi
}
trap cleanup EXIT

# --- Preflight: refuse to run an unsound bisect ---------------------------
#
# run-busybox.sh exits 0 with all-zero metrics ("skip_zero") whenever the
# cross toolchain, the BusyBox corpus, or qemu-user is missing — these are
# *environment* facts, not facts about the GCC commit under test. Bisect 1
# uses `script` mode, whose exit code IS the bisect verdict: script exit 0 =
# "good". If any of these three prerequisites were ever missing mid-run, every
# commit tested at that point would score "good" regardless of whether it
# actually ICEs, and `git bisect run` would silently converge on the wrong
# commit — with no error surfaced anywhere. The candidate cross-gcc itself is
# excluded from this check: it is (re)built fresh by the predicate for every
# commit under test, so its absence/presence is not a static environment fact
# but the very thing the build step establishes each time.
#
# Verify the two static prerequisites ONCE, up front, and abort the whole run
# if either is unsound, rather than letting a per-commit run degrade silently.
preflight_busybox_env() {
  local target=sh4-linux-gnu bbdir qemu bad=0
  bbdir="${BUSYBOX_DIR:-$MONITOR_DIR/busybox}"
  qemu=qemu-sh4-static

  if [ ! -d "$bbdir" ]; then
    echo "preflight: BusyBox corpus missing at $bbdir" >&2
    bad=1
  fi
  if ! command -v "$qemu" >/dev/null 2>&1; then
    echo "preflight: $qemu not found on PATH" >&2
    bad=1
  fi
  if [ ! -x "/usr/bin/${target}-size" ]; then
    echo "preflight: /usr/bin/${target}-size missing" >&2
    bad=1
  fi

  if [ "$bad" != 0 ]; then
    echo "preflight: environment is NOT sound for bisect 1 (BusyBox ICE)." >&2
    echo "           run-busybox.sh would silently report every commit as" >&2
    echo "           'good' (zero-metric skip path), corrupting the bisect." >&2
    echo "           Fix the missing prerequisite(s) above before retrying." >&2
    exit 1
  fi
  echo "=> preflight OK: BusyBox corpus, qemu-sh4-static, sh4-linux-gnu-size all present"
}
preflight_busybox_env

if [ ! -d "$BISECT_SRC/.git" ]; then
  echo "=> cloning gcc-mirror (blobless)"
  git clone --filter=blob:none https://github.com/gcc-mirror/gcc.git "$BISECT_SRC"
fi
git -C "$BISECT_SRC" fetch --all --quiet

# Idempotent restart: a prior interrupted run may have left a bisect session
# active in $BISECT_SRC (e.g. the driver was killed mid-run). `git bisect
# reset` clears any such state before we start; failure is expected and
# harmless when there is nothing to reset, hence `|| true`.
( cd "$BISECT_SRC" && git bisect reset >/dev/null 2>&1 || true )

run_bisect() {  # $1 = log file, rest = predicate argv
  local log="$1"; shift
  ( cd "$BISECT_SRC"
    git bisect reset >/dev/null 2>&1 || true
    git bisect start "$BAD" "$GOOD"
    git bisect run "$MONITOR_DIR/scripts/sh-bisect-predicate.sh" "$@"
  ) 2>&1 | tee "$log"
}

culprit_from_log() {  # extracts the SHA git bisect declared first-bad
  grep -oE '^[0-9a-f]{40} is the first bad commit' "$1" | head -1 | cut -d' ' -f1
}

echo "############################################################"
echo "# Bisect 1/2 — BusyBox ICE (range $GOOD..$BAD)"
echo "############################################################"
run_bisect "$OUT_ROOT/bisect1-ice.log" \
  script "TARGET=sh4-linux-gnu scripts/run-busybox.sh"
ICE_SHA=$(culprit_from_log "$OUT_ROOT/bisect1-ice.log")

echo
echo "############################################################"
echo "# Bisect 2/2 — CSiBE -Os size jump (same range, cache-warm)"
echo "############################################################"
run_bisect "$OUT_ROOT/bisect2-csibe.log" \
  metric --script scripts/run-csibe.sh \
         --key "$CSIBE_KEY" \
         --threshold "$CSIBE_THRESHOLD" \
         --direction below
CSIBE_SHA=$(culprit_from_log "$OUT_ROOT/bisect2-csibe.log")

# Capture the full ICE diagnostic at the culprit, not the truncated backtrace
# tail the CI logs preserve. This is the signature the Bugzilla search needs,
# and a ready-made reproducer if no report exists.
if [ -n "$ICE_SHA" ]; then
  echo
  echo "=> capturing full ICE report at $ICE_SHA"
  ( cd "$BISECT_SRC" && git checkout -q "$ICE_SHA" )
  sha="$ICE_SHA"
  if MONITOR_DIR="$MONITOR_DIR" "$MONITOR_DIR/scripts/sh-bisect-predicate.sh" build; then
    ( cd "$MONITOR_DIR" && TARGET=sh4-linux-gnu BB_EXTRA_CFLAGS=-freport-bug \
        scripts/run-busybox.sh ) > "$OUT_ROOT/ice-report.txt" 2>&1 || true
    echo "   wrote $OUT_ROOT/ice-report.txt"
  fi
fi

describe() { [ -n "$1" ] && git -C "$BISECT_SRC" log -1 --format='%h %s' "$1" || echo "(not identified)"; }

{
  echo "Aug 4 regression bisect summary"
  echo "Range: $GOOD..$BAD"
  echo
  echo "BusyBox ICE culprit:  $(describe "$ICE_SHA")"
  echo "CSiBE size culprit:   $(describe "$CSIBE_SHA")"
  echo
  if [ -n "$ICE_SHA" ] && [ "$ICE_SHA" = "$CSIBE_SHA" ]; then
    echo "=> SAME commit causes both symptoms."
  else
    echo "=> DIFFERENT commits. The two symptoms are independent."
  fi
  echo
  echo "CSiBE: good=$CSIBE_GOOD bad=$CSIBE_BAD threshold=$CSIBE_THRESHOLD ($CSIBE_KEY)"
  echo "Logs:  $OUT_ROOT/bisect1-ice.log  $OUT_ROOT/bisect2-csibe.log"
  echo "ICE:   $OUT_ROOT/ice-report.txt"
  echo
  echo "Review the per-step verdicts in the logs before trusting these SHAs:"
  echo "CI only sampled the range endpoints, so an intermittent or"
  echo "config-dependent fault would still converge on something."
} | tee "$OUT_ROOT/summary.txt"
