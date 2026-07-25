# TODO-30 - Windows pure-gsl Package

Status: Open
Branch: todo/30-windows-pure-gsl

## Purpose

Build, validate, and package `pure-gsl` with the CLANG64 GSL implementation.

## Scope

- Build the native bridge and install all associated Pure modules.
- Bundle GSL, CBLAS, and their required runtime dependencies.
- Cover representative numerical subsystems rather than import-only validation.

## Task List

1. [ ] Build the package against the staged Pure runtime and GSL.
2. [ ] Inventory every installed Pure module and shared-library dependency.
3. [ ] Add representative numerical and error-handling smoke tests.
4. [ ] Validate the complete staged package outside MSYS2.

## Guardrails

- Do not silently omit modules that are part of the advertised package.
- Numerical results must use documented tolerances.

## Validation Plan

- Import every module and exercise vectors, integration, roots, and special functions.
- Run with only the staged GSL/CBLAS DLLs on the loader search path.

## Progress Log

- 2026-07-25: Created as a scientific Windows package candidate.
