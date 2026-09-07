# Task 5 Report — Exact Toolchain, PE, and Install Contracts

Commit: this report and implementation are committed together with subject
`Enforce pure-odbc Windows package contracts`.

## Result

- Added opt-in `PURE_ODBC_STRICT_WINDOWS_AUDIT` without changing ordinary
  non-Windows or non-strict behavior.
- The strict configure accepts only the explicit Clang 22 x86-64 Windows
  compiler/target, Ninja, CLANG64 pkgconf and llvm-readobj, MSYS make, staged
  Pure executable/runtime/pkg-config directory, CLANG64 GMP/header/import
  library, and native System32 `odbc32.dll` paths.
- Exact, case-insensitive import manifests are enforced for the module and all
  13 staged PE members reached from `odbc.dll` and `pure.exe`. Every member is
  AMD64. Every non-system dependency resolves exactly once beneath staged
  `bin`; `ODBC32.dll` resolves only to the explicit native 64-bit System32
  file.
- Runtime and documentation installs have exact two-file and eight-file
  component manifests. A full portable-prefix path/SHA-256 snapshot proves the
  exact ten-file delta and preserves every baseline file byte-for-byte.
- Installed verification uses Task 4's native strict runner, with `PURELIB`
  absent and a replaced `PATH`, for the mandatory manager/enumeration/IM002
  smoke test, then runs the exact staged PE verifier.
- No ODBC manager, unixODBC/iODBC component, or known database-driver DLL may
  occur anywhere in the staged prefix. GMP and `libpure.dll` must match their
  explicit source files byte-for-byte.

## RED evidence

The three contract files were written before the corresponding production
changes. All fixture cleanup was performed by Task 4's validated `cleanup`
leaf or by removing a named regular fixture file within that leaf.

### Strict configure interface absent

```powershell
& C:/msys64/clang64/bin/cmake.exe `
  -DBINARY_DIR=C:/pure-lang/.worktrees/todo32-audit/build/task4-final-9b1248d6 `
  -DGENERATOR=Ninja -DMAKE_PROGRAM=C:/bin/ninja.exe `
  -DC_COMPILER=C:/msys64/clang64/bin/clang.exe `
  -DC_COMPILER_TARGET=x86_64-w64-windows-gnu `
  -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkgconf.exe `
  -DPKG_CONFIG_PATH=C:/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig `
  -DPURE_EXECUTABLE=C:/pure-lang/pure/build/windows-clang64-prefix/bin/pure.exe `
  -DLLVM_READOBJ_EXECUTABLE=C:/msys64/clang64/bin/llvm-readobj.exe `
  -DMSYS_MAKE_EXECUTABLE=C:/msys64/usr/bin/make.exe `
  -DGMP_RUNTIME_DLL=C:/msys64/clang64/bin/libgmp-10.dll `
  -DODBC_HEADER=C:/msys64/clang64/include/sql.h `
  -DODBC_IMPORT_LIBRARY=C:/msys64/clang64/lib/libodbc32.a `
  -DSYSTEM_ODBC_DLL=C:/Windows/System32/odbc32.dll `
  -DCLANG64_PREFIX=C:/msys64/clang64 `
  -DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=C:/Windows `
  -P pure-odbc/tests/configure_contract.cmake
```

Exact failure:

```text
CMake Error at pure-odbc/tests/configure_contract.cmake:72 (message):
  missing PURE_ODBC_CLANG64_PREFIX configuration unexpectedly succeeded
CONFIGURE_RED_EXIT=1
```

### Inclusive PE verifier

```powershell
& C:/msys64/clang64/bin/cmake.exe `
  -DBINARY_DIR=C:/pure-lang/.worktrees/todo32-audit/build/baseline `
  -DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=C:/Windows `
  -P pure-odbc/tests/runtime_verifier_contract.cmake
```

Exact failure:

```text
CMake Error at pure-odbc/tests/runtime_verifier_contract.cmake:250 (message):
  PE verifier accepted an extra import
