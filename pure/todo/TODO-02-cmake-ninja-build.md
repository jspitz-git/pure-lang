# TODO-02 - CMake and Ninja Build

Status: Closed on 2026-07-22
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

1. [x] Add `CMakeLists.txt`, helper modules, and LLVM 22 version checks.
2. [x] Generate `config.h` and model required platform feature checks.
3. [x] Define runtime, interpreter, executable, and generated-source dependencies.
4. [x] Add install rules and CTest integration for `run-tests`.
5. [x] Add CMake presets for `llvm22-debug`, `llvm22-release`, and `llvm22-asan`.
6. [x] Configure with Ninja and document expected LLVM-related compile failures.

## Bootstrap Findings

- The reference configuration requires Clang 22.x and LLVM 22.x by default;
  `PURE_STRICT_TOOLCHAIN=OFF` can later support exploratory compiler builds.
- LLVM is found through its exported CMake package, followed by an explicit 22.x
  range check. LLVM's package version file rejects a major-only request despite
  reporting 22.1.8, so the range check cannot be delegated to `find_package`.
- Required dependencies are Bison, Flex, Iconv, pkg-config, threads, GMP, MPFR,
  readline, and PCRE POSIX.
- GSL, Faust, Flang, GFortran, and Sphinx are detected as optional tools for
  examples, integration fixtures, and documentation.
- LLVM's exported targets require LibEdit, Zlib, zstd, and Curl development
  packages. Their installation is now part of the reference environment.
- `PureConfigure.cmake` now derives the target triple from Clang, detects ABI
  sizes and endianness, checks required headers/functions, and generates
  `config.h` from `config.h.cmake`.
- On the reference host, `long`, `size_t`, and pointers are 8 bytes and the host
  triple is `x86_64-pc-linux-gnu`.
- `strptime` is not visible with the current feature-test macros, so the source
  target must include the existing `strptime.c` fallback. This can be revisited
  after target compile definitions are finalized.
- A small set of historical LLVM feature defines remains as a documented bridge
  for the unported sources; TODO-03 removes these compatibility branches.
- `PureTargets.cmake` defines Bison/Flex generation in the build tree, shared
  `libpure` ABI version 8.0.0, the `pure` executable, and `pure-main-object` for
  embedding.
- Runtime sources link LLVM, GMP, MPFR, PCRE POSIX, threads, Iconv, `dl`, and
  `libm`; the executable adds readline. The `strptime.c` fallback is conditional.
- Generated `parser.cc`, `parser.hh`, `location.hh`, `position.hh`, `stack.hh`,
  and `lexer.cc` remain build artifacts and are not written into the source tree.
- CMake configures executable `run-test` and `run-tests` scripts in the build tree
  with the source path, runtime library path, `PURELIB`, `PURE_INCLUDE`, and C locale.
- CTest registers the existing golden corpus as `pure-regression` without changing
  the runner's output comparison semantics.
- Install rules cover `pure`, versioned `libpure`, `runtime.h`, `pure_main.c`, the
  embedding object renamed to `pure_main.o`, `lib/*.pure`, `pure.pc`, and `pure.1`.
  Emacs, TeXmacs, and downloaded documentation installation remain out of scope.
- `CMakePresets.json` provides matching configure, build, and test presets for
  Debug, Release, and ASan/UBSan builds. All select Ninja, Clang 22, and LLVM 22.
- The sanitizer preset applies AddressSanitizer and UndefinedBehaviorSanitizer to
  C, C++, executable linking, and shared-library linking, preserves frame pointers,
  and enables leak detection for CTest.
- `build/` is ignored locally so preset output cannot pollute Git status.
- A serial Debug build completes configuration and generated-source steps, then
  stops at the first C++ source because LLVM 22 no longer provides
  `llvm/ExecutionEngine/JIT.h`. This is the intended handoff to TODO-03 rather
  than a CMake dependency or target-graph failure.

## Guardrails

- Do not hardcode user-specific absolute paths except in overridable presets.
- Select compilers in presets or on the command line, not after CMake `project()`.
- Do not remove the old build until the final migration TODO.
- Avoid changing runtime behavior in this build-system-only step.

## Validation Plan

