# pure-odbc on native Windows

## Supported ODBC layer and package boundary

The Windows package relies on the native 64-bit Microsoft ODBC Driver Manager
at `C:\Windows\System32\odbc32.dll`; it does **not** contain that DLL,
unixODBC, or a database driver. The CLANG64 headers (`sql.h` and `sqlext.h`)
and `libodbc32.a` are build-time declarations and an import library, not a
second runtime manager. A database driver remains an architecture-matched user
or system component.

The mandatory tests need no credentials, DSN, network service, or third-party
driver. They allocate the manager, enumerate drivers and data sources, and
require the expected `IM002` diagnostic for a deliberately absent driver. The
separate Access CSV test runs only when the exact 64-bit
`Microsoft Access Text Driver (*.txt, *.csv)` is registered. Absence is CTest
skip code 77; any failure after the driver is found is an error. Passing that
test is not a certification of other Access variants, SQL Server, MySQL, or
any other driver.

## Audited prerequisites

The strict audit accepts the following explicit x86-64 Windows toolchain:

- CMake 3.25 or newer and Ninja from MSYS2 CLANG64;
- Clang major version 22 targeting `x86_64-w64-windows-gnu`;
- CLANG64 `pkgconf`, GMP 6.3, Windows ODBC headers, `libodbc32.a`, and
  `llvm-readobj`;
- MSYS `make` (required by the real source-distribution contract);
- a previously installed portable Pure 0.68 SDK containing `pure.exe`,
  `libpure.dll`, `libgmp-10.dll`, headers, and `pure.pc`;
- PyYAML for the repository workflow-semantic test.

The corresponding MSYS2 packages include `make`,
`mingw-w64-clang-x86_64-clang`, `mingw-w64-clang-x86_64-cmake`,
`mingw-w64-clang-x86_64-gmp`, `mingw-w64-clang-x86_64-llvm`,
`mingw-w64-clang-x86_64-ninja`, `mingw-w64-clang-x86_64-pkgconf`, and
`mingw-w64-clang-x86_64-python-yaml`.

## Reproducible strict build and tests

Run these commands from the repository root in PowerShell after staging Pure
at `pure/build/windows-clang64-prefix`:

```powershell
$cmake = 'C:/msys64/clang64/bin/cmake.exe'
$ctest = 'C:/msys64/clang64/bin/ctest.exe'
$python = 'C:/msys64/clang64/bin/python.exe'
$prefix = (Resolve-Path 'pure/build/windows-clang64-prefix').Path.Replace('\', '/')
$build = 'build/windows-pure-odbc-audit'

& $cmake -S pure-odbc -B $build -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/ninja.exe `
  -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe `
  -DCMAKE_C_COMPILER_TARGET=x86_64-w64-windows-gnu `
  -DBUILD_TESTING=ON -DPURE_ODBC_STRICT_WINDOWS_AUDIT=ON `
  -DPURE_ODBC_BUILD_FAULT_TESTS=ON `
  -DPURE_ODBC_CLANG64_PREFIX=C:/msys64/clang64 `
  "-DPURE_ODBC_PKG_CONFIG_PATH=$prefix/lib/pkgconfig" `
  -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkgconf.exe `
  -DLLVM_READOBJ_EXECUTABLE=C:/msys64/clang64/bin/llvm-readobj.exe `
  -DPURE_ODBC_MAKE_EXECUTABLE=C:/msys64/usr/bin/make.exe `
  "-DPURE_PREFIX=$prefix" "-DPURE_EXECUTABLE=$prefix/bin/pure.exe" `
  "-DPURE_RUNTIME_DLL=$prefix/bin/libpure.dll" `
  -DGMP_RUNTIME_DLL=C:/msys64/clang64/bin/libgmp-10.dll `
  -DODBC_HEADER=C:/msys64/clang64/include/sql.h `
  -DODBC_IMPORT_LIBRARY=C:/msys64/clang64/lib/libodbc32.a `
  -DSYSTEM_ODBC_DLL=C:/Windows/System32/odbc32.dll `
  -DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=C:/Windows
& $cmake --build $build --parallel 4
& $cmake --build $build --target verify-windows-dependencies --parallel 4

$savedPath = $env:Path
$env:Path = "$prefix/bin;C:/msys64/clang64/bin;C:/msys64/usr/bin;$env:SystemRoot/System32/WindowsPowerShell/v1.0;$env:SystemRoot/System32;$env:SystemRoot"
Remove-Item Env:PURELIB -ErrorAction SilentlyContinue
& $ctest --test-dir $build -L odbc --output-on-failure --no-tests=error
$env:Path = $savedPath

& $python -c "import yaml; print(yaml.__version__)"
& $python .github/scripts/test_validate_non_linux_release_workflow.py -v
& $python .github/scripts/validate_non_linux_release_workflow.py `
  .github/workflows/non-linux-release-validation.yml
```

The `odbc` label includes the native fault harness, mandatory manager smoke,
optional Access smoke, runner and cleanup contracts, exact configure/PE/install
mutation contracts, and the real source archive contract. The archive is built
with `make dist`, extracted below a path containing spaces, and configured,
built, tested, installed, and verified without checkout-side source inputs.

## Installation and verification

The following complete continuation of the preceding PowerShell session creates
a fresh stage, records the full pre-install prefix, installs runtime and
documentation separately, preserves both component manifests, and invokes the
installed verifier with every required argument. It does not depend on CI-only
variables.

```powershell
$sourceNative = (Resolve-Path 'pure-odbc').Path
$prefixNative = (Resolve-Path 'pure/build/windows-clang64-prefix').Path
$buildNative = [IO.Path]::GetFullPath($build)
$stageNative = [IO.Path]::GetFullPath('build/windows-pure-odbc-stage')
$baseline = Join-Path $buildNative 'windows-pure-odbc-baseline.sha256'
$runtimeManifest = Join-Path $buildNative 'install-manifest-runtime-ci.txt'
$documentationManifest =
  Join-Path $buildNative 'install-manifest-documentation-ci.txt'