RUNTIME_RED_EXIT=1
```

The accepted mutation was the valid additional import record
`Name: unexpected.dll` in `odbc.dll`.

### Inclusive installed-package verifier

```powershell
& C:/msys64/clang64/bin/cmake.exe `
  -DBINARY_DIR=C:/pure-lang/.worktrees/todo32-audit/build/task4-final-9b1248d6 `
  -DPORTABLE_PURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix `
  -DLLVM_READOBJ=C:/msys64/clang64/bin/llvm-readobj.exe `
  -DODBC_MODULE_SOURCE=C:/pure-lang/.worktrees/todo32-audit/build/task4-final-9b1248d6/odbc.dll `
  -DODBC_INTERFACE_SOURCE=C:/pure-lang/.worktrees/todo32-audit/pure-odbc/odbc.pure `
  -DREADME_SOURCE=C:/pure-lang/.worktrees/todo32-audit/build/task4-final-9b1248d6/README `
  -DCOPYING_SOURCE=C:/pure-lang/.worktrees/todo32-audit/pure-odbc/COPYING `
  -DCOPYING_LESSER_SOURCE=C:/pure-lang/.worktrees/todo32-audit/pure-odbc/COPYING.LESSER `
  -DWINDOWS_SOURCE=C:/pure-lang/.worktrees/todo32-audit/pure-odbc/WINDOWS.md `
  -DEXAMPLE_SOURCE=C:/pure-lang/.worktrees/todo32-audit/pure-odbc/examples/menagerie.pure `
  -DSMOKE_SOURCE=C:/pure-lang/.worktrees/todo32-audit/pure-odbc/tests/smoke.pure `
  -DPEOPLE_SOURCE=C:/pure-lang/.worktrees/todo32-audit/pure-odbc/tests/data/people.csv `
  -DSCHEMA_SOURCE=C:/pure-lang/.worktrees/todo32-audit/pure-odbc/tests/data/Schema.ini `
  -DGMP_DLL_SOURCE=C:/msys64/clang64/bin/libgmp-10.dll `
  -DPURE_RUNTIME_DLL_SOURCE=C:/pure-lang/pure/build/windows-clang64-prefix/bin/libpure.dll `
  -DRUN_PURE_TEST_EXECUTABLE=C:/pure-lang/.worktrees/todo32-audit/build/task4-final-9b1248d6/run_pure_test.exe `
  -DWINDOWS_DEPENDENCY_VERIFIER=C:/pure-lang/.worktrees/todo32-audit/pure-odbc/cmake/VerifyWindowsDependencies.cmake `
  -DWINDOWS_DIRECTORY=C:/Windows `
  -DSYSTEM_ODBC_DLL=C:/Windows/System32/odbc32.dll `
  -DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=C:/Windows `
  -P pure-odbc/tests/install_contract.cmake
```

Exact failure:

```text
CMake Error at pure-odbc/tests/install_contract.cmake:163 (message):
  Installed verifier accepted an extra file outside old ownership globs
INSTALL_RED_EXIT=1
```

The accepted mutation was
`share/task5-outside-old-globs.txt`.

## Exact PE manifests

All names below are normalized to lowercase and sorted before comparison.
System imports are accepted only when present in the exact per-file list.

