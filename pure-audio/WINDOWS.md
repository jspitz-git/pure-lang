# Windows build and runtime audit

The supported target is native Windows x64, built with MSYS2 CLANG64. MSYS2
supplies development tools; the installed runtime must not import MSYS,
libgcc or libstdc++. This guide describes the strict, opt-in audit. Ordinary
non-strict CMake configuration remains available but is not evidence of a
hermetic or distributable package.

| DLL | Pure interfaces |
| --- | --- |
| audio.dll | audio.pure, portaudio.pure |
| fftw.dll | fftw.pure |
| srcprocess.dll | samplerate.pure |
| sfinfo.dll | sndfile.pure |
| realtime.dll | realtime.pure |

## Prerequisites and fixed inputs

Use native x64 PowerShell and MSYS2 at `C:/msys64`. Install these packages
in the MSYS2 CLANG64 shell (a separate machine-preparation step):

```sh
pacman -S --needed tar gzip make \
  mingw-w64-clang-x86_64-{clang,cmake,llvm,ninja,pkgconf,make,python-yaml} \
  mingw-w64-clang-x86_64-{portaudio,fftw,libsamplerate,libsndfile,libogg,libvorbis,flac,opus,mpg123,lame} \
  mingw-w64-clang-x86_64-{winpthreads,libc++,gmp,mpfr,libiconv,pcre,readline,termcap,zstd,zlib}
```

Also provide a complete, already validated native Pure 0.68 portable prefix,
including `bin/pure.exe`, `bin/libpure.dll`, its dependency DLLs, standard
library, `include/pure/runtime.h` and `lib/libpure.dll.a`. Do not substitute
an unrelated Pure installation or only copy its executable.

The exercised tools are Clang/LLVM 22.1.8 (major 22,
`x86_64-w64-windows-gnu`), CMake 4.4.0 (minimum 3.25), Ninja 1.13.2,
pkgconf 3.0.4, GNU Make 4.4.1, GNU tar 1.35 and gzip 1.14. Native helpers
also use the authoritative Windows PowerShell installation. The source
producer checks GNU tar identity and its `--hard-dereference` capability.
Workflow validation requires Python with PyYAML; CI installs the CLANG64
`python-yaml` package explicitly.

Runtime and license payloads are version-sensitive, not a promise that later
rolling MSYS2 packages pass. Exact tested versions, upstream provenance and
27 payload SHA-256 values are in [THIRD_PARTY.md](THIRD_PARTY.md) and
[licenses/origins.tsv](licenses/origins.tsv). Dependency upgrades need a new
closure/license audit, not relaxed hashes.

## Standalone strict configure

The following PowerShell blocks form one session. Replace the three example
input paths with canonical, non-reparse paths. `AUDIO_BUILD` must be fresh
and at most 32 characters: nested install-contract tests still use Win32
path-limited APIs. Use a new short root for each audit; do not delete an
unknown tree to make a command pass. `AUDIO_STAGE` is a new child of it.

