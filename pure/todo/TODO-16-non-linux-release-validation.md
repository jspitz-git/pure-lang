# TODO-16 - Non-Linux Release Validation

Status: Closed on 2026-07-25
Branch: todo/16-non-linux-release-validation

## Purpose

Define and validate the supported non-Linux platform matrix for the LLVM 22 port.
Success means each declared operating-system and architecture combination has a
reproducible CMake/Ninja build, test, install, uninstall, and installed-program result.

## Scope

- Decide whether Windows, macOS, or both are release-supported.
- Record supported architectures, LLVM 22 distributions, generators, and shells.
- Validate platform-specific runtime loading, paths, object/link output, and optional assets.
- Add presets or CI jobs only after the support matrix is explicit.

## Task List

1. [x] Define required operating systems, architectures, and host toolchains.
2. [x] Configure and build each supported matrix entry from a clean tree.
3. [x] Run focused integration and complete regression tests.
4. [x] Validate batch object/link execution and platform library lookup behavior.
5. [x] Validate install manifests, pkg-config where applicable, and idempotent uninstall.
6. [x] Document unsupported combinations and any platform-specific prerequisites.

## Required Release Matrix

Non-Linux support is provisional until every gate in tasks 2 through 5 passes on the
corresponding native host. The LLVM 22 release requires these two entries:

| Host | Architecture | Environment | Required toolchain |
| --- | --- | --- | --- |
| macOS 15 | arm64 | Native Terminal with a POSIX shell; Ninja single-config generator | Clang 22 and matching LLVM 22 CMake package for arm64, CMake 3.25+, Bison 3+, Flex 2.6+, pkg-config, GMP, MPFR, GNU readline, and PCRE POSIX from one native Homebrew or upstream package set, plus the macOS SDK iconv |
| Windows 11 | x86_64 | Native MSYS2 CLANG64 shell; Ninja single-config generator | MSYS2 CLANG64 Clang 22 and matching LLVM 22 CMake package, CMake 3.25+, Bison 3+, Flex 2.6+, pkgconf, GMP, MPFR, GNU readline, PCRE POSIX, and iconv packages from the CLANG64 repository |

Both entries must use native binaries throughout: no Rosetta translation, WSL, Cygwin,
32-bit process, cross-compilation, mixed MSYS/MINGW/CLANG package prefixes, or Apple/system
Clang paired with a different LLVM ABI. `PURE_STRICT_TOOLCHAIN=ON` remains mandatory and
now rejects mismatched host/target systems, effective target architectures, compiler/LLVM
architectures, Windows frontends, and mixed CLANG64 dependency prefixes during configure.
The `windows-clang64-release` and `windows-clang64-debug` presets encode the validated
standard `C:\msys64` installation; the macOS CI workflow encodes its native-host runbook.

A matrix entry becomes release-supported only after preserving complete logs for a clean
Release configure/build, focused and complete CTest runs, batch object/link execution,
staged install, installed-program execution, pkg-config where available, and two successful
uninstall invocations. A Debug build and focused integration run are also required to catch
configuration-dependent assertions; sanitizer availability is recorded but is not a support
gate for this TODO. The native workflows archive these logs as
`macos-15-arm64-native-validation` and `windows-native-validation` artifacts.

The following combinations are outside the declared LLVM 22 release matrix: macOS x86_64,
Windows arm64, MSVC/clang-cl, the Visual Studio and Xcode generators, Cygwin, non-Apple Unix
systems other than the Linux reference host, and every 32-bit or cross-compiled target.
Existing `_WIN32`, `__MINGW32__`, `__MINGW64__`, and `APPLE` branches are portability
inventory, not evidence that these combinations currently pass.

## Current Portability Inventory

- CMake already selects `DYLD_LIBRARY_PATH` on Apple, uses standard shared-library and
  executable suffixes, and limits ELF JIT debug-object registration to Linux Debug builds.
- Windows path separators, drive-letter absolute paths, semicolon search paths, console
  interrupts, process spawning, stack size, and MinGW runtime quirks have dedicated source
  branches inherited from the historical MSYS2 port.
