# TODO-34 - Windows pure-midi Package

Status: Closed on 2026-09-11
Branch: todo/34-windows-pure-midi

## Purpose

Build, validate, and package `pure-midi` with PortMidi on Windows.

## Scope

- Build the native module and bundle the compatible PortMidi runtime.
- Cover device enumeration, message conversion, timing, and cleanup.
- Separate deterministic tests from tests requiring MIDI hardware.

## Task List

1. [x] Build the module against the staged runtime and PortMidi.
2. [x] Audit Windows device and timing behavior.
3. [x] Add deterministic encoding and no-device smoke tests.
4. [x] Run documented loopback or hardware validation.
5. [x] Stage and inspect the complete package.
6. [x] Harden checked MIDI file I/O, Pure event/matrix boundaries and owned
   PortMidi stream lifecycle (audit Tasks 1–3).
7. [x] Make mandatory tests hermetic with bounded native execution, final
   completion tokens and token-owned cleanup (Task 4).
8. [x] Require explicit strict toolchain inputs and recursive pinned PE closure
   (Task 5).
9. [x] Verify exact runtime/documentation installation and license origins
   (Task 6).
10. [x] Verify deterministic complete source archives and an independent
    extracted-source gate (Task 7).
11. [x] Add structural Windows CI mutation tests, audited documentation and a
    fresh Task 8 gate.
12. [ ] Complete Task 9 whole-branch review and fresh final validation before
    closing this TODO.

## Guardrails

- Absence of MIDI hardware must not crash or hang the test suite.
- Device handles must be closed on every exit path.

## Validation Plan

- Exercise enumeration and MIDI message conversion with bounded timeouts.
- Run a loopback test when a suitable virtual or physical device is available.

## Progress Log

- 2026-07-25: Created as an optional multimedia Windows package candidate.
- 2026-07-28: Installed CLANG64 PortMidi 2.0.8 (pkg-config version 2.0.7)
  and built `pmlib.dll` and `midifile.dll` as strict-warning x86-64 PE
  modules. Hardened both legacy clean targets. Commit: `2ec07fc2`.
- 2026-07-28: Audited the runtime closure: one `libportmidi.dll`, native
  WinMM device/timing backend, UCRT, and no MSYS/GNU runtime. Added bounded
  enumeration, PortTime, restart, and cleanup checks. Commit: `4191585e`.
- 2026-07-28: Added deterministic MIDI word/byte conversion, invalid-port,
  and Standard MIDI File round-trip tests. The bundled fixture has two tracks
  and 1632 events; both hardware-free CTests pass. Commit: `ed635d3f`.
- 2026-07-28: The 15-second-bounded output test passed twice on `MMSystem`
  device 0, `Microsoft MIDI Mapper`, with explicit Note Off and stream close.
  The host exposed two outputs and no inputs, so no loopback result is
  claimed. Commit: `2c051294`.
- 2026-07-28: Installed and verified a 16-file package delta: two modules,
  three Pure interfaces, PortMidi runtime, four package documents, one
  third-party license, two examples, and three test scripts. Both installed
  hardware-free tests pass with empty `PURELIB` and a sanitized staged-only
  runtime `PATH`.
- 2026-07-28: The complete portable prefix audit passes with 13 DLLs,
  12 resolved non-system dependency paths, and 56 staged files.

## Reopened audit — September 2026

The July progress log above is preserved as historical evidence. The September
audit reopened this TODO because the original two smoke tests and package count
did not establish malformed-file safety, exact Pure value boundaries, stream
alias/concurrency safety, hermetic execution, owned cleanup, immutable toolchain
inputs, recursive PE closure, exact installation/licensing, deterministic source
delivery or an enforced Windows CI gate. The active isolated audit branch is
`codex/todo34-audit`, based on `d751658e8b1f4497e1f143b48da6c90a61854ef8`.
The original branch field remains a historical record.

Reviewed task commits, including each review correction:

