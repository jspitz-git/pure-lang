# TODO-23 - Windows pure-ffi Package

Status: Open
Branch: todo/23-windows-pure-ffi

## Purpose

Build and validate `pure-ffi` with the Windows x86_64 calling conventions used by
the portable runtime.

## Scope

- Use the CLANG64 `libffi` package and bundle its required runtime files.
- Validate scalar, pointer, structure, callback, and library-loading behavior.
- Install the module and examples in the common distribution layout.

## Task List

1. [x] Build the module against the staged Pure runtime and CLANG64 `libffi`.
2. [ ] Audit calling-convention and symbol-loading assumptions.
3. [ ] Add native-call and callback smoke tests.
4. [ ] Stage and validate the package outside MSYS2.

## Guardrails

- Do not mix MSVC and MinGW C++ ABIs across the module boundary.
- Treat callback crashes or silent ABI corruption as release blockers.

## Validation Plan

- Call a known Win32 or bundled C function through FFI.
- Exercise a callback into Pure and inspect the staged PE dependencies.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
- 2026-07-26: Built and loaded the native module with the CLANG64 toolchain.
  - The legacy Makefile builds unchanged against the corrected portable Pure
    SDK, CLANG64 `libffi` 3.7.1, and GMP 6.3.0.
  - Added a reproducible CMake target with explicit pkg-config requirements for
    `pure>=0.68`, `libffi>=3.4`, and GMP. MinGW auto-import is retained for the
    exported `libffi` type objects used by the module.
  - The resulting PE32+ x86-64 DLL exports 44 module symbols and directly
    imports `libpure.dll`, `libffi-8.dll`, and `libgmp-10.dll`.
  - Validation:
    - `C:\msys64\usr\bin\bash.exe -lc "export PATH=/clang64/bin:/usr/bin; export PKG_CONFIG_PATH=/c/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig; cd /c/pure-lang/pure-ffi; mingw32-make clean; mingw32-make CC=clang"` passed.
    - With `PKG_CONFIG_PATH=C:\pure-lang\pure\build\windows-clang64-prefix\lib\pkgconfig`, `C:\msys64\clang64\bin\cmake.exe -S C:\pure-lang\pure-ffi -B C:\tmp\pure-ffi-build-step1-20260726 -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkg-config.exe` and `C:\msys64\clang64\bin\cmake.exe --build C:\tmp\pure-ffi-build-step1-20260726 --verbose` passed.
    - `C:\msys64\clang64\bin\llvm-readobj.exe --file-headers --coff-imports --coff-exports C:\tmp\pure-ffi-build-step1-20260726\ffi.dll` reported COFF x86-64, the three nonsystem direct imports above, and 44 exports.
    - With `PURELIB` unset and `PATH` limited to the portable runtime,
      `C:\msys64\clang64\bin`, and Windows system directories, the staged
      interpreter loaded `ffi.pure` plus the CMake-built `ffi.dll` and emitted a
      marker-checked success result.
  - `libffi-8.dll` still comes from the CLANG64 PATH in this build-only step;
    its explicit staging and the MSYS2-independent run remain tasks 2 and 4.
