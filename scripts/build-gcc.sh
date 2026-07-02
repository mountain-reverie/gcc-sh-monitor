#!/usr/bin/env bash
# Clone a gcc repo (default gcc-mirror/gcc) at $COMMIT and build a
# cross-compiler for $TARGET. $COMMIT may be a bare sha or a branch ref
# (e.g. devel/sh-lra) in the repo named by GCC_REPO.
#
# Usage:
#   build-gcc.sh <commit-sha> [<target>]
#
# Default target: sh4-linux-gnu (back-compat with Phase-0 invocations).
# Supported targets: sh4-linux-gnu, arm-linux-gnueabihf, i686-linux-gnu.
# Each target has its own sysroot, build dir, and install dir.
#
# Environment overrides (rarely needed; defaults below are per-target):
#   GCC_REPO      git repo URL to fetch from (default: https://github.com/gcc-mirror/gcc.git)
#   GCC_SRC_DIR   git clone of gcc (default: /tmp/gcc-src — shared across targets)
#   GCC_BUILD_DIR build tree (default: /tmp/gcc-build[-${TARGET}])
#   GCC_PREFIX    install prefix (default: /tmp/gcc-install[-${TARGET}])
#   CCACHE_DIR    ccache cache dir (default: /tmp/.ccache)
#   JOBS          parallel build jobs (default: $(nproc))

set -euo pipefail

COMMIT="${1:?usage: build-gcc.sh <commit-sha> [<target>]}"
TARGET="${2:-sh4-linux-gnu}"

# Per-target settings.
case "$TARGET" in
  sh4-linux-gnu)
    SYSROOT="/usr/sh4-linux-gnu"
    # Preserve original Phase-0 default paths for back-compat.
    GCC_BUILD_DIR="${GCC_BUILD_DIR:-/tmp/gcc-build}"
    GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
    EXTRA_CONFIGURE=()
    EXPECTED_ELF_MAGIC="Renesas SH"
    ;;
  arm-linux-gnueabihf)
    SYSROOT="/usr/arm-linux-gnueabihf"
    GCC_BUILD_DIR="${GCC_BUILD_DIR:-/tmp/gcc-build-arm}"
    GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install-arm}"
    # Match Debian's gcc-arm-linux-gnueabihf ABI: armv7-a + hard float + NEON.
    EXTRA_CONFIGURE=(--with-arch=armv7-a --with-float=hard --with-fpu=neon)
    EXPECTED_ELF_MAGIC="ARM"
    ;;
  i686-linux-gnu)
    SYSROOT="/usr/i686-linux-gnu"
    GCC_BUILD_DIR="${GCC_BUILD_DIR:-/tmp/gcc-build-x86}"
    GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install-x86}"
    EXTRA_CONFIGURE=(--with-arch=i686 --with-tune=generic)
    EXPECTED_ELF_MAGIC="Intel i386"
    ;;
  riscv64-linux-gnu)
    # 32-bit RISC-V (rv32gc/ilp32d) on Debian's riscv64 binutils (which handle
    # elf32-littleriscv). There is no rv32 glibc, so libgcc is built freestanding
    # (--without-headers, no --with-sysroot); musl supplies headers at the
    # BusyBox link stage. C only, no libatomic; smoke is compile-only since
    # there's no libc to link at toolchain-build time.
    SYSROOT="/usr/riscv64-linux-gnu"
    GCC_BUILD_DIR="${GCC_BUILD_DIR:-/tmp/gcc-build-riscv32}"
    GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install-riscv32}"
    EXTRA_CONFIGURE=(--with-arch=rv32gc --with-abi=ilp32d --without-headers \
                     --disable-shared --disable-threads --disable-libssp \
                     --disable-libquadmath)
    EXPECTED_ELF_MAGIC="UCB RISC-V"
    LANGS="c"
    SMOKE_MODE="compile"
    WITH_SYSROOT="no"
    LIBATOMIC_MAKE=""
    LIBATOMIC_INSTALL=""
    ;;
  *)
    echo "build-gcc: unsupported TARGET=$TARGET" >&2
    exit 2
    ;;
