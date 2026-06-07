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

[ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails failures"; exit 1; }
