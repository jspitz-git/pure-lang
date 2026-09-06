# Building pure-xml for the Windows bundle

The native module is built in the MSYS2 CLANG64 environment against the
portable Pure prefix and the official CLANG64 libxml2 and libxslt packages.
The validated versions are libxml2 2.15.3 and libxslt 1.1.45.

```sh
export PATH=/clang64/bin:/usr/bin
export PKG_CONFIG_PATH=/c/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig:/clang64/lib/pkgconfig
cmake -S /c/pure-lang/pure-xml \
  -B /c/pure-lang/pure/build/windows-clang64-xml \
  -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=/clang64/bin/clang.exe \
  -DPKG_CONFIG_EXECUTABLE=/clang64/bin/pkgconf.exe \
  -DBUILD_TESTING=ON \
  -DPURE_EXECUTABLE=/c/pure-lang/pure/build/windows-clang64-prefix/bin/pure.exe \
  -DLLVM_READOBJ_EXECUTABLE=/clang64/bin/llvm-readobj.exe
cmake --build /c/pure-lang/pure/build/windows-clang64-xml
cmake --build /c/pure-lang/pure/build/windows-clang64-xml \
  --target verify-windows-dependencies
ctest --test-dir /c/pure-lang/pure/build/windows-clang64-xml \
  -L xml --output-on-failure --no-tests=error
```

The package adds `libxml2-16.dll` and `libxslt-1.dll` to the shared bundle
runtime. Libxml2 also uses the bundle's existing `libiconv-2.dll` and
`zlib1.dll`; no duplicate copies are installed. The CLANG64 libxml2 build
provides DTD validation, XPath, XPointer, XInclude, schemas, iconv, and zlib.
It has no built-in HTTP or FTP loader feature. The automated network contract
checks those libxml2 capabilities directly; the smoke runner also clears XML
catalog settings and replaces proxy variables with an unreachable loopback
endpoint.

Libxslt 1.1.45 was compiled against the compatible libxml2 2.15 ABI. The
runtime dependency check requires AMD64 PE images and exact direct-import sets
for `xml.dll`, libxml2, libxslt, iconv, and zlib. This deliberately fails when
a package update adds a new runtime dependency, so the shared bundle closure
must be reviewed instead of being accepted accidentally.

CTest also installs the exact 17-file package manifest, compares the packaged
libxml2/libxslt DLLs with their configured inputs, overlays it on a copy of the
portable Pure prefix, and runs the installed package from `C:\Windows`. The
runner constructs a PATH containing only the staged package/runtime, Pure, and
Windows system directories; it does not inherit MSYS2 for execution.