esac

# Per-target build knobs (defaults for the glibc targets; rv32 overrides above).
# Use ${v-default} (not :-) so an intentionally-empty value survives.
LANGS="${LANGS:-c,c++}"
SMOKE_MODE="${SMOKE_MODE:-link}"
WITH_SYSROOT="${WITH_SYSROOT:-yes}"
LIBATOMIC_MAKE="${LIBATOMIC_MAKE-all-target-libatomic}"
LIBATOMIC_INSTALL="${LIBATOMIC_INSTALL-install-target-libatomic}"

GCC_SRC_DIR="${GCC_SRC_DIR:-/tmp/gcc-src}"
CCACHE_DIR="${CCACHE_DIR:-/tmp/.ccache}"
JOBS="${JOBS:-$(nproc)}"

export CCACHE_DIR
export PATH="/usr/lib/ccache:$PATH"   # ccache wrappers for host gcc/g++
ccache --max-size=3G >/dev/null 2>&1 || true

# When $GCC_SRC_DIR is a host bind-mount, its uid may not match the in-container
# user, which makes git refuse to operate on it ("dubious ownership"). Mark it
# safe unconditionally — this script runs in disposable CI containers.
git config --global --add safe.directory "$GCC_SRC_DIR"
git config --global --add safe.directory "$GCC_BUILD_DIR"

# Source repo defaults to the upstream mirror; the sh-lra lane overrides it.
GCC_REPO="${GCC_REPO:-https://github.com/gcc-mirror/gcc.git}"

# Fetch only what we need. $COMMIT is normally a bare sha (works because
# GitHub's smart HTTP allows fetch-by-sha); it may also be a branch name
# (e.g. devel/sh-lra), in which case we fetch that ref.
if [ ! -d "$GCC_SRC_DIR/.git" ]; then
  mkdir -p "$GCC_SRC_DIR"
  git -C "$GCC_SRC_DIR" init -q
  git -C "$GCC_SRC_DIR" remote add origin "$GCC_REPO"
fi
git -C "$GCC_SRC_DIR" fetch --depth 1 origin "$COMMIT"
git -C "$GCC_SRC_DIR" checkout -q FETCH_HEAD
echo "build-gcc: $GCC_REPO @ $COMMIT -> $(git -C "$GCC_SRC_DIR" rev-parse HEAD)"

# Clean contents without removing the directories themselves — they may be
# bind-mounted from the host, in which case `rm -rf <mountpoint>` fails with
# "Device or resource busy".
mkdir -p "$GCC_BUILD_DIR" "$GCC_PREFIX"
find "$GCC_BUILD_DIR" "$GCC_PREFIX" -mindepth 1 -delete

cd "$GCC_BUILD_DIR"
CONFIGURE_ARGS=(
  --target="$TARGET"
  --enable-languages="$LANGS"
  --disable-multilib
  --disable-bootstrap
  --enable-checking=release
  --disable-libsanitizer
  --disable-werror
  --prefix="$GCC_PREFIX"
)
if [ "$WITH_SYSROOT" = yes ]; then
  CONFIGURE_ARGS+=(--with-sysroot="$SYSROOT")
fi
CONFIGURE_ARGS+=("${EXTRA_CONFIGURE[@]}")
"$GCC_SRC_DIR/configure" "${CONFIGURE_ARGS[@]}"

# The SH backend's spec unconditionally injects -latomic_asneeded into the
# link line, so libatomic must be present alongside libgcc — otherwise even
# a trivial `int main(){}` fails to link. Other backends don't strictly
# need it but it's cheap and harmless to build for all targets.
make -j"$JOBS" all-gcc all-target-libgcc $LIBATOMIC_MAKE
make install-gcc install-target-libgcc $LIBATOMIC_INSTALL