- Test drivers now select `PATH` on Windows, `DYLD_LIBRARY_PATH` on macOS, and
  `LD_LIBRARY_PATH` elsewhere, preserve the inherited search path, and invoke generated POSIX
  drivers through an explicitly discovered `sh`.
- The batch executable test now exercises the actual `pure -c ... -o program` path. Batch
  assembly and linkage default to `clang` and `clang++` from the configured LLVM prefix,
  retain `CC`/`CXX` overrides, locate `pure_main.o` and the runtime from the active `PURELIB`,
  and keep ELF- and Mach-O-specific link options scoped to their hosts. Native x86_64 COFF
  and arm64 Mach-O object and executable output passed their respective host validation.
- Installed macOS executables have loader paths for the sibling library directory;
  `pure.pc` advertises `-dynamiclib` on macOS and omits `-fPIC` on Windows. Native install,
  execution, and module-consumer validation passed on both supported hosts.
- Staged Unix installs can be uninstalled with the same `DESTDIR`; native Windows validation
  uses a dedicated configured prefix because CMake does not support drive-letter `DESTDIR`.
- Linux presets retain their compiler names and `/usr/lib/llvm-22`. The Windows presets use
  the standard `C:\msys64` CLANG64 prefix and an explicit standard Faust path;
  nonstandard installations should continue to use the explicit cache arguments below.
- The non-Linux workflow runs for relevant pushes and pull requests and can also be dispatched
  manually. Its native macOS and Windows jobs encode the runbooks and upload their complete
  validation logs. GitHub Actions run 30167622744 passed every original macOS gate; the
  original native Windows validation is recorded below.
- The closure counts below are historical evidence from 2026-07-25: macOS registered 20 tests
  and Windows registered 22. After the LLVM migration follow-ups through TODO-15, the current
  Windows development configuration registers 53 tests. A release claim for a newer revision
  depends on fresh successful native workflow artifacts, not on the historical counts alone.

## Native Validation Runbook

Run from a clean checkout on each declared native host and preserve the complete output of
all commands. Use `build/native-release`, `build/native-debug`, and
`build/native-prefix` only as illustrative local paths; the archived logs must record their
resolved absolute paths.

### macOS 15 arm64

Use one native arm64 Homebrew installation or one self-consistent upstream toolchain. Record
`uname -m`, `sw_vers`, `clang --version`, `clang -dumpmachine`, `llvm-config --version`,
`llvm-config --host-target`, `brew config` when applicable, and all dependency prefixes.
Configure with the LLVM 22 `clang`, `clang++`, and `LLVM_DIR` paths explicitly; do not use
Apple Clang or Rosetta:

```text
cmake -S . -B build/native-release -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=<llvm-22-prefix>/bin/clang \
  -DCMAKE_CXX_COMPILER=<llvm-22-prefix>/bin/clang++ \
  -DLLVM_DIR=<llvm-22-prefix>/lib/cmake/llvm \
  -DCMAKE_PREFIX_PATH=<native-dependency-prefixes> \
  -DCMAKE_INSTALL_PREFIX=<absolute-native-prefix> \
  -DPURE_STRICT_TOOLCHAIN=ON
cmake --build build/native-release --parallel 1
ctest --test-dir build/native-release -E pure-regression --output-on-failure
ctest --test-dir build/native-release --output-on-failure
cmake --install build/native-release
<absolute-native-prefix>/bin/pure --version
<absolute-native-prefix>/bin/pure examples/hello.pure
<absolute-native-prefix>/bin/pure -v0100 -c test/batch-smoke.pure -o build/native-batch
build/native-batch
PKG_CONFIG_PATH=<absolute-native-prefix>/lib/pkgconfig pkg-config --modversion pure
otool -L <absolute-native-prefix>/bin/pure
file build/native-batch
cmake --build build/native-release --target uninstall
cmake --build build/native-release --target uninstall
```

