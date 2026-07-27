# TODO-28 - Windows pure-stllib Package

Status: Completed
Branch: todo/28-windows-pure-stllib

## Purpose

Build, validate, and package the complete `pure-stllib` collection for Windows.

## Scope

- Build its native C++ modules with the distribution CLANG64 toolchain.
- Install the associated Pure modules and examples.
- Validate representative containers, algorithms, iterators, and object lifetimes.

## Task List

1. [x] Inventory and build every native submodule.
2. [x] Resolve common C++ runtime and package dependencies.
3. [x] Add representative tests for each installed module family.
4. [x] Stage the package and verify the complete installed manifest.

## Guardrails

- A partial build must not be presented as the complete package.
- Use one compatible C++ runtime throughout the distribution.

## Validation Plan

- Import every installed module and run representative container and algorithm cases.
- Run the suite outside MSYS2 and inspect all native module dependencies.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
- 2026-07-28: Built all six native modules with Clang 22, C++17, and strict
  warnings.
- 2026-07-28: Verified that every module uses the shared `libc++.dll` runtime
  and the expected internal DLL dependency graph.
- 2026-07-28: Added CTest coverage for vectors, algorithms, maps, multimaps,
  hash maps, sets, iterators, and reference-counted lifetimes; both suites pass.
- 2026-07-28: Installed the complete 42-file manifest and ran both installed
  suites from `C:\Windows` with an isolated path and no MSYS2 dependency.
- 2026-07-28: Completed.
