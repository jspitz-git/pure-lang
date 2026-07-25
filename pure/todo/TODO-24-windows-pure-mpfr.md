# TODO-24 - Windows pure-mpfr Package

Status: Open
Branch: todo/24-windows-pure-mpfr

## Purpose

Build, validate, and package `pure-mpfr` with the GMP and MPFR libraries already
used by the Windows runtime.

## Scope

- Reuse the staged GMP and MPFR DLLs without duplicate copies.
- Validate precision, rounding, conversion, and exceptional values.
- Stage module sources, binaries, examples, and license material.

## Task List

1. [ ] Build the module against the portable runtime.
2. [ ] Confirm compatible GMP/MPFR headers and runtime DLL versions.
3. [ ] Add numerical smoke tests and staged import coverage.
4. [ ] Record the package manifest and close the TODO.

## Guardrails

- Keep one compatible copy of each shared runtime DLL in the distribution.
- Do not reduce numerical precision or change rounding semantics.

## Validation Plan

- Exercise configurable precision, all supported rounding modes, NaN, and infinity.
- Run from the installed tree with no MSYS2 directory on `PATH`.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
