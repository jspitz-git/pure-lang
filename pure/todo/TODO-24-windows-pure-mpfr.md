# TODO-24 - Windows pure-mpfr Package

Status: Open
Branch: todo/24-windows-pure-mpfr

## Purpose

Build, validate, and package `pure-mpfr` with the GMP and MPFR libraries already
used by the Windows runtime.

## Scope

- Reuse the staged GMP and MPFR DLLs without duplicate copies.
- Validate precision, rounding, conversion, and exceptional values.
- Stage module sources, binaries, examples, and license material.

## Task List

1. [x] Build the module against the portable runtime.
2. [x] Confirm compatible GMP/MPFR headers and runtime DLL versions.
3. [ ] Add numerical smoke tests and staged import coverage.
4. [ ] Record the package manifest and close the TODO.

## Guardrails

- Keep one compatible copy of each shared runtime DLL in the distribution.
- Do not reduce numerical precision or change rounding semantics.

## Validation Plan

- Exercise configurable precision, all supported rounding modes, NaN, and infinity.
- Run from the installed tree with no MSYS2 directory on `PATH`.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
- 2026-07-27: Built and loaded the native module with the CLANG64 toolchain.
  - The unchanged legacy Makefile builds against the portable Pure 0.68 SDK,
    MPFR 4.2.2, and GMP 6.3.0.
  - Added a reproducible CMake module target with explicit pkg-config
    requirements for `pure>=0.68`, `mpfr>=4.2`, and GMP.
  - The resulting PE32+ x86-64 DLL exports all 38 module entry points and
    directly imports `libpure.dll`, `libmpfr-6.dll`, and `libgmp-10.dll`;
    remaining imports are Windows system DLLs and UCRT API-set contracts.
  - Validation:
    - `C:\msys64\usr\bin\bash.exe -lc "export PATH=/clang64/bin:/usr/bin; export PKG_CONFIG_PATH=/c/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig; cd /c/pure-lang/pure-mpfr; mingw32-make clean; mingw32-make CC=clang"` passed.
    - With the portable SDK in `PKG_CONFIG_PATH`, a clean Ninja configuration
      in `C:\tmp\pure-mpfr-build-step1-20260727` and
      `cmake --build ... --verbose` passed with CLANG64 Clang 22.1.8.
    - `llvm-readobj --file-headers --coff-imports --coff-exports` confirmed
      x86-64 architecture, the three nonsystem direct imports, and 38 exports.
    - From `C:\Windows`, with `PURELIB` unset and `PATH` restricted to the
      portable runtime plus Windows system directories, `pure.exe` loaded the
      CMake-built module, created an MPFR value, and emitted
      `PURE_MPFR_LOAD_OK`.
- 2026-07-27: Confirmed header, runtime, and ABI compatibility for MPFR and GMP.
  - The CLANG64 headers declare MPFR 4.2.2 and GMP 6.3.0. A compiled probe
    loaded the portable runtime DLLs and reported the same two runtime versions.
  - The GMP ABI uses 8-byte limbs with 64 value bits and no nail bits. The
    probe also exercised 128-bit MPFR initialization, parsing, conversion, and
    cleanup successfully.
  - Both staged DLLs are PE32+ x86-64. `libmpfr-6.dll` directly imports the
    staged `libgmp-10.dll`; GMP adds only Windows system and UCRT imports.
  - SHA-256 comparison showed that the staged and CLANG64 copies are identical:
    - `libmpfr-6.dll`:
      `253A0C7CC5551CC893DA7D3147736D9C568EB5C9D8466A9477D20066C330FBE7`
    - `libgmp-10.dll`:
      `3F3482CC32744FBDFA8F816E9345AB29F75DB0B14EE50FB0F429B6B7F85310E8`
  - Validation:
    - A CLANG64 probe compiled against `mpfr.h` and `gmp.h`, then ran from
      `C:\Windows` with `PATH` restricted to the portable runtime and Windows
      system directories.
    - It reported `MPFR_HEADER=MPFR_RUNTIME=4.2.2`,
      `GMP_HEADER=GMP_RUNTIME=6.3.0`, `ABI=limb:8,numb:64,prec:4,exp:4`, and
      emitted `PURE_MPFR_ABI_OK`.
    - `llvm-readobj --file-headers --coff-imports --coff-exports` confirmed both
      staged DLL architectures, the MPFR-to-GMP import, and the
      `mpfr_get_version` and `__gmp_version` exports.
