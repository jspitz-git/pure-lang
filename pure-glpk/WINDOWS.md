# pure-glpk on native Windows

The supported native Windows build uses the MSYS2 CLANG64 compiler and package
`mingw-w64-clang-x86_64-glpk` while the installed solver runs without an MSYS2
shell. The build consumes the staged Pure SDK.

## Build

Set `MSYSTEM_PREFIX=/clang64`, put `/clang64/bin` before `/usr/bin`, and point
`PKG_CONFIG_PATH` at the staged Pure SDK and `/clang64/lib/pkgconfig`. Then:

```sh
cmake -S . -B build -G Ninja \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-Wall -Wextra -Werror"
cmake --build build
cmake --build build --target verify-windows-dependencies
ctest --test-dir build --output-on-failure
```

GLPK 5.0 does not ship a pkg-config file in the CLANG64 package, so CMake
locates `glpk.h` and the GLPK import library under `MSYSTEM_PREFIX` explicitly.
GMP remains a direct dependency because the native wrapper itself uses GMP.

## Runtime closure and deduplication

The verified non-system dependency graph is:

```text
glpk.dll
  -> libpure.dll
  -> libglpk-40.dll
  -> libgmp-10.dll

libglpk-40.dll
  -> libcolamd.dll -> libsuitesparseconfig.dll -> libomp.dll
  -> libamd.dll   -> libsuitesparseconfig.dll -> libomp.dll
  -> libgmp-10.dll
  -> zlib1.dll
```

The current CLANG64 GLPK package does not import `ltdl` or an ODBC DLL. The
legacy Makefile's broader link list does not describe the actual PE runtime
closure.

`libgmp-10.dll` and `zlib1.dll` are already present in the Windows bundle.
Their staged copies have the same SHA-256 hashes as the current CLANG64 files,
so installation must reuse them rather than add conflicting copies. GLPK adds
exactly five runtime DLLs: GLPK, AMD, COLAMD, SuiteSparseConfig, and OpenMP.

The PE audit rejects MSYS, libgcc, and libstdc++ dependencies.
