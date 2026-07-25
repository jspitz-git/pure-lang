# TODO-48 - Windows pure-readline Package

Status: Open
Branch: todo/48-windows-pure-readline

## Purpose

Determine whether the separate `pure-readline` package adds supported functionality
beyond the interpreter's existing Windows readline integration.

## Scope

- Build the package against the same readline and terminal libraries as the core.
- Compare its API and behavior with built-in interpreter facilities.
- Package it only if it provides distinct, tested value.

## Task List

1. [ ] Build the module and audit duplicate runtime dependencies.
2. [ ] Compare its exported behavior with the core runtime.
3. [ ] Add input, history, completion, and interruption smoke tests.
4. [ ] Decide whether to include or retire it from the Windows distribution.

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
