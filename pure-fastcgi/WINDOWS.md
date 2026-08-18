# Building PureFastCGI on Windows

PureFastCGI is a candidate optional 64-bit Windows component for the MSYS2
CLANG64 Pure distribution. The candidate build embeds the required fcgi2
2.4.7 C sources in `fastcgi.dll`; it is designed not to install or load a
separate `libfcgi.dll`. Shipping remains conditional on clean-runner evidence.

The commands below are PowerShell commands. They deliberately keep source,
build, and staging paths containing spaces. Replace `C:/pure-lang` and the
Pure prefix only if your checkout or installed Pure runtime uses another
location.

## Prerequisites

Install CMake 3.25 or newer, Ninja, Clang/LLVM, pkg-config, GMP, MPFR, and a
matching Pure 0.68 or newer runtime in the MSYS2 CLANG64 environment. The
examples assume that Pure is installed under `C:/pure-prefix` and that its
pkg-config file is in `C:/pure-prefix/lib/pkgconfig`.

## Fetch the pinned source explicitly

Configuration and rebuilding never access the network. Fetch the one accepted
archive in a separate, explicit operation:

```powershell
$repo = 'C:/pure-lang'
$archive = "$repo/build/deps/fcgi2-2.4.7.tar.gz"
New-Item -ItemType Directory -Path (Split-Path $archive) -Force | Out-Null
& C:/msys64/clang64/bin/cmake.exe `
  "-DOUTPUT=$archive" `
  -P "$repo/pure-fastcgi/cmake/FetchFcgi2Entry.cmake"
```

The entry point invokes the fetch helper and accepts only release 2.4.7, commit
`47f2c03b7771f0ef61d887734ef91e6fa747f837`, URL
`https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/2.4.7.tar.gz`,
size `263969`, and SHA-256
`e41ddc3a473b555bdc0cbd80703dcb1f4610c1a7700d3b9d3d0c14a416e1074b`.
It refuses a mismatching pre-existing file.

## Configure and build

```powershell
$repo = 'C:/pure-lang'
$archive = "$repo/build/deps/fcgi2-2.4.7.tar.gz"
$build = "$repo/build/PureFastCGI build with spaces"
$purePrefix = 'C:/pure-prefix'
$env:PKG_CONFIG_PATH = "$purePrefix/lib/pkgconfig;C:/msys64/clang64/lib/pkgconfig"

& C:/msys64/clang64/bin/cmake.exe `
  -S "$repo/pure-fastcgi" -B $build -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe `
  "-DPURE_FASTCGI_FCGI2_ARCHIVE=$archive" `
  "-DPURE_FASTCGI_PURE_EXECUTABLE=$purePrefix/bin/pure.exe" `
  "-DPURE_FASTCGI_PURE_RUNTIME_DIR=$purePrefix/bin" `
  -DBUILD_TESTING=ON
& C:/msys64/clang64/bin/cmake.exe --build $build --parallel 1
```

## Test

Run the entire FastCGI label, or a focused protocol/package selection:

```powershell
& C:/msys64/clang64/bin/ctest.exe `
  --test-dir $build -L fastcgi --output-on-failure --no-tests=error
& C:/msys64/clang64/bin/ctest.exe `
  --test-dir $build `
  -R 'pure-fastcgi-(protocol|package|relocation)' --output-on-failure
& C:/msys64/clang64/bin/cmake.exe `
  --build $build --target verify-windows-dependencies
```

The protocol tests use a unique local Windows named pipe and impose bounded
timeouts. They do not start a TCP listener or a web server.

## Stage and verify only the optional component

```powershell
$stage = "$repo/build/staged PureFastCGI package"
& C:/msys64/clang64/bin/cmake.exe `
  --install $build --prefix $stage --component PureFastCGI

$savedPath = $env:PATH
try {
  $env:PATH = "$stage/lib/pure;$purePrefix/bin;$env:SystemRoot/System32/WindowsPowerShell/v1.0;$env:SystemRoot/System32;$env:SystemRoot"
  Remove-Item Env:PURELIB -ErrorAction SilentlyContinue
  & C:/msys64/clang64/bin/cmake.exe `
    "-DBUILD_DIR=$build" `
    "-DSTAGE_PREFIX=$stage" `
    "-DSOURCE_DIR=$repo/pure-fastcgi" `
    "-DPURE_RUNTIME_ROOT=$purePrefix/bin" `
    -DLLVM_READOBJ=C:/msys64/clang64/bin/llvm-readobj.exe `
    "-DPOWERSHELL_EXECUTABLE=$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" `
    "-DPROTOCOL_HARNESS=$build/pure-fastcgi-protocol-harness.exe" `
    "-DPROTOCOL_WORKER=$repo/pure-fastcgi/tests/protocol_worker.pure" `
    -DRUN_RUNTIME_TESTS=ON `
    -P "$repo/pure-fastcgi/cmake/VerifyInstalledPackage.cmake"
} finally {
  $env:PATH = $savedPath
}
```

In the candidate build, an unqualified install excludes PureFastCGI and local
validation explicitly selects component `PureFastCGI`. Its planned ownership
boundary is exactly the files declared by the external build oracle and
installed inventory. This is not a shipping claim before clean CI evidence.

## Deployment boundary

The proposed component would supply the Pure module and provenance documents
only. It is not intended to install, configure, or validate IIS, Apache,
nginx, or any other web server. A deployment would need to separately provide
and configure a FastCGI listener
compatible with the standard FastCGI responder protocol and must arrange the
process environment, permissions, request limits, logging, and supervision.
The local named-pipe harness is a protocol test tool, not a production server.

Clean-runner artifact evidence and the final ship/defer decision are recorded
in TODO-46 only after the GitHub Actions job has actually succeeded.
