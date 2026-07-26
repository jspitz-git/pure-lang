# TODO-22 - Windows pure-csv Package

Status: Closed on 2026-07-26
Branch: todo/22-windows-pure-csv

## Purpose

Build, validate, and package `pure-csv` for the portable Windows distribution.

## Scope

- Port the native component to the supported CLANG64 toolchain where necessary.
- Stage the module, Pure sources, examples, runtime DLLs, and licenses.
- Cover Windows text, newline, quoting, and path behavior.

## Task List

1. [x] Configure and build the native module on Windows.
2. [x] Resolve and document its complete runtime dependency set.
3. [x] Add CSV read/write and error-handling smoke tests.
4. [x] Validate the staged package outside MSYS2.

## Installed Package Manifest

- `lib/pure/csv.dll`
- `lib/pure/csv.pure`
- `share/doc/pure-csv/README`
- `share/doc/pure-csv/COPYING`

The installed README contains the package's user examples with the version and
build date expanded. The existing portable runtime supplies the twelve DLLs
listed below; `pure-csv` does not duplicate them in its package manifest.

## Runtime Dependencies

- `csv.pure` dynamically loads the package module `csv.dll`.
- `csv.dll` directly imports only `libpure.dll` from the bundle. Its remaining
  direct imports are `KERNEL32.dll` and Windows UCRT API-set contracts for
  conversion, heap, private CRT, runtime, standard I/O, and strings.
- The complete bundled DLL closure for `pure.exe` plus `csv.dll` is:
  `libc++.dll`, `libgmp-10.dll`, `libiconv-2.dll`, `libmpfr-6.dll`,
  `libpcre-1.dll`, `libpcreposix-0.dll`, `libpure.dll`, `libreadline8.dll`,
  `libtermcap-0.dll`, `libwinpthread-1.dll`, `libzstd.dll`, and `zlib1.dll`.
- All twelve DLLs are already part of the portable Pure runtime. The CSV package
  adds no third-party native runtime dependency.
- Other transitive imports resolve to Windows system DLLs or Windows API-set
  contracts; no unresolved nonsystem import remains.

## Guardrails

- Preserve CSV behavior across supported hosts.
- Do not rely on the current working directory for module or data lookup.

## Validation Plan

- Round-trip quoted, multiline, empty, and Unicode fields.
- Exercise files in a path containing spaces with a sanitized `PATH`.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
- 2026-07-26: Configured and built the native CSV module with CLANG64.
  - The first legacy Makefile build exposed a public SDK layout defect:
    `pure/runtime.h` includes `<glob.h>`, but the Windows compatibility headers
    had been installed below `include/pure` while `pure.pc` only publishes
    `include`.
  - The Windows Pure SDK now installs `glob.h` and `fnmatch.h` in the public
    include root. A clean SDK prefix contains those two headers plus
    `include/pure/runtime.h`, with no stale copies below `include/pure`.
  - Added a CMake build for `csv.dll` using `pure>=0.68` through pkg-config and
    explicit automatic exports on Windows. The legacy Makefile build also
    succeeds against the corrected SDK.
  - Validation:
    - `C:\msys64\usr\bin\bash.exe -lc "export PATH=/clang64/bin:/usr/bin; export PKG_CONFIG_PATH=/c/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig; cd /c/pure-lang/pure-csv; mingw32-make clean; mingw32-make CC=clang"` initially failed because `<glob.h>` was not reachable.
    - `C:\msys64\clang64\bin\cmake.exe --install C:\pure-lang\pure\build\windows-clang64-release --prefix C:\tmp\pure-csv-sdk-step1-20260726` installed the corrected SDK layout.
    - With `PKG_CONFIG_PATH=C:\tmp\pure-csv-sdk-step1-20260726\lib\pkgconfig`, the same `mingw32-make CC=clang` command passed.
    - `C:\msys64\clang64\bin\cmake.exe -S C:\pure-lang\pure-csv -B C:\tmp\pure-csv-build-step1-final-20260726 -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkg-config.exe` and `C:\msys64\clang64\bin\cmake.exe --build C:\tmp\pure-csv-build-step1-final-20260726 --verbose` passed.
    - `C:\msys64\clang64\bin\llvm-readobj.exe --file-headers --coff-imports --coff-exports C:\tmp\pure-csv-build-step1-final-20260726\csv.dll` reported COFF x86-64 and exports for `csv_open`, `csv_close`, `csv_read`, `csv_write`, and `csv_getheader`.
    - With `PURELIB` unset and `PATH` limited to the staged runtime and Windows
      system directories, staged `pure.exe --norc -I C:\pure-lang\pure-csv -L C:\tmp\pure-csv-build-step1-final-20260726 -x C:\tmp\pure-csv-load-step1-20260726.pure` loaded the module and exited with status 0.
