# TODO-22 - Windows pure-csv Package

Status: Open
Branch: todo/22-windows-pure-csv

## Purpose

Build, validate, and package `pure-csv` for the portable Windows distribution.

## Scope

- Port the native component to the supported CLANG64 toolchain where necessary.
- Stage the module, Pure sources, examples, runtime DLLs, and licenses.
- Cover Windows text, newline, quoting, and path behavior.

## Task List

1. [ ] Configure and build the native module on Windows.
2. [ ] Resolve and document its complete runtime dependency set.
3. [ ] Add CSV read/write and error-handling smoke tests.
4. [ ] Validate the staged package outside MSYS2.

## Guardrails

- Preserve CSV behavior across supported hosts.
- Do not rely on the current working directory for module or data lookup.

## Validation Plan

- Round-trip quoted, multiline, empty, and Unicode fields.
- Exercise files in a path containing spaces with a sanitized `PATH`.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
