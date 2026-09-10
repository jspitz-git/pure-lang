# Windows pure-midi Audit Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make TODO-34's Windows `pure-midi` implementation safe for malformed files and invalid FFI values, deterministic without hardware, and exactly reproducible as a source and binary package.

**Architecture:** Put checked SMF I/O and allocation behind a testable native seam, put PortMidi handles behind synchronized owned wrappers, and route all Pure tests through one hermetic Windows runner. Build exact strict-toolchain, recursive PE, installation, source-archive, CI, license, and documentation contracts around those corrected boundaries.

**Tech Stack:** C11, Pure 0.68 FFI, PortMidi/PortTime 2.0.8, CMake 3.25+, Ninja, Clang 22 CLANG64, llvm-readobj, Windows synchronization and Job Objects, PowerShell, PyYAML.

**Spec:** `docs/superpowers/specs/2026-09-10-windows-pure-midi-audit-hardening-design.md`

## Global Constraints

- Preserve existing public Pure names and successful-path value shapes.
- Valid SMF files accepted by the existing API retain the same event representation and round-trip behavior.
- Production dispatch always calls the real C runtime and PortMidi; injection exists only in fault-test targets.
- Mandatory tests never open physical or virtual MIDI devices and never inherit Pure/module lookup paths.
- Failed close quarantines native state; no alias may reuse or free it.
- Recursive cleanup requires a fixed owned root, exact unpredictable sentinel, canonical non-reparse ancestors, and unique leaves.
- Normal upstream configuration remains available; strict Clang 22 x86-64 audit constraints are opt-in.
- Strict Windows build and PE commands use exactly four workers.
- TODO-34 remains open until task reviews and fresh whole-branch verification pass.

---

### Task 1: Make Standard MIDI File Parsing and Serialization Fail Closed

**Files:**
- Modify: `pure-midi/midifile/midifile.c`
- Modify: `pure-midi/midifile/midifile.h`
- Create: `pure-midi/tests/midifile_fault_harness.c`
- Create: `pure-midi/tests/midifile_test_api.h`
- Modify: `pure-midi/CMakeLists.txt`

**Interfaces:**
- Produces `midi_checked_add_size(size_t, size_t, size_t *)` and `midi_checked_mul_size(size_t, size_t, size_t *)`.
- Produces test-only `MidiFileIoApi` and `MidiFileAllocApi` dispatch tables under `PURE_MIDI_TEST_SEAM`; production tables call `fread`, `fwrite`, `fseek`, `ftell`, `fflush`, `fclose`, `malloc`, `calloc`, and `free`.
- Produces bounded parser counters consumed by the fault harness; Task 2 consumes the checked arithmetic.

- [ ] **Step 1: Add RED truncated-file and chunk-boundary cases**

Create byte fixtures for every truncation point in `MThd`, RIFF/RMID, track header, delta VLQ, running status, channel event, SysEx, meta event, and end-of-track. For each fixture assert `MidiFile_load` returns null within two seconds and tracked allocations/files return to zero.

- [ ] **Step 2: Add RED hostile-length and I/O-failure cases**

Inject a five-byte VLQ, wraparound in `chunk_start + chunk_size`, event length beyond the remaining chunk, `SIZE_MAX` multiplication, null allocation, short read/write, failed seek/tell/flush/close, and a missing end-of-track. Expected pre-fix outcomes include incorrect acceptance, invalid memory access, or leaked partial state.

- [ ] **Step 3: Run RED Release and ASan harnesses**

Run only `pure-midi-midifile-fault` and its ASan variant. Require the failure to identify unchecked I/O/bounds rather than harness setup.

- [ ] **Step 4: Implement checked reader and allocation primitives**

Use explicit success results and division-based overflow checks:

```c
bool midi_checked_mul_size(size_t a, size_t b, size_t *out) {
  if (!out || (a != 0 && b > SIZE_MAX / a)) return false;
  *out = a * b;
  return true;
}
```

Track current offset and enclosing chunk end in unsigned representable sizes. Read VLQs in at most four bytes, reject EOF before conversion, and verify every payload fits both native types and remaining bytes before allocation.

- [ ] **Step 5: Make parse rollback complete**

Check every file, file-object, track, event, and payload allocation. On failure free the partial graph through one ownership-aware path and close the input exactly once. Never dereference a failed allocation or preserve a partially decoded track.

- [ ] **Step 6: Make save failure observable**