Repeat configure/build and the focused CTest command in `build/native-debug` with
`CMAKE_BUILD_TYPE=Debug`. Installed-program and batch-program execution must succeed without
`DYLD_LIBRARY_PATH`; `otool` must show only the selected arm64 prefixes and the expected
loader-relative runtime path. Build and load `examples/hellomod` using the installed
`pure.pc` to validate `-dynamiclib` and the installed headers/runtime.

### Windows 11 x86_64

Run only in a native MSYS2 CLANG64 shell. The compiler, LLVM, pkgconf libraries, and target
binaries must resolve below `/clang64`; MSYS tools such as `/usr/bin/sh`, Bison, and Flex are
allowed only as build-time programs. Record `uname -m`, `cmd.exe /c ver`, `clang --version`,
`clang -dumpmachine`, `llvm-config --version`, `llvm-config --host-target`, and `pkgconf
--path` for every required module:

```text
cmake -S . -B build/native-release -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=/clang64/bin/clang.exe \
  -DCMAKE_CXX_COMPILER=/clang64/bin/clang++.exe \
  -DLLVM_DIR=/clang64/lib/cmake/llvm \
  -DCMAKE_INSTALL_PREFIX=<absolute-clang64-prefix> \
  -DPURE_STRICT_TOOLCHAIN=ON
cmake --build build/native-release --parallel 1
ctest --test-dir build/native-release -E pure-regression --output-on-failure
ctest --test-dir build/native-release --output-on-failure
cmake --install build/native-release
PATH=<absolute-clang64-prefix>/bin:$PATH <absolute-clang64-prefix>/bin/pure.exe --version
PATH=<absolute-clang64-prefix>/bin:$PATH <absolute-clang64-prefix>/bin/pure.exe examples/hello.pure
PATH=<absolute-clang64-prefix>/bin:$PATH <absolute-clang64-prefix>/bin/pure.exe \
  -v0100 -c test/batch-smoke.pure -o build/native-batch.exe
PATH=<absolute-clang64-prefix>/bin:$PATH build/native-batch.exe
PKG_CONFIG_PATH=<absolute-clang64-prefix>/lib/pkgconfig pkgconf --modversion pure
llvm-readobj --file-headers --coff-exports <absolute-clang64-prefix>/bin/libpure.dll
llvm-readobj --file-headers build/native-batch.exe
cmake --build build/native-release --target uninstall
cmake --build build/native-release --target uninstall
```

With MSYS2 installed at `C:\msys64` and Faust at `C:\Program Files\Faust`, the
equivalent exercised Release entry point is `cmake --preset windows-clang64-release`,
followed by the matching build and test presets. The explicit commands remain the runbook
for nonstandard installation locations and for producing archived validation logs.

Repeat configure/build and focused CTest in Debug. Run tests once with the parent shell's
`PATH` stripped of the build directory, verify every DLL/import library in the install
manifest, and build/load `examples/hellomod` from installed `pure.pc`. A path containing
spaces and a semicolon-separated `PURE_INCLUDE`/`PURE_LIBRARY` lookup are required path
round trips. Do not use `DESTDIR`; configure the disposable staging prefix directly.

## Guardrails

- Do not infer Windows or macOS support from the Linux/WSL validation.
- Do not add nominal presets which have not been exercised on their target host.
- Keep platform-specific workarounds narrowly scoped and covered by tests.

## Validation Plan

- Run strict native-toolchain configure probes for both supported entries and retain negative
  checks which reject translated, cross-compiled, mixed-prefix, or wrong-architecture inputs.
- Run the focused Debug suite plus focused and complete Release CTest suites. Treat the number
  of registered tests as revision-specific evidence and record the exact count in each artifact.
- Exercise batch object and executable output, installed `pure --version` and `hello.pure`,
  pkg-config consumption, and the platform-native Mach-O or COFF inspection tools.
- On Windows, install the portable runtime dependency closure, run it with a sanitized `PATH`
  and no `PURELIB`, and apply `AuditWindowsPortableInstall.cmake` to its recursive PE imports
  and forbidden build/MSYS2 prefixes.
- Confirm every manifest path remains below the selected installation prefix, run uninstall
  twice, and verify that no manifest entry remains after the first invocation.