```text
odbc.dll:
  api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;kernel32.dll;libgmp-10.dll;libpure.dll;odbc32.dll
pure.exe:
  api-ms-win-crt-convert-l1-1-0.dll;api-ms-win-crt-environment-l1-1-0.dll;api-ms-win-crt-filesystem-l1-1-0.dll;api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-locale-l1-1-0.dll;api-ms-win-crt-math-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;kernel32.dll;libc++.dll;libpure.dll;libreadline8.dll
libpure.dll:
  advapi32.dll;api-ms-win-crt-convert-l1-1-0.dll;api-ms-win-crt-environment-l1-1-0.dll;api-ms-win-crt-filesystem-l1-1-0.dll;api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-locale-l1-1-0.dll;api-ms-win-crt-math-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-process-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;api-ms-win-crt-time-l1-1-0.dll;api-ms-win-crt-utility-l1-1-0.dll;kernel32.dll;libc++.dll;libgmp-10.dll;libiconv-2.dll;libmpfr-6.dll;libpcreposix-0.dll;libwinpthread-1.dll;libzstd.dll;ntdll.dll;ole32.dll;shell32.dll;zlib1.dll
libc++.dll:
  api-ms-win-crt-convert-l1-1-0.dll;api-ms-win-crt-environment-l1-1-0.dll;api-ms-win-crt-filesystem-l1-1-0.dll;api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-locale-l1-1-0.dll;api-ms-win-crt-math-l1-1-0.dll;api-ms-win-crt-multibyte-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;api-ms-win-crt-time-l1-1-0.dll;api-ms-win-crt-utility-l1-1-0.dll;kernel32.dll
libgmp-10.dll:
  api-ms-win-crt-convert-l1-1-0.dll;api-ms-win-crt-environment-l1-1-0.dll;api-ms-win-crt-filesystem-l1-1-0.dll;api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-locale-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;api-ms-win-crt-time-l1-1-0.dll;api-ms-win-crt-utility-l1-1-0.dll;kernel32.dll
libiconv-2.dll:
  api-ms-win-crt-convert-l1-1-0.dll;api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-locale-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;api-ms-win-crt-utility-l1-1-0.dll;kernel32.dll
libmpfr-6.dll:
  api-ms-win-crt-convert-l1-1-0.dll;api-ms-win-crt-filesystem-l1-1-0.dll;api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-locale-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;api-ms-win-crt-utility-l1-1-0.dll;kernel32.dll;libgmp-10.dll
libpcre-1.dll:
  api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;api-ms-win-crt-utility-l1-1-0.dll;kernel32.dll
libpcreposix-0.dll:
  api-ms-win-crt-convert-l1-1-0.dll;api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-locale-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;api-ms-win-crt-utility-l1-1-0.dll;kernel32.dll;libpcre-1.dll
libreadline8.dll:
  api-ms-win-crt-convert-l1-1-0.dll;api-ms-win-crt-environment-l1-1-0.dll;api-ms-win-crt-filesystem-l1-1-0.dll;api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-locale-l1-1-0.dll;api-ms-win-crt-math-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;api-ms-win-crt-utility-l1-1-0.dll;kernel32.dll;libtermcap-0.dll;user32.dll
libtermcap-0.dll:
  api-ms-win-crt-convert-l1-1-0.dll;api-ms-win-crt-environment-l1-1-0.dll;api-ms-win-crt-filesystem-l1-1-0.dll;api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-locale-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;api-ms-win-crt-time-l1-1-0.dll;kernel32.dll
libwinpthread-1.dll:
  api-ms-win-crt-convert-l1-1-0.dll;api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;api-ms-win-crt-utility-l1-1-0.dll;kernel32.dll
libzstd.dll:
  api-ms-win-crt-convert-l1-1-0.dll;api-ms-win-crt-filesystem-l1-1-0.dll;api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-locale-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;api-ms-win-crt-time-l1-1-0.dll;api-ms-win-crt-utility-l1-1-0.dll;kernel32.dll
zlib1.dll:
  api-ms-win-crt-convert-l1-1-0.dll;api-ms-win-crt-heap-l1-1-0.dll;api-ms-win-crt-locale-l1-1-0.dll;api-ms-win-crt-private-l1-1-0.dll;api-ms-win-crt-runtime-l1-1-0.dll;api-ms-win-crt-stdio-l1-1-0.dll;api-ms-win-crt-string-l1-1-0.dll;api-ms-win-crt-utility-l1-1-0.dll;kernel32.dll
```

`odbc32.dll` is deliberately not given a version-sensitive import manifest,
because it is an operating-system component. Its canonical path must be
`<OS Windows directory>/System32/odbc32.dll`, its PE header must be AMD64, and
no staged ODBC manager may shadow it.

## Exact install manifests

Runtime component (2):

```text
lib/pure/odbc.dll
lib/pure/odbc.pure
```

Documentation component (8), complete package ownership delta (10):

```text
share/doc/pure-odbc/README
share/doc/pure-odbc/COPYING
share/doc/pure-odbc/COPYING.LESSER
share/doc/pure-odbc/WINDOWS.md
share/doc/pure-odbc/examples/menagerie.pure
share/doc/pure-odbc/tests/smoke.pure
share/doc/pure-odbc/tests/data/people.csv
share/doc/pure-odbc/tests/data/Schema.ini
```

