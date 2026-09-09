# Task 9 — whole-branch review, consolidated fixes and final verification

Final status: **GREEN; closed on 2026-09-09**. The final section records the
separate full verification after clean scoped re-review. The initial fix-wave
section below is preserved as historical evidence of the earlier open state.

Date: 2026-09-09. Base: `2c168ce108ca9d4f8cec20ea015e23f18fed56b7`.
This report covers the one authorized implementation wave for the three
confirmed findings, not Task 9 closure. TODO-33 remains **Open**. The parent
requires one scoped re-review before the separate fresh full verification;
the slow outer ten-test suite and public distcheck were explicitly deferred
to that phase. No merge, push, hardware test, subagent or build/ deletion.

## Changes and boundaries

1. `audio.pure` checks bigint sign/range before conversion to native signed
   `long` for `open_stream` and raw-pointer read/write. Open sizes in the
   representable nonpositive range retain the historical 512-frame default;
   raw counts must also be nonnegative. Existing test-seam-only atomic entry
   counters in `audio.c` prove native open/transfer was not called. No production
   test exports or runtime counters were added. Four public assertions cover
   eight rejected inputs (two opens and six raw calls), two accepted zero raw
   transfers and three accepted default opens. The actual bigint values include
   `4294967296L` and `-4294967295L`; public bounds increases from 24 to 28 checks.
2. The native runner accepts repeatable, explicit `--hardware-device NAME=INDEX`
   arguments for exactly `PURE_AUDIO_IN` and `PURE_AUDIO_OUT`. Values are
   canonical decimal integers `0..2147483647`; unknown/duplicate names, empty
   values, signs, leading zeros, whitespace, globs, separators and overflow are
   rejected. The complete Unicode environment remains case-insensitively sorted
   (`PATH`, optional two selectors, `SystemRoot`, `TEMP`, `TMP`, `WINDIR`), never
   merged with ambient data. `RunHardwareTest.cmake` alone reads and validates
   the two optional environment selectors, passes typed variables explicitly
   through `RunPureTest.cmake`, and retains the 15-second hardware deadline.
   Tests use native child oracles, not real audio hardware. Normal runs prove
   poisoned ambient selectors and Pure discovery variables are absent.
3. `audio$(DLL)` in the legacy Makefile now depends on `audio_test_api.h`.
   The owned Make contract uses `-q` and `-q -W audio_test_api.h` to prove the
   current DLL is up to date but a changed header schedules rebuilding. Explicit
   empty compile/link flags keep this dependency-only probe independent of
   compiler/pkgconf discovery and timestamps.

Sibling audit: matrix audio and samplerate public wrappers already check
nonnegative bigint counts, native-long bounds and matrix capacity. FFTW wrapper
dimensions derive from actual matrices, not unchecked caller bigints. The 19
libsndfile `sf_count_t` declarations use signed `int64`, so the reported 32-bit
truncation does not occur at that boundary. Generated raw PortAudio/libsndfile
externs are ABI-level interfaces and are not arbitrary-bigint safety wrappers;
their callers must supply representable values and valid buffers. No unrelated
raw API or Pure core dimension change was made. WINDOWS.md explicitly records
these boundaries and distinguishes numeric runner selectors from the unchanged
public `audio::find_device` glob API.

## TDD and diagnosis

Evidence root: `C:/pure-lang/task9-fix/`. Initial logs are in `logs/`;
the final strict wave is in `logs2/`. Test setup uses Task 4-owned native leaves.

- `logs/bigint-red.log`: actual public test failed (CTest exit 8, 8.23 s),
  reporting `PUBLIC_NARROWING_ENTRY_DELTA open=2 raw=6` before the new guard
  assertion. This is direct pre-FFI behavioral evidence, not a source grep.
- `logs/runner-make-red.log`: two tests failed, total 19.75 s. Make reported
  pristine/header-newer `0/0` instead of `0/1`. Runner reported five transport
  failures: three unsupported direct options and both public hardware modes
  entered a child without the selected environment values.
