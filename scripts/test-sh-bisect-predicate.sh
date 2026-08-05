#!/usr/bin/env bash
# Tests sh-bisect-predicate.sh with stubbed build-gcc.sh / run-dejagnu.sh.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
pred="$here/sh-bisect-predicate.sh"
fails=0

setup() {
  root=$(mktemp -d)
  ( cd "$root" && git init -q && git -c user.email=t@t -c user.name=t \
      commit -q --allow-empty -m x )
  mon="$root/mon"; mkdir -p "$mon/scripts"
  out="$root/out"; mkdir -p "$out"
}

mk_build() {  # $1 = exit code the stub build should return
  cat > "$mon/scripts/build-gcc.sh" <<EOF
#!/usr/bin/env bash
exit $1
EOF
  chmod +x "$mon/scripts/build-gcc.sh"
}

mk_dejagnu() {  # writes a gcc.sum into \$OUT_DIR
  cat > "$mon/scripts/run-dejagnu.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$1" > "\$OUT_DIR/gcc.sum"
EOF
  chmod +x "$mon/scripts/run-dejagnu.sh"
}

mk_shsim_build() {  # $1 = exit code the stub sh-elf gcc build returns
  cat > "$mon/scripts/build-sh-elf-gcc.sh" <<EOF
#!/usr/bin/env bash
exit $1
EOF
  chmod +x "$mon/scripts/build-sh-elf-gcc.sh"
}

mk_shsim_run() {  # $1 = a line written into \$OUT_DIR/execute-<ISAS>.sum
  cat > "$mon/scripts/run-sh-sim.sh" <<EOF
#!/usr/bin/env bash
mkdir -p "\$OUT_DIR"
printf '%s\n' "$1" > "\$OUT_DIR/execute-\${ISAS}.sum"
EOF
  chmod +x "$mon/scripts/run-sh-sim.sh"
}

mk_shsim_run_ieee() {  # $1 = a line written into $OUT_DIR/ieee-<ISAS>.sum
  cat > "$mon/scripts/run-sh-sim.sh" <<EOF
#!/usr/bin/env bash
mkdir -p "\$OUT_DIR"
printf '%s\n' "$1" > "\$OUT_DIR/ieee-\${ISAS}.sum"
EOF
  chmod +x "$mon/scripts/run-sh-sim.sh"
}

check() {  # $1 desc, $2 expected-exit, then runs pred with remaining args/env
  desc="$1"; want="$2"; shift 2
  ( cd "$root" && MONITOR_DIR="$mon" OUT_DIR="$out" "$pred" "$@" )
  got=$?
  if [ "$got" = "$want" ]; then echo "PASS $desc"; else
    echo "FAIL $desc: want exit $want got $got"; fails=$((fails+1)); fi
}

setup; mk_build 0; check "build-ok-good" 0 build
setup; mk_build 1; check "build-broken-bad" 1 build

setup; mk_build 1; check "script-buildbroken-skip" 125 script "true"
setup; mk_build 0; check "script-ok-good" 0 script "true"
setup; mk_build 0; check "script-fail-bad" 1 script "false"

setup; mk_build 0; mk_dejagnu "FAIL: gcc.target/sh/pr1.c (test for excess errors)"
echo "gcc.target/sh/pr1.c (test for excess errors)" > "$root/regressed.txt"
check "dejagnu-still-failing-bad" 1 dejagnu "$root/regressed.txt"

setup; mk_build 0; mk_dejagnu "PASS: gcc.target/sh/pr1.c (test for excess errors)"
echo "gcc.target/sh/pr1.c (test for excess errors)" > "$root/regressed.txt"
check "dejagnu-now-passing-good" 0 dejagnu "$root/regressed.txt"

# dejagnu: missing regressed-tests file -> skip(125)
setup; mk_build 0; mk_dejagnu "PASS: x"
check "dejagnu-missing-regressed-file-skip" 125 dejagnu "$root/does-not-exist.txt"

# dejagnu: run-dejagnu wrote no gcc.sum -> skip(125)
setup; mk_build 0
cat > "$mon/scripts/run-dejagnu.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$mon/scripts/run-dejagnu.sh"
echo "gcc.target/sh/pr1.c (test for excess errors)" > "$root/regressed.txt"
check "dejagnu-no-gccsum-skip" 125 dejagnu "$root/regressed.txt"

