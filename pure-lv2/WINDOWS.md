# pure-lv2 on Windows

The Windows package provides the Pure LV2 module and a native
`pure2lv2.cmd`/PowerShell generator. The generator does not invoke Bash and
supports paths containing spaces. Both batch-compiled and source-loaded
plugins use Dynamic Manifest discovery.

Generating a plugin is a development operation. It requires the portable Pure
SDK, the installed LV2 headers, and a native Clang/LLVM toolchain. Set
`PURE2LV2_CC` to `clang.exe` and `PURE2LV2_TOOL_DIR` to the directory
containing the matching LLVM tools. An installer may alternatively place that
toolchain below `tools/bin`. Generated plugins do not need the compiler or
MSYS2 at run time.

Batch mode is the distribution default:

```powershell
$env:PURE2LV2_CC = 'C:\msys64\clang64\bin\clang.exe'
$env:PURE2LV2_TOOL_DIR = 'C:\msys64\clang64\bin'
pure2lv2.cmd -o C:\plugins\pure_amp.lv2 `
  -u urn:example C:\examples\pure_amp.pure
```

Add `-s` to create a source-loaded development bundle. Keep the copied Pure
script and any additional sources beside the generated DLL. The Windows bridge
resolves the script relative to the plugin DLL, so discovery does not depend
on a global `LV2_PATH`.

## Build, test, and stage

Run the build from an MSYS2 CLANG64 shell and point `PKG_CONFIG_PATH` at the
portable Pure SDK and the CLANG64 packages:

```sh
export PKG_CONFIG_PATH=C:/path/to/pure-prefix/lib/pkgconfig:/clang64/lib/pkgconfig
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON
cmake --build build
ctest --test-dir build --output-on-failure
cmake --build build --target verify-windows-dependencies
```

Install into a prefix which already contains Pure and `pure-lilv`. The
installed-package verifier generates both plugin types, discovers them through
the staged Lilv host, processes fixed audio buffers, unloads them, and checks
their PE exports/imports with `PURELIB` and `LV2_PATH` unset:

```sh
cmake --install build --prefix C:/tmp/pure-lv2-stage
cmake -DSTAGE_PREFIX=C:/tmp/pure-lv2-stage \
  -DSOURCE_RUNTIME_DIR=C:/path/to/pure-runtime/bin \
  -DPURE2LV2_CC=/clang64/bin/clang.exe \
  -DPURE2LV2_TOOL_DIR=/clang64/bin \
  -DLLVM_READOBJ=/clang64/bin/llvm-readobj.exe \
  -P cmake/VerifyInstalledPackage.cmake
```

Repeat the verifier after copying the complete installed tree to a different
path. At run time a generated plugin needs only the matching Pure/LV2 bundle
runtime and Windows system libraries; neither the compiler nor an MSYS2 shell
belongs in the runtime closure.