- The first public GREEN attempt exposed two test-authoring errors (private
  declaration punctuation and stream-info indexing precedence), corrected
  before final runs. These are not counted as feature RED cases.
- Development-tree install seals correctly rejected edited source hashes and
  changed inventories. They were not deleted or bypassed; never-used strict
  `final/`, then `final2/` after the approved CMake change, supplied fresh seals.

ASan diagnosis and the explicitly approved narrow timeout adjustment:

- `logs/asan-tests.log`: native passed 30.47 s; public hit the original 45000 ms
  runner deadline (124), without an ASan diagnostic. The isolated unchanged
  public rerun in `asan-public-isolated.log` reproduced that deadline at 45.20 s.
- A diagnostic-only copy in owned ASan leaf
  `run-e12d16679063c722d3a3384bdab23a29` retained all 28 checks and added phase
  timestamps. With a diagnostic 90-second ceiling it completed in 49.974 s,
  then 47.845 s with timestamps. Import/JIT consumed approximately 22 s
  (`PHASE_SYSTEM` +2.9 s to `PHASE_IMPORTS` +24.9 s), followed by continuously
  completing checks through +46.9 s. There was no stuck native call or sanitizer
  error. This diagnostic is not substituted for actual fixture GREEN.
- Parent approved only ASan public-bounds inner **90000 ms** / outer **105 s**.
  CMake probes the configured compiler's sanitizer feature rather than matching
  a flags substring. Normal public bounds remains 45000 ms/60 s; other CTest
  budgets and hardware 15000 ms are unchanged. No general JIT-flake retry or
  timeout relaxation was introduced.
- `logs/asan-timeout-contract-red.log`: generated CTest inspection rejected the
  original 45000 value when independently requiring 90000. Final inspection
  checks all 11 strict tests / six non-strict tests, explicit inner argument
  identity, duplicates, exact outer properties, nonempty required core inventory
  and unchanged hardware deadline. The parent-supplied expected branch is also
  checked independently (normal 45000; ASan 90000).
- Five generated-file mutations in a Task 4-owned copy were all rejected:
  unrelated load outer=105, public outer-only=105, duplicate inner arguments,
  inner=900000 prefix confusion, missing public fixture. One copied pristine
  inventory passed and the exact owned leaf cleaned successfully. Logs:
  `logs2/timeout-*.log`. These five diagnostic mutations are separate from the
  recurring runner count, not silently added to it.

## Fresh GREEN evidence

Strict source: `C:/pure-lang/.worktrees/todo33-audit/pure-audio`.
Baseline: `C:/pure-lang/pure/build/windows-clang64-prefix` (40 files).
Final build: `C:/pure-lang/task9-fix/final2`; package: `final2/package`.
The exact first two actual workflow run strings were executed with concrete
local environment paths, strict explicit inputs and the declared sanitized
runtime PATH. Configure **6.5255044 s**; normal **23/23** build and **29 AMD64
PE32+** closure passed with two distinct `--parallel 4` commands, **7.9471052 s**
combined. The seal contains 74 records: runtime 22/documentation 39/baseline 13.
Logs: `logs2/{configure,build,pe}-pure-audio.log`.

Focused normal command:

```powershell
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task9-fix/final2 -R '^pure-audio-(fault-bounds|load|processing|public-bounds|runner-contract|cleanup-contract)$' -V --no-tests=error --parallel 4
```