- Upload complete `macos-15-arm64-native-validation` and `windows-native-validation` artifacts
  for every revision used as non-Linux release evidence.

## Origin

Created from TODO-02's Linux-only compatibility note, TODO-13 retrospective gate 5,
and TODO-13's unresolved release-matrix question.

## Progress Log

- 2026-07-25: Defined the provisional native non-Linux release matrix.
  - Selected macOS 15 arm64 with a native LLVM 22 prefix and Windows 11 x86_64 in the MSYS2
    CLANG64 environment as the only required non-Linux entries.
  - Required strict matching Clang/LLVM 22 tools, CMake/Ninja, native architecture packages,
    Debug focused coverage, and the full Release build/test/install/uninstall lifecycle.
  - Explicitly excluded translated, cross, mixed-prefix, 32-bit, MSVC/clang-cl, Cygwin,
    macOS x86_64, Windows arm64, Visual Studio, and Xcode configurations from this release.
  - Distinguished historical platform conditionals from validated support and recorded known
    runtime-loader, batch-link, preset, and CI gaps for the native-host tasks.
  - Validation:
    - Read-only audit of CMake configuration, targets, presets, test drivers, installation
      documentation, runtime platform branches, and historical port notes; no non-Linux
      support claim was made without a native-host run.
- 2026-07-25: Prepared the native test, batch, loader, and install paths for target-host runs.
  - Selected `PATH`, `DYLD_LIBRARY_PATH`, or `LD_LIBRARY_PATH` by host, preserved inherited
    search paths, and made every CTest POSIX driver run through the discovered `sh`.
  - Replaced the CMake-only batch link smoke path with direct `pure -c -o` coverage. The
    batch compiler now defaults to matching LLVM-prefix Clang tools, derives its runtime
    library search directory from `PURELIB`, applies only host-appropriate link options,
    and preserves documented `CC`/`CXX` overrides.
  - Added macOS install and batch runtime paths, platform-specific `pure.pc` module flags,
    and `DESTDIR`-aware idempotent uninstall. Added exact native-host evidence and command
    requirements while retaining provisional support status.
  - Native blocker: this workspace is a Linux/WSL host and cannot satisfy the macOS 15 arm64
    or Windows 11 MSYS2 CLANG64 gates. Tasks 2 through 5 remain unchecked until complete
    logs from both native hosts exist. The next safe action is the macOS Release/Debug
    runbook followed by the Windows Release/Debug runbook, fixing only reproduced failures.
  - Validation:
    - `cmake --preset llvm22-release && cmake --build --preset llvm22-release --parallel 1`
      passed with Clang/LLVM 22.1.8.
    - `ctest --preset llvm22-release -R "pure-(formatted-io|bitcode-|batch-)"
      --output-on-failure` passed all 15 selected tests in 92 seconds.
    - `ctest --preset llvm22-release --output-on-failure` passed all 22 tests,
      including the complete regression corpus, in 374 seconds.
    - `cmake --preset llvm22-debug && cmake --build --preset llvm22-debug --parallel 1
      && ctest --preset llvm22-debug -E pure-regression --output-on-failure` passed all 21
      focused Debug tests in 208 seconds.
    - `ctest --preset llvm22-release -R pure-batch-executable --output-on-failure` passed;
      the logged direct link used `/usr/lib/llvm-22/bin/clang++`.
    - `cmake --preset llvm22-asan && cmake --build --preset llvm22-asan --parallel 1 &&
      ctest --preset llvm22-asan -R pure-batch-executable --output-on-failure` passed with
      AddressSanitizer and UndefinedBehaviorSanitizer in 1.5 seconds.
    - Fresh `build/todo16-install/build` Release configure/build/install passed. The installed
      interpreter reported Pure 0.68 with LLVM 22.1.8, ran `examples/hello.pure`, directly
      compiled and ran `test/batch-smoke.pure`, and used LLVM-prefix `opt`, `llc`, and
      `clang++`; installed `pure.pc` reported 0.68, `-shared`, and `-fPIC` on Linux.
    - Both normal-prefix and `DESTDIR` installs had 28 manifest entries; two uninstall
      invocations succeeded in each mode and left no installed file or symlink behind.
    - Native macOS and Windows validation was not run and no support claim is made.