```powershell
$ErrorActionPreference = 'Stop'
$env:AUDIO_SOURCE = 'C:/src/pure-audio'
$env:AUDIO_BUILD = 'C:/pa8'
$env:AUDIO_PREFIX = 'C:/pure-portable'
$env:AUDIO_STAGE = "$env:AUDIO_BUILD/package"
$env:CMAKE_EXE = 'C:/msys64/clang64/bin/cmake.exe'
$env:CTEST_EXE = 'C:/msys64/clang64/bin/ctest.exe'
$env:PATH = "$env:AUDIO_PREFIX/bin;C:/msys64/clang64/bin;C:/msys64/usr/bin;C:/Windows/System32;C:/Windows"
$env:PURELIB = ''
$env:PURE_INCLUDE = ''
$env:PURE_LIBRARY = ''
if ($env:AUDIO_BUILD.Length -gt 32) { throw 'Use a short audit build root' }
if (Test-Path -LiteralPath $env:AUDIO_BUILD) { throw 'Choose a fresh audit build root' }
$runtimeSources = @(
  "pure.exe|$env:AUDIO_PREFIX/bin/pure.exe"
  "libpure.dll|$env:AUDIO_PREFIX/bin/libpure.dll"
  "libc++.dll|$env:AUDIO_PREFIX/bin/libc++.dll"
  "libgmp-10.dll|$env:AUDIO_PREFIX/bin/libgmp-10.dll"
  "libiconv-2.dll|$env:AUDIO_PREFIX/bin/libiconv-2.dll"
  "libmpfr-6.dll|$env:AUDIO_PREFIX/bin/libmpfr-6.dll"
  "libpcre-1.dll|$env:AUDIO_PREFIX/bin/libpcre-1.dll"
  "libpcreposix-0.dll|$env:AUDIO_PREFIX/bin/libpcreposix-0.dll"
  "libreadline8.dll|$env:AUDIO_PREFIX/bin/libreadline8.dll"
  "libtermcap-0.dll|$env:AUDIO_PREFIX/bin/libtermcap-0.dll"
  "libwinpthread-1.dll|$env:AUDIO_PREFIX/bin/libwinpthread-1.dll"
  "libzstd.dll|$env:AUDIO_PREFIX/bin/libzstd.dll"
  "zlib1.dll|$env:AUDIO_PREFIX/bin/zlib1.dll"
  'libportaudio.dll|C:/msys64/clang64/bin/libportaudio.dll'
  'libfftw3-3.dll|C:/msys64/clang64/bin/libfftw3-3.dll'
  'libsamplerate-0.dll|C:/msys64/clang64/bin/libsamplerate-0.dll'
  'libsndfile-1.dll|C:/msys64/clang64/bin/libsndfile-1.dll'
  'libogg-0.dll|C:/msys64/clang64/bin/libogg-0.dll'
  'libvorbisenc-2.dll|C:/msys64/clang64/bin/libvorbisenc-2.dll'
  'libFLAC.dll|C:/msys64/clang64/bin/libFLAC.dll'
  'libopus-0.dll|C:/msys64/clang64/bin/libopus-0.dll'
  'libmpg123-0.dll|C:/msys64/clang64/bin/libmpg123-0.dll'
  'libmp3lame-0.dll|C:/msys64/clang64/bin/libmp3lame-0.dll'
  'libvorbis-0.dll|C:/msys64/clang64/bin/libvorbis-0.dll'
) -join ';'
& $env:CMAKE_EXE -S "$env:AUDIO_SOURCE" -B "$env:AUDIO_BUILD" -G Ninja `
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON -DPURE_AUDIO_STRICT_WINDOWS_AUDIT=ON `
  -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe `
  -DCMAKE_C_COMPILER_TARGET=x86_64-w64-windows-gnu `
  -DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/ninja.exe `
  -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkgconf.exe `
  -DLLVM_READOBJ=C:/msys64/clang64/bin/llvm-readobj.exe `
  -DPURE_AUDIO_MAKE_EXECUTABLE=C:/msys64/clang64/bin/mingw32-make.exe `
  -DPURE_AUDIO_SH_EXECUTABLE=C:/msys64/usr/bin/sh.exe `
  -DPURE_AUDIO_CLANG64_PREFIX=C:/msys64/clang64 `
  "-DPURE_AUDIO_PURE_PREFIX=$env:AUDIO_PREFIX" `
  "-DPURE_INCLUDE_DIR=$env:AUDIO_PREFIX/include" `
  "-DPURE_EXECUTABLE=$env:AUDIO_PREFIX/bin/pure.exe" `
  "-DPURE_HEADER=$env:AUDIO_PREFIX/include/pure/runtime.h" `
  "-DPURE_IMPORT_LIBRARY=$env:AUDIO_PREFIX/lib/libpure.dll.a" `
  "-DPURE_RUNTIME_DLL=$env:AUDIO_PREFIX/bin/libpure.dll" `
  -DPORTAUDIO_HEADER=C:/msys64/clang64/include/portaudio.h `
  -DPORTAUDIO_IMPORT_LIBRARY=C:/msys64/clang64/lib/libportaudio.dll.a `
  -DFFTW_HEADER=C:/msys64/clang64/include/fftw3.h `
  -DFFTW_IMPORT_LIBRARY=C:/msys64/clang64/lib/libfftw3.dll.a `
  -DSAMPLERATE_HEADER=C:/msys64/clang64/include/samplerate.h `
  -DSAMPLERATE_IMPORT_LIBRARY=C:/msys64/clang64/lib/libsamplerate.dll.a `
  -DSNDFILE_HEADER=C:/msys64/clang64/include/sndfile.h `
  -DSNDFILE_IMPORT_LIBRARY=C:/msys64/clang64/lib/libsndfile.dll.a `
  -DPTHREAD_HEADER=C:/msys64/clang64/include/pthread.h `
  -DPTHREAD_IMPORT_LIBRARY=C:/msys64/clang64/lib/libpthread.dll.a `
  -DGMP_HEADER=C:/msys64/clang64/include/gmp.h `
  -DMPFR_HEADER=C:/msys64/clang64/include/mpfr.h `
  -DPURE_AUDIO_WINDOWS_HEADER=C:/msys64/clang64/include/windows.h `
  -DPURE_AUDIO_WINDOWS_SYSTEM_DIRECTORY=C:/Windows/System32 `
  "-DPURE_AUDIO_RUNTIME_SOURCES=$runtimeSources"
if ($LASTEXITCODE -ne 0) { throw 'Strict audio configure failed' }
```