Check every write, seek, tell, flush, and close. Do not report success if track-size backpatching or final close fails. Tests require a valid file to round-trip unchanged after the seam is restored.

- [ ] **Step 7: Run GREEN harnesses and valid corpus**

Run Release and ASan fault matrices plus the existing 1632-event fixture. Expected: every negative is rejected, no sanitizer diagnostic, exact zero resource deltas, and valid round-trip equality.

- [ ] **Step 8: Commit**

```powershell
git add pure-midi/midifile/midifile.c pure-midi/midifile/midifile.h pure-midi/tests/midifile_fault_harness.c pure-midi/tests/midifile_test_api.h pure-midi/CMakeLists.txt
git commit -m "Harden pure-midi file parsing"
```

### Task 2: Validate Event, Matrix, and PortMidi ABI Boundaries

**Files:**
- Modify: `pure-midi/midifile/mf.c`
- Modify: `pure-midi/midifile/mf.h`
- Modify: `pure-midi/midifile/midifile.c`
- Modify: `pure-midi/midi.pure`
- Create: `pure-midi/tests/bounds.pure`
- Create: `pure-midi/tests/midi_boundary_harness.c`
- Modify: `pure-midi/tests/midifile_fault_harness.c`
- Modify: `pure-midi/CMakeLists.txt`

**Interfaces:**
- Produces `pure_midi_matrix_elements(size_t, size_t, size_t *)`, `pure_midi_validate_event(...)`, and test-only wrappers under `PURE_MIDI_TEST_SEAM`.
- Produces transactional `mf_put_track`/`mf_put_tracks`; Task 3 uses the same native validation conventions.

- [ ] **Step 1: Add RED native event mutations**

Test `{0xff}`, missing meta type, meta end marker with payload, empty/oversized SysEx, wrong channel-message lengths, status/data outside `0..255`, negative/overflow tick, non-vector matrices, `size1 * size2` overflow, null payloads, allocation failure, and empty extracted lists. Place guard regions around all matrices.

- [ ] **Step 2: Add RED public Pure boundary tests**

Call `midifile::new`, `put_track`, `put_tracks`, `midi::word`, `bytes`, `read`, `write`, `readmsg`, and `writemsg` with wrong types, ranks, shapes, lengths, signed values, bigint values, and closed/null streams. Print the generated completion token only after every value is rejected without an unhandled expression.

- [ ] **Step 3: Verify RED failures**

Run the boundary harness under ASan and `pure-midi-bounds`. Expected failure includes the one-byte meta-event out-of-bounds read at the old `mat->data[1]` access.

- [ ] **Step 4: Implement exact event validation**

Require exact two- or three-byte channel messages by status, at least two bytes for meta, exact zero payload for end-of-track, nonzero representable SysEx, and every element in `0..255`. Convert counts only after proving fit in `int`, `int32_t`, and `size_t`.

- [ ] **Step 5: Make matrix construction allocation-safe**

Use Task 1 arithmetic for block allocation and `memset`. Check decoded native length/pointer pairs and every `pure_*` construction result before use. Release extraction arrays on empty and all failure paths.

- [ ] **Step 6: Implement transactional track insertion**

Record the file's track/event boundary before mutation. If any event or allocation fails, remove everything created by that call and restore counts/links. `put_tracks` rolls back all tracks added during its call.

- [ ] **Step 7: Harden Pure wrappers before FFI entry**

Validate contiguous integer-vector layout, exact event row shape, ABI-representable event count, direction-appropriate stream, byte ranges, and SysEx start before calling PortMidi. The native seam records zero calls for rejected inputs.

- [ ] **Step 8: Run GREEN and commit**

Run native Release/ASan boundaries, public bounds, and valid smoke/round-trip tests.

```powershell
git add pure-midi/midifile/mf.c pure-midi/midifile/mf.h pure-midi/midifile/midifile.c pure-midi/midi.pure pure-midi/tests pure-midi/CMakeLists.txt
git commit -m "Validate pure-midi event boundaries"
```

### Task 3: Make PortMidi Stream Lifecycle Deterministic

**Files:**
- Create: `pure-midi/midi_stream.c`
- Create: `pure-midi/midi_stream.h`
- Create: `pure-midi/tests/midi_lifecycle_harness.c`
- Modify: `pure-midi/pmdev.c`
- Modify: `pure-midi/pmdev.h`
- Modify: `pure-midi/midi.pure`
- Modify: `pure-midi/CMakeLists.txt`