# sh-sim: regressed test still FAILs -> bad(1)
setup; mk_shsim_build 0; mk_shsim_run "FAIL: gcc.c-torture/execute/foo.c   -O2  execution test"
printf 'm2a:gcc.c-torture/execute/foo.c -O2 execution test\n' > "$root/regressed.txt"
check "shsim-still-failing-bad" 1 sh-sim "$root/regressed.txt"

# sh-sim: now passing -> good(0)
setup; mk_shsim_build 0; mk_shsim_run "PASS: gcc.c-torture/execute/foo.c   -O2  execution test"
printf 'm2a:gcc.c-torture/execute/foo.c -O2 execution test\n' > "$root/regressed.txt"
check "shsim-now-passing-good" 0 sh-sim "$root/regressed.txt"

# sh-sim: build broken -> skip(125)
setup; mk_shsim_build 1
printf 'm2a:gcc.c-torture/execute/foo.c -O2 execution test\n' > "$root/regressed.txt"
check "shsim-buildbroken-skip" 125 sh-sim "$root/regressed.txt"

# sh-sim: missing regressed-tests file -> skip(125)
setup; mk_shsim_build 0
check "shsim-missing-file-skip" 125 sh-sim "$root/does-not-exist.txt"

# sh-sim: regression only in the ieee suite -> bad(1)
setup; mk_shsim_build 0; mk_shsim_run_ieee "FAIL: gcc.c-torture/execute/ieee/mzero.c   execution,  -O1"
printf 'm4:gcc.c-torture/execute/ieee/mzero.c execution, -O1\n' > "$root/regressed.txt"
check "shsim-ieee-failing-bad" 1 sh-sim "$root/regressed.txt"

mk_metric() {  # $1 = metric value the stub script emits
  cat > "$mon/scripts/stub-metric.sh" <<EOF
#!/usr/bin/env bash
mkdir -p "\$(dirname "\$OUT_FILE")"
cat > "\$OUT_FILE" <<JSON
[{"name":"csibe_total_os_bytes_sh4","unit":"bytes","value":$1}]
JSON
EOF
  chmod +x "$mon/scripts/stub-metric.sh"
}

mk_metric_empty() {  # emits valid JSON that lacks the key
  cat > "$mon/scripts/stub-metric.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p "$(dirname "$OUT_FILE")"
printf '[{"name":"other_key","unit":"bytes","value":1}]\n' > "$OUT_FILE"
EOF
  chmod +x "$mon/scripts/stub-metric.sh"
}

MOPTS="--key csibe_total_os_bytes_sh4 --threshold 1519843 --direction below"

# value above threshold (pre-regression size) -> good(0)
setup; mk_build 0; mk_metric 1543331
check "metric-above-threshold-good" 0 metric --script scripts/stub-metric.sh $MOPTS

# value below threshold (post-regression size) -> bad(1)
setup; mk_build 0; mk_metric 1496355
check "metric-below-threshold-bad" 1 metric --script scripts/stub-metric.sh $MOPTS

# exactly at threshold is not "below" -> good(0)
setup; mk_build 0; mk_metric 1519843
check "metric-at-threshold-good" 0 metric --script scripts/stub-metric.sh $MOPTS

# direction=above inverts the verdict
setup; mk_build 0; mk_metric 1543331
check "metric-direction-above-bad" 1 metric --script scripts/stub-metric.sh \
      --key csibe_total_os_bytes_sh4 --threshold 1519843 --direction above

# GCC build broken -> skip(125)
setup; mk_build 1; mk_metric 1496355
check "metric-buildbroken-skip" 125 metric --script scripts/stub-metric.sh $MOPTS

# metric script fails -> skip(125)
setup; mk_build 0
printf '#!/usr/bin/env bash\nexit 1\n' > "$mon/scripts/stub-metric.sh"
chmod +x "$mon/scripts/stub-metric.sh"
check "metric-script-failed-skip" 125 metric --script scripts/stub-metric.sh $MOPTS

# key absent from output -> skip(125)
setup; mk_build 0; mk_metric_empty
check "metric-key-absent-skip" 125 metric --script scripts/stub-metric.sh $MOPTS

