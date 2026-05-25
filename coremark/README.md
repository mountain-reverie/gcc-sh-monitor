# CoreMark — EEMBC benchmark snapshot

Vendored snapshot of the EEMBC CoreMark 1.0 benchmark.

## Provenance

- **Source:** https://github.com/eembc/coremark
- **Snapshot commit:** 1f483d5b8316753a742cbf5590caf5bd0a4e4777
- **Snapshot date:** 2026-05-25

## License

Apache-derived. See `LICENSE.md` (untouched from upstream).
Upstream README preserved as `UPSTREAM-README.md`.

## Usage

`scripts/run-coremark-size.sh` builds this corpus with the sh4-linux-gnu
cross compiler at `-O2 -funroll-loops` (CoreMark's published-score flags)
and measures the resulting binary's .text / .rodata / total bytes.

## Updates

To refresh:
1. `git clone --depth 1 https://github.com/eembc/coremark /tmp/c`
2. Replace `coremark/` contents with the fresh source.
3. Update Snapshot commit and date above.
4. Re-run `scripts/run-coremark-size.sh` locally to confirm.
5. Commit with message `vendor: refresh CoreMark to <date>`.
