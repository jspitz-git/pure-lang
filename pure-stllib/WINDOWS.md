# Building pure-stllib for the Windows bundle

The native modules are built in the MSYS2 CLANG64 environment with CMake,
Clang and libc++. Configure the package against the portable Pure prefix:

```sh
export PATH=/clang64/bin:/usr/bin
export PKG_CONFIG_PATH=/c/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig:/clang64/lib/pkgconfig
cmake -S /c/pure-lang/pure-stllib \
  -B /c/pure-lang/pure/build/windows-clang64-stllib \
  -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_COMPILER=clang++
cmake --build /c/pure-lang/pure/build/windows-clang64-stllib
cmake --build /c/pure-lang/pure/build/windows-clang64-stllib \
  --target verify-windows-runtime
```

The six package DLLs must use the same `libc++.dll` as the rest of the
portable Windows bundle. The package does not install another C++ runtime.
Its only non-system runtime dependencies are `libpure.dll`, `libc++.dll` and
the package DLLs themselves: `stlvec`, `stlmap`, `stlmmap` and `stlhmap`
depend on `stlbase`, while `stlalgorithm` depends on both `stlbase` and
`stlvec`.