| Task | Commits | Result |
| --- | --- | --- |
| 1, checked file I/O | `9907482c`, `f20a9741` | checked parsing/save, allocation rollback, fault/deadline coverage |
| 2, event boundary | `d1e56f54`, `f2d578c1`, `0895edd1` | validated matrices/events, preserved padded short messages, absolute alignment |
| 3, stream lifecycle | `1bd8a9f8`, `41fc4b28` | owned aliases, deterministic close/quarantine, shutdown continues past a pending close |
| 4, hermetic runner | `6fb287f7`, `ffbc8c8c` | explicit child environment, deadlines, completion after owned cleanup |
| 5, strict inputs/PE | `cd8d3469`, `d82197e9` | immutable explicit inputs and complete recursive PE policy |
| 6, exact installation | `4c738661`, `1c3beb7c` | pinned complete baseline, guarded component dispatch and license inventory |
| 7, source delivery | `a7b40c89`, `7eab4076` | complete archive/extracted gate and paired archive/manifest recovery |
| 8, CI and documentation | this commit, `Validate pure-midi in Windows CI` | structural YAML contract, audited commands and corrected fresh checkout/extracted gates |

The binding design and implementation plan are
`docs/superpowers/specs/2026-09-10-windows-pure-midi-audit-hardening-design.md`
and `docs/superpowers/plans/2026-09-10-windows-pure-midi-audit-hardening.md`.
Detailed RED/GREEN transcripts, review rounds and the ledger are retained in the
ignored task-local directory
`.superpowers/sdd/2026-09-10-windows-pure-midi-audit-hardening/`.
Task 7's final reviewed checkout gate passed 19/19 in 1189.59 seconds;
its extracted gate passed 19/19 in 1185.78 seconds. The verified Task 7 archive
contained 63 regular files, SHA-256
`d15e9098190874ca8861f8c29fd4d9ee1966056436f21ed6137eafa3ec582239`.
Those are prior-task results, not the changed documentation's new archive hash.

### Task 8 RED and workflow implementation

The status was changed to Open before writing independent PyYAML fixtures.
Against the old workflow and old validator:

```powershell
& C:/Python314/python.exe .github/scripts/test_validate_non_linux_release_workflow.py MidiWorkflowMutationTests -v
```

Exit 1: three methods ran in 55.004 seconds, with 315 failures: the actual
workflow omitted the mandatory MIDI gate, and 314 of the 374 independently
authored mutations were incorrectly accepted. Six independent valid variants
passed. Existing shared checks already rejected the remaining 60 mutations.
The full RED output is `task-8-workflow-red.log`.

