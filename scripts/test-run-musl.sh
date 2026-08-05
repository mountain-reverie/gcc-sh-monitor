#!/usr/bin/env bash
# Tests run-musl.sh failure taxonomy: environment-absent cases emit zeros and
# exit 0; configure/build/install/ELF-missing failures exit 1 with no metrics.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
script="$here/run-musl.sh"
fails=0

setup() {
  root=$(mktemp -d)
  prefix="$root/gcc-install"; mkdir -p "$prefix/bin"
  musldir="$root/musl";       mkdir -p "$musldir"
  bindir="$root/bin";         mkdir -p "$bindir"
  out="$root/metrics.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$prefix/bin/sh4-linux-gnu-gcc"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bindir/sh4-size"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bindir/qemu-sh4-static"
  chmod +x "$prefix/bin/sh4-linux-gnu-gcc" "$bindir/sh4-size" "$bindir/qemu-sh4-static"
  cat > "$musldir/configure" <<'EOFCONF'
#!/usr/bin/env bash
# Parse --prefix argument and inject it into the Makefile
for arg in "$@"; do
  case "$arg" in
    --prefix=*)
      prefix="${arg#--prefix=}"
      cat > Makefile <<EOF
all:
	@exit \$(STUB_BUILD)
install:
	@mkdir -p $prefix/lib
	@exit \$(STUB_INSTALL)
EOF
      ;;
  esac
done
exit ${STUB_CONFIGURE:-0}
EOFCONF
  chmod +x "$musldir/configure"
  # Create a default Makefile in case configure isn't called
  cat > "$musldir/Makefile" <<'EOF'
all:
	@exit $(STUB_BUILD)
install:
	@mkdir -p /tmp/musl-install/lib
	@exit $(STUB_INSTALL)
EOF
}

run() {
  ( PATH="$bindir:$PATH" \
    GCC_PREFIX="$prefix" MUSL_DIR="$musldir" OUT_FILE="$out" \
    SH4_SIZE="$bindir/sh4-size" JOBS=1 \
    STUB_CONFIGURE="${STUB_CONFIGURE:-0}" \
    STUB_BUILD="${STUB_BUILD:-0}" \
    STUB_INSTALL="${STUB_INSTALL:-0}" \
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

setup; rm -f "$bindir/sh4-size"
check "missing-size-soft" 0 yes

setup; rm -f "$bindir/qemu-sh4-static"
check "missing-qemu-soft" 0 yes

# Compile failures -> hard fail, no metrics file, exit 1. Each case must
# reach its OWN fail_hard call site, not a different one that happens to
# also exit 1 with no metrics file (all hard-fail shapes look identical
# from exit code + file-absence alone — pin the exact message).
setup; STUB_CONFIGURE=1
check "configure-failed-hard" 1 no "::error::run-musl: configure failed"
unset STUB_CONFIGURE

setup; STUB_BUILD=1
check "build-failed-hard" 1 no "::error::run-musl: build failed"
unset STUB_BUILD

setup; STUB_INSTALL=1
check "install-failed-hard" 1 no "::error::run-musl: install failed"
unset STUB_INSTALL

# install "succeeds" but produces no libc.so ELF -> hard fail
setup
check "libc-so-missing-hard" 1 no "::error::run-musl: libc.so ELF missing"

[ "$fails" -eq 0 ] && echo "PASS" || { echo "$fails failures"; exit 1; }
