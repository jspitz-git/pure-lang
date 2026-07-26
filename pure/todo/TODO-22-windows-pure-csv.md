# TODO-22 - Windows pure-csv Package

Status: Open
Branch: todo/22-windows-pure-csv

## Purpose

Build, validate, and package `pure-csv` for the portable Windows distribution.

## Scope

- Port the native component to the supported CLANG64 toolchain where necessary.
- Stage the module, Pure sources, examples, runtime DLLs, and licenses.
- Cover Windows text, newline, quoting, and path behavior.

## Task List

1. [x] Configure and build the native module on Windows.
2. [ ] Resolve and document its complete runtime dependency set.
3. [ ] Add CSV read/write and error-handling smoke tests.
4. [ ] Validate the staged package outside MSYS2.

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