`logs2/focused.log`: **6/6 PASS, 26.91 s** (load 7.18, native 8.71,
processing 9.97, public 12.29, cleanup 9.07, runner 19.65 s).
Native: **2391 checks**, ten concurrency iterations, 120 waiter completions,
ten callback drains, zero descriptors/native streams/owned sync outside the
intentional quarantine. Quarantine remains one orphaned stream, three retained
allocations and three retained synchronization objects; this is not a claim of
leak-free backend-close failure handling. Public: **28 checks**, native open/raw
entry delta **0/0**, token `PURE_AUDIO_DONE_5992265ae33a53f7e72960ecddd18ff5`.
Runner: **45 negatives / 13 positive controls / one descendant check**, plus
three executable-parent checks. Cleanup: **13 negatives / two controls**;
Make cleanup **6/2**; direct Make cleanup **64/24**; header dependency **one
mutation / one control**. After final inventory guard tightening the full runner
was rerun: **1/1 PASS, 18.67 s**, same counts (`logs2/runner-final.log`).

The dedicated non-strict ASan tree `C:/pure-lang/task9-fix/asan` uses Debug,
`-fsanitize=address -fno-omit-frame-pointer`, and matching EXE/SHARED/MODULE
sanitizer link flags, explicit CLANG64 tools and baseline pkgconfig roots.
Initial configure **4.2663156 s**, 18-action build **1.2555164 s**; after the
approved deadline change, reconfigure succeeded and Ninja had no work to do.
Actual, unmodified fixture command:

```powershell
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task9-fix/asan -R '^pure-audio-(fault-bounds|public-bounds)$' -V --no-tests=error --parallel 1
```

`logs/asan-final.log`: **2/2 PASS, 79.52 s**, native **28.58 s / 2391 checks**,
public **50.94 s / 28 checks**, entry delta **0/0**, no ASan diagnostic. Token:
`PURE_AUDIO_DONE_50568b3776da2eb896e1a80d1d0e7bef`.

Both component installs and public verifier used the unchanged actual fourth
workflow run string with the fresh final2 stage: **42.841542 s**, runtime **22**
and documentation **39**, exact added delta **61**, **27 license payloads**,
**29 PEs = 22 third-party DLLs + seven project-owned PEs**. Final stage has
**101 files**; independent SHA-256 comparison confirmed all **40 baseline files
unchanged**. Runtime batch reserved63 endpoints; documentation reserved41;
both published two conventional manifests, held identities and tore down.
Public token: `PURE_AUDIO_DONE_a4d92e15a3c5c06ae982e31394173520`.
Preserved manifests are under
`final2/install-audits/a5d1602efd5df00b4d34666c6eb1c412520564e24b74dfcbac891450c9402837`.
This is fresh pristine component/public verification, not a rerun of the slow
install mutation matrix. Existing whole-package license/threat boundaries stand.

Workflow and docs:

```powershell
C:/Python314/python.exe .github/scripts/test_validate_non_linux_release_workflow.py -v
C:/Python314/python.exe .github/scripts/validate_non_linux_release_workflow.py .github/workflows/non-linux-release-validation.yml
```

`logs2/workflow-tests.log`: **11/11 PASS, 53.410 s**, **386 distinct negative
scenarios** (324 audio +17 context +42 expansion +3 ODBC), **two pristine
variants / five controls**. Actual pristine CLI passed. No workflow/parser
source was changed in this wave. PowerShell AST parsing accepted **six actual
workflow blocks** (five audio plus semantic) and **five WINDOWS guide blocks**,
zero errors (`logs2/command-parser.log`).

Public standalone archive command, with the documented MSYS tool PATH and
an explicitly created, checked non-reparse output directory:

```powershell
C:/msys64/clang64/bin/mingw32-make.exe -C pure-audio SHELL=C:/msys64/usr/bin/sh.exe DIST_CMAKE=C:/msys64/clang64/bin/cmake.exe DIST_OUTPUT_DIRECTORY=C:/pure-lang/task9-fix/release2 dist
```