- `cmake --preset llvm22-debug`
- `cmake --build --preset llvm22-debug` as far as the current LLVM API permits.
- `ctest --preset llvm22-debug --show-only` to verify test registration.

## Compatibility Note

- This TODO validates the initial CMake implementation on Linux/WSL only.
  TODO-16 owns the explicit Windows/macOS support matrix and validation; neither
  platform is declared supported by the recorded Linux result.

## Progress Log

- 2026-07-22: Closed TODO-02 after verifying the expected LLVM source-port
  boundary.
  - Validation:
    - `cmake --preset llvm22-debug` configured and generated Ninja files.
    - `cmake --build --preset llvm22-debug -- -j1` completed generated-source
      steps, then failed while compiling `expr.cc` through `interpreter.hh`:
      `fatal error: 'llvm/ExecutionEngine/JIT.h' file not found`.
    - The failure is owned by TODO-03; no CMake target, dependency, or generated
      source error preceded it.
    - All six checklist milestones are complete; full build, install, and CTest
      execution remain downstream LLVM port validation.
    - Removed the temporary Debug preset build directory after validation.
- 2026-07-22: Added Debug, Release, and ASan/UBSan CMake presets.
  - Validation:
    - `cmake --list-presets=all` listed all three configure, build, and test presets.
    - `cmake --preset llvm22-debug`, `cmake --preset llvm22-release`, and
      `cmake --preset llvm22-asan` all configured and generated Ninja files.
    - The ASan cache contained `-fsanitize=address,undefined` for C, C++,
      executable linking, and shared-library linking, plus frame pointers.
    - Removed all preset build directories after validation.
- 2026-07-22: Added CTest runner generation and baseline install rules.
  - Validation:
    - CMake configuration generated executable `run-test` and `run-tests` scripts
      with the expected source and environment paths.
    - `ctest --test-dir build/llvm22-install --show-only` reported exactly one
      test, `pure-regression`.
    - Inspected `cmake_install.cmake`; it includes `runtime.h`, `pure_main.o`,
      `pure.pc`, and `pure.1` at their planned destinations.
    - Full `cmake --install` remains blocked until the LLVM 22 source port builds
      `pure-runtime` and `pure`.
    - Removed the temporary `build/llvm22-install` directory after validation.
- 2026-07-22: Added generated-source, runtime library, interpreter executable,
  and embedding object targets.
  - Validation:
    - CMake generation succeeded after installing LLVM's Zlib, zstd, and Curl
      development dependencies.
    - `cmake --build build/llvm22-targets --target pure-generated-sources
      --verbose` generated all Flex/Bison outputs in the build tree.
    - `cmake --build build/llvm22-targets --target pure-main-object --verbose`
      compiled `pure_main.c` successfully with Clang 22.
    - Removed the temporary `build/llvm22-targets` directory after validation.
- 2026-07-22: Added platform checks and generated CMake `config.h` support.
  - Validation:
    - Reconfigured with Clang/LLVM 22 and Ninja successfully.
    - Generated values included host `x86_64-pc-linux-gnu`, LLVM 22.1.8,
      `SIZEOF_LONG=8`, `SIZEOF_SIZE_T=8`, and `SIZEOF_VOID_P=8`.
    - Header, complex-number, `_setjmp`/`_longjmp`, readline history, and GNU
      linker checks passed; `strptime` was absent and retains its fallback path.
    - Removed the temporary `build/cmake-config` directory after inspection.
- 2026-07-22: Added the CMake bootstrap, toolchain validation, and dependency
  discovery modules.
  - Validation:
    - `cmake -S . -B build/cmake-bootstrap -G Ninja
      -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_COMPILER=clang-22
      -DCMAKE_CXX_COMPILER=clang++-22
      -DLLVM_DIR=/usr/lib/llvm-22/lib/cmake/llvm` completed successfully.
    - Detected Clang/LLVM 22.1.8, Bison 3.8.2, Flex 2.6.4, GMP 6.3.0,
      MPFR 4.2.1, readline 8.2, PCRE POSIX 8.39, GSL 2.7.1, Faust,
      Flang 22, GFortran, and Sphinx.
    - Removed the temporary bootstrap build directory after validation.
- 2026-07-22: Initial CMake migration plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