The implemented gate follows portable Pure staging: explicit CLANG64 PortMidi
prerequisites, fresh short strict Release configuration, separate normal/PE
`--parallel 4` builds in one tree, every mandatory no-hardware CTest with
`--no-tests=error`, fresh baseline copy, runtime and documentation installs,
complete installed verification, and public `make distcheck`.
Both event path filters include pure-midi, TODO-34 and both validator files;
push branches remain master, todo/** and codex/**, and pull requests target
master. The validator checks effective shell/directory, expression contexts,
exact origins, environment replacement, ordering and native failure propagation.

An additional self-review regression proved that bare unavailable contexts
such as `toJSON(runner)` were missed by a dotted-reference-only check:

```powershell
& C:/Python314/python.exe .github/scripts/test_validate_non_linux_release_workflow.py MidiWorkflowMutationTests.test_rejects_bare_unavailable_context_references -v
```

RED exit 1: 16 rejected-context assertions failed in 2.554 seconds. After
expression token validation, the same command exited 0 in 2.455 seconds.
Quoted literals and property names remain distinct from expression roots.

Complete workflow checks before the later directory-setup correction:

```powershell
& C:/Python314/python.exe .github/scripts/test_validate_non_linux_release_workflow.py -v
& C:/Python314/python.exe .github/scripts/validate_non_linux_release_workflow.py .github/workflows/non-linux-release-validation.yml
& .superpowers/sdd/2026-09-10-windows-pure-midi-audit-hardening/tools/actionlint-1.7.12/actionlint.exe -color .github/workflows/non-linux-release-validation.yml
```

All exit 0. Sixteen unittest methods passed in 125.493 seconds: MIDI 374
semantic mutations and 16 bare-context cases, seven independent MIDI controls;
existing audio 342, execution-context 17, expansion 42, and three ODBC build
mutations remain passing. All 794 negative cases reject. Actual pristine
workflow and existing audio controls also pass. Actionlint 1.7.12
(go1.26.1, windows/amd64) emitted no diagnostics.

Local CLANG64 Python has no PyYAML; local semantic tests use Python 3.14.5 at
`C:/Python314/python.exe` with PyYAML 6.0.3. The hosted job explicitly installs
`mingw-w64-clang-x86_64-python-yaml` and invokes its own CLANG64 interpreter.
No local package or global runtime installation was performed.

### Task 8 initial fresh verification

The fresh gate executes the first PowerShell block in `pure-midi/WINDOWS.md`,
substituting only the fresh build root `C:/pure-lang/m8f`. Its explicit
toolchain, Pure, headers, runtime and system-directory arguments are printed
there. The original sandbox attempt in `C:/pure-lang/m8` stalled in Ninja's
compiler ABI child and was interrupted and retained. The unchanged configure
outside the sandbox passed in 7.6 seconds (generation 0.2 seconds). This
environment-only interrupted attempt is not counted as a passing gate.

```powershell
& C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/m8f --parallel 4
& C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/m8f --target verify-windows-dependencies --parallel 4
& C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/m8f -L '^no-hardware$' -LE '^hardware$' --output-on-failure --no-tests=error -V
```

Tool inputs are Clang/llvm-readobj 22.1.8, `x86_64-w64-windows-gnu`,
CMake 4.4.0, Ninja 1.13.2, pkgconf 3.0.4, GNU Make 4.4.1, Pure 0.68 for LLVM
22.1.8, and pinned PortMidi `1~2.0.8-1` (pkg-config reports 2.0.7).
Current local PowerShell is 7.6.5; native Windows contract children use Windows
PowerShell. All three documentation PowerShell blocks and all 37 Windows
PowerShell workflow steps parsed without errors. Optional hardware commands
were parsed only and were never executed.

### Task 8 directory correction and repeated gate

The intermediate `m8f` checkout gate passed 19/19 in 1214.66 seconds.
Its exact standalone runtime/documentation install and installed verifier also
passed (baseline 49, added files 17, final entries 71, PE 16, installed tests 2).
Public distcheck then correctly failed before extraction because the new
`C:/pure-lang/s8` output directory did not exist. The workflow/documented
commands now create that directory with a checked `cmake -E make_directory`
call before public Make. No original-source locks had been acquired.

Directory-setup regression command:

```powershell
& C:/Python314/python.exe .github/scripts/test_validate_non_linux_release_workflow.py MidiWorkflowMutationTests.test_distcheck_requires_directory_creation MidiWorkflowMutationTests.test_independent_pristine_and_formatting_variants -v
```

RED: two failures in 0.789s (missing creation accepted; new valid fixture
rejected). GREEN after the fix: both methods passed in 1.640s. The actual
corrected directory creation plus public `make dist` prerequisite passed,
producing 63 files with SHA-256
`f3f2555fdfba00e436394d198d7be1756dcc8c0567c0a5021f63e9bab2df92ee`.
Because packaged documentation changed, a new clean gate in
`C:/pure-lang/m8g` repeats every required test; the earlier result is retained
as intermediate evidence. Corrected configure: 7.5s; generation: 0.2s.

The corrected full workflow suite (`C:/Python314/python.exe
.github/scripts/test_validate_non_linux_release_workflow.py -v`) passed
17 methods in 120.430s: all 800 negatives reject (MIDI semantic 376,
bare-context 16, directory setup 4, audio 342, execution-context 17,
expansion 42, ODBC 3), with seven independent MIDI controls and the existing
pristine controls passing. Log: `task-8-workflow-corrected.log`.

### Task 8 corrected checkout evidence

The corrected `C:/pure-lang/m8g` fresh gate passed 19/19 in 1198.62s.
Both distinct four-worker invocations passed, with 50 normal build steps,
17 sealed install artifacts and recursive PE closure 16:

```powershell
& C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/m8g --parallel 4
& C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/m8g --target verify-windows-dependencies --parallel 4
& C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/m8g -L '^no-hardware$' -LE '^hardware$' --output-on-failure --no-tests=error -V
```

Release and ASan each passed 10 lifecycle matrices plus 200 deterministic
concurrency processes, 86 boundary cases and 189 midifile fault cases with the
1632-event round trip. Runner 53, owned cleanup 13, hardware selector 3 and
real-script/fake-backend 9 cases passed. Configure 127/7 (133.63s), PE 62/4
(169.12s), source 86/13 (79.85s), install 41/13 (454.02s) and guard 18/10
(198.56s) passed. Guard output: `outside_writes=0 controlled_rollback=4`.
Configure/PE each recorded one uncounted symlink-privilege skip. The corrected
source archive hashes matched `f3f2555fdfba00e436394d198d7be1756dcc8c0567c0a5021f63e9bab2df92ee`.
Full checkout log SHA-256:
`1dfa31661a836dfa2a3ae9d5cfe5c6714bd1bf85e465a53462e9cd2eb16b2796`.

### Task 8 final installed and extracted evidence

The corrected standalone package and public source command both passed:

```powershell
& C:/msys64/clang64/bin/cmake.exe -E copy_directory C:/pure-lang/pure/build/windows-clang64-prefix C:/pure-lang/m8g/package
& C:/msys64/clang64/bin/cmake.exe --install C:/pure-lang/m8g --prefix C:/pure-lang/m8g/package --component runtime
& C:/msys64/clang64/bin/cmake.exe --install C:/pure-lang/m8g --prefix C:/pure-lang/m8g/package --component documentation
& C:/msys64/clang64/bin/cmake.exe -DMIDI_INSTALL_CONTEXT=C:/pure-lang/m8g/windows-install-context.cmake -DSTAGE_PREFIX=C:/pure-lang/m8g/package -P C:/pure-lang/.worktrees/todo34-audit/pure-midi/cmake/VerifyInstalledPackage.cmake
& C:/msys64/clang64/bin/cmake.exe -E make_directory C:/pure-lang/s8
& C:/msys64/clang64/bin/mingw32-make.exe -C C:/pure-lang/.worktrees/todo34-audit/pure-midi distcheck DLL=.dll CMAKE=C:/msys64/clang64/bin/cmake.exe CLANG64_PREFIX=C:/msys64/clang64 PURE_PREFIX=C:/pure-lang/pure/build/windows-clang64-prefix DIST_ROOT=C:/pure-lang/s8 DIST_DIR=C:/pure-lang/s8 SHELL=C:/msys64/usr/bin/sh.exe
```

The public command exited 0 in owned leaf `C:/pure-lang/s8/s3c7be7c742cf`.
It denied all 63 original source inputs, proved four independent driver probes
could not read them, configured solely from extraction under a path with spaces,
and completed a normal and a separate PE-target build, each with `--parallel 4`.
All 19 extracted CTests passed in 1165.50s: configure 127/7 (125.70s),
PE 62/4 (163.09s), source 86/13 (79.10s), install 41/13 (442.27s), guard 18/10
(198.42s), with zero outside writes and four controlled rollbacks.
Release/ASan counters remained unchanged. Both components and full installed
verification then passed from extraction.

Both final stages verify baseline=49, runtime=6, documentation=11, delta_files=17,
delta_directories=5, final=71, pe=16, installed_tests=2, license_payloads=1.
Independent enumeration found 57 files, 14 directories and no reparse entries
in each stage. The leak scan covered all 275 generated files, UTF-8/UTF-16LE/
UTF-16BE, all casing and overlapping full-length reads. All original locks were
released; every one of the 63 checkout source sizes/hashes still matched the
verified source manifest afterward.

Final 164163-byte archive:
`C:/pure-lang/s8/s3c7be7c742cf/pure-midi-0.6.tar.gz`, SHA-256
`f3f2555fdfba00e436394d198d7be1756dcc8c0567c0a5021f63e9bab2df92ee`.
Its 63-row, 5863-byte manifest SHA-256 is
`d9973ab55b98b027610ac24cdff236349c5109f504a6c0e5be221e056f918b08`.
Final extracted test log SHA-256:
`8764a22c7d7e625b43e47ba0fc68bb6697102a5cf0a05852821b59f34fcae65d`.
The complete outer package/distcheck log SHA-256 is
`f72f90dae5737fc816101748053e492ce750474d30834e5574588e54497c200d`.

Task 8 self-review confirms only its seven listed files changed, earlier task
implementation is preserved, the July log is verbatim, all required local gates
passed, and Task 9 remains unchecked. No push, merge or global installation.

### Residual boundaries and final closure

Physical/virtual MIDI I/O, a true connected-input loopback, driver timing
accuracy, Windows ThreadSanitizer, native POSIX behavior and hosted-CI runtime
budget remain unverified. The current source tooling requires Windows
PowerShell/.NET; native POSIX `make dist` and Debian packaging are explicit
residuals. The July Microsoft MIDI Mapper result is historical output-only
evidence. Release/ASan deterministic concurrency and fake-device tests do not
establish those platform/hardware results.

Strict package/PE origins and PortMidi payload hashes are version-sensitive;
rolling MSYS2 upgrades may require a reviewed policy update. Installation and
source publication cover cooperating processes, owned reservations,
serialization and controlled rollback, not hostile same-account mutation or
whole-tree crash/power-loss atomicity. File-symlink tests are explicitly skipped
when Windows denies creation; mandatory junction/hardlink cases still run.
Task 8 leaves this TODO Open. Only Task 9 may close it after whole-branch review
and another fresh final gate.

### Task 9 closure evidence (2026-09-11)

The whole-branch review found seven important compatibility, validation,
packaging and timeout issues. All seven were corrected in
`9d9d094f8b90b0ec051ca76cf880ad60a9b85a9c`; the scoped re-review found no
remaining Critical or Important issue.

Fresh final verification used previously absent `C:/pure-lang/z9r`, `z9a`,
`z9stage` and `s9` roots. The complete checkout passed 19/19 tests in 1343.19s.
The separate native gate initially hit one unexplained LLVM
`IMAGE_REL_AMD64_ADDR32NB` startup abort; its unchanged rerun passed 7/7 in
75.80s, including the ASan boundary's 96 cases in 27.73s. The checkout ASan
boundary independently passed in 25.30s.

Standalone installation verification passed with baseline=49, runtime=6,
documentation=11, final=71, PE closure=16, installed tests=2 and license
payloads=1. Two public 167661-byte archives and their 63-row manifests were
byte-identical. Archive SHA-256 is
`c459186261cb2d403f08c5d868de75beae526450e716060f3f13a03bb5780372`;
manifest SHA-256 is
`1aa8f5d50dcbe04bef8b143d62e1a85425b364a16c12d597a78cc77f1dde9fdb`.

Public extracted `distcheck` passed 19/19 tests in 1345.55s and returned in
about 1437.413s. Its exact installation counts matched the standalone stage;
the leak scan covered 275 files in UTF-8, UTF-16LE and UTF-16BE; all 63 source
locks were released and source hashes still matched. The extracted ASan
boundary passed in 28.95s, leaving 1.05s below its 30s timeout.

Workflow validation passed 17 mutation/pristine methods with 800 rejected
negatives and seven MIDI pristine controls. The semantic validator, actionlint
1.7.12, all 37 `windows-pure-core` PowerShell blocks and all three documented
PowerShell fences passed. Final tools included CMake/CTest 4.4.0, Ninja 1.13.2,
Clang 22.1.8, Pure 0.68, PortMidi package 1~2.0.8-1 (pkgconf 2.0.7), Python
3.14.5 and PowerShell 7.6.5 / Windows PowerShell 5.1.

The retained initial LLVM abort and 1.05s extracted-ASan timeout margin remain
explicit reliability residuals. Hardware/loopback timing, ThreadSanitizer,
native POSIX behavior and hosted-CI runtime are still outside the claimed
verification boundary. The closure documentation is committed separately as
`Close TODO-34 Windows pure-midi audit`; its immutable commit ID is recorded in
the branch handoff because a commit cannot contain its own hash.

After this documentation-only change, the complete checkout suite was run once
more in the same nonsandboxed Windows environment: 19/19 passed in 1346.14s.
The ASan boundary passed in 29.65s, narrowing the observed timeout margin to
0.35s. An earlier sandbox diagnostic attempt timed out that test at 30.11s and
also produced an MSYS2 `couldn't create signal pipe, Win32 error 5`; it was
interrupted after those environment-specific failures and is not counted as a
passing gate. The successful nonsandboxed result is the closure gate, while the
tight timing margin remains an explicit follow-up risk.
