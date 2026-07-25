# TODO-16 - Non-Linux Release Validation

Status: Open
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
2. [ ] Configure and build each supported matrix entry from a clean tree.
3. [ ] Run focused integration and complete regression tests.
4. [ ] Validate batch object/link execution and platform library lookup behavior.
5. [ ] Validate install manifests, pkg-config where applicable, and idempotent uninstall.
6. [ ] Document unsupported combinations and any platform-specific prerequisites.

## Required Release Matrix

Non-Linux support is provisional until every gate in tasks 2 through 5 passes on the
corresponding native host. The LLVM 22 release requires these two entries:

| Host | Architecture | Environment | Required toolchain |
| --- | --- | --- | --- |
| macOS 15 | arm64 | Native Terminal with a POSIX shell; Ninja single-config generator | Clang 22 and matching LLVM 22 CMake package for arm64, CMake 3.25+, Bison 3+, Flex 2.6+, pkg-config, GMP, MPFR, GNU readline, PCRE POSIX, and iconv from one consistent Homebrew or upstream prefix |
| Windows 11 | x86_64 | Native MSYS2 CLANG64 shell; Ninja single-config generator | MSYS2 CLANG64 Clang 22 and matching LLVM 22 CMake package, CMake 3.25+, Bison 3+, Flex 2.6+, pkgconf, GMP, MPFR, GNU readline, PCRE POSIX, and iconv packages from the CLANG64 repository |

Both entries must use native binaries throughout: no Rosetta translation, WSL, Cygwin,
32-bit process, cross-compilation, mixed MSYS/MINGW/CLANG package prefixes, or Apple/system
Clang paired with a different LLVM ABI. `PURE_STRICT_TOOLCHAIN=ON` remains mandatory.
Repository presets remain Linux-specific until exercised target-host presets can be added.

A matrix entry becomes release-supported only after preserving complete logs for a clean
Release configure/build, focused and complete CTest runs, batch object/link execution,
staged install, installed-program execution, pkg-config where available, and two successful
uninstall invocations. A Debug build and focused integration run are also required to catch
configuration-dependent assertions; sanitizer availability is recorded but is not a support
gate for this TODO.

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
- The current test driver incorrectly uses `LD_LIBRARY_PATH` on every non-Apple host, so
  native Windows runtime loading is an expected validation target rather than assumed to
  work.
- The complete batch link driver has only a Linux-specific `-no-pie` adjustment; Mach-O and
  COFF object/link behavior must be observed on their native hosts.
- All repository presets contain Linux compiler names and `/usr/lib/llvm-22`; target-host
  commands must initially use explicit cache arguments and must not copy these presets.
- There is no CI workflow for a non-Linux host and no preserved LLVM 22 native-host log.

## Guardrails

- Do not infer Windows or macOS support from the Linux/WSL validation.
- Do not add nominal presets which have not been exercised on their target host.
- Keep platform-specific workarounds narrowly scoped and covered by tests.

## Validation Plan

- Preserve complete configure, build, CTest, install, execution, and uninstall logs for
  every supported matrix entry.
- Confirm no generated or installed path escapes the selected build or prefix.

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
