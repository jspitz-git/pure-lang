# Windows pure-midi build and runtime

The supported audit configuration is native Windows x86-64, MSYS2 CLANG64
Clang/LLVM 22, Ninja, and staged portable Pure 0.68. It produces `pmlib.dll`
and `midifile.dll` with public `midi`, `portmidi`, and `midifile`
interfaces. MSYS2 supplies build tools; installed programs/modules use native
Windows DLLs and must not import `msys-2.0.dll`, libgcc or libstdc++.

## Prerequisites and versions

Install MSYS2 at `C:/msys64`. In its CLANG64 shell:

```sh
pacman -S --needed make mingw-w64-clang-x86_64-clang \
  mingw-w64-clang-x86_64-cmake mingw-w64-clang-x86_64-llvm \
  mingw-w64-clang-x86_64-ninja mingw-w64-clang-x86_64-pkgconf \
  mingw-w64-clang-x86_64-make mingw-w64-clang-x86_64-python-yaml \
  mingw-w64-clang-x86_64-portmidi mingw-w64-clang-x86_64-gmp \
  mingw-w64-clang-x86_64-mpfr mingw-w64-clang-x86_64-libc++ \
  mingw-w64-clang-x86_64-libiconv mingw-w64-clang-x86_64-pcre \
  mingw-w64-clang-x86_64-readline mingw-w64-clang-x86_64-termcap \
  mingw-w64-clang-x86_64-winpthreads mingw-w64-clang-x86_64-zstd \
  mingw-w64-clang-x86_64-zlib
```

MSYS2's base installation supplies `usr/bin/sh.exe`. Native Windows
PowerShell/.NET is required for runner, package and archive contracts. First
build/stage portable Pure using the core's Windows instructions. Its prefix
must contain the executable, headers (including `glob.h`), import library,
Pure standard library and complete runtime closure, and remain unchanged
throughout configuration, builds, tests and installation.

The local audit used Clang/llvm-readobj 22.1.8 targeting
`x86_64-w64-windows-gnu`, CMake 4.4.0, Ninja 1.13.2, pkgconf 3.0.4,
GNU Make 4.4.1 and Pure 0.68 built for LLVM 22.1.8. PortMidi is pinned to
`mingw-w64-clang-x86_64-portmidi 1~2.0.8-1`; its pkg-config file reports
2.0.7. Strict configuration checks the pinned package payloads, not that
pkg-config version. See [THIRD_PARTY.md](THIRD_PARTY.md).

These are version-sensitive inputs. Rolling MSYS2 updates may fail the frozen
PortMidi hashes or recursive PE import policy. Updating the policy requires
inspecting the new package, recording origins/license and rerunning the full
gate. Normal non-strict upstream CMake remains available but does not provide
this audit contract.

## Strict standalone gate

Run these PowerShell blocks from the repository root. Set the local source,
staged Pure prefix and never-used short build paths for your machine. Inputs
must be canonical ordinary paths with no symlink, junction or other reparse
ancestor. Keep the build root at most 32 characters long for nested Windows
tests. Retain failed builds as evidence and select a fresh root for a new gate.

