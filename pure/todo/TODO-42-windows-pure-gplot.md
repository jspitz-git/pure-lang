# TODO-42 - Windows pure-gplot Package

Status: Closed on 2026-07-29
Branch: todo/42-windows-pure-gplot

## Purpose

Validate and package `pure-gplot` with a clearly defined Windows gnuplot dependency.

## Scope

- Decide whether gnuplot is bundled, detected, or offered as a separate component.
- Make process launching and temporary-file handling Windows-safe.
- Cover noninteractive rendering as well as an interactive smoke test.

## Task List

1. [x] Define the supported gnuplot version and packaging policy.
2. [x] Repair executable discovery, quoting, and path handling where needed.
3. [x] Add deterministic file-rendering smoke tests.
4. [x] Stage and validate the package in clean, relocated Windows prefixes.

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
prefix. Windows builds add a small `gplot.dll` process bridge which uses
`CreateProcessW` with an explicit application path and an inherited stdin
pipe; it does not invoke `cmd.exe`. The bridge derives the managed
`tools/gnuplot/bin/gnuplot.exe` path from its own installed location, while an
exact `GPLOT_EXE` environment override remains available. The public Pure API
stays `open`, `puts`, and `close`.

The source module and native bridge remain installable without gnuplot. The
CMake option which copies the managed component is off by default, so TODO-49
can expose it as an installer feature. A missing optional component makes
`open` fail without falling back to `PATH`. Documentation records the upstream
license and provenance. No temporary files are created by the binding:
deterministic tests write directly to a caller-selected output path below a
controlled directory.

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
- 2026-07-29: Replaced the planned cmd/CRT-popen launcher with a native
  `CreateProcessW` bridge after controlled tests showed the LLVM22 Windows
  `system.pure` pipe path gives the child EOF before its first write. An
  equivalent standalone C `_popen` test passed, isolating the failure from
  gnuplot itself. The user approved the architecture change; the public Pure
  API and optional-component policy are unchanged.
- 2026-07-29: Verified the native bridge with Clang 22.1.8 and the portable
  Pure runtime. `pure-gplot-command` passed while `GPLOT_EXE` pointed to
  `C:\tmp\Gnuplot 6.0.4 Controlled\bin\gnuplot.exe` and `PATH` contained no
  gnuplot. The acquisition script also installed and version-checked the
  official artifact with SHA-256
  `2c31e3fc91b21c450f4b015f1cd1f2f84f7a8cfc63afc037f9ba5efb47cc0c23`.
- 2026-07-29: Added a deterministic `pngcairo` smoke test in a path with
  spaces. It validated the PNG signature, 320x200 IHDR dimensions, and a
  payload above 1 KiB. With `PURE_GPLOT_INTERACTIVE_TESTS=ON`, the Windows
  terminal test opened a plot, paused, closed the terminal, and exited within
  its timeout. Command, render, and desktop tests all passed with sanitized
  `PATH`.
- 2026-07-29: Installed the binding plus optional component into
  `C:\tmp\Pure Gplot Stage 20260729` and copied it to
  `C:\tmp\Relocated Pure Gplot Bundle 20260729`. Both prefixes passed the
  installed verifier: 13 required package files, four unchanged runtime DLL
  hashes, bundle-relative gnuplot 6.0.4, 320x200 PNG rendering, and deliberate
  failure without any `PATH` fallback when `tools/gnuplot` was hidden. A
  separate binding-only install also succeeded and contained no gnuplot tree.
- 2026-07-29: Pre-merge review tightened the launcher to an explicit Win32
  handle list with `NUL` fallbacks, moved the absent-component check into a
  disposable miniature prefix, and froze the validated gnuplot tree below the
  build directory before installation. The fresh 3/3 CTest run, final stage,
  relocated final stage, binding-only install, and compiler-free non-Windows
  configure all passed.