# --threshold as trailing token with no value -> skip(125), not "unbound variable" exit 1
setup; mk_build 0; mk_metric 1500000
check "metric-missing-value-threshold-skip" 125 metric --script scripts/stub-metric.sh \
      --key csibe_total_os_bytes_sh4 --direction below --threshold

# --script as trailing token with no value -> skip(125)
setup; mk_build 0; mk_metric 1500000
check "metric-missing-value-script-skip" 125 metric \
      --key csibe_total_os_bytes_sh4 --threshold 1519843 --direction below --script

# ---- per-SHA build cache ----
mk_counting_build() {  # stub build increments a counter and populates GCC_PREFIX
  cat > "$mon/scripts/build-gcc.sh" <<'EOF'
#!/usr/bin/env bash
echo x >> "$COUNTER"
mkdir -p "$GCC_PREFIX/bin"
echo built > "$GCC_PREFIX/bin/marker"
exit 0
EOF
  chmod +x "$mon/scripts/build-gcc.sh"
}

# Cache miss then hit: the second run must not invoke build-gcc.sh.
setup; mk_counting_build
cache="$root/cache"; prefix="$root/prefix"; counter="$root/counter"; : > "$counter"
for i in 1 2; do
  ( cd "$root" && MONITOR_DIR="$mon" OUT_DIR="$out" \
      BISECT_CACHE_DIR="$cache" GCC_PREFIX="$prefix" COUNTER="$counter" \
      "$pred" build ) >/dev/null 2>&1
done
n=$(wc -l < "$counter")
if [ "$n" = 1 ]; then echo "PASS cache-second-run-is-a-hit"; else
  echo "FAIL cache-second-run-is-a-hit: build ran $n times, want 1"; fails=$((fails+1)); fi

# A cache hit must actually restore the install tree.
if [ -f "$prefix/bin/marker" ]; then echo "PASS cache-hit-restores-prefix"; else
  echo "FAIL cache-hit-restores-prefix: marker missing"; fails=$((fails+1)); fi

# A corrupted/truncated cache tarball under the `build` arm must SKIP (125),
# never be reported as a compile failure (1) — it is an infra fact, not a
# verdict on the commit under test.
setup; mk_counting_build
cache="$root/cache"; prefix="$root/prefix"; counter="$root/counter"; : > "$counter"
mkdir -p "$cache"
sha=$(cd "$root" && git rev-parse HEAD)
head -c 16 /dev/zero > "$cache/$sha.tar.zst"   # truncated/corrupt, not a valid archive
( cd "$root" && MONITOR_DIR="$mon" OUT_DIR="$out" \
    BISECT_CACHE_DIR="$cache" GCC_PREFIX="$prefix" COUNTER="$counter" \
    "$pred" build ) >/dev/null 2>&1
got=$?
if [ "$got" = 125 ]; then echo "PASS build-corrupt-cache-skip"; else
  echo "FAIL build-corrupt-cache-skip: want exit 125 got $got"; fails=$((fails+1)); fi

# A genuine compile failure under the `build` arm must still be BAD (1),
# even with BISECT_CACHE_DIR set and no cache entry present (miss -> build).
setup; mk_build 1
cache="$root/cache"; prefix="$root/prefix"
( cd "$root" && MONITOR_DIR="$mon" OUT_DIR="$out" \
    BISECT_CACHE_DIR="$cache" GCC_PREFIX="$prefix" "$pred" build ) >/dev/null 2>&1
got=$?
if [ "$got" = 1 ]; then echo "PASS build-genuine-failure-still-bad"; else
  echo "FAIL build-genuine-failure-still-bad: want exit 1 got $got"; fails=$((fails+1)); fi

# With BISECT_CACHE_DIR unset, every run rebuilds (unchanged behaviour).
setup; mk_counting_build
prefix="$root/prefix"; counter="$root/counter"; : > "$counter"
for i in 1 2; do
  ( cd "$root" && MONITOR_DIR="$mon" OUT_DIR="$out" \
      GCC_PREFIX="$prefix" COUNTER="$counter" "$pred" build ) >/dev/null 2>&1
done
n=$(wc -l < "$counter")
if [ "$n" = 2 ]; then echo "PASS no-cache-always-rebuilds"; else
  echo "FAIL no-cache-always-rebuilds: build ran $n times, want 2"; fails=$((fails+1)); fi

[ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails failures"; exit 1; }