`logs2/dist-green.log`: **PASS, 2.0295903 s**, **92 files / 92 matching source
hashes / 247484 bytes**. Independent Python tarfile inspection verifies unique
regular entries, exact source bytes and uid/gid/mtime zero. Archive:
`C:/pure-lang/task9-fix/release2/pure-audio-0.6.tar.gz`, SHA-256
`c1c1eb3a82c25a5ac638ff9ea2bb6ebe200d078368a2b0cbc468edb981b9dc33`.
Two earlier invocation-setup mistakes (missing gzip PATH, then absent required
output directory) were rejected before publication; their logs are retained
as `logs2/dist.log` and `dist-final.log`, not counted as product regressions or
mutation GREEN. No full source mutation/pristine distcheck or extracted-source
end-to-end run is claimed for this wave; those remain required after re-review.

## Self-review and remaining closure work

TDD and systematic-debugging skills drove entry-counter behavior oracles,
native child transport controls, deterministic Make dependency probing and
the isolated ASan investigation. Verification-before-completion kept diagnostic,
fresh and historical evidence separate. Self-review checked signed bounds and
default compatibility, guards before native calls, production seam exclusion,
sorted explicit environment construction, integer overflow, duplicate options,
driver argument quoting, deadline scope, archive inclusion and retained seals.
`git diff --check` passes. Exactly 14 scoped files are intended for this commit:
12 pure-audio implementation/test/doc files, TODO-33 and this report. The ignored
progress ledger stays local and is not force-added. Pre-existing `build/` stays
untouched. Independent scoped re-review and Task 9 final closure are still open.

Observed versions: Clang/LLVM **22.1.8**, CMake **4.4.0**, Ninja **1.13.2**,
pkgconf **3.0.4**, Make **4.4.1**, GNU tar **1.35**, gzip **1.14**, Pure **0.68**,
PowerShell **7.6.5**, Python **3.14.5** / PyYAML **6.0.3**. Dependency versions:
PortAudio **19.7.0** (pkgconfig19), FFTW **3.3.11**, samplerate **0.2.2**,
sndfile **1.2.2**. Local CLANG64 Python lacks PyYAML; the independent Python314
interpreter ran the semantic checks, while CI explicitly declares python-yaml.
No hosted workflow, physical hardware, ASIO, elevated scheduling, TSan or native
POSIX result is claimed. The approved same-principal, crash/power-loss and
license-obligation limitations from Tasks 6–8 remain unchanged.

## Final verification and closure — 2026-09-09

After the parent's clean scoped re-review of `8aff6642664d9237dc2ae67103c89d88f7b4340f`,
the complete Task 9 gate was run without any product-code changes. The root
`C:/pure-lang/task9-final` was absent and its ancestors non-reparse before
creation. Both `pa9` (strict Release) and `asan` (instrumented Debug) were
never-before-used build directories; fixtures used the existing owned helpers.
Verification finished GREEN at **2026-09-09 17:42:52 UTC / 19:42:52 Europe/Prague**.
The earlier fix-wave section above is historical; its deferred gates have now
been completed, not assumed from old results. Only this report and TODO-33
are changed by the separate closure commit.

### Complete invocation record

All eight complete executed command scripts are preserved under
`C:/pure-lang/task9-final/commands/`; their SHA-256 values are in
`logs/command-hashes.sha256`. Scripts 1–5 contain the five actual workflow
bodies verbatim, with only concrete local environment values and timing
capture around them. They ran from the worktree's `pure/` directory.
The ASan, structural and parser scripts ran from the worktree root.
The exact native command arguments, full stdout/stderr and timing files are
retained under `C:/pure-lang/task9-final/logs/`.

The shared strict environment was:

```powershell
$env:AUDIO_SOURCE='C:/pure-lang/.worktrees/todo33-audit/pure-audio'
$env:AUDIO_BUILD='C:/pure-lang/task9-final/pa9'
$env:AUDIO_STAGE='C:/pure-lang/task9-final/pa9/package'
$env:AUDIO_PREFIX='C:/pure-lang/pure/build/windows-clang64-prefix'
$env:CMAKE_EXE='C:/msys64/clang64/bin/cmake.exe'
$env:CTEST_EXE='C:/msys64/clang64/bin/ctest.exe'
$env:LOG_DIR='C:/pure-lang/task9-final/logs'
$env:PATH='C:/pure-lang/pure/build/windows-clang64-prefix/bin;C:/msys64/clang64/bin;C:/msys64/usr/bin;C:/Windows/System32;C:/Windows'
$env:PURELIB=''
$env:PURE_INCLUDE=''
$env:PURE_LIBRARY=''
```

