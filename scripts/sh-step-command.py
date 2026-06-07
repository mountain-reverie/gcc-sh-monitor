#!/usr/bin/env python3
"""Map a ci-full.yml SH-lane step name to the command that reproduces it.

The bisect predicate uses this to re-run exactly the step that failed at each
candidate gcc-mirror commit. The table mirrors the SH script steps of the
`build-and-test` job in .github/workflows/ci-full.yml — keep it in sync.

Only script-crash steps are listed. The build step ("Build cross GCC") and the
dejagnu step have dedicated good/bad logic in the predicate, so they are NOT
here; asking for them returns "unknown" (exit 2).

Usage:
  sh-step-command.py "<step name>"   # prints the reproduce command, exit 0
                                     # prints nothing, exit 2 if unknown
"""
import sys

STEP_COMMANDS = {
    "Run CSiBE size measurements":                     "scripts/run-csibe.sh",
    "Run CoreMark size measurement":                   "scripts/run-coremark-size.sh",
    "Run LRA differential watchdog":                   "scripts/run-lra-corpus.sh",
    "Run BusyBox build + smoke + size":                "scripts/run-busybox.sh",
    "Run BusyBox+musl build + smoke + size":           "scripts/run-busybox-musl.sh",
    "Run BusyBox+musl FDPIC build + smoke + size":     "ABI=fdpic scripts/run-busybox-musl.sh",
    "Run BusyBox+musl LTO build + smoke + size":       "LTO=1 scripts/run-busybox-musl.sh",
    "Run BusyBox+musl FDPIC+LTO build + smoke + size": "LTO=1 ABI=fdpic scripts/run-busybox-musl.sh",
    "Run musl build + smoke + size":                   "scripts/run-musl.sh",
}

def command_for(step: str):
    return STEP_COMMANDS.get(step)

def main(argv):
    if len(argv) != 2:
        print("usage: sh-step-command.py '<step name>'", file=sys.stderr)
        return 2
    cmd = command_for(argv[1])
    if cmd is None:
        return 2
    print(cmd)
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