Strict configure rejects wrong origins, ABI, active or inactive configuration
flags and discovery overrides. Its pinned compiler launcher clears ambient
header/library discovery variables for each actual compile and link. The PE
reader must be the canonical declared CLANG64 LLVM 22 tool; the production
verifier cannot substitute recorded output.

## Build, no-hardware tests, and installed package

Run both build commands, each with exactly four workers. The second checks
the complete recursive PE closure, including the portable Pure baseline.

```powershell
& $env:CMAKE_EXE --build "$env:AUDIO_BUILD" --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'Audio build failed' }
& $env:CMAKE_EXE --build "$env:AUDIO_BUILD" --target verify-windows-dependencies --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'Audio PE closure failed' }
& $env:CTEST_EXE --test-dir "$env:AUDIO_BUILD" -L '^audio$' -LE '^hardware$' `
  -E '^pure-audio-source-dist-contract$' --output-on-failure --no-tests=error --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'Audio no-hardware tests failed' }
if (Test-Path -LiteralPath $env:AUDIO_STAGE) { throw 'Choose a fresh package stage' }
& $env:CMAKE_EXE -E copy_directory "$env:AUDIO_PREFIX" "$env:AUDIO_STAGE"
if ($LASTEXITCODE -ne 0) { throw 'Portable baseline copy failed' }
& $env:CMAKE_EXE --install "$env:AUDIO_BUILD" --prefix "$env:AUDIO_STAGE" --component runtime
if ($LASTEXITCODE -ne 0) { throw 'Audio runtime install failed' }
& $env:CMAKE_EXE --install "$env:AUDIO_BUILD" --prefix "$env:AUDIO_STAGE" --component documentation
if ($LASTEXITCODE -ne 0) { throw 'Audio documentation install failed' }
& $env:CMAKE_EXE "-DAUDIO_INSTALL_CONTEXT=$env:AUDIO_BUILD/windows-install-context.cmake" `
  "-DSTAGE_PREFIX=$env:AUDIO_STAGE" -P "$env:AUDIO_SOURCE/cmake/VerifyInstalledPackage.cmake"
if ($LASTEXITCODE -ne 0) { throw 'Installed audio package verification failed' }
```

The first CTest command includes all ten mandatory tests other than the exact
source-distribution contract. It must find tests; no other exclusions are
allowed. The final `make distcheck` below executes that eleventh test, including
another real build and all ten tests from extracted sources. This ordering
avoids duplicating the long archive gate while retaining every audio test.
None opens a physical playback/capture stream. Do not use `--rerun-failed`
as evidence of a fresh complete gate.

The install context pins inputs and automatically retains the baseline and
both component manifests. Do not edit it, replace its manifests, pass helper
state or invoke internal sealing instead of the public verifier. Verification
checks exact membership/hashes, recursive PE closure, licenses, and a fresh
Task 4 completion token from the installed Pure fixture. That process receives
only staged `bin` and authoritative Windows directories in PATH, with Pure
discovery variables cleared. Host DLLs or prior helper includes cannot rescue
a broken package.

For the audited 40-file Pure baseline, pure-audio owns **61 artifacts**:
22 runtime (five DLLs, six interfaces, eleven new dependency DLLs) and 39
documentation artifacts. The combined stage has 101 files and 29 PEs:
22 third-party DLLs and seven project-owned PEs (Pure executable/runtime plus
five modules). `libc++.dll` and `libwinpthread-1.dll` are baseline-owned reused
dependencies; all baseline bytes remain identical. The complete DLL mapping
includes the other nine baseline third-party DLLs, without transferring binary
ownership. The 27 full license/notice payloads comprise 24 third-party texts
and three Pure texts, plus the module's own `COPYING` in the package. Windows
system DLLs follow the explicit system policy, not staged third-party counts.
This is not a source/static-component audit of Pure, nor a claim that bundled
texts alone discharge every distribution obligation; see THIRD_PARTY.md.

## Source distribution and cleanup boundaries

Finish the audit with the public target:

```powershell
& C:/msys64/clang64/bin/mingw32-make.exe -C "$env:AUDIO_SOURCE" `
  SHELL=C:/msys64/usr/bin/sh.exe DIST_CMAKE=C:/msys64/clang64/bin/cmake.exe `
  "DIST_AUDIT_BUILD=$env:AUDIO_BUILD" distcheck
if ($LASTEXITCODE -ne 0) { throw 'Audio source distribution contract failed' }
```

