# GCC SH backend — code-size optimization roadmap

**Date:** 2026-05-27
**Source:** disassembly deep dive of BusyBox+musl static binary, sh4-linux-gnu vs i686-linux-gnu (`gcc-sh-monitor` ci-full run 26539867757).
**Baseline:** sh4 `.text` = 922,374 bytes; x86 `.text` = 880,514 bytes (+4.75% sh4).

This file tracks deferred optimization opportunities surfaced by the deep dive. Each item is an independent piece of work that would benefit upstream GCC's SH backend.

The smaller two items (CSE-style peephole, MOVE_RATIO tuning) are being tackled separately — see `mov-add-cse-peephole.md` in this directory when it lands.

---

## Item 1 — Global / shared constant pool

**Estimated impact:** 3–6% `.text` reduction (28–55 KB on BusyBox+musl)
**Confidence:** High
**Effort:** Medium-large

### Problem

GCC currently emits a literal pool per function. Counting:

- 38,096 PC-relative `mov.l @(disp,PC),rN` loads
- 34,876 unique pool addresses (each holding a 4-byte constant)
- only **11,281 unique constant values** across the binary

Duplication ratio ≈ 3×. Per-function pool bytes ≈ 139 KB inlined in `.text`. Globally shared pool best case ≈ 45 KB → **savings ≈ 94 KB** before practical-reach constraints reduce that to 28–55 KB realistic.

### Proposed approach

Collect 32-bit constants per-TU (or per-LTO unit) into a dedicated pool, reference via a base register. SH4's `mov.l @(disp,Rm),Rn` has a 4-bit displacement → 64 byte reach per base; multiple bases or `mov.l @(R0,Rm),Rn` indexed addressing extend the reach.

The cleanest hook is repurposing the existing `--mfdpic` GBR-based scheme in `gcc/config/sh/sh.cc` (`sh_reorg`, `find_barrier`, `MACHINE_DEPENDENT_REORG`) as a `-mshared-pool` option.

### Blockers / caveats

- GBR is reserved for Linux TLS on SH4 — cannot be used as a pool base for kernel-compatible Linux binaries. Must use a regular GPR (e.g. R12) reserved across the TU.
- Cross-TU sharing requires LTO infrastructure cooperation.
- Linker support for relocations that resolve into the shared pool may be needed.

### Why defer

Architectural change to the SH backend's late-pass design. High value but high risk for a first contribution.

---

## Item 2 — Per-TU call-thunk table

**Estimated impact:** 2.5–3% `.text` reduction (23–28 KB)
**Confidence:** Medium
**Effort:** Medium

### Problem

17,286 of 24,149 `jsr` sites are preceded by a target-address pool load (`mov.l Lx,rN; jsr @rN`). Among 11,559 unique load sites, only **4,905 distinct call targets** — each target referenced 2.4× on average. Per-function duplication of target addresses ≈ 26 KB.

### Proposed approach

For frequently-called targets in a TU, intern them in a dedicated table accessed via a base register. Replace `mov.l Lx,rN + jsr @rN + slot` (6 bytes) with `mov.l @(disp,Rbase),rN + jsr @rN + slot` (6 bytes, but the disp slot is reused across calls — net saves the 4-byte pool entry per call site).

Backend hooks: `gcc/config/sh/sh.md` + a new `TARGET_INDIRECT_CALL` thunk-table option.

### Blockers / caveats

- Same base-register pressure as Item 1.
- Frequency-based decision: which targets are "frequent enough" to deserve a thunk slot? Needs heuristic or profile data.
- Combines naturally with Item 1 — they may want to be designed together.

### Why defer

Builds on Item 1's base-register plumbing. Design it after Item 1 lands.

---

## Item 3 — Better delay-slot fill for `jsr @rN` after target-load

**Estimated impact:** 0.8–1.2% `.text` reduction (7–11 KB)
**Confidence:** High
**Effort:** Small

### Problem

8,376 out of 60,028 delay-slot positions are NOP (14% miss rate). Disassembly samples consistently show the same pattern:

```
418740: mov.l 0x418918,r1   ! load call target into r1
418742: jsr   @r1
418744: nop                 ! delay slot unfilled
```

The instruction *immediately before* the `mov.l` is often unused in the slot — but GCC's scheduler doesn't try to sink it past the target-load.

### Proposed approach

Add a peephole2 (or scheduler-time sinking) pattern: when the sequence is `<INSN_X>; mov.l Lx,rN; jsr @rN; nop`, AND `INSN_X` has no dependency on the post-load state, sink `INSN_X` into the delay slot to yield `mov.l Lx,rN; jsr @rN; <INSN_X>`.

Backend location: `gcc/config/sh/sh.md` peephole2 patterns + possibly `sh_pr_n_sets`-style helpers.

### Blockers / caveats

- Need to ensure `INSN_X` doesn't write any register the call target uses as input (`r4`–`r7` argument registers).
- Some `INSN_X` candidates may set the T-bit — needs careful constraint.
- Easier than items 1-2 because it operates within an existing pass.

### Why defer

Quick win, but unrelated to the `mov+add` peephole we're tackling first. Worth filing as a separate GCC enhancement bug.

---

## Note on the smaller items

The `mov+add` CSE peephole and `MOVE_RATIO`/`CLEAR_RATIO` tuning are SMALL items but combined account for ~1% reduction. Tackling the peephole first because:

1. Small, well-bounded patch (~30 lines of `.md`).
2. Testable end-to-end via our existing BusyBox+musl size measurement on the dashboard.
3. Good first-contribution shape — clearly a missed optimization, not an architectural change.
4. Confidence-building: success here de-risks the bigger items above.

---

## Filing strategy

When tackling each of items 1-3:
1. File a GCC Bugzilla report describing the missed opportunity (with the BusyBox+musl numbers from the deep dive as evidence).
2. Prepare a small reproducer that highlights the pattern on a few-line C function.
3. Engage on gcc-patches mailing list before implementing — these are SH-backend architectural changes that benefit from maintainer input (Oleg Endo is the primary maintainer).
4. Iterate on patches with the gcc-sh-monitor dashboard providing real-world size measurement on every iteration.

The dashboard's multi-arch comparison (sh4 vs arm vs x86) gives an honest "did the patch help, hurt, or shift things around" view.