```powershell
$ErrorActionPreference = 'Stop'
$midiSource = (Resolve-Path ./pure-midi).Path.Replace('\', '/')
$midiPrefix = 'C:/pure-lang/pure/build/windows-clang64-prefix'
$midiBuild = 'C:/pure-lang/m8'
$midiStage = "$midiBuild/package"
$midiDist = 'C:/pure-lang/s8'
$midiTools = 'C:/msys64/clang64'
$env:PATH = "$midiPrefix/bin;$midiTools/bin;C:/msys64/usr/bin;C:/Windows/System32;C:/Windows"
Remove-Item Env:PURELIB, Env:PURE_INCLUDE, Env:PURE_LIBRARY -ErrorAction SilentlyContinue
function Assert-MidiExit {
  if ($LASTEXITCODE -ne 0) { throw "MIDI command failed: $LASTEXITCODE" }
}
if ($midiBuild.Length -gt 32 -or (Test-Path -LiteralPath $midiBuild)) {
  throw 'Choose a fresh MIDI build root at most 32 characters long'
}
$midiRuntime = @(
  'pure.exe', 'libpure.dll', 'libc++.dll', 'libgmp-10.dll', 'libiconv-2.dll',
  'libmpfr-6.dll', 'libpcre-1.dll', 'libpcreposix-0.dll', 'libreadline8.dll',
  'libtermcap-0.dll', 'libwinpthread-1.dll', 'libzstd.dll', 'zlib1.dll'
) | ForEach-Object { "$_|$midiPrefix/bin/$_" }
$midiRuntime += "libportmidi.dll|$midiTools/bin/libportmidi.dll"
& "$midiTools/bin/cmake.exe" -S $midiSource -B $midiBuild -G Ninja `
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON -DPURE_MIDI_STRICT_WINDOWS_AUDIT=ON `
  "-DCMAKE_C_COMPILER=$midiTools/bin/clang.exe" `
  -DCMAKE_C_COMPILER_TARGET=x86_64-w64-windows-gnu `
  "-DCMAKE_MAKE_PROGRAM=$midiTools/bin/ninja.exe" `
  "-DPKG_CONFIG_EXECUTABLE=$midiTools/bin/pkgconf.exe" `
  "-DLLVM_READOBJ=$midiTools/bin/llvm-readobj.exe" `
  "-DPURE_MIDI_MAKE_EXECUTABLE=$midiTools/bin/mingw32-make.exe" `
  -DPURE_MIDI_SH_EXECUTABLE=C:/msys64/usr/bin/sh.exe `
  "-DPURE_MIDI_CLANG64_PREFIX=$midiTools" "-DPURE_MIDI_PURE_PREFIX=$midiPrefix" `
  "-DPURE_INCLUDE_DIR=$midiPrefix/include" `
  "-DPURE_EXECUTABLE=$midiPrefix/bin/pure.exe" `
  "-DPURE_HEADER=$midiPrefix/include/pure/runtime.h" `
  "-DPURE_GLOB_HEADER=$midiPrefix/include/glob.h" `
  "-DPURE_IMPORT_LIBRARY=$midiPrefix/lib/libpure.dll.a" `
  "-DPURE_RUNTIME_DLL=$midiPrefix/bin/libpure.dll" `
  "-DPORTMIDI_HEADER=$midiTools/include/portmidi.h" `
  "-DPORTTIME_HEADER=$midiTools/include/porttime.h" `
  "-DPORTMIDI_IMPORT_LIBRARY=$midiTools/lib/libportmidi.dll.a" `
  "-DPORTMIDI_RUNTIME_DLL=$midiTools/bin/libportmidi.dll" `
  "-DGMP_HEADER=$midiTools/include/gmp.h" "-DMPFR_HEADER=$midiTools/include/mpfr.h" `
  "-DPURE_MIDI_WINDOWS_HEADER=$midiTools/include/windows.h" `
  -DPURE_MIDI_WINDOWS_SYSTEM_DIRECTORY=C:/Windows/System32 `
  "-DPURE_MIDI_RUNTIME_SOURCES=$($midiRuntime -join ';')"
Assert-MidiExit
& "$midiTools/bin/cmake.exe" --build $midiBuild --parallel 4
Assert-MidiExit
& "$midiTools/bin/cmake.exe" --build $midiBuild --target verify-windows-dependencies --parallel 4
Assert-MidiExit
& "$midiTools/bin/ctest.exe" --test-dir $midiBuild -L '^no-hardware$' -LE '^hardware$' `
  --output-on-failure --no-tests=error -V
Assert-MidiExit
```

The two build calls are distinct invocations in one strict tree. The normal
build includes Release and AddressSanitizer harnesses. All 19 mandatory CTests
run: lifecycle/concurrency, boundary and malformed-file faults, public Pure
suites, runner/cleanup, configuration/PE mutations, archive mutations and both
install contracts. They never open a physical or virtual MIDI port. Enumeration
and clock tests do not establish successful hardware I/O.

Pure runs through the native bounded runner, which replaces PATH with explicit
module/runtime and Windows system directories, clears Pure discovery variables,
preserves child exit status and requires a fresh completion token after all
assertions and owned cleanup. MSYS2's `usr/bin` is only on the outer build-tool
PATH; it is absent from the installed test child's PATH.

## Exact package and source verification

Continue in the same PowerShell session:

```powershell
if (Test-Path -LiteralPath $midiStage) { throw 'MIDI stage must be fresh' }
& "$midiTools/bin/cmake.exe" -E copy_directory $midiPrefix $midiStage
Assert-MidiExit
& "$midiTools/bin/cmake.exe" --install $midiBuild --prefix $midiStage --component runtime
Assert-MidiExit
& "$midiTools/bin/cmake.exe" --install $midiBuild --prefix $midiStage --component documentation
Assert-MidiExit
& "$midiTools/bin/cmake.exe" "-DMIDI_INSTALL_CONTEXT=$midiBuild/windows-install-context.cmake" `
  "-DSTAGE_PREFIX=$midiStage" -P "$midiSource/cmake/VerifyInstalledPackage.cmake"
Assert-MidiExit
& "$midiTools/bin/cmake.exe" -E make_directory $midiDist
Assert-MidiExit
& "$midiTools/bin/mingw32-make.exe" -C $midiSource distcheck DLL=.dll `
  "CMAKE=$midiTools/bin/cmake.exe" "CLANG64_PREFIX=$midiTools" `
  "PURE_PREFIX=$midiPrefix" "DIST_ROOT=$midiDist" "DIST_DIR=$midiDist" `
  SHELL=C:/msys64/usr/bin/sh.exe
Assert-MidiExit
```

The stage starts as a copy of portable Pure. Separate runtime/documentation
manifests check path, type, size and SHA-256 for the complete unchanged baseline
plus the exact declared delta. Installed verification repeats staged-only PE
closure and runs two installed Pure tests through the same runner.