**Interfaces:**
- Produces opaque `PureMidiStream`, direction/state enums, `pure_midi_open_input`, `pure_midi_open_output`, `pure_midi_close`, `pure_midi_abort`, checked I/O operations, and process-level start/stop functions.
- Produces test-only `PureMidiApi` dispatch and resource counters; Task 4 exposes these through public Pure fixtures.

- [ ] **Step 1: Add RED lifecycle failure matrix**

Inject failure for wrapper allocation, initialization, device lookup, open input/output, timer start, read/write, abort, close, terminate, and timer stop. Assert reverse cleanup and no returned usable wrapper after failed open.

- [ ] **Step 2: Add RED alias and failed-close cases**

Create multiple references to one wrapper, close through one, then query/I/O/finalize through all aliases. Inject close failure and require permanent failed/quarantined state, exactly one native close attempt, and no native use/free through aliases.

- [ ] **Step 3: Add RED concurrency cases**

Block read/write in the fake backend, race close and stop, and require bounded wakeup. Assert new operations cannot enter after closing, close waits for active operations, and synchronization/native storage is not destroyed early.

- [ ] **Step 4: Implement owned synchronized wrappers**

Track direction, state, native handle, active count, and initialized synchronization fields. Validate devices and direction before open. Every public operation acquires activity under the wrapper lock and rechecks state before native entry.

- [ ] **Step 5: Implement close and quarantine protocol**

Mark closing, reject new activity, wake blocked operations, wait for active count zero, and call `Pm_Close`. On success invalidate aliases and release owned state only after sentry detachment. On failure retain inert wrapper/handle storage until process exit and forbid restart.

- [ ] **Step 6: Coordinate global PortMidi and PortTime state**

Serialize initialize/terminate and timer transitions, count live/quarantined wrappers, and refuse unsafe terminate/reinitialize. Partial start rolls back only initialized components; repeated stop is deterministic.

- [ ] **Step 7: Run GREEN stress**

Run Release and ASan failure matrices and at least 200 deterministic concurrency iterations with independent hard timeouts and exact event/resource counters. Record Windows TSan unavailability if applicable.

- [ ] **Step 8: Commit**

```powershell
git add pure-midi/midi_stream.c pure-midi/midi_stream.h pure-midi/pmdev.c pure-midi/pmdev.h pure-midi/midi.pure pure-midi/tests/midi_lifecycle_harness.c pure-midi/CMakeLists.txt
git commit -m "Fix pure-midi stream lifecycle"
```

### Task 4: Replace Test Scripts with a Hermetic Native Runner

**Files:**
- Create: `pure-midi/tests/run_pure_test.c`
- Create: `pure-midi/tests/runner_contract.cmake`
- Create: `pure-midi/tests/cleanup_contract.cmake`
- Rewrite: `pure-midi/cmake/RunPureTest.cmake`
- Rewrite: `pure-midi/cmake/RunHardwareTest.cmake`
- Modify: `pure-midi/tests/device-timing.pure`
- Modify: `pure-midi/tests/smoke.pure`
- Modify: `pure-midi/tests/hardware-output.pure`
- Modify: `pure-midi/tests/bounds.pure`
- Modify: `pure-midi/Makefile`
- Modify: `pure-midi/midifile/Makefile`
- Modify: `pure-midi/CMakeLists.txt`

**Interfaces:**
- Produces `run_pure_test.exe --pure PATH --script PATH --token TOKEN --timeout-ms N --cwd PATH --path-entry PATH...` with exact exit propagation and captured streams.
- Produces owned-root/sentinel cleanup helpers consumed by Tasks 6 and 7.

- [ ] **Step 1: Add RED false-positive runner fixtures**

Cover parser diagnostic plus exit zero, unhandled expression, missing/wrong/duplicate/early token, nonzero exit, timeout, filled stdout/stderr pipes, inherited child process, and one pristine final-token case.

- [ ] **Step 2: Add RED environment and path poisoning**

Place fake modules in inherited `PATH`, `PURELIB`, `PURE_INCLUDE`, and `PURE_LIBRARY`; use executable/module/script/fixture paths through files, directories, symlinks, and junctions. Require only canonical declared regular inputs to launch.

- [ ] **Step 3: Add RED destructive-cleanup contract**

Exercise root, empty, outside root, missing/wrong sentinel, sentinel reparse, endpoint/ancestor junction, concurrent leaves, and valid owned leaf. Only the exact valid owned leaf may be recursively removed.

