# TODO-48 - Windows pure-readline Package

Status: Rejected on 2026-08-09
Branch: todo/48-windows-pure-readline

## Decision

Do not build, stage, or install the separate `pure-readline` package in the
Windows distribution. The Windows interpreter already requires and links GNU
readline for its interactive input, editing, history, completion, EOF, and
interruption behavior. The package adds only a script-facing wrapper with a
separate history and would share mutable process-global readline state with the
interpreter.

This is a Windows packaging decision only. The portable `pure-readline/`
sources remain unchanged for other platforms and batch-compiled applications.

## Task List

1. [x] Audit the module and duplicate runtime dependency risk.
2. [x] Compare its exported behavior with the core runtime.
3. [x] Audit bounded coverage for input, history, completion, EOF, and interruption.
4. [x] Reject it from the Windows distribution.

## Guardrails

- Do not bundle duplicate or conflicting readline/terminal DLLs.
- Interactive tests must have bounded automated substitutes where possible.

## Validation Plan

- Exercise line input, editing, history, completion, EOF, and interruption.
- Run in both Windows Terminal and a plain console where available.

## Open Questions

- Whether this package is redundant in the modern Windows runtime.

## Progress Log

- 2026-07-25: Created as a compatibility Windows package investigation.
- 2026-08-09: Rejected the separate package for Windows.
  - `pure/cmake/PureDependencies.cmake` requires GNU readline and
    `pure/cmake/PureTargets.cmake` links `PkgConfig::READLINE` into `pure.exe`.
  - `pure/pure.cc` already supplies readline input/editing, interpreter and
    debugger history, symbol/keyword/command completion, EOF propagation, and
    Windows console interruption handling.
  - `pure-readline` exports only script-callable wrappers for line input and
    history. It disables custom completion and swaps the same library's
    process-global history state, so it does not provide a second Windows
    terminal implementation.
  - No active Windows staging or installer manifest selects the package;
    TODO-49 remains responsible for admitting only independently approved
    packages. The core-owned readline DLL remains the sole permitted copy.
  - Static audits and the existing bounded non-Linux release workflow establish
    the rejection without an unbounded interactive test. The portable
    `pure-readline/` tree was left unchanged.
