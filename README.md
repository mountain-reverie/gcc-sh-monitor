# gcc-sh-monitor

Continuous testing of GCC's SuperH (sh4) backend against upstream `master`.

Watches `gcc-mirror/gcc`, runs cross-compiled tests on every change, and
publishes results to a public dashboard. See `docs/` (local-only design
notes) for architecture.

**Status:** Increment 1 complete — sync→push→CI chain verified on 2026-05-24.

## Repository layout

- `state/last-tested.json` — authoritative record of upstream commit under test.
- `scripts/` — sync and build helpers.
- `docker/` — pinned CI base image.
- `.github/workflows/` — sync, CI, image rebuild.

## License

MIT — see `LICENSE`.