- 2026-07-26: Resolved the complete Windows runtime dependency closure.
  - The CSV DLL adds only a direct dependency on the existing `libpure.dll`;
    its C runtime imports use Windows UCRT API-set contracts.
  - A recursive PE import walk starting from both `pure.exe` and `csv.dll`
    reached exactly the twelve DLLs already staged by the portable Pure runtime.
  - Validation:
    - `C:\msys64\clang64\bin\llvm-readobj.exe --coff-imports C:\tmp\pure-csv-build-step1-final-20260726\csv.dll` reported `libpure.dll`, `KERNEL32.dll`, and six UCRT API-set contracts as the complete direct import set.
    - Applying the same command recursively to each bundled import produced the
      twelve-file closure documented above, found zero unresolved nonsystem
      imports, and left zero staged DLLs outside the `pure.exe + csv.dll`
      static-import walk.
- 2026-07-26: Added focused CSV round-trip, newline, and error smoke tests.
  - The first raw-byte probe exposed Windows CRT text translation: explicit LF
    was written as CRLF and explicit CRLF as invalid `CR CR LF`.
  - Windows CSV streams now use binary mode, and `_WIN32` selects CRLF only for
    the native default. Explicit LF and CRLF terminators are preserved byte for
    byte without changing non-Windows behavior.
  - The smoke test round-trips quoted delimiters and quotes, multiline, empty,
    leading/trailing-space, Czech Unicode, and emoji fields. It also checks raw
    LF, CRLF, and native newline bytes plus malformed-input and invalid-mode
    errors.
  - The CTest runner feeds the script through stdin and requires an explicit
    success marker, because the interpreter can return status 0 after a Pure
    syntax error.
  - Validation:
    - With `PKG_CONFIG_PATH=C:\tmp\pure-csv-sdk-step1-20260726\lib\pkgconfig`, `C:\msys64\clang64\bin\cmake.exe -S C:\pure-lang\pure-csv -B "C:\tmp\pure csv smoke build step3 20260726" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkg-config.exe -DPURE_EXECUTABLE=C:\tmp\pure-csv-sdk-step1-20260726\bin\pure.exe` and `C:\msys64\clang64\bin\cmake.exe --build "C:\tmp\pure csv smoke build step3 20260726" --verbose` passed.
    - With `PURELIB` unset and `PATH` limited to the staged runtime and Windows
      system directories, `C:\msys64\clang64\bin\ctest.exe --test-dir "C:\tmp\pure csv smoke build step3 20260726" --output-on-failure` passed 1/1 test in 6.43 seconds.
    - Raw-byte inspection found `0A` for explicit LF and `0D 0A` for both
      explicit CRLF and the native Windows default, with no doubled `CR`.
    - Running the CMake test runner with a syntactically invalid Pure script
      failed on the missing success marker as expected.
- 2026-07-26: Staged and validated the complete portable Windows package.
  - Prefix-contained CMake install rules add only `csv.dll`, `csv.pure`, the
    versioned README with its user examples, and `COPYING`; absolute paths and
    parent traversals are rejected.
  - The package was installed into a fresh copy of the portable runtime in a
    path containing spaces. A literal scan found no source, build, temporary,
    CLANG64, or MSYS2 prefix in any package file.
  - The final smoke run uses staged `csv.pure` and `csv.dll`, an explicit data
    directory, and a marker-checked stdin runner. This supersedes the weaker
    step-1 `-x` load probe, whose status alone cannot detect Pure syntax errors.
  - Validation:
    - With `PKG_CONFIG_PATH=C:\tmp\pure-csv-sdk-step1-20260726\lib\pkgconfig`, `C:\msys64\clang64\bin\cmake.exe -S C:\pure-lang\pure-csv -B "C:\tmp\pure csv package build step4 20260726" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkg-config.exe -DPURE_EXECUTABLE="C:\tmp\Pure CSV portable package step4 20260726\bin\pure.exe" -DCMAKE_INSTALL_PREFIX="C:\tmp\Pure CSV portable package step4 20260726"`, `cmake --build`, and `cmake --install` passed.
    - Comparing the copied runtime before and after installation found exactly
      the four relative paths in the installed package manifest. The installed
      README header is `Version 1.6, July 26, 2026` and contains no unexpanded
      placeholder.
    - Configuring with `PURE_LIBRARY_INSTALL_DIR=../escape` failed with the
      expected prefix-containment diagnostic.
    - From `C:\Windows`, with `PURELIB` unset and `PATH` restricted to the staged
      `bin` and Windows system directories, `C:\msys64\clang64\bin\cmake.exe -DPURE_EXECUTABLE="C:\tmp\Pure CSV portable package step4 20260726\bin\pure.exe" -DPURE_SOURCE_DIR="C:\tmp\Pure CSV portable package step4 20260726\lib\pure" -DPURE_MODULE_DIR="C:\tmp\Pure CSV portable package step4 20260726\lib\pure" -DTEST_SCRIPT=C:\pure-lang\pure-csv\tests\smoke.pure -DTEST_DIRECTORY="C:\tmp\Pure CSV cwd-independent smoke data step4 20260726" -DNATIVE_NEWLINE=CRLF -P C:\pure-lang\pure-csv\cmake\RunSmokeTest.cmake` passed.
