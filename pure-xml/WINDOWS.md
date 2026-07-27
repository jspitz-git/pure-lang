# Building pure-xml for the Windows bundle

The native module is built in the MSYS2 CLANG64 environment against the
portable Pure prefix and the official CLANG64 libxml2 and libxslt packages.
The validated versions are libxml2 2.15.3 and libxslt 1.1.45.

```sh
export PATH=/clang64/bin:/usr/bin
export PKG_CONFIG_PATH=/c/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig:/clang64/lib/pkgconfig
cmake -S /c/pure-lang/pure-xml \
  -B /c/pure-lang/pure/build/windows-clang64-xml \
  -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang
cmake --build /c/pure-lang/pure/build/windows-clang64-xml
cmake --build /c/pure-lang/pure/build/windows-clang64-xml \
  --target verify-windows-dependencies
```

The package adds `libxml2-16.dll` and `libxslt-1.dll` to the shared bundle
runtime. Libxml2 also uses the bundle's existing `libiconv-2.dll` and
`zlib1.dll`; no duplicate copies are installed. The CLANG64 libxml2 build
provides DTD validation, XPath, XPointer, XInclude, schemas, iconv, and zlib.
It has no HTTP or FTP loader feature, which keeps the smoke tests local and
prevents accidental network entity resolution.

Libxslt 1.1.45 was compiled against the compatible libxml2 2.15 ABI. The
runtime dependency check rejects MSYS and GNU runtime DLLs.
