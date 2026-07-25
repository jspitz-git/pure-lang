# TODO-31 - Windows pure-glpk Package

Status: Open
Branch: todo/31-windows-pure-glpk

## Purpose

Build, validate, and package `pure-glpk` with a controlled Windows GLPK runtime.

## Scope

- Build against CLANG64 GLPK and its required GMP, zlib, and ltdl dependencies.
- Reuse compatible DLLs already present in the distribution.
- Validate model construction, solving, status reporting, and cleanup.

## Task List

1. [ ] Build the native module against the staged runtime and GLPK.
2. [ ] Resolve and deduplicate all transitive runtime DLLs.
3. [ ] Add LP/MIP solution and failure-path smoke tests.
4. [ ] Stage and validate the package outside MSYS2.

## Guardrails

- Do not bundle conflicting GMP or zlib versions.
- Solver handles and callbacks must remain valid across the native boundary.

## Validation Plan

- Solve small deterministic LP and MIP models and check objective and status.
- Inspect PE imports and repeat the test with a sanitized `PATH`.

## Progress Log

- 2026-07-25: Created as a scientific Windows package candidate.