Six runtime files are added: two modules, three interfaces and PortMidi.
Eleven documentation files are added: four documents, PortMidi license and
origins inventory, two examples (including the MIDI fixture), and three Pure
tests. The local baseline has 49 entries; its final tree has 71 entries
(57 files, 14 directories). Counts describe that baseline; exact manifests
determine acceptance. The recursive AMD64 PE32+ closure has 16 files: both
modules and all 14 declared runtime sources, including `pure.exe`. It checks
complete headers/imports, origins/hashes and Windows System32/API-set resolution.
A DLL on the host PATH cannot repair an incomplete stage.

Public `make distcheck` creates two byte-identical ordered 63-file archives,
extracts under a path with spaces, denies access to all original source inputs,
then runs strict configure, both four-worker builds, all 19 tests, both installs
and installed verification solely from extraction. Every generated file/log is
scanned for checkout paths. The archive matrix is nonrecursive; the extracted
workflow is an explicit public target. For archive generation alone, replace
`distcheck` with `dist` in that command.

Archive/manifest publication is paired for cooperating publishers. Unrecovered
failure retains recovery evidence and refuses later publication; inspect the
retained old bytes before removing recovery metadata. Package/source cleanup
uses unique token-owned leaves and rejects reparses. Installation covers
cooperating installers, serialization and controlled rollback. It does not
claim protection against an actively malicious same-account process or
whole-tree atomicity across power loss. Archive tooling currently requires
Windows PowerShell/.NET; native POSIX `make dist`/Debian packaging has not
been verified in this audit.

## Public event layouts and rejection

Byte messages use nonempty contiguous integer row or column vectors, with all
values in `0..255`. `midi::word` accepts one to four bytes. `midi::bytes`
accepts a nonnegative machine integer or bigint through `0xffffffffL` and
returns four little-endian bytes. Buffered `read`/`write` use contiguous
`n x 2` integer matrices: each row is `(packed message, timestamp)`. Empty,
strided, misaligned, wrong-shaped or unrepresentable buffers are rejected.

`writemsg stream time bytes` requires an output stream and nonnegative
signed-32-bit timestamp. Channel/system short messages have their MIDI lengths;
the historical four-byte form remains accepted with zero unused trailing bytes.
SysEx output begins `0xf0`, ends `0xf7`, and has seven-bit interior data.
`readmsg` returns `(timestamp, bytes)`; short messages retain their historical
four-byte padded vectors. Blocking reads observe terminal stream state.

A Standard MIDI File track is a list of exact `(tick, bytes)` tuples, with
ticks in `0..2147483647`. File channel events require exact MIDI lengths
and seven-bit data. Meta events use `{0xff, type, payload...}` with at least
status/type; `{0xff,0x2f}` has no payload and is handled by the serializer.
File SysEx vectors start `0xf0` or `0xf7` with representable nonzero length.
Constructors accept format 0/1/2, musical division 0 with resolution 1..32767,
or SMPTE division 24/25/29/30 with resolution 1..255. The bundled two-track,
1632-event fixture retains its valid round trip.

Malformed chunks, truncation, invalid running status, oversized/overlong lengths,
invalid events and allocation/short-I/O failures use existing null/false/error
or unevaluated Pure expression conventions. Check return values: an unevaluated
expression is not success. Failed `put_track`/`put_tracks` calls roll back
all tracks/events created by that call. A failed save does not promise a valid
output file. Stream misuse returns errors such as `BadPtr`/`BadData`.

Streams carry owned input/output state and active-operation synchronization.
Close excludes new I/O, waits for current operations and invalidates aliases;
repeated close/finalization is deterministic. A failed native close quarantines
its handle until process exit, preventing reuse. `midi::stop` closes owned
streams before termination, reports failure and prevents unsafe restart around
quarantined handles. Timer state is tracked through partial initialization and
repeated shutdown.

## Optional output and true loopback

Optional output requires an explicit runtime selector: a decimal device index
or exact, unique `interface:name` match. Globs and old `PURE_MIDI_OUT`
are unsupported.

```powershell
$env:PURE_MIDI_TEST_OUTPUT = 'MMSystem:Microsoft MIDI Mapper'
& "$midiTools/bin/cmake.exe" --build $midiBuild --target check-midi-output
Assert-MidiExit
Remove-Item Env:PURE_MIDI_TEST_OUTPUT
```

Run only with an intentionally selected output. The runner imposes a 12-second
child timeout. The script prints the device, sends middle-C Note On at velocity
32, waits 100 ms, attempts Note Off on cleanup, closes and stops. Mandatory
fake-backend tests verify selector and cleanup behavior.

The historical July 28, 2026 output test passed on `MMSystem` device 0,
`Microsoft MIDI Mapper`; that host exposed two outputs and no input. This
audit has not repeated physical output. True loopback needs connected input
and output, explicit selectors, bounded send/receive comparison and cleanup;
there is no implemented passing loopback target. Output-only success or absent
hardware cannot be recorded as loopback.

Windows ThreadSanitizer, physical/virtual MIDI ports, driver timing accuracy,
real loopback, native POSIX behavior and hosted-CI duration remain unverified.
Release/ASan fault and concurrency tests do not substitute for those results.
TODO-34 remains open until final Task 9 review.