if (Test-Path -LiteralPath $stageNative) {
  throw "Fresh pure-odbc stage already exists: $stageNative"
}
Get-ChildItem -LiteralPath $prefixNative -File -Recurse |
  Sort-Object FullName | ForEach-Object {
    $relative =
      [IO.Path]::GetRelativePath($prefixNative, $_.FullName).Replace('\', '/')
    $hash =
      (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash|$relative"
  } | Set-Content -LiteralPath $baseline -Encoding utf8

New-Item -ItemType Directory -Path $stageNative | Out-Null
Get-ChildItem -LiteralPath $prefixNative -Force |
  Copy-Item -Destination $stageNative -Recurse -Force

& $cmake --install $buildNative --prefix $stageNative --component runtime
if ($LASTEXITCODE -ne 0) { throw 'pure-odbc runtime install failed' }
Copy-Item -LiteralPath "$buildNative/install_manifest_runtime.txt" `
  -Destination $runtimeManifest

& $cmake --install $buildNative --prefix $stageNative `
  --component documentation
if ($LASTEXITCODE -ne 0) { throw 'pure-odbc documentation install failed' }
Copy-Item -LiteralPath "$buildNative/install_manifest_documentation.txt" `
  -Destination $documentationManifest

$source = $sourceNative.Replace('\', '/')
$prefix = $prefixNative.Replace('\', '/')
$buildPath = $buildNative.Replace('\', '/')
$stage = $stageNative.Replace('\', '/')
& $cmake `
  "-DSTAGE_PREFIX=$stage" `
  "-DBASELINE_MANIFEST=$($baseline.Replace('\', '/'))" `
  "-DRUNTIME_COMPONENT_MANIFEST=$($runtimeManifest.Replace('\', '/'))" `
  "-DDOCUMENTATION_COMPONENT_MANIFEST=$($documentationManifest.Replace('\', '/'))" `
  -DLLVM_READOBJ=C:/msys64/clang64/bin/llvm-readobj.exe `
  "-DODBC_MODULE_SOURCE=$buildPath/odbc.dll" `
  "-DODBC_INTERFACE_SOURCE=$source/odbc.pure" `
  "-DREADME_SOURCE=$buildPath/README" `
  "-DCOPYING_SOURCE=$source/COPYING" `
  "-DCOPYING_LESSER_SOURCE=$source/COPYING.LESSER" `
  "-DWINDOWS_SOURCE=$source/WINDOWS.md" `
  "-DEXAMPLE_SOURCE=$source/examples/menagerie.pure" `
  "-DSMOKE_SOURCE=$source/tests/smoke.pure" `
  "-DPEOPLE_SOURCE=$source/tests/data/people.csv" `
  "-DSCHEMA_SOURCE=$source/tests/data/Schema.ini" `
  -DGMP_DLL_SOURCE=C:/msys64/clang64/bin/libgmp-10.dll `
  "-DPURE_RUNTIME_DLL_SOURCE=$prefix/bin/libpure.dll" `
  "-DRUN_PURE_TEST_EXECUTABLE=$buildPath/run_pure_test.exe" `
  "-DWINDOWS_DEPENDENCY_VERIFIER=$source/cmake/VerifyWindowsDependencies.cmake" `
  -DWINDOWS_DIRECTORY=C:/Windows `
  -DSYSTEM_ODBC_DLL=C:/Windows/System32/odbc32.dll `
  -DPURE_ODBC_AUTHORITATIVE_WINDOWS_DIRECTORY=C:/Windows `
  -P pure-odbc/cmake/VerifyInstalledPackage.cmake
if ($LASTEXITCODE -ne 0) { throw 'Installed pure-odbc verification failed' }
```

The baseline format is `lowercase-sha256|relative/path`. The verifier fails
closed unless the stage is an exact extension of that baseline.

The verified install delta is exactly these ten files:

1. `lib/pure/odbc.dll`
2. `lib/pure/odbc.pure`
3. `share/doc/pure-odbc/README`
4. `share/doc/pure-odbc/COPYING`
5. `share/doc/pure-odbc/COPYING.LESSER`
6. `share/doc/pure-odbc/WINDOWS.md`
7. `share/doc/pure-odbc/examples/menagerie.pure`
8. `share/doc/pure-odbc/tests/smoke.pure`
9. `share/doc/pure-odbc/tests/data/people.csv`
10. `share/doc/pure-odbc/tests/data/Schema.ini`

Every pre-existing file must remain byte-identical, including the staged GMP
DLL. Installed smoke runs with `PURELIB` absent and `PATH` replaced by staged
`bin` plus Windows system directories. Exact AMD64 PE import sets and their
recursive 14-binary closure are deliberately version-sensitive; a Pure,
CLANG64, SDK, or import change requires a new audit rather than an allow-list
relaxation.

## Known limitations

- Only native 64-bit Windows and the explicit Clang 22 CLANG64 audit profile are
  covered by the bundle validation; ordinary non-strict upstream builds remain
  available.
- The OS-owned `odbc32.dll` is path- and architecture-checked, but Windows
  servicing may change its internal imports.
- Optional Access coverage depends on the exact locally registered 64-bit text
  driver. No external database server or general driver matrix is tested.
