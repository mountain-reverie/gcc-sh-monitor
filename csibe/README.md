# CSiBE — Code Size Benchmark

Vendored snapshot of the CSiBE corpus, used by `scripts/run-csibe.sh`
to track GCC's SuperH backend code-size trend per upstream commit.

## Provenance

- **Source:** https://github.com/szeged/csibe/releases/download/CSiBE-v2.1.1/CSiBE-v2.1.1.tar.gz
- **Snapshot date:** 2026-05-25
- **Snapshot commit (if cloned):** N/A — release tarball `CSiBE-v2.1.1.tar.gz`
  (discovered via the `download_old_testbed` function in `csibe.py` of
  https://github.com/szeged/csibe @ 652f2340ff472505e11d896e72f9ce259c5f4382)

The upstream tarball expands to a `CSiBE/` directory with `bin/`, `src/`,
`COPYING`, `CSiBE-README`, and `CSiBE-RUN-README`. We vendor those four
items at the top of `csibe/`, dropping the original `CSiBE/` wrapper dir.

Two large items from the upstream tarball are intentionally **excluded**
to keep the repo lean — neither is built by the canonical v2.1.1
configuration (`cmake/subprojects.cmake` in the szeged/csibe wrapper):

- `src/linux-2.4.23-pre3-testplatform/` (~41 MB) — Linux kernel test
  platform, not a build target.
- `src/testdata/` (~59 MB) — runtime input data (images, archives) used
  by the `CSiBE-RUN` execution suite, irrelevant to code-size measurement.

## Subprojects

The corpus contains the following 17 benchmark projects under `src/`,
one subdir each:

- `bzip2-1.0.2`
- `cg_compiler_opensrc`
- `compiler`
- `flex-2.5.31`
- `jikespg-1.3`
- `jpeg-6b`
- `libmspack`
- `libpng-1.2.5`
- `lwip-0.5.3.preproc`
- `mpeg2dec-0.3.1`
- `mpgcut-1.1`
- `replaypc-0.4.0.preproc`
- `teem-1.6.0-src`
- `ttt-0.10.1.preproc`
- `unrarlib-0.4.0`
- `zlib-1.1.4`

(`src/include/` holds shared headers — not a standalone subproject.)

Each subproject ships with its own build system (Makefile or similar).
Our `run-csibe.sh` invokes the subproject's build with `CC` and
`CFLAGS` from environment.

## Licensing

See `LICENSING.md` for per-subproject license details.

## Updates

This is a pinned snapshot. To refresh:
1. Fetch new corpus, replace contents of `csibe/`.
2. Update `Snapshot date` and `Snapshot commit` above.
3. Re-run `scripts/run-csibe.sh` locally to confirm builds.
4. Commit with message `vendor: refresh CSiBE to YYYY-MM-DD`.
