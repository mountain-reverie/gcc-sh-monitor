#!/usr/bin/env bash
# Tests run-busybox.sh failure taxonomy: environment-absent cases emit zeros
# and exit 0; compile failures exit 1 and write no metrics file.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/run-busybox.sh"
fails=0

setup() {
  root=$(mktemp -d)
  prefix="$root/gcc-install"; mkdir -p "$prefix/bin"
  bbdir="$root/busybox";      mkdir -p "$bbdir"
  bindir="$root/bin";         mkdir -p "$bindir"
  out="$root/metrics.json"

  # Stub cross gcc, size, and qemu so the environment checks pass.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$prefix/bin/sh4-linux-gnu-gcc"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bindir/sh4-linux-gnu-size"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bindir/qemu-sh4-static"
  chmod +x "$prefix/bin/sh4-linux-gnu-gcc" "$bindir/sh4-linux-gnu-size" "$bindir/qemu-sh4-static"
}

# $1 = exit code for the `defconfig` target, $2 = exit code for the default
# (build) target, $3 = "yes" to have the build produce a busybox binary.
mk_busybox() {
  : > "$bbdir/Config.in"
  cat > "$bbdir/Makefile" <<EOF
defconfig:
	@exit $1
oldconfig:
	@touch .config
all:
	@if [ "$3" = yes ]; then touch busybox; fi
	@exit $2
EOF
  # Real BusyBox writes .config during defconfig; emulate for the sed steps.
  printf '# CONFIG_STATIC is not set\n' > "$bbdir/.config"
}

run() {  # runs run-busybox.sh with the stubbed environment
  ( PATH="$bindir:$PATH" \
    GCC_PREFIX="$prefix" BUSYBOX_DIR="$bbdir" OUT_FILE="$out" \
    SH4_SIZE="$bindir/sh4-linux-gnu-size" JOBS=1 \
    "$script" >/dev/null 2>"$root/stderr" )
}

check() {  # $1 desc, $2 expected exit, $3 expected-metrics-file: yes|no,
           # $4 (optional) exact ::error:: message that must appear in stderr
  desc="$1"; want="$2"; wantfile="$3"; wantmsg="${4:-}"
  run; got=$?
  ok=1
  [ "$got" = "$want" ] || { echo "FAIL $desc: want exit $want got $got"; ok=0; }
  if [ "$wantfile" = yes ] && [ ! -f "$out" ]; then
    echo "FAIL $desc: expected metrics file, none written"; ok=0
  fi
  if [ "$wantfile" = no ] && [ -f "$out" ]; then
    echo "FAIL $desc: expected NO metrics file, one was written"; ok=0
  fi
  if [ -n "$wantmsg" ] && ! grep -qF "$wantmsg" "$root/stderr"; then
    echo "FAIL $desc: expected stderr to contain '$wantmsg', got:"; ok=0
    sed 's/^/    /' "$root/stderr"
  fi
  [ "$ok" = 1 ] && echo "PASS $desc" || fails=$((fails+1))
}

# Environment absent -> soft skip, zeros written, exit 0.
setup; rm -f "$prefix/bin/sh4-linux-gnu-gcc"
check "missing-cross-gcc-soft" 0 yes

setup; mk_busybox 0 0 yes; rm -rf "$bbdir"
check "missing-busybox-dir-soft" 0 yes

# Compile failures -> hard fail, no metrics file, exit 1. Each case must
# reach its OWN fail_hard call site, not a different one that happens to
# also exit 1 with no metrics file (all three hard-fail shapes look
# identical from exit code + file-absence alone — pin the exact message).
setup; mk_busybox 1 0 yes
check "defconfig-failed-hard" 1 no "::error::run-busybox: defconfig failed"

setup; mk_busybox 0 1 yes
check "build-failed-hard" 1 no "::error::run-busybox: build failed"

setup; mk_busybox 0 0 no
check "no-binary-produced-hard" 1 no "::error::run-busybox: build succeeded but no busybox binary produced"

[ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails failures"; exit 1; }
