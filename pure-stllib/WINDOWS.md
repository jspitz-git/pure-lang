# Building pure-stllib for the Windows bundle

The native modules are built in the MSYS2 CLANG64 environment with CMake,
Clang and libc++. The resulting package uses the portable Pure runtime and
does not require an MSYS2 installation at run time. Configure it with explicit
paths to the installed interpreter and PE inspection tool:

```sh
repo=/c/path/to/pure-lang
pure_prefix="$repo/pure/build/windows-clang64-prefix"
build="$repo/pure/build/windows-clang64-stllib"
export PATH=/clang64/bin:/usr/bin
export PKG_CONFIG_PATH="$pure_prefix/lib/pkgconfig:/clang64/lib/pkgconfig"
cmake -S "$repo/pure-stllib" -B "$build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_COMPILER=/clang64/bin/clang++ \
  -DPKG_CONFIG_EXECUTABLE=/clang64/bin/pkgconf \
  -DPURE_EXECUTABLE="$pure_prefix/bin/pure.exe" \
  -DLLVM_READOBJ_EXECUTABLE=/clang64/bin/llvm-readobj \
  -DBUILD_TESTING=ON
cmake --build "$build" --parallel 4
cmake --build "$build" \
  --target verify-windows-runtime
ctest --test-dir "$build" -L stllib --output-on-failure --no-tests=error
```

The validation builds all six modules with C++17 and
`-Wall -Wextra -Wpedantic -Werror`. It checks their exact AMD64 PE import
sets, including the shared `libc++.dll` and the internal module graph.
The package does not install another C++ runtime.

The CTest contract runs every vector, numeric, map, multimap, hash-map, set,
iterator and lifetime suite. Parser and runtime diagnostics on stderr fail the
test. The current Pure JIT can emit the narrowly recognized
`libunwind: pc not in table` diagnostic for callbacks; the runner counts and
reports only that known form.

The install contract verifies the exact 42-file package manifest, rejects
source/build/MSYS2 path leakage, copies the portable Pure runtime, installs the
package into that copy, poisons inherited `PURELIB`, sanitizes `PATH`, and
runs both installed suites from the Windows directory.