echo "build-gcc: $TARGET installed at $GCC_PREFIX"
"$GCC_PREFIX/bin/${TARGET}-gcc" --version

# Smoke: confirm the toolchain produces a valid ELF for the target. The rv32
# toolchain has no libc at build time, so it compiles to an object instead of
# linking a full executable.
echo "int main(void){return 0;}" > "$GCC_BUILD_DIR/smoke.c"
if [ "$SMOKE_MODE" = compile ]; then
  "$GCC_PREFIX/bin/${TARGET}-gcc" -B/usr/bin/${TARGET}- \
    -c "$GCC_BUILD_DIR/smoke.c" -o "$GCC_BUILD_DIR/smoke.o"
  SMOKE_ARTIFACT="$GCC_BUILD_DIR/smoke.o"
else
  "$GCC_PREFIX/bin/${TARGET}-gcc" -B/usr/bin/${TARGET}- \
    --sysroot="$SYSROOT" "$GCC_BUILD_DIR/smoke.c" -o "$GCC_BUILD_DIR/smoke"
  SMOKE_ARTIFACT="$GCC_BUILD_DIR/smoke"
fi
if ! file "$SMOKE_ARTIFACT" | grep -q "$EXPECTED_ELF_MAGIC"; then
  echo "build-gcc: smoke FAILED — expected '$EXPECTED_ELF_MAGIC' in:" >&2
  file "$SMOKE_ARTIFACT" >&2
  exit 1
fi
echo "build-gcc: smoke PASS for $TARGET"

# Sidecar FDPIC libgcc (sh4 only). The main toolchain is non-multilib, so it
# ships only a non-FDPIC libgcc. The BusyBox+musl fdpic lane needs an
# fdpic-compiled libgcc.a; build one here by forcing -mfdpic onto the target
# libgcc and copy the archive to a known sidecar path. Non-fatal: if it fails,
# the fdpic lane simply emits zero metrics.
if [ "$TARGET" = "sh4-linux-gnu" ]; then
  echo "build-gcc: building sidecar FDPIC libgcc..."
  FDPIC_BUILD="${GCC_BUILD_DIR}-fdpic"
  FDPIC_LIBGCC_DST="$GCC_PREFIX/lib/sh-fdpic/libgcc.a"
  mkdir -p "$FDPIC_BUILD"
  find "$FDPIC_BUILD" -mindepth 1 -delete
  git config --global --add safe.directory "$FDPIC_BUILD" || true
  if ( cd "$FDPIC_BUILD"
       "$GCC_SRC_DIR/configure" \
         --target="$TARGET" \
         --enable-languages=c \
         --disable-multilib --disable-bootstrap --disable-shared \
         --enable-checking=release \
         --with-sysroot="$SYSROOT" \
         --disable-libsanitizer --disable-werror \
         --prefix="$FDPIC_BUILD/inst" \
         CFLAGS_FOR_TARGET="-O2 -mfdpic" \
       && make -j"$JOBS" all-gcc all-target-libgcc \
       && make install-gcc install-target-libgcc ); then
    src=$(find "$FDPIC_BUILD/inst" -path '*sh4-linux-gnu*' -name libgcc.a | head -1)
    if [ -n "$src" ]; then
      mkdir -p "$(dirname "$FDPIC_LIBGCC_DST")"
      cp "$src" "$FDPIC_LIBGCC_DST"
      echo "build-gcc: sidecar FDPIC libgcc -> $FDPIC_LIBGCC_DST ($(stat -c %s "$FDPIC_LIBGCC_DST") bytes)"
    else
      echo "build-gcc: WARNING sidecar libgcc.a not found; fdpic lane will be zero" >&2
    fi
  else
    echo "build-gcc: WARNING sidecar FDPIC libgcc build failed; fdpic lane will be zero" >&2
  fi
fi
