# TODO-02 - CMake and Ninja Build

Status: Open
Branch: todo/02-cmake-ninja-build

## Purpose

Introduce a reproducible CMake/Ninja build targeting Clang and LLVM 22. Success means
that dependencies, generated configuration, source targets, installation rules, and
tests are represented without relying on Autoconf for the new build.

## Scope

- Add top-level CMake configuration and presets for Debug and release-style builds.
- Use `clang-22`, `clang++-22`, C++17, Ninja, and LLVM's CMake package.
- Detect GMP, MPFR, readline, PCRE POSIX, threads, and platform capabilities.
- Keep Autoconf files temporarily as a reference and fallback.
- Source-level LLVM API migration belongs to later TODOs.

## Task List

1. [ ] Add `CMakeLists.txt`, helper modules, and LLVM 22 version checks.
2. [ ] Generate `config.h` and model required platform feature checks.
3. [ ] Define runtime, interpreter, executable, and generated-source dependencies.
4. [ ] Add install rules and CTest integration for `run-tests`.
5. [ ] Add CMake presets for `llvm22-debug`, `llvm22-release`, and `llvm22-asan`.
6. [ ] Configure with Ninja and document expected LLVM-related compile failures.

## Guardrails

- Do not hardcode user-specific absolute paths except in overridable presets.
- Select compilers in presets or on the command line, not after CMake `project()`.
- Do not remove the old build until the final migration TODO.
- Avoid changing runtime behavior in this build-system-only step.

## Validation Plan

- `cmake --preset llvm22-debug`
- `cmake --build --preset llvm22-debug` as far as the current LLVM API permits.
- `ctest --preset llvm22-debug --show-only` to verify test registration.

## Open Questions

- Should normal builds regenerate Flex/Bison outputs or use checked-in generated files?
- Which installation layouts beyond Linux must remain supported initially?

## Progress Log

- 2026-07-22: Initial CMake migration plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