- 2026-07-25: Encoded the first native-host gate as a manual macOS 15 arm64 CI workflow.
  - Verified that GitHub's `macos-15` label is an arm64 M1 runner and that Homebrew currently
    provides LLVM/Clang 22.1.8 plus native GMP, MPFR, readline, and PCRE POSIX packages.
  - Added explicit native architecture/toolchain assertions, clean Release focused and full
    CTest runs, focused Debug coverage, Mach-O checks, installed execution without
    `DYLD_LIBRARY_PATH`, loader-path inspection, pkg-config module build/load, prefix-safe
    manifest checks, two uninstall runs, and always-uploaded logs.
  - Kept the workflow manual and macOS-only. Tasks 2 through 5 remain open until its uploaded
    logs pass review; the Windows workflow will be added only after macOS findings are fixed.
  - Validation:
    - Ruby's YAML parser accepted `.github/workflows/non-linux-release-validation.yml`.
    - Zed YAML diagnostics reported no errors or warnings.
    - Read-only review checked current GitHub runner labels, Homebrew formula metadata, shell
      quoting, CMake paths, expected artifacts, RPATH assertions, and log preservation.
    - The workflow was not dispatched from this local branch, so no native result is claimed.
- 2026-07-25: Made the provisional matrix constraints enforceable in strict CMake builds.
  - Centralized compiler target discovery in `PureToolchain.cmake` and compare C, C++, and
    LLVM host architectures while preserving the historical host triple in generated config.
  - Added effective compile probes so macOS universal/x86_64 flags, Rosetta hosts, Windows
    non-MinGW targets, clang-cl, 32-bit targets, and host/target OS mismatches fail configure.
  - Canonicalized one MSYS2 CLANG64 prefix and require Clang, LLVM, pkgconf, GMP, MPFR,
    readline, PCRE POSIX, and external iconv paths to remain within it. Both drive-qualified
    and `/clang64/...` pkgconf paths are handled; bare linker names rely on checked library
    directories rather than being misclassified as filesystem paths.
  - Validation:
    - `cmake --preset llvm22-release && cmake --build --preset llvm22-release --parallel 1`
      passed and reported matching `x86_64-pc-linux-gnu` C, C++, and LLVM host triples.
    - `ctest --preset llvm22-release -R "pure-(jit-smoke|batch-executable)"
      --output-on-failure` passed both selected tests in 0.7 seconds.
    - A fresh strict configure with `CMAKE_SYSTEM_NAME=Generic` failed at the intended
      matching-host-and-target-system guard.
    - Zed CMake diagnostics and `git diff --check` reported no errors.
    - Native macOS/Windows branches remain unexecuted pending the manual macOS workflow.
