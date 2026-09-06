# pure-glpk on native Windows

The supported native Windows build uses the MSYS2 CLANG64 compiler and
`mingw-w64-clang-x86_64-glpk`. Building requires MSYS2, but the installed
module and solver tests run without an MSYS2 directory in `PATH`. The build
consumes an already installed portable Pure SDK.

## Configure, build, and test

The following PowerShell commands use explicit tool and dependency locations.
Adjust `$purePrefix`, `$build`, and `$stage`; keep the CLANG64 tool paths and
the four-worker build limit explicit.

```powershell
$purePrefix = 'C:/path/to/portable-pure'
$build = 'C:/path/to/pure-glpk-build'
$stage = 'C:/path/to/fresh-pure-glpk-stage'
$env:MSYSTEM_PREFIX = 'C:/msys64/clang64'
$env:PKG_CONFIG_PATH = "$purePrefix/lib/pkgconfig;C:/msys64/clang64/lib/pkgconfig"
$env:Path = "C:/msys64/clang64/bin;C:/msys64/usr/bin;$env:Path"

& C:/msys64/clang64/bin/cmake.exe -S pure-glpk -B $build -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe `
  '-DCMAKE_C_FLAGS=-Wall -Wextra -Werror' `
  -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkgconf.exe `
  -DBUILD_TESTING=ON `
  "-DPURE_EXECUTABLE=$purePrefix/bin/pure.exe" `
  -DLLVM_READOBJ_EXECUTABLE=C:/msys64/clang64/bin/llvm-readobj.exe
& C:/msys64/clang64/bin/cmake.exe --build $build --parallel 4
& C:/msys64/clang64/bin/cmake.exe --build $build `
  --target verify-windows-dependencies --parallel 4

Remove-Item Env:PURELIB -ErrorAction SilentlyContinue
$env:Path = "$purePrefix/bin;$env:SystemRoot/System32/WindowsPowerShell/v1.0;$env:SystemRoot/System32;$env:SystemRoot"
& C:/msys64/clang64/bin/ctest.exe --test-dir $build -L glpk `
  --output-on-failure --no-tests=error
```

`MSYSTEM_PREFIX` remains an explicit discovery input for nested configure
contracts. It does not add MSYS2 to the runtime search path. The test runner
replaces each child process's `PATH` with only the module directory, the GLPK
runtime directory, the Pure executable directory, and Windows system
directories; it also removes `PURELIB` and runs from `C:/Windows`. The parent
CTest invocation above is sanitized as an independent check.

GLPK 5.0 does not provide a CLANG64 pkg-config file, so CMake locates `glpk.h`,
the import library, and runtime DLLs below the explicit `MSYSTEM_PREFIX`.
`PURE_EXECUTABLE` and `LLVM_READOBJ_EXECUTABLE` must name existing files. GMP
remains a direct link dependency because the native wrapper uses GMP itself.

## Install and verify a package stage

Start from a clean copy of the portable Pure prefix, then install the two
pure-glpk components. This is a distinct final-package boundary; the
`pure-glpk-install-contract` CTest already performs the same checks in its own
isolated mutation-test stages.

```powershell
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -Path "$purePrefix/*" -Destination $stage -Recurse
& C:/msys64/clang64/bin/cmake.exe --install $build --prefix $stage `
  --component runtime
& C:/msys64/clang64/bin/cmake.exe --install $build --prefix $stage `
  --component documentation

