# TODO-33 - Windows pure-audio Package

Status: Open
Branch: todo/33-windows-pure-audio

## Purpose

Build, validate, and package `pure-audio` and its supported codec/resampling
components for Windows.

## Scope

- Use CLANG64 PortAudio, libsndfile, libsamplerate, and FFTW where required.
- Cover device enumeration, playback, capture, file I/O, and resampling.
- Treat hardware-dependent tests as a separate validation tier.

## Task List

1. [x] Inventory and build every supported native component.
2. [x] Resolve audio backend, codec, and transitive DLL dependencies.
3. [x] Add deterministic no-hardware and file-processing smoke tests.
4. [x] Run documented playback/capture checks on a Windows host.
5. [x] Stage and validate the advertised package contents.
6. [x] Complete the audit hardening, Windows CI and reproducible documentation.
7. [ ] Complete Task 9 whole-branch review and fresh final verification.

## Guardrails

- Automated tests must not hang when no audio device is present.
- Do not advertise a codec or backend that was not built and tested.

## Validation Plan

- Import all modules and process a bundled audio fixture without physical hardware.
- Run bounded playback and capture tests and inspect every staged PE dependency.

## Progress Log

- 2026-09-09: Reopened for the approved Windows audit-hardening plan. The
  historical July milestones below remain records of their original scope,
  not evidence that the later memory-safety, hermeticity and exact-package
  audit is complete. Task 9 review and fresh final verification remain open.

- 2026-07-25: Created as an optional multimedia Windows package candidate.
- 2026-07-28: Built the five supported native modules (`audio`, `fftw`,
  `srcprocess`, `sfinfo`, and `realtime`) as x86-64 PE DLLs with strict
  warnings enabled. Added guarded clean targets. Commit: `3e7e3b92`.
- 2026-07-28: Audited the complete runtime closure: eleven new PortAudio,
  FFTW, libsamplerate, libsndfile, and codec DLLs; hash-matched the existing
  `libc++.dll` and `libwinpthread-1.dll`; rejected MSYS, libgcc, and
  libstdc++ dependencies. Commit: `6a49cd6d`.
- 2026-07-28: Added deterministic hardware-free tests covering all module
  imports, PortAudio enumeration/restart without streams, FFT round-trip,
  resampling, WAV write/read, and normal scheduling. Both CTest tests pass.
  Commit: `9f3306e7`.
- 2026-07-28: Added 15-second-bounded optional playback and capture checks.
  Playback passed on device 3, `Microsoft Sound Mapper - Output` (MME,
  2 channels, 44100 Hz); capture passed on device 0,
  `Microsoft Sound Mapper - Input` (MME, 2 channels, 44100 Hz). Corrected
  stream close/sentry handling and frame-count reporting. Commit: `ff4f088d`.
- 2026-07-28: Installed and verified a 40-file package delta: five modules,
  six Pure interfaces, eleven new runtime DLLs, four package documents,
  seven third-party license texts, two examples, and five test scripts.
  The installed smoke test passes with an empty `PURELIB` and a sanitized
  staged-only runtime `PATH`; the staged PE closure also passes.
- 2026-07-28: The complete portable prefix audit passes with 23 DLLs,
  19 resolved non-system dependency paths, and 80 staged files. Codec DLLs
  are documented as transitive libsndfile dependencies; only deterministic
  WAV file I/O is advertised as tested.

## September audit hardening (still Open)

- 2026-09-09: Tasks 1–3 corrected size/shape arithmetic, 64-bit FFI counts,
  frame/sample units, all supported callback layouts, blocking operations,
  callback/drain synchronization and close-failure lifetime handling.
  Commits: `db8db537`, `feca54ed`, `1a24c6fa`; `014f39f`, `6fe4d9e`;
  `6f1452b9`, `6026c924`. Task 1 had native 97/public 24 checks; Task 2
  native normal/ASan 1384 checks; Task 3 normal 4/4, focused ASan 2/2 and
  each 200-iteration normal/ASan stress 18731 checks, 2400 waiter completions,
  200 callback drains. Failed native close intentionally quarantines stable
  inert callback state until process exit. TSan was unavailable. The recorded
  intermittent pre-existing Pure LLVM/JIT relocation failure in Task 1 was
  not hidden or relabeled; its isolated rerun passed.
- 2026-09-09: Task 4 added the native token/timeout/descendant/environment
  runner and exact owned cleanup (`3d1d09c5`, `57ee5aca`): poisoned suite 6/6,
  106 rejected mutations, 35 controls and three executable-parent boundaries.
  Tasks 5 strict compile/PE provenance (`b82a221`, `ec67ed0`) use canonical
  CLANG64 origins, per-invocation compiler environment clearing, immutable
  configuration-specific flags, pinned LLVM 22 reader, and recursive PE 29.
  Task 7 corrected the Windows CreateSymbolicLink return marshaling in two
  Task 5 tests: actual privilege 1314 means explicit skips, not fake coverage.
  Demonstrated counts are configure 119 negatives/4 controls and verifier 41
  negatives/3 controls; the older 120/42 figures included unavailable setups.
