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

  # In a git worktree, $MONITOR_DIR/.git is a FILE ("gitdir: <parent>/.git/
  # worktrees/<name>"), pointing outside $MONITOR_DIR entirely. Bind-mounting
  # only $MONITOR_DIR leaves that path missing inside the container, and git
  # resolves the repository from cwd before it even knows whether the
  # subcommand needs one — so EVERY git invocation under /monitor fails
  # (including build-gcc.sh's early `git config --global --add
  # safe.directory`), build() fails at every commit, and the whole bisect
  # converges on "all skipped" without ever attempting a build. Detect this
  # and bind-mount the real common git dir at its identical absolute path
  # so paths embedded in the worktree's .git file still resolve inside the
  # container. Read-write: git writes index/lock files under this dir.
  extra_mounts=()
  # `git rev-parse --git-common-dir` returns a path relative to its OWN cwd,
  # not to $MONITOR_DIR, unless invoked with cwd already at $MONITOR_DIR —
  # `-C "$MONITOR_DIR"` changes git's working context but the printed path is
  # still relative to that context, so a bare `cd "$GIT_COMMON_DIR"` from the
  # driver's own (possibly different) cwd would resolve the wrong directory
  # or fail outright. Run the whole thing with cwd already inside
  # $MONITOR_DIR so a relative result resolves correctly regardless of where
  # the driver itself was invoked from.
  GIT_COMMON_DIR="$(cd "$MONITOR_DIR" && git rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -n "$GIT_COMMON_DIR" ]; then
    case "$GIT_COMMON_DIR" in
      /*) : ;;                              # already absolute
      *)  GIT_COMMON_DIR="$MONITOR_DIR/$GIT_COMMON_DIR" ;;
    esac
    GIT_COMMON_DIR="$(cd "$GIT_COMMON_DIR" && pwd -P)"
    case "$GIT_COMMON_DIR" in
      "$MONITOR_DIR"/*|"$MONITOR_DIR")
        # Ordinary checkout: common dir already lives under $MONITOR_DIR and
        # is covered by the existing mount. Nothing extra to do.
        ;;
      *)
        echo "=> worktree detected: also bind-mounting git common dir $GIT_COMMON_DIR"
        extra_mounts=(-v "$GIT_COMMON_DIR":"$GIT_COMMON_DIR")
        ;;
    esac
  fi

  exec docker run --rm -i \
    --memory=24g --memory-swap=24g \
    -e IN_CONTAINER=1 -e JOBS="$JOBS" -e OUT_ROOT=/out \
    -e KEEP_CACHE="${KEEP_CACHE:-0}" \
    -v "$MONITOR_DIR":/monitor \
    -v "$OUT_ROOT":/out \
    "${extra_mounts[@]}" \
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
  local rc=$?
  # Only prune on a clean (exit 0) run. An aborted/interrupted run (nonzero
  # exit, e.g. a shell error, a signal, or the script dying partway through)
  # is exactly when a retry needs the warm cache most — deleting it on abort
  # would throw away the whole reason bisect 2 exists to be fast, and would
  # force a full rebuild for no reason related to the actual failure.
  if [ "$rc" != 0 ]; then
    echo "=> driver exited nonzero ($rc); keeping build cache at $CACHE_DIR for retry" >&2
    return
  fi
  if [ "${KEEP_CACHE:-0}" != 1 ]; then
    echo "=> pruning build cache (set KEEP_CACHE=1 to keep it)"
    rm -rf "$CACHE_DIR"
  else
    echo "=> build cache kept at $CACHE_DIR ($(du -sh "$CACHE_DIR" | cut -f1))"
  fi
}
trap cleanup EXIT

# --- Preflight: prove git actually resolves a repository from /monitor ---
#
# A 7-minute silent no-op that looks like a completed run (every commit
# skipped, both bisects exhaust the range, ~7 min instead of ~3 hours, no
# GCC build ever attempted) is far worse than an immediate, loud abort. This
# happened for real when $MONITOR_DIR was a git worktree: the container only
# had $MONITOR_DIR bind-mounted, but a worktree's $MONITOR_DIR/.git is a FILE
# pointing at an absolute path outside $MONITOR_DIR (the parent repo's
# .git/worktrees/<name>), which does not exist inside the container. git
# resolves the repository from cwd before it even knows whether the
# subcommand needs one, so every git invocation under /monitor failed —
# including build-gcc.sh's early `git config --global --add safe.directory`
# — build() failed at every commit, and the predicate returned skip(125) for
# the whole range. The mount fix above (bind-mounting the real common git
# dir) addresses the cause; this check proves the fix actually worked,
# before spending hours pretending to bisect.
preflight_git_env() {
  # The container runs as a different UID than the owner of the bind-mounted
  # host directories, which trips git's "dubious ownership" protection on
  # every invocation (discovered live: `fatal: detected dubious ownership in
  # repository at '/monitor'`, surfaced by this very preflight check working
  # as intended). This is an ephemeral, single-purpose bisect container, not
  # a shared or security-sensitive host, and the exact set of paths to trust
  # varies (a worktree's mounted common dir can be anywhere) — so trust
  # unconditionally rather than trying to enumerate the exact directories,
  # matching the same pattern CI tooling (e.g. actions/checkout) uses for
  # this identical container/bind-mount scenario.
  git config --global --add safe.directory '*'
  if ! git -C "$MONITOR_DIR" rev-parse HEAD >/dev/null 2>"$OUT_ROOT/.git-preflight.err"; then
    echo "::error::preflight: git does not resolve a repository at $MONITOR_DIR" >&2
    echo "           (inside the container, if this is a worktree checkout)." >&2
    sed 's/^/           /' "$OUT_ROOT/.git-preflight.err" >&2
    echo "           This is exactly the failure that makes every bisect commit" >&2
    echo "           skip and the whole run silently converge on nothing." >&2
    exit 1
  fi
  rm -f "$OUT_ROOT/.git-preflight.err"
  echo "=> preflight OK: git resolves $MONITOR_DIR (HEAD=$(git -C "$MONITOR_DIR" rev-parse --short HEAD))"
}
preflight_git_env

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
  # `git bisect run` exits nonzero (verified: 2) when the range ends with
  # only skipped commits left ("We cannot bisect more!") — a real, expected
  # terminal state, not a driver malfunction. It also identifies a first bad
  # commit successfully in the ordinary case (exit 0). Either way, this
  # function's job is only to produce a log for culprit_from_log to parse;
  # its own exit status must never propagate to the caller, or `set -e`
  # would abort the whole driver on the skip-only outcome — before bisect 2
  # ever runs and before summary.txt/ice-report.txt get written.
  local log="$1"; shift
  # The `|| true` on the pipeline itself is required, not decorative: under
  # `set -e`, a failing pipeline aborts the script immediately at the point
  # it fails — a later `true` statement on its own line is never reached and
  # does NOT retroactively make this line safe.
  ( cd "$BISECT_SRC"
    git bisect reset >/dev/null 2>&1 || true
    git bisect start "$BAD" "$GOOD"
    git bisect run "$MONITOR_DIR/scripts/sh-bisect-predicate.sh" "$@"
  ) 2>&1 | tee "$log" || true
}

culprit_from_log() {  # extracts the SHA git bisect declared first-bad.
  # No match is a real, expected outcome (e.g. the bisect ends with only
  # skipped commits left, so git bisect never prints "is the first bad
  # commit" at all) — NOT a script error. Under `set -e`, letting the grep's
  # exit status propagate into a command-substitution assignment
  # (`X=$(culprit_from_log ...)`) would kill the whole driver right here,
  # before bisect 2 ever runs and before summary.txt/ice-report.txt are
  # written. Force success unconditionally so the caller always gets either
  # a SHA or an empty string, never a fatal signal.
  grep -oE '^[0-9a-f]{40} is the first bad commit' "$1" | head -1 | cut -d' ' -f1 || true
}

echo "############################################################"
echo "# Bisect 1/2 — BusyBox ICE (range $GOOD..$BAD)"
echo "############################################################"
run_bisect "$OUT_ROOT/bisect1-ice.log" \
  script "TARGET=sh4-linux-gnu scripts/run-busybox.sh"
ICE_SHA=$(culprit_from_log "$OUT_ROOT/bisect1-ice.log") || true

echo
echo "############################################################"
echo "# Bisect 2/2 — CSiBE -Os size jump (same range, cache-warm)"
echo "############################################################"
run_bisect "$OUT_ROOT/bisect2-csibe.log" \
  metric --script scripts/run-csibe.sh \
         --key "$CSIBE_KEY" \
         --threshold "$CSIBE_THRESHOLD" \
         --direction below
CSIBE_SHA=$(culprit_from_log "$OUT_ROOT/bisect2-csibe.log") || true

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
  # Only assert a same/different verdict when BOTH culprits were actually
  # identified. Two empty SHAs previously fell through to the `else` branch
  # and printed "DIFFERENT commits... independent" — a substantive, WRONG
  # claim about the regressions when in fact nothing was determined at all.
  # "We determined nothing" and "we determined they are independent" are
  # opposite findings; never let the former silently print as the latter.
  if [ -n "$ICE_SHA" ] && [ -n "$CSIBE_SHA" ]; then
    if [ "$ICE_SHA" = "$CSIBE_SHA" ]; then
      echo "=> SAME commit causes both symptoms."
    else
      echo "=> DIFFERENT commits. The two symptoms are independent."
    fi
  else
    echo "=> COULD NOT COMPARE: at least one bisect failed to identify a culprit."
    [ -z "$ICE_SHA" ]   && echo "   - BusyBox ICE bisect did not converge on a culprit (see bisect1-ice.log)."
    [ -z "$CSIBE_SHA" ] && echo "   - CSiBE size bisect did not converge on a culprit (see bisect2-csibe.log)."
    echo "   This usually means every commit in range was skipped — check the"
    echo "   preflight output above and the log for build/skip reasons before"
    echo "   re-running."
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

# A run that identified NEITHER culprit determined nothing and must not exit
# 0 — an operator (or any future automation reading this exit code) needs to
# notice. This composes correctly with cleanup(): it only prunes the build
# cache on a clean (exit 0) run, so exiting nonzero here also retains the
# cache for a retry, which is exactly what's wanted when nothing was learned.
if [ -z "$ICE_SHA" ] && [ -z "$CSIBE_SHA" ]; then
  echo "::error::bisect-aug04-regression: neither culprit was identified; see summary.txt" >&2
  exit 1
fi