Exact strict configure body (all 32 explicit inputs and 24 runtime mappings):

```powershell
$ErrorActionPreference = 'Stop'
if ($env:AUDIO_BUILD.Length -gt 32) { throw 'Use an audio build root at most 32 characters long' }
if (Test-Path -LiteralPath $env:AUDIO_BUILD) { throw 'Fresh audio build already exists' }
& $env:CMAKE_EXE -S "$env:AUDIO_SOURCE" -B "$env:AUDIO_BUILD" -G Ninja `
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON `
  -DPURE_AUDIO_STRICT_WINDOWS_AUDIT=ON `
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
  "-DPURE_AUDIO_RUNTIME_SOURCES=pure.exe|$env:AUDIO_PREFIX/bin/pure.exe;libpure.dll|$env:AUDIO_PREFIX/bin/libpure.dll;libc++.dll|$env:AUDIO_PREFIX/bin/libc++.dll;libgmp-10.dll|$env:AUDIO_PREFIX/bin/libgmp-10.dll;libiconv-2.dll|$env:AUDIO_PREFIX/bin/libiconv-2.dll;libmpfr-6.dll|$env:AUDIO_PREFIX/bin/libmpfr-6.dll;libpcre-1.dll|$env:AUDIO_PREFIX/bin/libpcre-1.dll;libpcreposix-0.dll|$env:AUDIO_PREFIX/bin/libpcreposix-0.dll;libreadline8.dll|$env:AUDIO_PREFIX/bin/libreadline8.dll;libtermcap-0.dll|$env:AUDIO_PREFIX/bin/libtermcap-0.dll;libwinpthread-1.dll|$env:AUDIO_PREFIX/bin/libwinpthread-1.dll;libzstd.dll|$env:AUDIO_PREFIX/bin/libzstd.dll;zlib1.dll|$env:AUDIO_PREFIX/bin/zlib1.dll;libportaudio.dll|C:/msys64/clang64/bin/libportaudio.dll;libfftw3-3.dll|C:/msys64/clang64/bin/libfftw3-3.dll;libsamplerate-0.dll|C:/msys64/clang64/bin/libsamplerate-0.dll;libsndfile-1.dll|C:/msys64/clang64/bin/libsndfile-1.dll;libogg-0.dll|C:/msys64/clang64/bin/libogg-0.dll;libvorbisenc-2.dll|C:/msys64/clang64/bin/libvorbisenc-2.dll;libFLAC.dll|C:/msys64/clang64/bin/libFLAC.dll;libopus-0.dll|C:/msys64/clang64/bin/libopus-0.dll;libmpg123-0.dll|C:/msys64/clang64/bin/libmpg123-0.dll;libmp3lame-0.dll|C:/msys64/clang64/bin/libmp3lame-0.dll;libvorbis-0.dll|C:/msys64/clang64/bin/libvorbis-0.dll" `
  2>&1 | Tee-Object -FilePath "$env:LOG_DIR/configure-pure-audio.log"
if ($LASTEXITCODE -ne 0) { throw 'Strict pure-audio configure failed' }
```

The remaining strict/public native invocations, in order, were:

```powershell
& $env:CMAKE_EXE --build "$env:AUDIO_BUILD" --parallel 4
& $env:CMAKE_EXE --build "$env:AUDIO_BUILD" --target verify-windows-dependencies --parallel 4
# Fresh ASan configure/build/tests ran here, as specified below.
& $env:CTEST_EXE --test-dir "$env:AUDIO_BUILD" -L "^audio$" -LE "^hardware$" -E "^pure-audio-source-dist-contract$" --output-on-failure --no-tests=error --parallel 4
# The complete LastTest.log was copied to logs/ctest-outer-detailed.log here.
& $env:CMAKE_EXE -E copy_directory "$env:AUDIO_PREFIX" "$env:AUDIO_STAGE"
& $env:CMAKE_EXE --install "$env:AUDIO_BUILD" --prefix "$env:AUDIO_STAGE" --component runtime
& $env:CMAKE_EXE --install "$env:AUDIO_BUILD" --prefix "$env:AUDIO_STAGE" --component documentation
& $env:CMAKE_EXE "-DAUDIO_INSTALL_CONTEXT=$env:AUDIO_BUILD/windows-install-context.cmake" "-DSTAGE_PREFIX=$env:AUDIO_STAGE" -P "$env:AUDIO_SOURCE/cmake/VerifyInstalledPackage.cmake"
& C:/msys64/clang64/bin/mingw32-make.exe -C "$env:AUDIO_SOURCE" SHELL=C:/msys64/usr/bin/sh.exe DIST_CMAKE=C:/msys64/clang64/bin/cmake.exe "DIST_AUDIT_BUILD=$env:AUDIO_BUILD" distcheck
```

The saved scripts retain every corresponding Tee-Object, fresh-directory
precondition and immediate nonzero-LASTEXITCODE throw. There was no retry,
`--rerun-failed`, extra exclusion, focused-only source flag or fixture bypass.
The initial JSON inventory independently confirmed exactly ten selected tests;
the public distcheck executed exactly the deferred eleventh CTest contract.

Fresh ASan used the same explicit PATH plus
`C:/msys64/clang64/lib/clang/22/lib/windows`, empty Pure discovery variables,
`MSYSTEM_PREFIX=C:/msys64/clang64`, and
`PKG_CONFIG_PATH=C:/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig;C:/msys64/clang64/lib/pkgconfig`.
Exact native arguments from `commands/asan.ps1`:

```powershell
C:/msys64/clang64/bin/cmake.exe -S C:/pure-lang/.worktrees/todo33-audit/pure-audio -B C:/pure-lang/task9-final/asan -G Ninja -DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/ninja.exe -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON '-DCMAKE_C_FLAGS=-fsanitize=address -fno-omit-frame-pointer' -DCMAKE_EXE_LINKER_FLAGS=-fsanitize=address -DCMAKE_SHARED_LINKER_FLAGS=-fsanitize=address -DCMAKE_MODULE_LINKER_FLAGS=-fsanitize=address -DPURE_AUDIO_MAKE_EXECUTABLE=C:/msys64/clang64/bin/mingw32-make.exe -DPURE_AUDIO_SH_EXECUTABLE=C:/msys64/usr/bin/sh.exe
C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/task9-final/asan --parallel 4
C:/msys64/clang64/bin/cmake.exe -DMODULE_DIR=C:/pure-lang/task9-final/asan -DPURE_SOURCE_DIR=C:/pure-lang/.worktrees/todo33-audit/pure-audio -DEXPECT_PUBLIC_BOUNDS_TIMEOUT=90000 -DTIMEOUT_CONTRACT_ONLY=ON -P C:/pure-lang/.worktrees/todo33-audit/pure-audio/tests/runner_contract.cmake
C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/task9-final/asan -R '^pure-audio-(fault-bounds|public-bounds)$' -V --no-tests=error --parallel 1
```

Final structural commands used `PYTHONDONTWRITEBYTECODE=1`:

```powershell
C:/Python314/python.exe C:/pure-lang/.worktrees/todo33-audit/.github/scripts/test_validate_non_linux_release_workflow.py -v
C:/Python314/python.exe C:/pure-lang/.worktrees/todo33-audit/.github/scripts/validate_non_linux_release_workflow.py C:/pure-lang/.worktrees/todo33-audit/.github/workflows/non-linux-release-validation.yml
& C:/pure-lang/task9-final/commands/parse.ps1
git diff --check 7c88827e..HEAD
git status --short
```