- 2026-09-09: Task 6 (`93e1a5bf`, `025940c7`, `bb9e8baa`, `547f47be`)
  established 61 exact owned artifacts (runtime 22/documentation 39), whole 29-PE
  license mappings, 27 full license/notice payloads, and exact 61/60/0 deltas.
  The user authorized official version-pinned upstream retrieval after the
  local-only license preflight blocked. Fresh suite 10/10; 127 rejected
  scenarios, 30 controls, 6 pristine packages plus a retained production stage.
  Authenticated guards retain destination identities and reject pre-existing
  writable hardlinks before batch writes; controlled pre-commit failures
  roll back owned bytes. Malicious same-principal live aliases/direct writes
  and crash/power-loss atomicity are explicitly outside the guarantee.
- 2026-09-09: Task 7 (`fddb0c2b`, `e82bc32`) produced a literal 92-file source
  closure and safe standalone/public packaging targets. Review fixes normalize
  source hardlinks into regular deterministic archive entries and rescan all
  extracted sources after every release phase. Fresh public distcheck1/1
  passed 1420.30s, extracted mandatory10/10 passed 1162.55s;34 rejected
  scenarios, 1 pristine, 7 controls. The Task 7 archive SHA was
  `ead0d8c9eebd18c2b3916d752bdc96df0ed8165c0011f615bf72d562d5151d42`;
  Task 8's guide/README changes intentionally require a new archive hash.
  Both extracted four-worker targets, PE 29, exact components and public
  installed token passed, with184 original/producer source handles released.
- 2026-09-09: Task 8 adds the five Windows CI steps after portable Pure staging,
  uses 32 explicit configure inputs/24 runtime rows/30 prerequisite packages,
  and preserves the existing ODBC gates. The first nonempty audio selection
  runs all ten no-hardware tests except exactly source-dist; final public
  `make distcheck` runs that eleventh contract and its extracted ten tests.
  Structural BaseLoader TDD first rejected the old workflow after 304/316
  mutations exposed its missing checks. Self-review added wrong-runner and
  job-directory REDs; four further mutations proved that comments or partial
  semantic invocations must not substitute for executing both validator steps.
  Current structural matrix:324 audio negatives,
  3 preserved ODBC negatives, 2 pristine and 2 formatting controls;7/7 methods
  passed 45.503 s in the final fresh structural run. Commands:
  `python .github/scripts/test_validate_non_linux_release_workflow.py -v`
  and `python .github/scripts/validate_non_linux_release_workflow.py .github/workflows/non-linux-release-validation.yml`.
  The exact standalone commands and supported layout/hardware/package boundaries
  are in [WINDOWS.md](../../pure-audio/WINDOWS.md); detailed fresh closure,
  timings and evidence are in the [Task 8 report](../../.superpowers/sdd/2026-09-08-windows-pure-audio-audit-hardening/task-8-report.md).
  Fresh actual workflow strict configure passed 6.336 s; normal 23/23 and PE 29
  four-worker commands passed (7.410 s combined); all ten selected tests passed
  1172.57 s, including install 814.34 s and guard 339.77 s. Outer contracts
  total 393 negatives/72 controls/6 pristine; native 2391/public 24 checks; two
  explicit unavailable file-symlink skips. Both components/public verifier
  passed 43.847 s: 61 artifacts/27 license payloads/29 PEs, 101 staged files,
  all 40 baseline hashes unchanged. Public token:
  `PURE_AUDIO_DONE_548d0d88c32acdcbebf61effc2af6c36`.
  Final public distcheck 1/1 passed 1418.81 s (wall 1419.055 s); pristine
  extracted 10/10 passed 1163.64 s (install 802.05 s, guard 342.46 s), again
  exercising 393 negatives/72 controls/6 pristine and the two explicit skips.
  Source contract 34 negatives/1 pristine/7 controls; both extracted 4-worker
  commands, components and public token passed. Extracted token:
  `PURE_AUDIO_DONE_2c7e5c32f2dc32bcd818830ce6111897`.
  Archive 92 files/92 hashes/242909 bytes, SHA-256
  `41254b9a93328917b58928ed8727a7778dd9a7f8f01afdafdcd19c05321248f5`.
  Both source scans 92, final build 73/stage 101/log 17 scans, 184 isolated handles
  and release, 8 empty stderr files, and post-run 92 unchanged original hashes
  passed. All 5 workflow+5 guide PowerShell blocks parse; git diff --check passes.
  Local tools: Clang/LLVM 22.1.8, CMake 4.4.0, Ninja 1.13.2, pkgconf 3.0.4,
  Make 4.4.1, tar 1.35, gzip 1.14, Pure 0.68, PowerShell 7.6.5,
  Python 3.14.5/PyYAML 6.0.3. CI declares its CLANG64 python-yaml package;
  this local host's CLANG64 Python lacks PyYAML, so Python 3.14 ran the YAML
  checks. The hosted complete workflow and its aggregate 120-minute budget
  were not exercised remotely. Task 8 independent review and Task 9 remain open.

