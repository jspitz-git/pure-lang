# pure-gsl on native Windows

The supported native Windows build uses the MSYS2 CLANG64 toolchain while the
installed program runs without an MSYS2 shell. It is built against the staged
Pure SDK and the official `mingw-w64-clang-x86_64-gsl` package.

## Build

Set `PATH` so that `/clang64/bin` precedes `/usr/bin`, and point
`PKG_CONFIG_PATH` at the staged Pure SDK and `/clang64/lib/pkgconfig`. Then run:

```sh
cmake -S . -B build -G Ninja \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-Wall -Wextra -Werror"
cmake --build build
cmake --build build --target verify-windows-dependencies
ctest --test-dir build --output-on-failure
```

The Windows runtime ABI validated by this package is GSL 2.8:

- `gsl.dll` imports `libpure.dll` and `libgsl-28.dll`;
- `libgsl-28.dll` imports `libgslcblas-0.dll`;
- neither GSL DLL nor the Pure module may import `msys-2.0.dll`, `libgcc`, or
  `libstdc++`.

The bundle must therefore place `libgsl-28.dll` and `libgslcblas-0.dll` next to
`pure.exe`. Both come from the same MSYS2 CLANG64 GSL package.

## Module inventory

The package installs `gsl.pure`, `gsl.dll`, and every module shipped below the
`gsl` namespace:

- `common`, `utils`, `matrix`, `sort`, `randist`;
- `stats`, `poly`, `fit`, `sf`, `complex`.

The umbrella `gsl.pure` advertises matrix and SVD operations, sorting, random
distributions and statistics, polynomial evaluation and roots, linear fitting,
and special functions. The experimental `gsl::complex` module is installed and
validated separately because it is not imported by the umbrella module.

This release does not contain a numerical-integration module or a general
nonlinear root solver. Tests cover all implemented and advertised numerical
families; “roots” means the polynomial-root API provided by `gsl::poly`.

Numerical smoke tests use explicit absolute tolerances. They are behavioral
checks, not bit-for-bit floating-point comparisons.