For an **unbuilt standalone source tree**, archive creation also works without
an existing runner. Choose a fresh output under an existing, canonical
non-reparse directory:

```powershell
& C:/msys64/clang64/bin/mingw32-make.exe -C "$env:AUDIO_SOURCE" `
  SHELL=C:/msys64/usr/bin/sh.exe DIST_CMAKE=C:/msys64/clang64/bin/cmake.exe `
  DIST_OUTPUT_DIRECTORY=C:/releases dist
if ($LASTEXITCODE -ne 0) { throw 'Audio source archive failed' }
```

The literal manifest contains 92 regular source files, including all native
helper sources. Root names, timestamps and gzip metadata are deterministic;
source hardlinks become regular members without changing bytes. Producer
subprocesses clear TAR_OPTIONS and GZIP. Existing archive destinations and
unsafe ancestors/reparse inputs are rejected. `distcheck` verifies exact
members/hashes, extracts to an owned path containing spaces, performs all
release phases with the original checkout unavailable, and rescans the entire
extracted tree after those phases for new nonregular files or checkout path
leakage. The nested source test is excluded only to prevent recursion; the
other ten tests still run.

Clean helpers remove only declared owned outputs. Contract roots use exact
owner sentinels and enumerated cleanup; unknown/non-owned/reparse paths fail
closed. Failed evidence may be retained deliberately. Do not replace these
helpers with recursive deletion. Windows `diffs`/`deb` fail explicitly where
legacy POSIX prerequisites cannot satisfy the ownership contract; native
POSIX packaging has not been exercised on this host.

The installer serializes cooperating installers with an authenticated guard,
retains destination/ancestor identities against rename/reparse replacement,
and rejects pre-existing hardlinks on every writable batch endpoint before
the first write. Controlled pre-commit failures roll back owned bytes. This
is **not** isolation from a malicious same-principal process creating new
hardlinks after validation or writing stage contents directly. Process-crash
and power-loss atomicity are not promised. Do not infer stronger transaction
or adversarial isolation guarantees from the mutation tests.

## Sample layout and lifecycle support

Callback and blocking boundaries support interleaved samples and
`NonInterleaved` channel-pointer arrays; the queue is canonical, frame-aligned
interleaved data. Capacity is frames times channels, not interchangeable
frame/sample/byte counts. Float32, Int32, Int16, Int8 and UInt8 have numeric
conversion; UInt8 silence is 128, other supported formats use zero silence.
Int24 is an opaque three-byte raw sample at the callback/queue/buffer boundary,
**not** a newly advertised Pure numeric matrix conversion. CustomFormat is
rejected.

Public wrappers reject malformed channel shapes, negative/overflowing sizes
and unsupported odd FFT lengths. `sf_count_t` uses its 64-bit ABI. Playback
accounting distinguishes frames enqueued from callback-consumed frames;
consumption does not prove physical DAC rendering or audibility.

Close wakes/drains concurrent operations and callbacks before destruction.
If the native backend cannot close, stable inert callback storage and
synchronization are deliberately quarantined until process exit (three
allocation and three synchronization objects in the fault case), not falsely
reported as zero-resource successful close. Windows TSan was unavailable;
deterministic concurrency/resource counters and earlier focused ASan runs
are complementary evidence, not TSan coverage.

## Optional hardware tier

These targets use the same bounded runner but are never part of CTest or CI:

```powershell
& $env:CMAKE_EXE --build "$env:AUDIO_BUILD" --target check-audio-playback
if ($LASTEXITCODE -ne 0) { throw 'Optional playback check failed' }
& $env:CMAKE_EXE --build "$env:AUDIO_BUILD" --target check-audio-capture
if ($LASTEXITCODE -ne 0) { throw 'Optional capture check failed' }
```

The current fixture uses one channel and the selected device's default sample
rate. Playback queues 256 Float32 silence frames and waits at most 500 ten-ms
polls for consumption; the whole process has a 15-second limit. Capture reads
128 frames into memory, without saving or printing samples. Report the exact
device, rate, frame count and host when running this tier. `PURE_AUDIO_IN` and
`PURE_AUDIO_OUT` can select devices. Historical two-channel 44100-Hz results
belong to the older fixture, not a fresh audit of this one.

No hardware tier was run during audit hardening. Normal `SCHED_OTHER` is
tested; FIFO/RR privilege elevation, ASIO and every transitive codec format
are not promised. The deterministic file test covers WAV I/O. Actual file
symlink tests requiring unavailable Windows privilege are reported as skips,
not passes; real junction and attribute-seam tests provide separately named
reparse coverage. No elevation or Developer Mode is required or requested.
