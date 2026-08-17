# Building and packaging PureReduce on Windows

PureReduce is a separate, optional Windows component. It embeds the headless
CSL algebra engine in `reduce.dll`; it does not install `reduce.exe`, the full
REDUCE frontend, GUI support, Redfront, a compiler toolchain, or upstream
sources. The default `cmake --install` selection is intentionally empty.
Installers produced by TODO-49 must request the `PureReduce` component
explicitly and may distribute the CI-built `windows-pure-reduce.zip` as a
separate artifact.

## Pinned source

The only supported upstream input is the official REDUCE repository at commit
`7efba90661139ae9c73c99fddd55f3fb2fabf69a`:

- Git tree: `5573613a2f86efea75695fbe65a73317383884c1`
- tracked-tree SHA-256: `134a68fdb10403d3a4c69051eb4e133803ff2659784f2d38ac4d94c7ee9f86d8`

From the Pure repository root, retrieve that exact source into a path with
spaces. CMake never fetches or updates it:

```powershell
$reduceCommit = '7efba90661139ae9c73c99fddd55f3fb2fabf69a'
$reduceSource = Join-Path (Get-Location).Path 'build/deps/REDUCE source with spaces'
New-Item -ItemType Directory -Path (Split-Path $reduceSource -Parent) -Force | Out-Null
git clone --filter=blob:none --no-checkout https://github.com/reduce-algebra/reduce-algebra.git $reduceSource
git -C $reduceSource config core.autocrlf false
git -C $reduceSource fetch --depth=1 origin $reduceCommit
git -C $reduceSource checkout --detach FETCH_HEAD
git -C $reduceSource rev-parse HEAD
git -C $reduceSource rev-parse 'HEAD^{tree}'
git -C $reduceSource status --short
```

The last three commands must print the commit and tree above and then no
tracked changes. The CMake source verifier additionally hashes Git's
pathname-sorted tracked-object record stream and rejects a different commit,
tree identity, non-top-level checkout, or dirty tracked tree. Two checked-in,
checksum-covered corrections are applied only to a private canonical source
materialization below the build directory; the checkout is not patched.

The historical `reduce-algebra-csl-r2204` archive under `reduce-files` is not
a Windows input and is not the supported upstream baseline.

## Prerequisites

Use a current 64-bit MSYS2 installation at `C:\msys64` and its CLANG64
environment. The validation job is configured to install these packages:

```powershell
& C:/msys64/usr/bin/bash.exe -lc @'
set -euxo pipefail
pacman --noconfirm -Sy --needed \
  autoconf-wrapper autoconf2.73 \
  automake-wrapper automake1.18 libtool make \
  bison flex diffutils \
  mingw-w64-clang-x86_64-clang \
  mingw-w64-clang-x86_64-gcc-compat \
  mingw-w64-clang-x86_64-llvm \
  mingw-w64-clang-x86_64-cmake \
  mingw-w64-clang-x86_64-ninja \
  mingw-w64-clang-x86_64-pkgconf \
  mingw-w64-clang-x86_64-gmp \
  mingw-w64-clang-x86_64-mpfr \
  mingw-w64-clang-x86_64-readline \
  mingw-w64-clang-x86_64-pcre \
  mingw-w64-clang-x86_64-libiconv \
  mingw-w64-clang-x86_64-zlib \
  mingw-w64-clang-x86_64-ncurses
'@
if ($LASTEXITCODE -ne 0) { throw 'MSYS2 package setup failed' }
```

`gcc-compat` is required even though the native compiler is Clang: one
vendored upstream build rule invokes `g++`, and CLANG64 supplies the compatible
Clang driver through that package. The build selects Autoconf 2.73 with
`WANT_AUTOCONF=2.73`; Automake and Libtool are also required by upstream
autogen.

PureReduce's functional and installed-package tests require an installed
Windows Pure interpreter. Build it with the same CLANG64 packages and the
same conventions used by the `windows-pure-faust` validation job:

```powershell
$cmake = 'C:/msys64/clang64/bin/cmake.exe'
$repo = (Get-Location).Path
$pureBuild = Join-Path $repo 'build/windows pure release'
$purePrefix = Join-Path $repo 'build/windows pure prefix'
& $cmake -S pure -B $pureBuild -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe `
  -DCMAKE_CXX_COMPILER=C:/msys64/clang64/bin/clang++.exe `
  -DLLVM_DIR=C:/msys64/clang64/lib/cmake/llvm `
  "-DCMAKE_INSTALL_PREFIX=$purePrefix" `
  -DPURE_STRICT_TOOLCHAIN=ON
if ($LASTEXITCODE -ne 0) { throw 'Pure configure failed' }
& $cmake --build $pureBuild --parallel 1
if ($LASTEXITCODE -ne 0) { throw 'Pure build failed' }
& $cmake --install $pureBuild
if ($LASTEXITCODE -ne 0) { throw 'Pure install failed' }
```

## Configure, build, test, install, and verify

These are the supported commands. They retain spaces in the source, build,
and staged-install paths and use one upstream build worker to control peak
memory and preserve the measured build profile:

```powershell
$cmake = 'C:/msys64/clang64/bin/cmake.exe'
$ctest = 'C:/msys64/clang64/bin/ctest.exe'
$repo = (Get-Location).Path
$reduceSource = Join-Path $repo 'build/deps/REDUCE source with spaces'
$reduceBuild = Join-Path $repo 'build/windows PureReduce release'
$pureExe = Join-Path $repo 'build/windows pure prefix/bin/pure.exe'
$stage = Join-Path $reduceBuild 'staged PureReduce package'

& $cmake -S pure-reduce -B $reduceBuild -G Ninja `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_CXX_COMPILER=C:/msys64/clang64/bin/clang++.exe `
  "-DPURE_REDUCE_SOURCE_DIR=$reduceSource" `
  -DPURE_REDUCE_MSYS2_BASH=C:/msys64/usr/bin/bash.exe `
  -DPURE_REDUCE_MAKE=C:/msys64/usr/bin/make.exe `
  "-DPURE_EXECUTABLE=$pureExe" `
  -DBUILD_TESTING=ON
if ($LASTEXITCODE -ne 0) { throw 'PureReduce configure failed' }

& $cmake --build $reduceBuild --parallel 1
if ($LASTEXITCODE -ne 0) { throw 'PureReduce build failed' }
& $ctest --test-dir $reduceBuild -L reduce --output-on-failure --no-tests=error
if ($LASTEXITCODE -ne 0) { throw 'PureReduce tests failed' }

& $cmake `
  "-DBUILD_DIR=$reduceBuild" `
  "-DSTAGE_PREFIX=$stage" `
  "-DAUTHORITATIVE_MANIFEST=$reduceBuild/PureReduceExpected.sha256" `
  "-DPURE_EXECUTABLE=$pureExe" `
  -DLLVM_READOBJ=C:/msys64/clang64/bin/llvm-readobj.exe `
  "-DSOURCE_PREFIX=$repo/pure-reduce" `
  -P pure-reduce/cmake/VerifyInstalledPackage.cmake
if ($LASTEXITCODE -ne 0) { throw 'installed package verification failed' }
```

The verifier snapshots the pre-install manifests, installs only the
`PureReduce` component into `$stage`, proves the install did not change its
oracles, and then verifies the staged package. Do not pre-install into this
trust-establishing stage. To inspect a separately installed external prefix,
pass the same required arguments plus `-DVERIFY_ONLY=ON`.

The complete upstream build intentionally uses official autogen/configure and
`make -j1` for the native, headless, non-Cygwin x86-64 CSL configuration. It
builds the complete text-mode image, derives the current 106-object embedded
closure, and excludes only GUI/FOX/X11 and the optional Redfront/libedit
frontend.

## Installed layout and runtime contract

The `PureReduce` component currently owns exactly 80 files. Its stable roots
are:

```text
lib/pure/reduce.pure
lib/pure/reduce.dll
lib/pure/reduce.img
lib/pure/reduce.resources/**
lib/pure/reduce.fonts/**
share/doc/pure-reduce/**
```

`share/doc/pure-reduce/PureReduceInventory.tsv` records purpose, origin,
SHA-256, byte count, and license for every other payload. The build-tree
`PureReduceExpected.sha256` is the authoritative 80-file manifest. The package
contains the Pure and REDUCE licenses, detailed licenses for the statically
linked closure, both applied patch files, runtime manifests, sanitized metrics,
and functional tests. It contains no development archives, source tree,
MSYS2 tools, `reduce.exe`, or non-system runtime DLL at the current pin.

`reduce.pure` finds the loaded `reduce.dll` through the Pure module loader, and
the bridge opens the adjacent `reduce.img` through Windows wide-character
APIs. Moving the whole installation prefix preserves those relative
relationships. Runtime validation clears `PURELIB`, removes MSYS2 from
`PATH`, starts in `C:\Windows`, and checks smoke, lifecycle, exact inventory,
hashes, PE imports, and absence of source/build/original-prefix leaks.

## Diagnostics

Start with the installed verifier command above. Useful focused checks are:

```powershell
& C:/msys64/clang64/bin/ctest.exe --test-dir $reduceBuild `
  -R '^pure-reduce-(installed|manifest-failures|relocation)$' `
  --output-on-failure
Get-Content "$stage/share/doc/pure-reduce/pure-reduce-package-metrics.json"
Get-FileHash "$stage/lib/pure/reduce.dll" -Algorithm SHA256
Get-FileHash "$stage/lib/pure/reduce.img" -Algorithm SHA256
& C:/msys64/clang64/bin/llvm-readobj.exe --coff-imports `
  "$stage/lib/pure/reduce.dll"
```

A changed pin, dirty checkout, checksum mismatch, new runtime DLL, missing
license, unexpected file, prefix leak, or runtime stderr is a hard failure.
Upstream transcripts and artifact audits are under the configured
`reduce-upstream/logs` build directory; they are diagnostics and are not
installed.

## Upgrade and removal

For an upgrade, build and verify a new stage, then let the installer replace
the optional component as one unit. Do not overlay files from a different
REDUCE pin or preserve an old `reduce.img`. Re-run the installed verifier after
the replacement.

TODO-49 should use the installed inventory as the ownership boundary. A manual
removal may delete only these component-owned paths from the chosen prefix:

```powershell
$prefix = 'C:/Program Files/Pure'
Remove-Item -LiteralPath "$prefix/lib/pure/reduce.pure" -Force
Remove-Item -LiteralPath "$prefix/lib/pure/reduce.dll" -Force
Remove-Item -LiteralPath "$prefix/lib/pure/reduce.img" -Force
Remove-Item -LiteralPath "$prefix/lib/pure/reduce.resources" -Recurse -Force
Remove-Item -LiteralPath "$prefix/lib/pure/reduce.fonts" -Recurse -Force
Remove-Item -LiteralPath "$prefix/share/doc/pure-reduce" -Recurse -Force
```

Resolve and inspect `$prefix` before running these commands. Do not recursively
remove `lib/pure`, `share/doc`, the installation prefix, or unrelated files.

## Source and license offer

The official source retrieval commands and exact identity are recorded above
and in `THIRD_PARTY.md`. The distributable includes the applicable notices and
the checksum-covered PureReduce patch files under
`share/doc/pure-reduce`. Anyone redistributing the binary component must keep
those files with it and preserve access to the exact official source commit.
