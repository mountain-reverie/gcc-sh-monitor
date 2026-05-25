#!/usr/bin/env bash
# Clone gcc-mirror/gcc at $COMMIT and build a sh4-linux-gnu cross-compiler.
#
# Usage:
#   build-gcc.sh <commit-sha>
#
# Environment:
#   GCC_SRC_DIR   where to clone GCC (default: /tmp/gcc-src)
#   GCC_BUILD_DIR build tree (default: /tmp/gcc-build)
#   GCC_PREFIX    install prefix (default: /tmp/gcc-install)
#   CCACHE_DIR    ccache cache dir (default: /tmp/.ccache)
#   JOBS          parallel build jobs (default: $(nproc))

set -euo pipefail

COMMIT="${1:?usage: build-gcc.sh <commit-sha>}"
GCC_SRC_DIR="${GCC_SRC_DIR:-/tmp/gcc-src}"
GCC_BUILD_DIR="${GCC_BUILD_DIR:-/tmp/gcc-build}"
GCC_PREFIX="${GCC_PREFIX:-/tmp/gcc-install}"
CCACHE_DIR="${CCACHE_DIR:-/tmp/.ccache}"
JOBS="${JOBS:-$(nproc)}"

export CCACHE_DIR
export PATH="/usr/lib/ccache:$PATH"   # ccache wrappers for host gcc/g++
ccache --max-size=5G >/dev/null 2>&1 || true

# When $GCC_SRC_DIR is a host bind-mount, its uid may not match the in-container
# user, which makes git refuse to operate on it ("dubious ownership"). Mark it
# safe unconditionally — this script runs in disposable CI containers.
git config --global --add safe.directory "$GCC_SRC_DIR"
git config --global --add safe.directory "$GCC_BUILD_DIR"

# Fetch only the requested commit. Works even when COMMIT is not a ref tip
# because GitHub's smart HTTP supports uploadpack.allowReachableSHA1InWant.
if [ ! -d "$GCC_SRC_DIR/.git" ]; then
  mkdir -p "$GCC_SRC_DIR"
  git -C "$GCC_SRC_DIR" init -q
  git -C "$GCC_SRC_DIR" remote add origin https://github.com/gcc-mirror/gcc.git
fi
git -C "$GCC_SRC_DIR" fetch --depth 1 origin "$COMMIT"
git -C "$GCC_SRC_DIR" checkout -q FETCH_HEAD

# Clean contents without removing the directories themselves — they may be
# bind-mounted from the host, in which case `rm -rf <mountpoint>` fails with
# "Device or resource busy".
mkdir -p "$GCC_BUILD_DIR" "$GCC_PREFIX"
find "$GCC_BUILD_DIR" "$GCC_PREFIX" -mindepth 1 -delete

cd "$GCC_BUILD_DIR"
"$GCC_SRC_DIR/configure" \
  --target=sh4-linux-gnu \
  --enable-languages=c,c++ \
  --disable-multilib \
  --disable-bootstrap \
  --enable-checking=release \
  --with-sysroot=/usr/sh4-linux-gnu \
  --disable-libsanitizer \
  --disable-werror \
  --prefix="$GCC_PREFIX"

# The SH backend's spec unconditionally injects -latomic_asneeded into the
# link line, so libatomic must be present alongside libgcc — otherwise even
# a trivial `int main(){}` fails to link.
make -j"$JOBS" all-gcc all-target-libgcc all-target-libatomic
make install-gcc install-target-libgcc install-target-libatomic

echo "build-gcc: installed at $GCC_PREFIX"
"$GCC_PREFIX/bin/sh4-linux-gnu-gcc" --version
