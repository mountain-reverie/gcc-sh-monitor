#!/usr/bin/env bash
# Build the COMMIT-INDEPENDENT half of the sh-sim toolchain and bake it into the
# base image: sh-elf binutils-gdb (with the SH instruction-set simulator,
# sh-elf-run) + newlib, installed under /opt/sh-elf.
#
# The gcc itself is NOT baked — it tracks the tested commit and is built per-CI-run
# by scripts/build-sh-elf-gcc.sh, which installs into this same /opt/sh-elf prefix
# (reusing the binutils + newlib here). A throwaway reference gcc is built only to
# compile newlib, then discarded.
#
# Runs at image-build time (docker/Dockerfile.gcc-sh-base). Sources come from
# sourceware/gnu.org, NOT github: GitHub refuses anonymous git-over-https for
# bminor/* in some environments, while sourceware.org / gcc.gnu.org serve it fine.
#
# Env overrides:
#   PREFIX        install prefix            (default /opt/sh-elf)
#   REF_GCC_REF   reference gcc branch/tag  (default releases/gcc-15)
#   BINUTILS_REF  binutils-gdb ref          (default master)
#   NEWLIB_REF    newlib-cygwin ref         (default main)
#   MULTILIB_LIST SH multilib list          (default m2,m2a,m4)
#   JOBS          parallelism               (default nproc)

set -euo pipefail

PREFIX="${PREFIX:-/opt/sh-elf}"
REF_GCC_REF="${REF_GCC_REF:-releases/gcc-15}"
BINUTILS_REF="${BINUTILS_REF:-master}"
NEWLIB_REF="${NEWLIB_REF:-main}"
MULTILIB_LIST="${MULTILIB_LIST:-m2,m2a,m4}"
JOBS="${JOBS:-$(nproc)}"
TARGET=sh-elf

GCC_URL="${GCC_URL:-https://gcc.gnu.org/git/gcc.git}"
BINUTILS_URL="${BINUTILS_URL:-https://sourceware.org/git/binutils-gdb.git}"
NEWLIB_URL="${NEWLIB_URL:-https://sourceware.org/git/newlib-cygwin.git}"

SRC=/tmp/sh-elf-base-src
BUILD=/tmp/sh-elf-base-build

echo "=== sh-elf base toolchain (binutils+sim+newlib) -> $PREFIX ==="
echo "    binutils-gdb=$BINUTILS_REF  newlib=$NEWLIB_REF  ref-gcc=$REF_GCC_REF  multilib=$MULTILIB_LIST  JOBS=$JOBS"

fetch() {  # dir url ref
  local dir="$1" url="$2" ref="$3" attempt
  mkdir -p "$dir"; git -C "$dir" init -q
  git -C "$dir" remote add origin "$url" 2>/dev/null || true
  git config --global --add safe.directory "$dir" || true
  echo "--- fetch $url @ $ref ---"
  # Retry: sourceware/gnu.org can be transiently unreachable; a single timeout
  # shouldn't sink a 30-minute image build.
  for attempt in 1 2 3 4 5; do
    if git -C "$dir" fetch -q --depth 1 origin "$ref"; then
      git -C "$dir" checkout -q FETCH_HEAD
      return 0
    fi
    echo "fetch attempt $attempt failed; retrying in $((attempt*15))s..." >&2
    sleep $((attempt*15))
  done
  echo "FATAL: could not fetch $url @ $ref after 5 attempts" >&2
  return 1
}

fetch "$SRC/binutils-gdb" "$BINUTILS_URL" "$BINUTILS_REF"
fetch "$SRC/gcc"          "$GCC_URL"      "$REF_GCC_REF"
fetch "$SRC/newlib"       "$NEWLIB_URL"   "$NEWLIB_REF"

mkdir -p "$PREFIX" "$BUILD"
export PATH="$PREFIX/bin:$PATH"

# 1. binutils-gdb (+sim) -> PREFIX  (gives sh-elf-as/ld/ar + sh-elf-run)
echo "########## [1/3] binutils-gdb (+sim) ##########"
b="$BUILD/binutils"; mkdir -p "$b"; cd "$b"
"$SRC/binutils-gdb/configure" --target="$TARGET" --prefix="$PREFIX" \
  --disable-gdb --disable-gdbserver --disable-werror --disable-nls --enable-sim
make -j"$JOBS"
make install
command -v "${TARGET}-run" >/dev/null || { echo "FATAL: sh-elf-run not installed" >&2; exit 1; }

# 2. reference gcc (all-gcc only) -> SAME prefix as binutils.
# It must share the prefix so newlib's configure sees a complete toolchain
# (gcc + its sibling sh-elf-as/ld) — a split prefix makes newlib's compile probe
# fail with "cannot compute suffix of object files". The gcc bits are stripped in
# step 4 so only binutils+sim+newlib are baked; the per-commit trunk gcc supplies
# the real compiler.
echo "########## [2/3] reference gcc ($REF_GCC_REF, all-gcc) ##########"
g="$BUILD/refgcc"; mkdir -p "$g"; cd "$g"
"$SRC/gcc/configure" --target="$TARGET" --prefix="$PREFIX" \
  --enable-languages=c --with-newlib \
  --enable-multilib --with-multilib-list="$MULTILIB_LIST" \
  --disable-libssp --disable-shared --disable-threads \
  --disable-nls --disable-bootstrap --enable-checking=release --disable-werror
make -j"$JOBS" all-gcc
make install-gcc

# 3. newlib (libc + libgloss, per multilib) -> PREFIX, built with the reference gcc
echo "########## [3/3] newlib ##########"
n="$BUILD/newlib"; mkdir -p "$n"; cd "$n"
"$SRC/newlib/configure" --target="$TARGET" --prefix="$PREFIX"
make -j"$JOBS"
make install

# 4. Strip the reference gcc, leaving only binutils + sim + newlib. The driver
# binaries AND the gcc guts (cc1 in libexec/gcc, internals in lib/gcc) go, so
# /opt/sh-elf has NO working gcc until the per-commit trunk build installs one —
# guaranteeing the sim never silently runs a non-trunk compiler. Binutils tools
# (sh-elf-as/ld/ar/nm/ranlib/run, no "gcc" in the name) are untouched.
echo "########## [4] strip reference gcc (keep binutils+sim+newlib) ##########"
rm -f  "$PREFIX"/bin/${TARGET}-gcc* "$PREFIX"/bin/${TARGET}-cpp \
       "$PREFIX"/bin/${TARGET}-gcov* "$PREFIX"/bin/${TARGET}-lto-dump
rm -rf "$PREFIX"/libexec/gcc "$PREFIX"/lib/gcc
rm -rf "$SRC" "$BUILD"

echo "=== sh-elf base installed ==="
ls "$PREFIX/bin" | grep -E "sh-elf-(as|ld|run|ar)" || true
echo "newlib multilibs:"; ls "$PREFIX/$TARGET/lib" 2>/dev/null | tr '\n' ' '; echo
test -f "$PREFIX/$TARGET/lib/libc.a" || { echo "FATAL: newlib libc.a missing" >&2; exit 1; }
test -x "$PREFIX/bin/${TARGET}-run" || { echo "FATAL: sh-elf-run missing" >&2; exit 1; }
test -x "$PREFIX/bin/${TARGET}-as"  || { echo "FATAL: sh-elf-as removed by strip (glob too broad)" >&2; exit 1; }
[ ! -e "$PREFIX/bin/${TARGET}-gcc" ] || { echo "FATAL: reference gcc not stripped" >&2; exit 1; }
echo "OK"
