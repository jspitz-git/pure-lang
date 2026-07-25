# TODO-28 - Windows pure-stllib Package

Status: Open
Branch: todo/28-windows-pure-stllib

## Purpose

Build, validate, and package the complete `pure-stllib` collection for Windows.

## Scope

- Build its native C++ modules with the distribution CLANG64 toolchain.
- Install the associated Pure modules and examples.
- Validate representative containers, algorithms, iterators, and object lifetimes.

## Task List

1. [ ] Inventory and build every native submodule.
2. [ ] Resolve common C++ runtime and package dependencies.
3. [ ] Add representative tests for each installed module family.
4. [ ] Stage the package and verify the complete installed manifest.

## Guardrails

- A partial build must not be presented as the complete package.
- Use one compatible C++ runtime throughout the distribution.

## Validation Plan

- Import every installed module and run representative container and algorithm cases.
- Run the suite outside MSYS2 and inspect all native module dependencies.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