The parser independently loads the current YAML using BaseLoader, selects the
six exact actual step names and parses their run bodies plus all five guide
PowerShell fences with `Management.Automation.Language.Parser.ParseInput`.
It does not substitute the saved execution-script wrappers for actual workflow
content.

### Fresh results, counts and timing

| Phase | Fresh result |
| --- | --- |
| Strict Release configure | PASS, 6.5574256 s |
| Normal build / separate PE target, each four workers | 23/23 actions / 29 AMD64 PE32+; 7.6075985 s combined |
| Fresh ASan configure / build | PASS, 4.6887257 s / 18 actions, 1.2184614 s |
| Actual ASan native / public fixtures | 2/2 PASS, 79.31 s CTest / 79.3693747 s wall; 28.91 / 50.40 s |
| Outer mandatory no-hardware tests | 10/10 PASS, 1165.81 s CTest / 1165.8888829 s wall |
| Outer install / guard individual tests | 806.72 / 340.46 s |
| Outer runtime + documentation + public package verification | PASS, 43.3765545 s |
| Public make distcheck | 1/1 PASS, 1472.07 s CTest / 1472.277236 s wall |
| Pristine extracted mandatory tests | 10/10 PASS, 1212.26 s |
| Extracted install / guard individual tests | 825.47 / 367.65 s |
| Final YAML mutations / actual pristine CLI | 11/11 PASS, 51.807 s unittest / 52.4532545 s combined wall |
| Final PowerShell AST parsing | 6 workflow +5 guide blocks, zero errors |

Each complete ten-test run independently reports **416 rejected scenarios,
79 positive controls and six pristine packages**. The breakdown is runner/
cleanup/Make **129 negatives /42 controls** (including the new header probe),
strict configure **119/4**, runtime verifier **41/3**, install **99 negatives /
10 controls /four pristine**, and guard **28 negatives /20 controls /two
pristine**. Each run has **two explicit file-symlink privilege1314 skips**, not
counted as negatives; real junction and injected file-reparse contracts run.
Both generated timeout inventories confirm normal public45000/60 and
hardware15000; the separate fresh ASan inventory confirms90000/105 only there.

Native harnesses report **2391 checks**; actual public fixtures **28 checks**
and native open/raw delta **0/0**. Each native lifecycle run includes ten
iterations,120 waiter completions,10 callback drains and the unchanged
intentional quarantine (one orphan/three allocations/three sync objects).
Fresh ASan has no sanitizer diagnostic. Its token is
`PURE_AUDIO_DONE_163d4c6889365e5adf2fc3f07ea095e7`.

Both outer and pristine extracted packages have runtime **22**, documentation
**39**, exact added delta **61**, license payloads **27**, **29 PEs**
(22 third-party DLLs +seven project-owned PEs), and **101 files** including
the unchanged **40-file baseline**. Independent end-of-run checks compare all
40 original baseline hashes against both stages, not merely module presence.
Install mutations also confirm identical-existing-file delta60 and empty/no-op
delta0. Each guard run proves three concurrent installers, zero outside writes,
12 controlled pre-commit rollback cases and12 successful retries.

Outer public token:
`PURE_AUDIO_DONE_470f745514abbe6afb909c9c508aa8c0`.
Outer preserved component manifests:
`pa9/install-audits/ff2650ffdedbd0d916ec13d181846416538b917c606dcdf4b6d5c8f1e24c9f24`.
Extracted public token:
`PURE_AUDIO_DONE_24ff44bf11f8f63c9a89b17b1b8f80d3`.

