# TODO-19 - Portable Windows Runtime

Status: Open
Branch: todo/19-portable-windows-runtime

## Purpose

Make `pure.exe` and `libpure.dll` relocatable so they run on Windows without
MSYS2, MinGW, a fixed installation prefix, or machine-wide environment variables.

## Scope

- Resolve the runtime prefix and Pure library directory relative to `pure.exe`.
- Remove embedded build-tree and `C:\msys64` paths from installed artifacts.
- Stage the required non-system DLLs and retain environment-variable overrides.
- Keep compiler and LLVM command-line tools outside the mandatory runtime.

## Task List

1. [x] Implement executable-relative runtime and library discovery.
2. [x] Define and create the portable runtime staging layout.
3. [ ] Audit all direct and transitive PE imports.
4. [ ] Validate interpreter, JIT, module loading, and paths containing spaces.
5. [ ] Document the runtime/developer-tool boundary and close the TODO.

## Guardrails

- The staged runtime must not load `msys-2.0.dll`.
- Do not require global `PATH`, `PURELIB`, or registry changes.
- Preserve explicit user overrides for development and diagnostics.

## Validation Plan

- Run staged `pure.exe --version` and `examples/hello.pure` with a sanitized `PATH`.
- Load a native module and inspect the complete DLL dependency graph.
- Reject staged files containing build-prefix or MSYS2-prefix paths.

## Progress Log

- 2026-07-25: Created from the Windows distribution inventory.
- 2026-07-25: Made the default Windows Pure library lookup runtime-relative.
  - `libpure.dll` resolves `../lib/pure` from its loaded module path using
    wide-character Windows APIs; `PURELIB` remains an explicit override.
  - The interpreter, embedding API, and relocated batch executables share the
    lookup, while non-Windows hosts retain their configured installation path.
  - Windows binaries no longer embed the configured installation prefix.
  - Validation:
    - Windows CLANG64 Release configure and build passed.
    - `ctest --preset windows-clang64-release -E pure-regression` passed 21/21
      focused tests in 46.94 seconds.
    - A copied prefix in a spaced `C:\tmp` path ran `pure --version` and
      `examples/hello.pure` without `PURELIB` from `C:\Windows`.
    - A batch executable in a spaced path outside the prefix ran without
      `PURELIB`; binary string audit found no configured installation prefix.
- 2026-07-25: Added reproducible portable Windows staging to `cmake --install`.
  - CMake collects the full non-system runtime dependency closure into `bin`
    and filters DLLs supplied by Windows itself.
  - The documented layout separates runtime, Pure library, development, and
    shared-data files; dependency bundling can be disabled for developer prefixes.
  - Validation:
    - A clean install into a unique path containing spaces completed without
      runtime-dependency policy warnings.
    - The clean stage contained exactly 12 runtime DLLs, including `libpure.dll`
      and its 11 transitive non-system dependencies.
    - `pure --version` and `examples/hello.pure` passed with `PATH` limited to
      staged `bin` and Windows system directories and with `PURELIB` unset.
    - No `msys-2.0.dll` or Windows system DLL was copied into the stage.