- 2026-07-25: Completed the native Windows 11 x86_64 implementation and local validation.
  - Vendored the user-provided MinGW `glob`/`fnmatch` sources, corrected their Win64 size
    accounting, installed their headers, and linked them directly into `libpure.dll`.
  - Fixed Clang/MinGW header ordering, non-SEH setjmp selection, Windows DLL exports, CRT
    allocator and `puts` resolution in ORC, batch tool paths, locale handling, CRLF output,
    and cmd.exe-incompatible test commands. Added explicit Flang 22 discovery and repaired
    readline feature checks with the required headers and include paths.
  - Added `windows-clang64-release` and `windows-clang64-debug` configure, build, and test
    presets for the validated standard MSYS2/Faust installation paths.
  - Validation:
    - A clean explicit Release configure and build passed with Clang/LLVM 22.1.8 targeting
      `x86_64-w64-windows-gnu`, Bison 3.8.2, Flex 2.6.4, CLANG64 GMP/MPFR/readline/PCRE/iconv,
      Faust, Flang, and strict toolchain checks enabled.
    - `ctest --test-dir build/native-release --output-on-failure --parallel 4` passed all
      22 tests, including the full regression corpus, formatted I/O, Faust lifecycle, JIT,
      bitcode, batch object, batch executable, and batch Faust coverage in 152 seconds.
    - The clean `windows-clang64-release` preset configured, built, found Faust, and passed
      all 22 tests through its test preset in 154 seconds.
    - A clean explicit Debug configure/build and focused `ctest -E pure-regression` run
      passed all 21 selected tests in 27 seconds.
    - The 29-entry native install manifest included `pure.exe`, `libpure.dll`, the import
      library, runtime and compatibility headers, `pure_main.o`, libraries, `pure.pc`, and
      the manual. The installed interpreter reported Pure 0.68/LLVM 22.1.8, ran hello,
      compiled and ran the batch smoke program, and `pkgconf` reported version 0.68.
    - `examples/hellomod` built against the installed `pure.pc` and loaded successfully.
      Semicolon-separated `PURE_INCLUDE`/`PURE_LIBRARY` values whose working entries used
      paths containing spaces also loaded the module successfully.
    - LLVM inspection identified `libpure.dll` and the installed batch program as x86_64
      COFF, and the installed import library exposed the sampled public runtime symbols.
      Two uninstall runs succeeded and left all 29 manifest paths absent.
  - Windows remains provisional at the overall TODO level until its logs are archived and
    the required macOS 15 arm64 entry passes. The current broad DLL auto-export surface is
    functional but should be narrowed by a separately reviewed public export definition.
- 2026-07-25: Completed native macOS 15 arm64 validation and closed the release matrix.
  - GitHub Actions run [30167622744](https://github.com/jspitz-git/pure-lang/actions/runs/30167622744)
    passed on the native `macos-15` arm64 runner with Homebrew Clang/LLVM 22.1.8.
  - Fixed imported macOS SDK include ordering, unsupported LLVM debug-only diagnostics,
    public GMP/MPFR include propagation, equivalent `macosx`/`darwin` target triples, and
    unambiguous loading of the selected Homebrew PCRE POSIX library.
  - The clean Release build passed all 19 focused tests and all 20 complete CTest entries,
    including the 96-input regression corpus, bitcode ABI checks, formatted I/O, native
    batch object generation, and batch executable linkage and execution.
  - Installed `pure` ran its version check and hello program without `DYLD_LIBRARY_PATH`,
    compiled and ran an arm64 Mach-O batch executable, and used the expected loader-relative
    runtime path. The installed `pure.pc` built and loaded `examples/hellomod`.
  - The clean Debug build and focused tests passed. Manifest containment checks and two
    uninstall invocations succeeded without leaving any manifest path behind.
  - The workflow uploaded its complete native validation logs as the
    `macos-15-arm64-native-validation` artifact. Together with the recorded native Windows
    run, this satisfies every task and required entry in the non-Linux release matrix.
- 2026-08-21: Audited the closed matrix against the expanded LLVM migration test surface.
  - Corrected the formal closure status and distinguished the original 20-test macOS and
    22-test Windows results from the current 53-test development configuration.
  - Updated the workflow description for its `push`, `pull_request`, and `workflow_dispatch`
    triggers and expanded the validation plan with strict-toolchain, portable-runtime, PE,
    manifest-containment, and artifact requirements.
  - Added the `windows-pure-core` GitHub Actions job. It installs native CLANG64 LLVM 22 and
    Flang plus the pinned official Faust payload, exercises the Windows Release and Debug
    presets, confirms that a cross-target configure is rejected by the intended strict-toolchain
    guard, runs focused and complete CTest, audits the installed portable runtime, validates
    installed programs and COFF metadata, performs idempotent uninstall, and uploads the
    `windows-native-validation` logs.
  - Validation:
    - The pre-change static acceptance check failed for the missing Windows job and artifact,
      stale status and manual-only description, and absent current 53-test inventory.
    - Local workflow syntax and static acceptance validation are recorded by the follow-up
      audit. The new native job and the expanded current macOS suite require successful GitHub
      Actions runs before their artifacts can be used as fresh release evidence.
