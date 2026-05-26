# BusyBox — size + smoke benchmark snapshot

Vendored BusyBox source, used by `scripts/run-busybox.sh` to track
GCC's SuperH backend code-size trend on a real-world static binary
plus validate cross-compiled correctness via a 10-applet smoke test.

## Provenance

- **Source:** https://git.busybox.net/busybox
- **Tag:** 1_37_0
- **Snapshot commit:** be7d1b7b1701d225379bc1665487ed0871b592a5
- **Snapshot date:** 2026-05-26

## License

GPL-2.0-only. See `LICENSE` (vendored verbatim from upstream).

## Usage

`scripts/run-busybox.sh` will:
1. Copy this tree to a workdir.
2. `make defconfig` + force `CONFIG_STATIC=y`.
3. Build with the sh4-linux-gnu cross compiler.
4. Run a 10-applet smoke test under qemu-sh4-static.
5. Emit size metrics and smoke pass count to `/tmp/metrics/busybox.json`.

## Updates

To refresh:
1. Re-vendor following the steps in the BusyBox plan with a newer tag.
2. Update the Tag/Commit/Date above.
3. Re-run `scripts/run-busybox.sh` locally to confirm builds.
