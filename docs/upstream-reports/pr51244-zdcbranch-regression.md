# GCC SH backend: -mzdcbranch peephole not firing on the pr51244 family

**Component:** target / sh
**Severity:** normal (missed optimization, not correctness)
**Status:** new
**Detected:** by `gcc-sh-monitor`, upstream commit `8d81ccde31888032b031995ec2c20341eb7541ac`
**Reference compiler:** GCC 14.2 (Debian 14.2.0-19) — same behaviour as trunk
**Affected compiler:** GCC trunk (sh4-linux-gnu cross, post-LRA migration on SH)

## Summary

The `-mzdcbranch` (zero-displacement conditional branch) peephole that the
`pr51244-{11,12,19,20}` tests were designed to exercise is **not firing** on
current trunk. The tests use `scan-assembler-not subc|and|bra` together
with `scan-assembler-times "bf\t0f" 1` / `scan-assembler-times "bt\t0f" 1`,
i.e. they want the SH back end to collapse a "compute predicate into a
GPR via `tst` + `subc`/`and`" sequence into a short zero-displacement
conditional branch idiom.

Instead, trunk emits the branchless `tst` + `subc` + `and` sequence,
which is what the tests forbid.

Bisection / local cross-check: **Debian's GCC 14.2.0-19 emits exactly the
same code** as trunk for these inputs, so the peephole has not been
firing for at least a release. This is therefore a *long-standing* missed
optimization, not a fresh post-LRA regression. It only surfaces now on
the gcc-sh-monitor dashboard because we started running the SH testsuite
continuously again.

The emitted code is correct, just not what the test expects (and
presumably not what was originally intended for `-mzdcbranch` on the
short, predictable branches in these test functions).

## Reproducer

From `gcc/testsuite/gcc.target/sh/pr51244-11.c`:

```c
/* { dg-do compile } */
/* { dg-options "-O1 -mzdcbranch" } */
/* { dg-final { scan-assembler-not "subc|and|bra" } } */
/* { dg-final { scan-assembler-times "bf\t0f" 1 } } */
/* { dg-final { scan-assembler-times "bt\t0f" 1 } } */

int*
test_00 (int* s)
{
  if (s[0] == 0)
    if (!s[3])
      s = 0;
  return s;
}

int*
test_01 (int* s)
{
  if (s[0] == 0)
    if (s[3])
      s = 0;
  return s;
}
```

Compile with:

```sh
sh4-linux-gnu-gcc -O1 -mzdcbranch -S pr51244-11.c -o out.s
```

## Expected (what the test asks for)

A zero-displacement conditional branch idiom — no `subc`/`and`/`bra` and
exactly one `bf\t0f` plus one `bt\t0f`, e.g. something of the form:

```asm
test_00:
    mov.l   @r4,r1
    tst     r1,r1
    bf      0f                  ! zero-displacement branch
    mov.l   @(12,r4),r1
    tst     r1,r1
    bt      0f                  ! zero-displacement branch
    mov     #0,r4
0:
    rts
    mov     r4,r0
```

(The exact shape above is illustrative; the test only constrains the
absence of `subc|and|bra` and the presence of one `bf\t0f` and one
`bt\t0f`.)

## Actual (GCC trunk on sh4-linux-gnu, -O1 -mzdcbranch)

```asm
test_00:
    mov.l   @r4,r1
    tst     r1,r1
    bf/s    .L4
    mov     r4,r0
    mov.l   @(12,r4),r1
    tst     r1,r1
    subc    r1,r1               ! <- forbidden by scan-assembler-not
    not     r1,r1
    and     r1,r0               ! <- forbidden by scan-assembler-not
.L4:
    rts
    nop

test_01:
    mov.l   @r4,r1
    tst     r1,r1
    bf/s    .L8
    mov     r4,r0
    mov.l   @(12,r4),r1
    tst     r1,r1
    subc    r1,r1               ! <- forbidden by scan-assembler-not
    and     r1,r0               ! <- forbidden by scan-assembler-not
.L8:
    rts
    nop
```

GCC 14.2 (Debian 14.2.0-19) emits **byte-for-byte the same** assembly.

## Affected tests

All four fail the same way (scan-assembler patterns):

- `gcc.target/sh/pr51244-11.c` — 3 scan-assembler checks fail
- `gcc.target/sh/pr51244-12.c` — 3 scan-assembler checks fail
- `gcc.target/sh/pr51244-19.c` — 1 check fails (`scan-assembler-not movt`)
- `gcc.target/sh/pr51244-20.c` — 1 check fails (`scan-assembler-times tst 7`)

8 dejagnu FAIL lines total.

## Environment

- Target: `sh4-linux-gnu`
- Cross compiler built from upstream GCC commit
  `8d81ccde31888032b031995ec2c20341eb7541ac`
- Optimization level: `-O1` (per each test's `dg-options`)
- Reference: Debian GCC 14.2.0-19 (`/usr/bin/sh4-linux-gnu-gcc`)
- Discovered via the gcc-sh-monitor dashboard at
  <https://mountain-reverie.github.io/gcc-sh-monitor/> — "Currently failing
  tests" panel.

## Notes

Of the 36 dejagnu FAIL lines currently visible on sh4-linux-gnu, 27 are
benign scan-assembler pattern drift (instruction selection improved past
what the tests literally match for) and have been catalogued in
`state/dejagnu-known-stale.json` in the gcc-sh-monitor repo. The
`pr51244-{11,12,19,20}` family is **not** in that list because the
intended optimization (zero-displacement conditional branch collapse
under `-mzdcbranch`) is not happening at all — this is a genuine missed
optimization, not equivalent codegen in a different shape.

The fact that GCC 14.2 exhibits the same behaviour suggests the peephole
either regressed long ago or never matched these particular patterns;
either way, the tests have been silently FAILing on SH for at least one
release cycle and deserve a look.
