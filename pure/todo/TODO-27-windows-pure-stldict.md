# TODO-27 - Windows pure-stldict Package

Status: Open
Branch: todo/27-windows-pure-stldict

## Purpose

Build, validate, and package `pure-stldict` with the C++ runtime selected for the
portable Windows distribution.

## Scope

- Build all native components with one compatible CLANG64 C++ toolchain.
- Validate dictionary operations, iteration, ordering, and object lifetime.
- Reuse the distribution's existing C++ runtime DLLs.

## Task List

1. [ ] Build the package against the staged Pure runtime.
2. [ ] Audit C++ ABI and runtime DLL dependencies.
3. [ ] Add focused dictionary and lifetime smoke tests.
4. [ ] Stage and validate the package outside MSYS2.

## Guardrails

- Do not mix incompatible C++ standard libraries in one process.
- Keep object ownership and exception handling valid across the module boundary.

## Validation Plan

- Exercise insertion, lookup, deletion, iteration, copying, and cleanup.
- Inspect PE imports and run with only staged runtime DLLs available.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