Source evidence:
`C:/pure-lang/task9-final/pa9/pure-audio-contract-root/run-768d813e70aa16826074f89c5cfbe5d1`.
The pristine extracted short build is
`C:/pure-lang/task9-final/pa9/d-EPJcUVYadyjIU2_hCfrajg`.
The source matrix reports **34 negatives /one pristine /seven controls**,
including real hardlink topology and both real post-configure rejection cases.
Each postflight negative completes all seven phases and four real core tests;
the unmodified pristine fixture runs all ten. Pristine extracted phase timers
(integer seconds) are configure7/build4/PE4/tests1212/runtime11/docs9/verifier24.
Initial and final extracted-source scans cover92 files; final build73, stage101
and raw-log17 scans pass, with no size cutoff. All184 original/producer read
exclusion handles (two roots) are released. The eight pristine raw stderr
captures in `logs/` are empty. The owned short-build/MAX_PATH mutation reports
a202-character test budget and successful exact cleanup/outside preservation.

Archive has **92 unique regular files /92 source hashes /247484 bytes**:
`producer checkout with spaces/pure-audio-0.6.tar.gz` under the source evidence
root. SHA-256:
`c1c1eb3a82c25a5ac638ff9ea2bb6ebe200d078368a2b0cbc468edb981b9dc33`.
Its repeat and ambient-poisoned counterparts are byte-identical. The two
topology fixtures (241759 bytes each) both hash to
`539e2412b61b45653a4a515133e1a25ba85585b91ab6476e5f057c7a7a804aaf`.
All five archive hashes/sizes were checked again after the complete gate.
Independent tarfile inspection confirms regularity, uniqueness, exact original
source bytes and uid/gid/mtime zero. All92 tracked source hashes still match
the pre-run snapshot.

Final structural suite has **386 distinct negatives** (324 audio +17 execution
context +42 expansion +3 ODBC), **two pristine variants /five controls**.
The actual pristine CLI and6+5 PowerShell AST parses pass. These are fresh
results: **51.807 s** belongs to this final closure; the earlier fix-wave
structural run took53.410 s.

### Final integrity diagnostic and limitations

A supplemental ad-hoc checker initially compared the physical CRLF TSV hash
to the inventory's **canonical LF-text** pin and correctly halted that checker.
Closure was paused for diagnosis. `VerifyInstalledPackage.cmake:165–179`
explicitly sorts/joins rows with LF and uses `string(SHA256)`, then compares
canonical file-read text; it does not define the TSV pin as raw file SHA.
The corrected independent checker normalizes CRLF to LF, verifies both74-row
pins, then independently verifies every row's source **raw-byte SHA-256**
(**148 rows total**) and both native guard executable pins. All pass
(`logs/final-seal-checks.log`). No product file, stored pin, test deadline or
gate was changed, and no failed product test was retried or concealed.

The final whole-branch diff check from `7c88827e` passes. Before closure edits,
Git reports only the preserved pre-existing untracked `build/`. All fresh
evidence/builds are under the explicitly created `task9-final` root; no old
workspace/build artifact was removed. The ignored progress ledger remains local.
Executing-plans and verification-before-completion governed sequencing and
evidence; systematic debugging resolved the supplemental checker's serialization
mistake before closure. Per the explicit instruction, the finishing workflow
keeps branch `codex/todo33-audit` and its worktree unchanged: no merge or push.

Fresh versions remain Clang/LLVM22.1.8, CMake4.4.0, Ninja1.13.2, pkgconf3.0.4,
Make4.4.1, GNU tar1.35, gzip1.14, Pure0.68, PowerShell7.6.5,
Python3.14.5/PyYAML6.0.3; PortAudio19.7.0 (pkgconfig19), FFTW3.3.11,
samplerate0.2.2, sndfile1.2.2. Native MSYS helpers used the tool sandbox
override, not OS elevation. No fresh physical hardware/ASIO/elevated scheduling,
TSan, native POSIX or remote hosted-workflow claim is made; local CLANG64 Python
still lacks PyYAML and Python314 supplied the required parser. Only tested WAV
processing is advertised, not every transitive codec. The documented close-failure
quarantine, hostile same-principal exclusion, crash/power-loss boundary and
source/static/full-distribution license-obligation limitations remain explicit.
All approved mandatory Task9 gates are now GREEN.
