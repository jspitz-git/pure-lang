# TODO-23 - Windows pure-ffi Package

Status: Open
Branch: todo/23-windows-pure-ffi

## Purpose

Build and validate `pure-ffi` with the Windows x86_64 calling conventions used by
the portable runtime.

## Scope

- Use the CLANG64 `libffi` package and bundle its required runtime files.
- Validate scalar, pointer, structure, callback, and library-loading behavior.
- Install the module and examples in the common distribution layout.

## Task List

1. [ ] Build the module against the staged Pure runtime and CLANG64 `libffi`.
2. [ ] Audit calling-convention and symbol-loading assumptions.
3. [ ] Add native-call and callback smoke tests.
4. [ ] Stage and validate the package outside MSYS2.

## Guardrails

- Do not mix MSVC and MinGW C++ ABIs across the module boundary.
- Treat callback crashes or silent ABI corruption as release blockers.

## Validation Plan

- Call a known Win32 or bundled C function through FFI.
- Exercise a callback into Pure and inspect the staged PE dependencies.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
