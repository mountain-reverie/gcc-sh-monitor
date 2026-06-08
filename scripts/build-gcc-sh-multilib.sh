#!/usr/bin/env bash
set -euo pipefail
# Build a COMPILER-ONLY multilib SH GCC into a separate prefix, so the
# code-density lane has a compiler whose driver accepts -m2/-m2a/-m4.
#
# WHY: the main sh4 compiler (build-gcc.sh, --disable-multilib) rejects -m2/-m2a
# with "command-line option '-m2' is not supported by this configuration" — its
# driver only knows the configured sh4 ISA. A multilib build's driver accepts
# the multilib -m options. We build `all-gcc` only (no libgcc/startfiles):
# compile-to-object never links, so libgcc is unnecessary, which is both fastest
# and sidesteps the config/sh/t-linux bare-m2a libgcc exclusion.
#
# Reuses the cached GCC source (already checked out to the tested commit by
# build-gcc.sh) and the shared ccache, so the host compile is mostly a cache hit
# off the main build — the marginal cost is roughly the cc1 relink, not a full
# from-scratch compile.
#
# Environment (mirrors build-gcc.sh):
#   TARGET        GNU triple (default sh4-linux-gnu) — reused for sysroot/binutils
#   GCC_SRC_DIR   GCC source clone (default /tmp/gcc-src)
#   GCC_BUILD_DIR build tree (default /tmp/gcc-build-multilib)
#   GCC_PREFIX    install prefix (default /tmp/gcc-multilib-install)
#   CCACHE_DIR    ccache dir (default /tmp/.ccache)
#   MULTILIB_LIST SH multilib list (default m2,m2a,m4)
#   JOBS          parallelism (default nproc)

TARGET="${TARGET:-sh4-linux-gnu}"
GCC_SRC_DIR="${GCC_SRC_DIR:-/tmp/gcc-src}"
GCC_BUILD_DIR="${GCC_BUILD_DIR:-/tmp/gcc-build-multilib}"
GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-multilib-install}"
CCACHE_DIR="${CCACHE_DIR:-/tmp/.ccache}"
MULTILIB_LIST="${MULTILIB_LIST:-m2,m2a,m4}"
JOBS="${JOBS:-$(nproc)}"
SYSROOT="/usr/${TARGET}"

export CCACHE_DIR
export PATH="/usr/lib/ccache:$PATH"   # reuse the host gcc/g++ ccache wrappers
ccache --max-size=3G >/dev/null 2>&1 || true

[ -d "$GCC_SRC_DIR/.git" ] || { echo "build-gcc-sh-multilib: GCC_SRC_DIR=$GCC_SRC_DIR not a checkout (run build-gcc.sh first)" >&2; exit 1; }
[ -d "$SYSROOT" ]          || { echo "build-gcc-sh-multilib: sysroot $SYSROOT missing" >&2; exit 1; }

echo "build-gcc-sh-multilib: TARGET=$TARGET multilib=$MULTILIB_LIST prefix=$GCC_PREFIX"

# Build OUTSIDE the (cached) source tree so build artefacts never bloat the
# gcc-src cache.
rm -rf "$GCC_BUILD_DIR"; mkdir -p "$GCC_BUILD_DIR"; cd "$GCC_BUILD_DIR"

"$GCC_SRC_DIR/configure" \
  --target="$TARGET" \
  --prefix="$GCC_PREFIX" \
  --with-sysroot="$SYSROOT" \
  --enable-languages=c \
  --enable-multilib \
  --with-multilib-list="$MULTILIB_LIST" \
  --enable-checking=release \
  --disable-nls \
  --disable-bootstrap \
  --disable-werror

# Compiler only: cc1 + the driver + the multilib spec (which encodes the
# accepted -m options). No target libraries — compile-to-object doesn't link.
make -j"$JOBS" all-gcc
make install-gcc

GCC="$GCC_PREFIX/bin/${TARGET}-gcc"
echo "build-gcc-sh-multilib: installed $GCC"

# Self-check (informative; the CI 'Verify SH ISA flags' step is the real gate):
# the driver MUST now accept the multilib -m options that --disable-multilib
# rejected. Compile-to-assembly (-S) avoids needing as/binutils here.
echo "=== accepted multilib variants ==="
"$GCC" -print-multi-lib 2>/dev/null || true
for isa in m2 m2a m4; do
  if printf 'int f(int x){return x*3+1;}\n' | "$GCC" -O2 -"$isa" -S -x c - -o /dev/null 2>/dev/null; then
    echo "build-gcc-sh-multilib: -$isa OK"
  else
    echo "build-gcc-sh-multilib: -$isa FAILED (multilib list may not include it)" >&2
  fi
done
