# TODO-21 - Windows pure-rational Package

Status: Open
Branch: todo/21-windows-pure-rational

## Purpose

Validate and package `pure-rational` for the portable Windows distribution.

## Scope

- Build or install the package using the staged Pure runtime.
- Include its Pure sources, metadata, examples, and required license material.
- Avoid adding dependencies not required by the package.

## Task List

1. [ ] Reproduce package installation in a clean CLANG64 build environment.
2. [ ] Stage the package without build-prefix references.
3. [ ] Add focused import and rational-arithmetic smoke tests.
4. [ ] Record installed files and runtime dependencies.

## Guardrails

- The installed package must run outside MSYS2.
- Keep package files within the distribution prefix.

## Validation Plan

- Import the module from the staged runtime with a sanitized `PATH`.
- Run representative construction, arithmetic, comparison, and conversion cases.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
