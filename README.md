# gcc-sh-monitor

Continuous testing of GCC's SuperH (sh4) backend against upstream `master`.

Watches `gcc-mirror/gcc`, runs cross-compiled tests on every change, and
publishes results to a public dashboard. See `docs/` (local-only design
notes) for architecture.

**Status:** Increment 3 complete — dejagnu + CSiBE + CoreMark size tracking live.

Dashboard: <https://mountain-reverie.github.io/gcc-sh-monitor/>
Badges:
![dejagnu](https://mountain-reverie.github.io/gcc-sh-monitor/badge/dejagnu.svg)
![csibe](https://mountain-reverie.github.io/gcc-sh-monitor/badge/csibe.svg)
![coremark](https://mountain-reverie.github.io/gcc-sh-monitor/badge/coremark.svg)

## Repository layout

- `state/last-tested.json` — authoritative record of upstream commit under test.
- `state/baseline.json` — pinned baseline metrics; advanced manually.
- `scripts/` — sync, build, dejagnu helpers.
- `boards/` — custom DejaGnu board file wrapping qemu-sh4.
- `dashboard/` — static landing page and chart viewer published to Pages.
- `docker/` — pinned CI base image.
- `.github/workflows/` — sync, CI, image rebuild.

## License

MIT — see `LICENSE`.
