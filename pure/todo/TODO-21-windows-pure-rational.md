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
2. [x] Stage the package without build-prefix references.
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
- 2026-07-26: Added prefix-contained CMake staging for the package.
  - The `runtime` component installs the two Pure modules under `lib/pure`; the
    `documentation` component installs a version-expanded README (which contains
    the package examples) and GPL license under `share/doc/pure-rational`.
  - Both install destinations must be relative and may not contain a parent
    traversal, keeping every package file inside the selected prefix.
  - Validation:
    - `C:\msys64\clang64\bin\cmake.exe -S pure-rational -B "C:\tmp\pure-rational stage build" -DCMAKE_INSTALL_PREFIX="C:\tmp\pure-rational staged package"` passed.
    - `C:\msys64\clang64\bin\cmake.exe --install "C:\tmp\pure-rational stage build"` installed exactly four declared files: both modules, `README`, and `COPYING`.
    - A literal scan of all staged files found no source-tree, build-tree,
      CLANG64, or MSYS2 prefix; `@version@` was expanded to `0.1`.
    - Configuring with `PURE_LIBRARY_INSTALL_DIR=../escape` failed with the
      expected prefix-containment diagnostic.
