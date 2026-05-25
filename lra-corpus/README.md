# LRA differential corpus

A curated set of SH backend test cases used by `scripts/run-lra-corpus.sh`
to detect behavioural divergence between two compilers:

- **Current:** the upstream GCC built per `state/last-tested.json`.
- **Reference:** Debian's `/usr/bin/sh4-linux-gnu-gcc` (GCC 14.2), pre-LRA.

Differences expose LRA-migration-induced regressions or output changes.

## Cases

See `manifest.json` for the canonical list with provenance and expected
outcomes. All cases are vendored from `gcc/testsuite/gcc.target/sh/` at
upstream commit `29e4b7f1100ad3dd611da6fc3314a41978c5fc25` and inherit
its license (GPLv3+ with GCC runtime library exception). See
`LICENSING.md`.

Some cases (named `pr55212-bz-*.c`) originate from PR 55212's Bugzilla
attachments at https://gcc.gnu.org/bugzilla/show_bug.cgi?id=55212.

## Adding cases

1. Drop the `.c` file in this directory.
2. Add a `manifest.json` entry with `source`, `description`, `expected`
   (`compiles_only` or `compiles_and_runs`), and `opt_levels`.
3. Run `scripts/run-lra-corpus.sh` locally to verify it categorises.
4. Commit.

## Updates

To refresh from a newer upstream commit, re-run the seeding steps in
the Inc 4 plan with the new commit SHA.
