# TODO-44 - Windows pure-faust Package

Status: Closed on 2026-08-16
Branch: todo/44-windows-pure-faust

## Purpose

Build, validate, and package `pure-faust` with a reproducible Windows Faust
toolchain.

## Scope

- Define the supported Faust version and whether its compiler is bundled.
- Remove fixed external-tool paths and use distribution-relative discovery.
- Cover compilation, module loading, DSP processing, diagnostics, and cleanup.

## Task List

1. [x] Select and reproduce the Windows Faust dependency set.
2. [x] Deliberately exclude the legacy native bridge and audit the
   generated-code tool requirements.
3. [x] Add deterministic compile and DSP smoke tests.
4. [x] Keep the compiler in the optional `FaustDeveloper` component.
5. [x] Stage and validate the advertised configuration.

## Guardrails

- Do not require MSYS2 at package runtime.
- Keep generated-code compiler dependencies explicit.

## Validation Plan

- Compile a small Faust program, load it, and process a fixed signal buffer.
- Run from a clean VM with only the selected installer components present.

## Open Questions

- None. The default `Runtime` selection loads prebuilt bitcode; Faust 2.85.9
  and the Clang/LLVM 22 compile-only closure are optional `FaustDeveloper`
  content.

## Progress Log

- 2026-07-25: Created as an optional DSP Windows package candidate.
- 2026-08-16: Completed local implementation and prepared clean-runner
  automation.
  - `Runtime` contains `faust2.pure`, documentation, and the prebuilt fixture;
    it deliberately excludes `faust.cc`, `faust.pure`, `pure.cpp`,
    `faust.dll`, Faust, Clang, LLVM tools, and MSYS2.
  - `FaustDeveloper` pins Faust 2.85.9 and a dependency-derived Clang/LLVM 22
    compile-only closure. The installed helper supports paths containing
    spaces, verifies bitcode before atomic publication, and rebuilds the same
    deterministic two-input/one-output fixture consumed by the runtime smoke.
  - On the development Windows host, the sanitized `Runtime` label passed 3/3
    CTests in 13.68 seconds and the sanitized `faust` label passed 8/8 CTests
    in 26.55 seconds. The complete unfiltered suite also passed 8/8 in 26.59
    seconds.
    Exact labeled commands:

    ```powershell
    $env:Path = 'C:/tmp/pure faust runtime/bin;C:/Windows/System32/WindowsPowerShell/v1.0;C:/Windows/System32;C:/Windows'
    Remove-Item Env:PURELIB -ErrorAction SilentlyContinue
    C:/msys64/clang64/bin/ctest.exe --test-dir build/pure-faust -L runtime --output-on-failure

    $env:Path = 'C:/tmp/pure faust full/bin;C:/Windows/System32/WindowsPowerShell/v1.0;C:/Windows/System32;C:/Windows'
    C:/msys64/clang64/bin/ctest.exe --test-dir build/pure-faust -L faust --output-on-failure
    C:/msys64/clang64/bin/ctest.exe --test-dir build/pure-faust --output-on-failure
    ```

  - Before the final helper-publication cleanup in `ae71a5b1`, fresh stages in
    paths containing spaces passed the installed-package verifier:
    runtime-only contained 5 files with sorted inventory SHA-256
    `917f73e596348654eb98c918045b52c92bdfe9ab35dadd8ec292dd04563de386`;
    runtime plus developer contained 52 files with sorted inventory SHA-256
    `03c48fc651a0ff7979c52765e269500ea007ed6f7928e743ba769e321ef8d2d0`.
    The authoritative developer allowlist SHA-256 was
    `ff283ce1b7b1d97fc6a35bda10c1657f804490fc5a2a4fbe53304c51a971bbdc`.
    Exact staging and verifier commands (`$cmake` was
    `C:/msys64/clang64/bin/cmake.exe`, `$purePrefix` was
    `C:/pure-lang/pure/build/windows-clang64-prefix`, and `$pure` was
    `$purePrefix/bin/pure.exe`):

    ```powershell
    & $cmake --install build/pure-faust --prefix 'C:/tmp/pure faust runtime' --component Runtime
    & $cmake --install build/pure-faust --prefix 'C:/tmp/pure faust full' --component Runtime
    & $cmake --install build/pure-faust --prefix 'C:/tmp/pure faust full' --component FaustDeveloper

    & $cmake '-DBUILD_DIR=C:/pure-lang/.worktrees/todo-44-windows-pure-faust/build/pure-faust' '-DSTAGE_PREFIX=C:/tmp/pure faust runtime' -DEXPECT_DEVELOPER=OFF -P pure-faust/cmake/VerifyInstalledPackage.cmake

    & $cmake '-DBUILD_DIR=C:/pure-lang/.worktrees/todo-44-windows-pure-faust/build/pure-faust' '-DSOURCE_DIR=C:/pure-lang/.worktrees/todo-44-windows-pure-faust/pure-faust' "-DPURE_EXECUTABLE=$pure" "-DPURE_PREFIX=$purePrefix" '-DRUNTIME_SMOKE_SCRIPT=C:/pure-lang/.worktrees/todo-44-windows-pure-faust/pure-faust/tests/runtime-smoke.pure' '-DSTAGE_PREFIX=C:/tmp/pure faust full' -DEXPECT_DEVELOPER=ON -P pure-faust/cmake/VerifyInstalledPackage.cmake
    ```

    Both historical verifier invocations printed
    `Verified installed pure-faust runtime`; the full verifier regenerated,
    verified, and ran the fixture using only the staged developer payload plus
    the staged Pure runtime. The final `ae71a5b1` cleanup removed the installed
    CMake driver, so these inventory counts and hashes are retained only as
    pre-cleanup evidence; the final packaged ZIP hashes are recorded below.
  - Clean Windows validation passed on the final implementation commit
    `ae71a5b1399eecabdbf086e5e751473a28d85eb3` in
    [GitHub Actions run 31917331064](https://github.com/jspitz-git/pure-lang/actions/runs/31917331064).
    The `Runtime` job passed 3/3 CTests with a sanitized `PATH` and completed
    in 3:22;
    its inner `windows-pure-faust-runtime.zip` SHA-256 is
    `8e32fe9e1ac2a6a740e9adb00ce8ce50895d45cb15fdbb14086ac8d5809517e8`,
    and the uploaded GitHub artifact digest is
    `sha256:acb39a9037b3c8ca85a47cd177453c22eab29e04e39d637cae1800c6c690a7bc`.
    The `Runtime+FaustDeveloper` job passed 8/8 CTests with a sanitized `PATH`
    and completed in 4:33; its inner `windows-pure-faust-full.zip` SHA-256 is
    `f466c50ba5976e59e14cab24d77c9c316494032958e83912d0482fac9849557a`,
    and the uploaded GitHub artifact digest is
    `sha256:698c70fb61f33c5cd455928367ab58ec06dc62548d1cb3b87832bb4ea16a9ab0`.
    Both jobs checked out into paths containing spaces. The same run's macOS
    release-validation job also passed and completed in 8:36.