- [ ] **Step 4: Implement Windows runner and cleanup helper**

Create an explicit environment block, unique owned CWD, redirected pipes drained concurrently, Job Object child-tree timeout, exact wait/exit handling, and final token validation. Canonicalize every input and reject reparse ancestors before launch or deletion.

- [ ] **Step 5: Convert Pure fixtures and hardware selector transport**

Each fixture consumes the unpredictable token and prints it exactly once after all cleanup. Hardware selection is passed explicitly at execution time, always sends Note Off when Note On succeeded, closes the stream on every exit path, and reports the selected device.

- [ ] **Step 6: Enumerate Make cleanup outputs**

Validate the exact module suffix and delete only named object/module/generated-header outputs. Remove broad recursive wildcard deletion.

- [ ] **Step 7: Run GREEN contracts and commit**

Run runner, cleanup, hardware-runner structural cases, and all no-hardware Pure tests under poisoned parent variables.

```powershell
git add pure-midi/CMakeLists.txt pure-midi/Makefile pure-midi/midifile/Makefile pure-midi/cmake pure-midi/tests
git commit -m "Make pure-midi tests hermetic"
```

### Task 5: Enforce Strict Toolchain Inputs and Exact PE Closure

**Files:**
- Modify: `pure-midi/CMakeLists.txt`
- Rewrite: `pure-midi/cmake/VerifyWindowsDependencies.cmake`
- Create: `pure-midi/tests/configure_contract.cmake`
- Create: `pure-midi/tests/runtime_verifier_contract.cmake`

**Interfaces:**
- Produces opt-in `PURE_MIDI_STRICT_WINDOWS_AUDIT` with explicit compiler, target, build tool, pkgconf, Pure, PortMidi, runtime, `llvm-readobj`, and Windows-system inputs.
- Produces exact recursive PE verifier consumed by install, source, and CI tasks.

- [ ] **Step 1: Add RED configure mutations**

Test missing, directory, nonexistent, wrong-origin, symlink/junction, wrong Clang major/target, wrong-machine import library, mismatched PortMidi header/library/runtime, ambient `MSYSTEM_PREFIX`, duplicate runtime names, and one independent pristine configuration.

- [ ] **Step 2: Implement strict opt-in mode**

Keep non-strict configuration functional. Strict mode requires canonical regular explicit paths, Clang major 22, `x86_64-w64-windows-gnu`, Pure 0.68, exact CLANG64 origins, and frozen source SHA-256 values. Ignore or reject ambient discovery.

- [ ] **Step 3: Add RED PE mutations**

Fixture wrong machine/format, missing/duplicate/malformed/delay import, mixed-case forbidden runtime, missing/ambiguous transitive DLL, host fallback, wrong configured hash/origin, extra staged PE, and a pristine exact closure.

- [ ] **Step 4: Implement fail-closed recursive verifier**

Parse complete `llvm-readobj` records, require AMD64 PE32+, traverse every non-system import, and resolve it uniquely to the declared stage/source. Resolve system imports only through the authoritative Windows directory/API-set policy. Compare names case-insensitively and reject MSYS/libgcc/libstdc++.

- [ ] **Step 5: Run GREEN contracts and direct target**

Record exact negative/pristine counts, PE file count, import set, origins, hashes, and tool versions. Re-run a normal non-strict configure control.

- [ ] **Step 6: Commit**

```powershell
git add pure-midi/CMakeLists.txt pure-midi/cmake/VerifyWindowsDependencies.cmake pure-midi/tests/configure_contract.cmake pure-midi/tests/runtime_verifier_contract.cmake
git commit -m "Enforce pure-midi Windows PE contracts"
```

### Task 6: Make Installation Exact and License Inputs Reproducible

**Files:**
- Rewrite: `pure-midi/cmake/Install.cmake`
- Rewrite: `pure-midi/cmake/VerifyInstalledPackage.cmake`
- Create: `pure-midi/tests/install_contract.cmake`
- Create: `pure-midi/tests/install_guard_contract.ps1`
- Create: `pure-midi/cmake/install_guard.c`
- Create: `pure-midi/licenses/PortMidi.txt`
- Create: `pure-midi/licenses/origins.tsv`
- Modify: `pure-midi/THIRD_PARTY.md`
- Modify: `pure-midi/CMakeLists.txt`

