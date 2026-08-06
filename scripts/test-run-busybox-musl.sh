#!/usr/bin/env bash
# Tests run-busybox-musl.sh failure taxonomy: environment-absent cases emit
# zeros and exit 0; compile failures exit 1 and write no metrics file.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/run-busybox-musl.sh"
fails=0

setup() {
  root=$(mktemp -d)
  prefix="$root/gcc-install"; mkdir -p "$prefix/bin"
  musldir="$root/musl";       mkdir -p "$musldir"
  bbdir="$root/busybox";      mkdir -p "$bbdir"
  bindir="$root/bin";         mkdir -p "$bindir"
  out="$root/metrics.json"

  # Stub cross gcc, size, and qemu so the environment checks pass.
  # Gcc stub respects STUB_GCC_FAIL env var to simulate failure.
  cat > "$prefix/bin/sh4-linux-gnu-gcc" <<'EOFGCC'
#!/usr/bin/env bash
if [ "${STUB_GCC_FAIL:-0}" = "1" ]; then exit 1; fi
exit 0
EOFGCC
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bindir/sh4-linux-gnu-size"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bindir/qemu-sh4-static"
  chmod +x "$prefix/bin/sh4-linux-gnu-gcc" "$bindir/sh4-linux-gnu-size" "$bindir/qemu-sh4-static"

  # Stub musl configure/build/install with expected signatures
  mkdir -p "$musldir"
  touch "$musldir/configure" "$musldir/Makefile"
  chmod +x "$musldir/configure"
}

# $1 = exit code for musl configure, $2 = exit code for musl make (build),
# $3 = exit code for musl make install, $4 = exit code for bb defconfig,
# $5 = exit code for bb make (build), $6 = "yes" to produce busybox binary,
# $7 = (optional) wrapper sanity check exit code (default 0 = success)
mk_musl_busybox() {
  local musl_cfg_ret="$1" musl_make_ret="$2" musl_install_ret="$3"
  local bb_defconfig_ret="$4" bb_make_ret="$5" bb_binary="$6"
  local wrapper_ret="${7:-0}"

  # Create musl configure script
  cat > "$musldir/configure" <<EOF
#!/bin/bash
exit $musl_cfg_ret
EOF
  chmod +x "$musldir/configure"

  # Create musl Makefile
  cat > "$musldir/Makefile" <<EOF
all:
	@exit $musl_make_ret
install:
	@mkdir -p \$(DESTDIR)/lib \$(DESTDIR)/include
	@exit $musl_install_ret
EOF

  # Create busybox Config.in and Makefile
  : > "$bbdir/Config.in"
  cat > "$bbdir/Makefile" <<EOF
defconfig:
	@touch .config
	@exit $bb_defconfig_ret
oldconfig:
	@touch .config
all:
	@if [ "$bb_binary" = yes ]; then touch busybox; fi
	@exit $bb_make_ret
EOF
  # Note: defconfig is intentionally first so that `make -j"$JOBS"` without
  # an explicit target runs defconfig instead of all, exposing the bug.

  # Real BusyBox writes .config during defconfig; emulate for the sed steps.
  printf '# CONFIG_STATIC is not set\n' > "$bbdir/.config"
}

run() {  # runs run-busybox-musl.sh with the stubbed environment
  ( PATH="$bindir:$PATH" \
    GCC_PREFIX="$prefix" MUSL_DIR="$musldir" BUSYBOX_DIR="$bbdir" \
    OUT_FILE="$out" SH4_SIZE="$bindir/sh4-linux-gnu-size" JOBS=1 \
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

setup; rm -rf "$musldir"
check "missing-musl-dir-soft" 0 yes

setup; rm -rf "$bbdir"
check "missing-busybox-dir-soft" 0 yes

# Compile failures -> hard fail, no metrics file, exit 1. Each case must
# reach its OWN fail_hard call site, not a different one that happens to
# also exit 1 with no metrics file (all three hard-fail shapes look
# identical from exit code + file-absence alone — pin the exact message).
setup; mk_musl_busybox 1 0 0 0 0 yes
check "musl-configure-failed-hard" 1 no "::error::run-busybox-musl: musl configure failed"

setup; mk_musl_busybox 0 1 0 0 0 yes
check "musl-build-failed-hard" 1 no "::error::run-busybox-musl: musl build failed"

setup; mk_musl_busybox 0 0 1 0 0 yes
check "musl-install-failed-hard" 1 no "::error::run-busybox-musl: musl install failed"

# Wrapper CC sanity check failure (gcc broken during compilation)
setup; mk_musl_busybox 0 0 0 0 0 yes
( STUB_GCC_FAIL=1 PATH="$bindir:$PATH" \
  GCC_PREFIX="$prefix" MUSL_DIR="$musldir" BUSYBOX_DIR="$bbdir" \
  OUT_FILE="$out" SH4_SIZE="$bindir/sh4-linux-gnu-size" JOBS=1 \
  "$script" >/dev/null 2>"$root/stderr" )
got=$?
ok=1
[ "$got" = "1" ] || { echo "FAIL wrapper-cc-sanity-failed-hard: want exit 1 got $got"; ok=0; }
if [ -f "$out" ]; then
  echo "FAIL wrapper-cc-sanity-failed-hard: expected NO metrics file, one was written"; ok=0
fi
if ! grep -qF "::error::run-busybox-musl: wrapper-cc sanity failed" "$root/stderr"; then
  echo "FAIL wrapper-cc-sanity-failed-hard: expected stderr to contain '::error::run-busybox-musl: wrapper-cc sanity failed', got:"; ok=0
  sed 's/^/    /' "$root/stderr"
fi
[ "$ok" = 1 ] && echo "PASS wrapper-cc-sanity-failed-hard" || fails=$((fails+1))

setup; mk_musl_busybox 0 0 0 0 0 yes; rm -f "$bbdir/Config.in"
check "workdir-copy-incomplete-hard" 1 no "::error::run-busybox-musl: bb workdir copy incomplete"

setup; mk_musl_busybox 0 0 0 1 0 yes
check "bb-defconfig-failed-hard" 1 no "::error::run-busybox-musl: bb defconfig failed"

setup; mk_musl_busybox 0 0 0 0 1 yes
check "bb-build-failed-hard" 1 no "::error::run-busybox-musl: bb build failed"

setup; mk_musl_busybox 0 0 0 0 0 no
check "no-binary-produced-hard" 1 no "::error::run-busybox-musl: build succeeded but no busybox binary produced"

[ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails failures"; exit 1; }
