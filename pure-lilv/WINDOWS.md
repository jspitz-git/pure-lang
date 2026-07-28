# pure-lilv on Windows

The Windows package uses a native CLANG64 build of Lilv 0.26.4 with Dynamic
Manifest support enabled. This differs from the stock MSYS2 Lilv package,
whose upstream Meson option leaves that feature disabled.

The `lilv::world` operation preserves the usual Lilv discovery behavior.
Use `lilv::world_at path` for a self-contained application or deterministic
test. It sets Lilv's application-specific search option and does not modify
the process or machine-wide `LV2_PATH`. Separate multiple Windows paths with
semicolons.

The bundle installs the LV2 specification bundles below `lib/lv2`. Third-party
plugins are not bundled. Windows LV2 plugins must contain native DLL binaries;
plugins built for Linux or macOS cannot be loaded.

The package includes a controlled static plugin and Dynamic Manifest generator
under its documentation directory. They are validation fixtures, are not on
the default discovery path, and must not be presented as compatibility proof
for arbitrary third-party plugins.

## Build, test, and stage

Run the build from an MSYS2 CLANG64 shell. Point `PKG_CONFIG_PATH` at the
portable Pure SDK and the CLANG64 packages:

```sh
export PKG_CONFIG_PATH=C:/path/to/pure-prefix/lib/pkgconfig:/clang64/lib/pkgconfig
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build build
ctest --test-dir build --output-on-failure
cmake --build build --target verify-windows-dependencies
```

Copy the portable Pure runtime to a fresh prefix before installing this
package. The verifier checks the exact LV2 specification and license
inventories, reused runtime hashes, both controlled plugin types, and the
staged PE closure with `PURELIB` and `LV2_PATH` unset:

```sh
cmake --install build --prefix C:/tmp/pure-lilv-stage
cmake -DSTAGE_PREFIX=C:/tmp/pure-lilv-stage \
  -DSOURCE_RUNTIME_DIR=C:/path/to/pure-runtime/bin \
  -DLLVM_READOBJ=/clang64/bin/llvm-readobj.exe \
  -P cmake/VerifyInstalledPackage.cmake
```

Repeat the verifier after copying the installed tree to a different path to
validate relocation. At run time the bundle needs only its own `bin`,
`lib/pure`, and `lib/lv2` trees plus Windows system directories on `PATH`.