**Interfaces:**
- Produces disjoint runtime/documentation manifests, exact baseline-plus-delta verification, cooperating-installer guard, and binary-to-license inventory.
- Consumes Task 4 runner and Task 5 PE verifier; Task 7 packages every source.

- [ ] **Step 1: Establish exact artifact and license inventory**

Record source/destination/hash for both modules, three Pure interfaces, PortMidi runtime, documents, example, fixture, tests, license, and origins row. Store the complete upstream PortMidi license locally and pin its authoritative URL and SHA-256.

- [ ] **Step 2: Add RED component/install mutations**

Test collisions, changed baseline, missing/extra/cross-component manifest entries, source hash changes, wrong runtime origin/hash, absent/changed license mapping, hardlinks, reparse endpoints/ancestors, controlled write failure, rollback, and host-rescued installed smoke.

- [ ] **Step 3: Implement component preflight and guarded mutation**

Validate canonical destinations and reservations before writes. Serialize cooperating installers, retain validated ancestor/destination handles, require single-link writable endpoints, and roll back controlled pre-commit failures. Do not claim hostile same-principal or power-loss atomicity.

- [ ] **Step 4: Implement exact full-tree verification**

Require post-install tree = byte-identical sorted baseline + declared disjoint runtime/documentation deltas. Hash-match every installed file, reject non-regular/reparse/hardlink/extra paths, run installed Pure tests hermetically, and repeat recursive PE closure from the stage only.

- [ ] **Step 5: Run GREEN install matrices and commit**

Record runtime/documentation/delta/final counts, license mappings, PE count, negative/control/pristine counts, and limitations.

```powershell
git add pure-midi/CMakeLists.txt pure-midi/cmake/Install.cmake pure-midi/cmake/VerifyInstalledPackage.cmake pure-midi/cmake/install_guard.c pure-midi/tests/install_contract.cmake pure-midi/tests/install_guard_contract.ps1 pure-midi/licenses pure-midi/THIRD_PARTY.md
git commit -m "Verify the exact pure-midi package"
```

### Task 7: Build and Verify a Self-Contained Source Distribution

**Files:**
- Modify: `pure-midi/Makefile`
- Create: `pure-midi/cmake/CreateSourceArchive.cmake`
- Create: `pure-midi/cmake/SourceArchiveTools.ps1`
- Create: `pure-midi/cmake/SourceWorkflow.cmake`
- Create: `pure-midi/tests/source_dist_contract.cmake`
- Create: `pure-midi/tests/source_dist_extracted.cmake`
- Create: `pure-midi/tests/source_dist_tools.ps1`
- Modify: `pure-midi/CMakeLists.txt`

**Interfaces:**
- Consumes all Task 1–6 sources, harnesses, runners, licenses, and contracts.
- Produces deterministic public `make dist`/`distcheck` consumed by Windows CI.

- [ ] **Step 1: Add RED real-archive and input mutations**

Run the actual public target twice. Reject missing declared sources, extra files, generated/build/cache files, reparse inputs/ancestors, path quoting failures, changed metadata/order/time, and checkout content leaked across scan boundaries or after 9 MiB.

- [ ] **Step 2: Define exact source manifest and archive creation**

Enumerate all C/header/Pure/CMake/PowerShell sources, tests, harnesses, runner, fixture, example, documentation, package license, third-party license, and origins inventory. Validate each regular source and produce deterministic ordering, timestamps, ownership, permissions, and gzip bytes without recursive wildcard cleanup.

- [ ] **Step 3: Run extracted-source workflow**

Extract below a path containing spaces, deny checkout-side driver access, compare exact regular-file hashes, then run strict configure, two four-worker builds, Release and ASan mandatory tests, recursive PE verification, both component installs, installed verification, and checkout-leak scan solely from extraction.

- [ ] **Step 4: Run GREEN twice and commit**

Require identical archive SHA-256, exact archive file count, all mutation/control/pristine cases, and successful extracted verification.

```powershell
git add pure-midi/Makefile pure-midi/CMakeLists.txt pure-midi/cmake/CreateSourceArchive.cmake pure-midi/cmake/SourceArchiveTools.ps1 pure-midi/cmake/SourceWorkflow.cmake pure-midi/tests/source_dist_contract.cmake pure-midi/tests/source_dist_extracted.cmake pure-midi/tests/source_dist_tools.ps1
git commit -m "Verify pure-midi source releases"
```

