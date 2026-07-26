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

1. [x] Reproduce package installation in a clean CLANG64 build environment.
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
- 2026-07-26: Reproduced package installation in a clean CLANG64 environment.
  - The package is source-only and imports only the staged standard `math` and
    `dict` modules; CLANG64 `mingw32-make` installed `rational.pure` and
    `rat_interval.pure` into a copied portable prefix in a path with spaces.
  - Validation:
    - `C:\msys64\usr\bin\bash.exe -lc "export PATH=/clang64/bin:/usr/bin; cd /c/pure-lang/pure-rational && mingw32-make clean && mingw32-make install prefix='/c/tmp/pure-rational clean install'"` passed.
    - From `C:\Windows`, with `PURELIB` unset and `PATH` limited to the staged
      `bin` and Windows system directories, `pure.exe --version` reported Pure
      0.68 with LLVM 22.1.8.
    - `pure.exe -b C:\tmp\pure-rational-step1-smoke.pure` imported `rational`,
      evaluated `num_den (44%(-14))` as `-22L,7L`, and exited with status 0.