- 2026-09-09: Task 8 review fix round 1 (base `a442d5fe`) pins the semantic
  step to explicit pwsh/pure and structurally resolves workflow/job/step run
  defaults and overrides. Custom shells, unsafe directories and conditional or
  ignored validation fail closed. The quote-aware PowerShell lexer distinguishes
  literal single quotes from expanding arguments and rejects unsupported
  interpolation/concatenation/operators and invalid trailing-space continuations.
  Initial focused RED:35 failures/7.109 s (34 wrongly accepted negative cases
  plus one rejected safe-inheritance control); continuation RED:2 failures/5.639 s.
  Final `C:/Python314/python.exe .github/scripts/test_validate_non_linux_release_workflow.py -v`:
  11/11 PASS50.790 s, 386 distinct negatives (324 existing audio +17 context
  +42 expansion +3 ODBC), two pristine/five positive controls. Actual pristine
  validator CLI also passed. Fresh exact first two workflow scripts in
  `C:/pure-lang/task8-fix1/pa8`: strict configure6.2621647 s, normal23/23 and
  PE29 both four-worker PASS7.4748183 s combined. Four real no-hardware core
  tests passed4/4 in10.47 s; inventory still selects exactly ten mandatory tests.
  All six audited workflow blocks (five audio +semantic) and five guide blocks
  parse with zero errors; native quote characterization confirms the literal
  `$env:AUDIO_PREFIX` does not equal the expanded path.
  Five audio step objects and all92 source hashes remain unchanged; retained
  archive SHA256 remains `41254b9a93328917b58928ed8727a7778dd9a7f8f01afdafdcd19c05321248f5`.
  Per approved proportional verification, the original full10/10, component/
  public verifier and distcheck/extracted10 results above are historical
  unchanged regression evidence, not fix-round reruns. No new install/dist
  counts are claimed. Fresh tools: Clang/LLVM22.1.8, CMake4.4.0, Ninja1.13.2,
  pkgconf3.0.4, Pure0.68, PowerShell7.6.5, Python3.14.5/PyYAML6.0.3. Details,
  logs, self-review and unchanged limitations are in the Task 8 report. TODO
  remains Open pending independent re-review and Task 9; no merge/push.

- 2026-09-09: Task 9 consolidated fix wave (base `2c168ce1`) addresses the
  three whole-branch findings: public bigint open/raw-count guards before FFI,
  explicit numeric-only hardware selector transport in the sanitized runner,
  and the legacy Make audio-test-header dependency. Behavioral RED recorded
  native open/raw entries2/6, five missing selector transports and missing Make
  rebuild scheduling. Fresh strict final2 configure6.5255044 s, normal23/23
  and PE29 four-worker targets7.9471052 s passed. Focused normal6/6 PASS26.91 s:
  native2391/public28 checks, open/raw delta0/0; runner45 negatives/13 controls,
  cleanup13/2, Make6/2, direct Make64/24, header1 mutation/1 control. Final runner
  rerun1/1 PASS18.67 s. Isolated ASan showed legitimate cumulative import/JIT
  work beyond45 s; approved ASan-only public deadline90/105 s, normal45/60 and
  hardware15 unchanged. Generated CTest inventory and five mutation/one pristine
  checks prove this scope. Actual ASan2/2 PASS79.52 s (native28.58/public50.94),
  2391/28 checks and no sanitizer diagnostic. Runtime22+documentation39 and
  public installed verifier PASS42.841542 s: delta61, licenses27, PE29,
  stage101 with all40 baseline SHA-256 values unchanged. Workflow11/11
  PASS53.410 s,386 distinct negatives/two pristine/five controls; pristine CLI
  and six workflow+five guide PowerShell parses pass. Public make dist PASS
  2.0295903 s:92 regular files/92 hashes/247484 bytes, SHA-256
  `c1c1eb3a82c25a5ac638ff9ea2bb6ebe200d078368a2b0cbc468edb981b9dc33`.
  Exact commands, logs, tokens, sibling-API audit, versions, ASan diagnosis and
  self-review are in task-9-report.md. Per the explicit sequencing ruling the
  slow ten-test gate and public distcheck/extracted-source verification were
  not rerun in this wave: one scoped re-review and fresh Task 9 full verification
  remain required. TODO remains Open; no merge/push/hardware test/build deletion.

No hardware playback/capture was rerun during September audit hardening.
Current optional fixtures use one channel at the device's default sample
rate, not the older July two-channel fixture. ASIO, elevated FIFO/RR and all
transitive codecs remain unclaimed. Native POSIX execution is unverified.
Bundled license texts cover the staged DLL inventory, not all source/static
components or every distribution obligation. TODO stays Open until Task 9
whole-branch review and fresh final verification complete.