Remove-Item Env:PURELIB -ErrorAction SilentlyContinue
$env:Path = "$stage/bin;$env:SystemRoot/System32/WindowsPowerShell/v1.0;$env:SystemRoot/System32;$env:SystemRoot"
& C:/msys64/clang64/bin/cmake.exe `
  "-DSTAGE_PREFIX=$stage" `
  -DSOURCE_RUNTIME_DIR=C:/msys64/clang64/bin `
  -DLLVM_READOBJ=C:/msys64/clang64/bin/llvm-readobj.exe `
  "-DGLPK_MODULE_SOURCE=$build/glpk.dll" `
  -DGLPK_INTERFACE_SOURCE=pure-glpk/glpk.pure `
  "-DREADME_SOURCE=$build/README" `
  -DCOPYING_SOURCE=pure-glpk/COPYING `
  -DWINDOWS_SOURCE=pure-glpk/WINDOWS.md `
  -DEXAMPLE_SOURCE=pure-glpk/examples/lp.pure `
  -DTEST_SOURCE=pure-glpk/tests/smoke.pure `
  -DGLPK_DLL_SOURCE=C:/msys64/clang64/bin/libglpk-40.dll `
  -DCOLAMD_DLL_SOURCE=C:/msys64/clang64/bin/libcolamd.dll `
  -DAMD_DLL_SOURCE=C:/msys64/clang64/bin/libamd.dll `
  -DSUITESPARSECONFIG_DLL_SOURCE=C:/msys64/clang64/bin/libsuitesparseconfig.dll `
  -DOMP_DLL_SOURCE=C:/msys64/clang64/bin/libomp.dll `
  -DGLPK_LICENSE_SOURCE=C:/msys64/clang64/share/licenses/glpk/LICENSE `
  -DSUITESPARSE_LICENSE_SOURCE=C:/msys64/clang64/share/licenses/suitesparse/LICENSE `
  -DLLVM_LICENSE_SOURCE=C:/msys64/clang64/share/licenses/llvm/LICENSE `
  -DRUN_PURE_TEST_SCRIPT=pure-glpk/cmake/RunPureTest.cmake `
  -DWINDOWS_DEPENDENCY_VERIFIER=pure-glpk/cmake/VerifyWindowsDependencies.cmake `
  -P pure-glpk/cmake/VerifyInstalledPackage.cmake
```

Run these commands from the repository root so the relative source arguments
resolve correctly. The verifier requires every argument shown, compares every
installed package file with its declared source by SHA-256, runs the staged
solver and callback test under the sanitized environment, and reruns the exact
PE audit. Pure 0.68 does not reliably parse its libraries when its executable
prefix contains non-ASCII characters. For such a physical stage, obtain its
Windows 8.3 alias with `GetShortPathNameW` and use that ASCII alias for `$stage`
when setting `PATH` and invoking the verifier; the files being verified remain
in the original Unicode directory. Ordinary spaces need no alias.

## Runtime and package ownership

The non-system runtime closure is:

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

The CLANG64 GLPK package does not import ltdl or an ODBC DLL. The legacy
Makefile's broader link list is not the PE runtime contract. The verifier
compares the complete case-insensitive, sorted import set for all eight AMD64
binaries (`glpk.dll`, GLPK, AMD, COLAMD, SuiteSparseConfig, OpenMP, GMP, and
zlib), including Windows system and UCRT API-set imports. These literal sets
are deliberately version-sensitive: upgrading the CLANG64 packages requires a
fresh audit and an intentional expectation update. Missing and unexpected
imports both fail.

`libgmp-10.dll` and `zlib1.dll` belong to the portable Pure SDK. They are not
installed by pure-glpk and must remain byte-identical to the selected CLANG64
files. pure-glpk owns exactly these 15 files:

```text
bin/libamd.dll
bin/libcolamd.dll
bin/libglpk-40.dll
bin/libomp.dll
bin/libsuitesparseconfig.dll
lib/pure/glpk.dll
lib/pure/glpk.pure
share/doc/pure-glpk/COPYING
share/doc/pure-glpk/README
share/doc/pure-glpk/WINDOWS.md
share/doc/pure-glpk/examples/lp.pure
share/doc/pure-glpk/glpk-LICENSE
share/doc/pure-glpk/llvm-openmp-LICENSE
share/doc/pure-glpk/suitesparse-LICENSE
share/doc/pure-glpk/tests/smoke.pure
```

Any extra file in those package-owned namespaces or any hash mismatch fails
the install contract.

## Callback lifetime

The public callback remains `glp::mip_cb tree info`, and pointer-valued
`cb_info` is passed through unchanged. GLPK owns `tree`; the Pure handle is
valid only during that callback invocation. The wrapper invalidates its
pointer payload before freeing the native wrapper. Retaining `tree` is safe,
but a later `glp::ios_*` call rejects the stale handle instead of dereferencing
freed memory.

## Source distribution

`make dist` includes the legacy package inputs plus every file needed for the
Windows CMake flow: `CMakeLists.txt`, `WINDOWS.md`, all `cmake/*.cmake`, all
`tests/*.cmake`, `tests/load.pure`, and `tests/smoke.pure`. The source-dist
contract runs the real archive recipe from a path containing spaces, extracts
the archive, checks these inputs, removes its source copy, and configures only
the extracted tree. This detects both an incomplete archive and accidental
configuration dependencies on the checkout.
