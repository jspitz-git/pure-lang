# TODO-42 - Windows pure-gplot Package

Status: In Progress
Branch: todo/42-windows-pure-gplot

## Purpose

Validate and package `pure-gplot` with a clearly defined Windows gnuplot dependency.

## Scope

- Decide whether gnuplot is bundled, detected, or offered as a separate component.
- Make process launching and temporary-file handling Windows-safe.
- Cover noninteractive rendering as well as an interactive smoke test.

## Task List

1. [x] Define the supported gnuplot version and packaging policy.
2. [ ] Repair executable discovery, quoting, and path handling where needed.
3. [ ] Add deterministic file-rendering smoke tests.
4. [ ] Stage and validate the package on a clean Windows VM.

## Guardrails

- Do not depend on an unrelated gnuplot found on the build host.
- Quote every executable and data path safely.

## Validation Plan

- Render a known plot to a file in a path containing spaces and verify the output.
- Launch one interactive plot and close it cleanly.

## Design Decision

Gnuplot is an optional, installer-managed component. The supported dependency
is the official x86-64 Windows Clang build of gnuplot 6.0.4,
`gp604-win64-clang.exe`, published with an upstream SHA-256 checksum. The build
never accepts a gnuplot found implicitly on the host `PATH`: dependency
acquisition validates the pinned artifact, while package staging consumes an
explicit `GNUPLOT_ROOT` containing the extracted official distribution.

The optional component is installed below `tools/gnuplot` in the portable
prefix. A uniquely named `bin/pure-gnuplot.cmd` launcher resolves
`../tools/gnuplot/bin/gnuplot.exe` relative to itself and fails clearly when
the component is absent. On Windows, `gplot::GPLOT_EXE` uses an explicit
`GPLOT_EXE` environment override first and the managed launcher otherwise.
`gplot::open` treats its argument as an executable path and quotes it safely;
it does not accept an executable plus arbitrary shell arguments.

The module remains installable without gnuplot. The CMake option which copies
the managed component is off by default, so TODO-49 can expose it as an
installer feature. Documentation records the upstream license and provenance.
No temporary files are created by the binding: deterministic tests write
directly to a caller-selected output path below a controlled directory.

Validation uses a prefix and output path containing spaces with `PATH`
restricted to the prefix and Windows. A noninteractive `pngcairo` test verifies
the PNG signature, dimensions, and a nontrivial payload. A separate interactive
Windows-terminal smoke test opens one plot and sends an explicit close/exit
sequence with a timeout; it requires an interactive desktop and is labelled so
CI or headless verification can omit it without weakening the deterministic
rendering test.

## Progress Log

- 2026-07-25: Created as an optional visualization Windows package candidate.
- 2026-07-29: Selected the official x86-64 Windows Clang build of gnuplot
  6.0.4 as an optional, installer-managed component. The portable package
  uses an explicit validated distribution root and a bundle-relative launcher;
  it never falls back to an unrelated `gnuplot.exe` on the host `PATH`.