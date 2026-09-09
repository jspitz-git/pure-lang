# Task 9 — consolidated whole-branch review fix wave

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
