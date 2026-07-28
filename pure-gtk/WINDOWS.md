# Building pure-gtk on Windows

The supported Windows build uses the MSYS2 CLANG64 GTK 2 stack and the
portable Pure prefix. Configure and build from a CLANG64 shell:

```sh
export PKG_CONFIG_PATH=/path/to/pure-prefix/lib/pkgconfig:/clang64/lib/pkgconfig
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
cmake --build build --target verify-windows-dependencies
```

The package builds the `gtk`, `glib`, `atk`, `cairo`, and `pango` modules.
Windows PE modules do not expose symbols from their dependencies in the same
way as ELF shared objects, so the Pure sources explicitly load the applicable
runtime DLLs. `gtk.dll` also exports aliases for GTK functions which the
Windows headers redirect to UTF-8 implementations.

The optional Pure GUI callback test requires an already built `pure-ffi`:

```sh
cmake -S . -B build \
  -DPURE_FFI_SOURCE_DIR=/path/to/pure-ffi \
  -DPURE_FFI_MODULE_DIR=/path/to/pure-ffi-build
ctest --test-dir build -R 'pure-gtk-(windows-gui|gui-smoke)' \
  --output-on-failure
```

Installation includes the complete PE dependency closure, GdkPixbuf loaders,
GTK engines and accessibility module, themes, icons, and Fontconfig data. The
installed GdkPixbuf cache is a relocatable template. On first load, `gtk.dll`
materializes an absolute cache below the user's temporary directory, keyed by
the current bundle prefix, and configures GTK, GdkPixbuf, and Fontconfig paths
for that process. A portable bundle must keep the installed `bin`, `lib`,
`etc`, and `share` directories together; no MSYS2 environment variables are
required at run time.

GTK 2 is retained for compatibility with the existing Pure bindings. New
applications should avoid adding new GTK 2-only dependencies.