### Task 8: Add Windows CI and Audited Documentation

**Files:**
- Modify: `.github/workflows/non-linux-release-validation.yml`
- Modify: `.github/scripts/validate_non_linux_release_workflow.py`
- Modify: `.github/scripts/test_validate_non_linux_release_workflow.py`
- Rewrite: `pure-midi/WINDOWS.md`
- Modify: `pure-midi/README`
- Modify: `pure-midi/THIRD_PARTY.md`
- Modify: `pure/todo/TODO-34-windows-pure-midi.md`

**Interfaces:**
- Consumes Tasks 4–7 runner, strict inputs, mandatory tests, PE, install, license, and distcheck commands.
- Produces semantic CI validation and evidence-bearing closure documentation.

- [ ] **Step 1: Reopen TODO and write RED YAML mutations**

Set `Status: Open`. Add independent PyYAML fixtures/mutations for both path filters, branches, prerequisites, strict inputs, exact step order, effective shell/directory, runner-context legality, sanitized environment, failure propagation, nonempty mandatory label, two distinct four-worker builds, both install components, verifier, and public distcheck.

- [ ] **Step 2: Add exact workflow gate**

After portable Pure staging, configure `PURE_MIDI_STRICT_WINDOWS_AUDIT=ON` in a fresh short directory, build normally and run PE target with distinct `--parallel 4` calls, run all mandatory non-hardware tests, install both components into a fresh stage, run installed verifier, and execute `make distcheck`.

- [ ] **Step 3: Run GREEN workflow semantics**

Require every mutation to fail and independently authored/pristine workflow variants to pass. Run `actionlint` in addition to repository semantic validation so unavailable expression contexts cannot be committed.

- [ ] **Step 4: Rewrite Windows and README guidance**

Document exact prerequisites and commands, MSYS2-as-build-only boundary, public supported event layouts, malformed-input behavior, package/license ownership, hardware/output/loopback separation, and version-sensitive PE/runtime closure. Remove obsolete Windows download/build guidance.

- [ ] **Step 5: Record exact TODO evidence without overwriting history**

Preserve the July log, identify reopened audit findings, list task commits, exact RED/GREEN commands, counts/timings/tool versions, and residual hardware/TSan/POSIX/hosted-CI limitations. Keep status open for Task 9.

- [ ] **Step 6: Run fresh Task 8 gate and commit**

Run strict clean configure, both four-worker targets, all mandatory CTests, exact install/verifier, public distcheck, workflow mutation/pristine tests, actionlint, PowerShell parsing, and diff checks.

```powershell
git add .github pure-midi/WINDOWS.md pure-midi/README pure-midi/THIRD_PARTY.md pure/todo/TODO-34-windows-pure-midi.md
git commit -m "Validate pure-midi in Windows CI"
```

### Task 9: Whole-Branch Review and Final Verification

**Files:**
- Modify only files required by confirmed whole-branch review findings and the final TODO closure entry.

**Interfaces:**
- Consumes the full diff from `b9181357b9e384b560c7e04586f64e5755702752` plus all task reports and review rulings.
- Produces a merge-ready reviewed branch with fresh final evidence.

- [ ] **Step 1: Request whole-branch review**

Review parser/I/O safety, event/FFI boundaries, lifecycle/concurrency, fake fidelity, runner/destructive safety, exact build/PE/install/license/source/CI contracts, compatibility, and documentation claims. Report Critical, Important, and Minor findings with file/line evidence.

- [ ] **Step 2: Fix confirmed findings once**

Use one consolidated RED/GREEN wave for confirmed findings, commit it, and perform one scoped re-review. Do not fold unrelated refactoring into closure.

- [ ] **Step 3: Run fresh final verification**

Use never-before-used strict Release and ASan directories. Run configure, normal build and PE target with exactly four workers, native fault/boundary/lifecycle suites, all mandatory Pure/contract CTests, exact component install and installed verification, two identical archives and extracted-source gate, workflow mutations/actionlint, `git diff --check b9181357..HEAD`, and status inspection.

- [ ] **Step 4: Close TODO after evidence is GREEN**

Set `Status: Closed on YYYY-MM-DD` using the actual local closure date. Append exact final counts, timings, hashes, versions, limitations, review outcome, and closure commit. Commit documentation separately.

- [ ] **Step 5: Present integration options**

Use `superpowers:finishing-a-development-branch`. Do not merge or push without the user's explicit choice.
