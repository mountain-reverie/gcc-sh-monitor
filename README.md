# gcc-sh-monitor

[![Dejagnu](https://mountain-reverie.github.io/gcc-sh-monitor/badge/dejagnu.svg)](https://mountain-reverie.github.io/gcc-sh-monitor/benchmark/)
[![CSiBE -Os](https://mountain-reverie.github.io/gcc-sh-monitor/badge/csibe.svg)](https://mountain-reverie.github.io/gcc-sh-monitor/benchmark/)
[![CoreMark .text](https://mountain-reverie.github.io/gcc-sh-monitor/badge/coremark.svg)](https://mountain-reverie.github.io/gcc-sh-monitor/benchmark/)
[![ci-full](https://github.com/mountain-reverie/gcc-sh-monitor/actions/workflows/ci-full.yml/badge.svg)](https://github.com/mountain-reverie/gcc-sh-monitor/actions/workflows/ci-full.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Continuous testing of GCC's SuperH (sh4) backend against upstream `master`.

Watches `gcc-mirror/gcc`, runs cross-compiled tests on every change, and
publishes results to a public dashboard. See `docs/` (local-only design
notes) for architecture.

**Status:** Increment 3 complete — dejagnu + CSiBE + CoreMark size tracking live.

Dashboard: <https://mountain-reverie.github.io/gcc-sh-monitor/>

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