The install contract validates CMake's generated
`install_manifest_runtime.txt` and
`install_manifest_documentation.txt` against those sets before evaluating the
full prefix delta.

## GREEN evidence

### Fresh strict Release configure

The build directory `build/task5-final-00910e28` did not exist before this
command.

```powershell
& C:/msys64/clang64/bin/cmake.exe `
  -S pure-odbc -B build/task5-final-00910e28 -G Ninja `
  -DCMAKE_MAKE_PROGRAM=C:/bin/ninja.exe `
  -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe `
  -DCMAKE_C_COMPILER_TARGET=x86_64-w64-windows-gnu `
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON `
  -DPURE_ODBC_STRICT_WINDOWS_AUDIT=ON `
  -DPURE_ODBC_CLANG64_PREFIX=C:/msys64/clang64 `
  -DPURE_ODBC_PKG_CONFIG_PATH=C:/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig `
  -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkgconf.exe `
  -DPURE_EXECUTABLE=C:/pure-lang/pure/build/windows-clang64-prefix/bin/pure.exe `
  -DPURE_RUNTIME_DLL=C:/pure-lang/pure/build/windows-clang64-prefix/bin/libpure.dll `
  -DLLVM_READOBJ_EXECUTABLE=C:/msys64/clang64/bin/llvm-readobj.exe `
  -DPURE_ODBC_MAKE_EXECUTABLE=C:/msys64/usr/bin/make.exe `
  -DGMP_RUNTIME_DLL=C:/msys64/clang64/bin/libgmp-10.dll `
  -DODBC_HEADER=C:/msys64/clang64/include/sql.h `
  -DODBC_IMPORT_LIBRARY=C:/msys64/clang64/lib/libodbc32.a `
  -DSYSTEM_ODBC_DLL=C:/Windows/System32/odbc32.dll
```

```text
-- The C compiler identification is Clang 22.1.8
-- Found PkgConfig: C:/msys64/clang64/bin/pkgconf.exe (found version "3.0.4")
-- Found pure, version 0.68
-- Found gmp, version 6.3.0
-- Configuring done (8.8s)
-- Generating done (0.1s)
```

### Exact four-worker build and PE target

```powershell
& C:/msys64/clang64/bin/cmake.exe `
  --build build/task5-final-00910e28 --parallel 4
& C:/msys64/clang64/bin/cmake.exe `
  --build build/task5-final-00910e28 `
  --target verify-windows-dependencies --parallel 4
```

```text
[1/6] Building C object CMakeFiles/pure-odbc-run-pure-test-alternate.dir/tests/run_pure_test.c.obj
[2/6] Building C object CMakeFiles/pure-odbc-run-pure-test.dir/tests/run_pure_test.c.obj
[3/6] Linking C executable run_pure_test_alternate.exe
[4/6] Linking C executable run_pure_test.exe
[5/6] Building C object CMakeFiles/odbc.dir/odbc.c.obj
[6/6] Linking C shared module odbc.dll
[1/1] Verifying the exact pure-odbc Windows dependency closure
-- Verified exact pure-odbc PE imports and recursive AMD64 closure for 14 staged binaries; ODBC32 resolves only to C:/Windows/System32/odbc32.dll
```

### Complete strict test suite

```powershell
& C:/msys64/clang64/bin/ctest.exe `
  --test-dir build/task5-final-00910e28 `
  --output-on-failure --no-tests=error
```

```text
1/7 pure-odbc-manager-smoke ............... Passed    6.26 sec
2/7 pure-odbc-access-text-smoke ........... Passed    4.46 sec
3/7 pure-odbc-runner-contract ............. Passed   77.29 sec
4/7 pure-odbc-cleanup-contract ............ Passed    5.27 sec
5/7 pure-odbc-configure-contract .......... Passed   61.19 sec
6/7 pure-odbc-runtime-verifier-contract ... Passed   83.00 sec
7/7 pure-odbc-install-contract ............ Passed  133.54 sec
100% tests passed out of 7
Total Test time (real) = 371.04 sec
```

After strengthening the non-x86-64 fixture so it reaches the project's target
check instead of failing in CMake's compiler probe, its covering test was run
again:

```powershell
& C:/msys64/clang64/bin/ctest.exe `
  --test-dir build/task5-final-00910e28 `
  -R '^pure-odbc-configure-contract$' `
  --output-on-failure --no-tests=error
```

```text
1/1 Test #5: pure-odbc-configure-contract ..... Passed   60.82 sec
100% tests passed out of 1
```

Contract case counts are 37 rejected configure mutations plus one positive
configure, 15 rejected PE mutations plus two pristine full-closure passes, and
10 rejected install mutations plus two pristine installed-package passes.

### Non-strict compatibility

```powershell
& C:/msys64/clang64/bin/cmake.exe -E env `
  MSYSTEM_PREFIX=C:/msys64/clang64 `
  PKG_CONFIG_PATH=C:/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig `
  C:/msys64/clang64/bin/cmake.exe `
  -S pure-odbc -B build/task5-nonstrict-compat -G Ninja `
  -DCMAKE_MAKE_PROGRAM=C:/bin/ninja.exe `
  -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe `
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON `
  -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkgconf.exe `
  -DPURE_EXECUTABLE=C:/pure-lang/pure/build/windows-clang64-prefix/bin/pure.exe `
  -DPURE_RUNTIME_DLL=C:/pure-lang/pure/build/windows-clang64-prefix/bin/libpure.dll `
  -DLLVM_READOBJ_EXECUTABLE=C:/msys64/clang64/bin/llvm-readobj.exe `
  -DGMP_RUNTIME_DLL=C:/msys64/clang64/bin/libgmp-10.dll `
  -DPURE_ODBC_MAKE_EXECUTABLE=C:/msys64/usr/bin/make.exe
& C:/msys64/clang64/bin/cmake.exe `
  --build build/task5-nonstrict-compat --parallel 4
```

Result: configure completed in 4.2 seconds and all six build edges completed.

## Self-review

- Strict mode performs no `find_*` lookup for the compiler, generator,
  pkgconf, llvm-readobj, make, Pure, Pure runtime, GMP runtime, ODBC header,
  ODBC import library, or System32 ODBC manager. Every accepted path is regular,
  canonical, non-reparse, and compared to its audited origin.
- The explicit `sql.h` parent also must contain a regular, non-reparse
  CLANG64 `sqlext.h`. The GMP pkg-config prefix must equal CLANG64, while Pure
  pkg-config, `pure.exe`, and `libpure.dll` must agree on the staged Pure SDK.
- The parser requires exactly one COFF-x86-64 file/format/arch/address/machine
  header, one `Name` for every recognized `Import` or `DelayImport`, valid DLL
  names, and no duplicate or unknown import records. Exact mismatch diagnostics
  contain file, expected, actual, missing, and unexpected sets.
- The PE resolver seeds both `odbc.dll` and `pure.exe`, uses only exact
  case-folded filenames beneath staged `bin` for non-system dependencies, and
  fails on zero or duplicate resolution.
- The baseline manifest rejects malformed hashes, unsafe paths, and duplicate
  case-folded records. Component manifests reject paths outside the stage and
  duplicate records. Owned artifact hashes are compared to their source/build
  files after exact delta and baseline preservation checks.
- `Install.cmake` uses named files for the example and two data fixtures; no
  directory glob can silently expand the package.
- The three new contracts share Task 4's validated `cleanup` leaf and are
  `RUN_SERIAL`. Their only recursive reset is the helper's sentinel-protected
  reset. Every direct removal names one regular fixture file under that leaf.
- `git diff --check` reported no whitespace errors; only informational
  LF-to-CRLF warnings were emitted by Git on Windows.

## Concerns

- The exact staged import manifests intentionally bind this audit to the
  current Pure/CLANG64 runtime. A toolchain or staged SDK upgrade must be
  re-audited and update the literal manifests.
- System `odbc32.dll` is path- and architecture-checked but its own imports are
  not version-pinned, because Windows servicing may legitimately change that
  OS-owned implementation.
- The Codex sandbox cannot create the MSYS make signal pipe and can stall
  CMake's Ninja/Clang child detection. Required configure/build/CTest commands
  therefore ran outside that wrapper with the user's already-approved local
  CMake/CTest prefixes. They used no network and wrote only the designated
  worktree/build leaves.
