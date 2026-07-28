# Windows build and runtime notes

The supported Windows build uses MSYS2 CLANG64 only as a build environment.
It downloads the official liblo 0.36 source archive, verifies SHA-256
`c08d14832e8dcf8f06840405824a4f9611a0cb3daed0198946326c740941c8b6`,
and builds a shared `liblo.dll` with native Winsock and threading support.

The Pure wrapper is built as `lo.dll`. Its only package-specific runtime
delta is `liblo.dll`. It reuses the bundle's `libpure.dll` and
`libgmp-10.dll`; Windows networking, IP Helper, UCRT, and other system DLLs
are never copied. Neither binary imports an MSYS, GCC, or C++ runtime.

All automated OSC traffic is restricted to IPv4 loopback. Tests use bounded
timeouts and must stop and free server threads before exiting.

## Build and test

Run these commands from an MSYS2 CLANG64 shell after setting
`PKG_CONFIG_PATH` to the staged Pure SDK's `lib/pkgconfig` directory:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DBUILD_TESTING=ON
cmake --build build
cmake --build build --target verify-windows-dependencies
ctest --test-dir build --output-on-failure
```

To validate the installed package, first copy the portable Pure runtime to a
fresh staging prefix, then install and verify pure-liblo:

```sh
cmake --install build --prefix C:/tmp/pure-liblo-stage
cmake -DSTAGE_PREFIX=C:/tmp/pure-liblo-stage \
  -DSOURCE_RUNTIME_DIR=C:/path/to/pure-runtime/bin \
  -DLLVM_READOBJ=/clang64/bin/llvm-readobj.exe \
  -P cmake/VerifyInstalledPackage.cmake
```

The installed verifier clears `PURELIB`, restricts `PATH` to the staged
`bin` directory and Windows system directories, reruns the bounded loopback
test, checks the reused Pure/GMP DLL hashes, and audits the staged PE imports.
