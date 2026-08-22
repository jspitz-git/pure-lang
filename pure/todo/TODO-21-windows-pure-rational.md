# TODO-21 - Windows pure-rational Package

Status: Closed on 2026-07-26
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
3. [x] Add focused import and rational-arithmetic smoke tests.
4. [x] Record installed files and runtime dependencies.

## Installed Package Manifest

- `lib/pure/rational.pure`
- `lib/pure/rat_interval.pure`
- `share/doc/pure-rational/README`
- `share/doc/pure-rational/COPYING`

## Runtime Dependencies

- `rational.pure` imports the package module `rat_interval.pure` and the standard
  Pure modules `math.pure` and `dict.pure`.
- `rat_interval.pure` imports the standard Pure module `math.pure`.
- The package is Pure source only. It adds no executable, DLL, import library,
  static library, or third-party native runtime dependency to the bundle.
- The existing portable Pure runtime and its baseline DLL set provide everything
  else required to interpret these modules.

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
- 2026-07-26: Added a focused CTest smoke test for the staged package.
  - The test imports both `rational` and `rat_interval`, then checks rational
    normalization, addition, comparison, mixed-fraction formatting and parsing,
    and interval arithmetic.
  - Tests are enabled only with an explicit `PURE_EXECUTABLE`, preventing CMake
    from silently selecting an unrelated interpreter from `PATH`; `--norc`
    excludes user startup configuration.
  - Validation:
    - `C:\msys64\clang64\bin\cmake.exe -S C:\pure-lang\pure-rational -B C:\tmp\pure-rational-smoke-build-step3-20260726 -DCMAKE_INSTALL_PREFIX=C:\tmp\pure-rational-smoke-step3-20260726 -DPURE_EXECUTABLE=C:\tmp\pure-rational-smoke-step3-20260726\bin\pure.exe` passed.
    - `C:\msys64\clang64\bin\cmake.exe --install C:\tmp\pure-rational-smoke-build-step3-20260726` installed the package into a copy of the portable runtime.
    - With `PURELIB` unset and `PATH` limited to the staged `bin` and Windows
      system directories, `C:\msys64\clang64\bin\ctest.exe --test-dir C:\tmp\pure-rational-smoke-build-step3-20260726 --output-on-failure`
      passed 1/1 test in 11.33 seconds.
    - The generated CTest command references
      `C:\tmp\pure-rational-smoke-step3-20260726\bin\pure.exe`, confirming that
      the staged interpreter was tested.
- 2026-07-26: Recorded the final package manifest and runtime dependencies.
  - A clean install into an empty prefix contained exactly the two Pure modules,
    the version-expanded README, and the GPL license listed above.
  - A source scan found only `rat_interval`, `math`, and `dict` imports and no
    foreign-library declarations; the package-only prefix contained zero binary
    files.
  - Validation:
    - `C:\msys64\clang64\bin\cmake.exe -S C:\pure-lang\pure-rational -B "C:\tmp\pure-rational manifest build step4 20260726" -DCMAKE_INSTALL_PREFIX="C:\tmp\pure-rational manifest step4 20260726" -DBUILD_TESTING=OFF` passed.
    - `C:\msys64\clang64\bin\cmake.exe --install "C:\tmp\pure-rational manifest build step4 20260726"` produced exactly the four documented relative paths; SHA-256 hashes were successfully calculated for every installed file.
    - Installing the same build into a fresh copy of the portable runtime found
      `math.pure`, `dict.pure`, `rat_interval.pure`, and `rational.pure` under
      `lib/pure`.
    - `$env:PURELIB=$null; $env:PATH="C:\tmp\pure-rational runtime step4 20260726\bin;$env:SystemRoot\System32;$env:SystemRoot"; & "C:\tmp\pure-rational runtime step4 20260726\bin\pure.exe" --norc -x "C:\pure-lang\pure-rational\tests\smoke.pure"` exited with status 0 outside MSYS2.
- 2026-08-22: Audited and hardened the package validation contract.
  - The audit reproduced two false-success paths in the original CTest setup:
    configuring without `PURE_EXECUTABLE` registered no tests while CTest still
    exited successfully, and an inherited `PURELIB` could supply modules which
    were not installed beside the selected interpreter.
  - `BUILD_TESTING=ON` now requires an existing `PURE_EXECUTABLE`; packaging
    without runtime tests remains available with `BUILD_TESTING=OFF`.
  - The install contract creates a package-only stage, verifies the exact
    four-file manifest and source/configured-file hashes, rejects source, build,
    MSYS2 and unexpanded-version references, copies a clean portable runtime,
    installs the current package into that copy, and executes the smoke test
    with `PURELIB` removed and `PATH` limited to the staged runtime and Windows
    system directories.
  - A configure contract verifies that the missing-interpreter case fails with
    the intended diagnostic. The install-contract test itself starts with a
    deliberately inherited `PURELIB`; a wrapper verifies that sanitization
    occurred before launching Pure. Removing the sanitization was confirmed to
    make the focused test fail.
  - The Windows core job in `non-linux-release-validation.yml` now configures
    and runs both pure-rational contracts against the freshly installed
    portable Pure runtime. Changes below `pure-rational/` and this TODO file are
    included in the workflow path filters.
  - Local validation from a worktree and build path containing spaces passed
    both contracts (2/2 in 1.22 seconds) using Pure 0.68 with LLVM 22.1.8. The
    staged smoke-test environment contained no MSYS2 path and no `PURELIB`.
