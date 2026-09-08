# Windows pure-audio Audit Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make TODO-33's native Windows pure-audio implementation memory-safe, deterministic without hardware, and exactly reproducible as a source and binary package.

**Architecture:** Keep one frame-aligned interleaved queue internally and gather/scatter PortAudio non-interleaved channel arrays at the callback boundary. Introduce test-only native API dispatch and a strict process runner, then build exact PE, install, source archive, CI, license, and documentation contracts around the corrected modules.

**Tech Stack:** C11, Pure 0.68 FFI, PortAudio 19, libsndfile 1.2, libsamplerate 0.2, FFTW 3.3, CMake 3.25+, Ninja, Clang 22 CLANG64, llvm-readobj, PowerShell, PyYAML.

**Spec:** `docs/superpowers/specs/2026-09-08-windows-pure-audio-audit-hardening-design.md`

## Global Constraints

- Preserve all public Pure symbol names and successful-path value shapes, except that every native `sf_count_t` declaration must use signed 64-bit FFI types.
- Fully support both interleaved and `Pa::NonInterleaved` callback layouts.
- Internal queues contain complete interleaved frames only; partial-frame transfer is forbidden.
- Production dispatch always calls the real native libraries; injection exists only in test targets.
- Mandatory tests must not open physical audio devices, use credentials/network services, or depend on inherited Pure/runtime paths.
- Recursive cleanup requires an owned fixed root, exact sentinel, canonical non-reparse ancestors, and unique leaves.
- Normal upstream configuration remains available; strict Clang 22 x86-64 audit constraints are opt-in.
- Strict Windows builds and PE targets use exactly four workers.
- TODO-33 remains open until all task reviews and final whole-branch verification pass.

---

### Task 1: Correct ABI Widths, Matrix Bounds, and Size Arithmetic

**Files:**
- Modify: `pure-audio/sndfile/sndfile.pure`
- Modify: `pure-audio/audio.pure`
- Modify: `pure-audio/audio.c`
- Modify: `pure-audio/samplerate/samplerate.pure`
- Modify: `pure-audio/fftw/fftw.pure`
- Create: `pure-audio/tests/audio_fault_harness.c`
- Create: `pure-audio/tests/audio_test_api.h`
- Modify: `pure-audio/CMakeLists.txt`

**Interfaces:**
- Produces `pure_audio_checked_mul_size(size_t, size_t, size_t *)`, `pure_audio_frame_bytes(unsigned, unsigned long, size_t *)`, and test-only public wrappers under `PURE_AUDIO_TEST_SEAM`.
- Produces correct Pure `int64` declarations for every `sf_count_t` parameter/result.
- Later callback and lifecycle tasks consume the checked size helpers and fault harness.

- [ ] **Step 1: Add RED native boundary tests**

Add harness cases that assert overflow rejection before allocation or loop entry, invalid/negative counts, and exact conversions at `INT32_MAX`, `INT32_MAX + 1`, `SIZE_MAX / channels`, and one past the safe product. The expected interface is:

```c
size_t bytes = 0;
CHECK(!pure_audio_checked_mul_size(SIZE_MAX, 2, &bytes));
CHECK(pure_audio_frame_bytes(2, paFloat32, &bytes) && bytes == 8);
CHECK(!pure_audio_frame_bytes(UINT_MAX, paFloat32, &bytes));
```

- [ ] **Step 2: Add RED Pure public-path fixtures**

Extend a dedicated `tests/bounds.pure` fixture to call audio read/write and samplerate wrappers with matrices smaller than `frames * channels`, invalid ratios, odd FFT shapes, and signed 64-bit libsndfile boundary declarations. Require a completion marker only after every rejection is observed.

- [ ] **Step 3: Run RED tests**

Configure a fault-test build and run only `pure-audio-bounds` and `pure-audio-fault`; expected failures are unchecked capacity/overflow and incorrect `sf_count_t` declarations, not missing fixtures.

- [ ] **Step 4: Implement checked arithmetic and wrappers**

Use division-based overflow checks before multiplication:

```c
bool pure_audio_checked_mul_size(size_t a, size_t b, size_t *out) {
  if (!out || (a && b > SIZE_MAX / a)) return false;
  *out = a * b;
  return true;
}
```

Make allocation sizes and loop bounds consume the same validated result. In Pure, reject a matrix unless its actual element count is at least the checked requirement. Change all `sf_count_t` declarations to signed `int64`, and reject unsupported odd FFT input shapes explicitly.

- [ ] **Step 5: Fix conversion fall-through**

Give `paInt16`, `paInt8`, and `paUInt8` independent terminating branches for both read and write. Add exact min/zero/max conversion assertions and prove the native write call occurs once.

- [ ] **Step 6: Run GREEN and regression tests**

Run the two focused tests under ASan plus the existing load/processing tests. Expected: all cases pass, no sanitizer diagnostic, zero tracked allocation delta.

- [ ] **Step 7: Commit**

```powershell
git add pure-audio/audio.c pure-audio/audio.pure pure-audio/sndfile/sndfile.pure pure-audio/samplerate/samplerate.pure pure-audio/fftw/fftw.pure pure-audio/tests pure-audio/CMakeLists.txt
git commit -m "Harden pure-audio ABI and buffer bounds"
```

### Task 2: Frame-Aligned Interleaved and Non-Interleaved Callbacks

**Files:**
- Modify: `pure-audio/audio.c`
- Modify: `pure-audio/audio.pure`
- Modify: `pure-audio/tests/audio_fault_harness.c`
- Modify: `pure-audio/audio_test_api.h`

**Interfaces:**
- Produces a frame-counted ring queue and `pure_audio_api` dispatch table whose production default calls PortAudio.
- Produces gather/scatter callback helpers for channel-pointer arrays; Task 3 extends the same dispatch for lifecycle faults.

- [ ] **Step 1: Add RED callback-layout tests**

Drive the real callback through the test seam with one, two, and three channels for `Float32`, `Int32`, `Int24` where supported, `Int16`, `Int8`, and `UInt8`. Assert exact logical ordering for interleaved and non-interleaved buffers and require guard bytes around every channel.

- [ ] **Step 2: Add RED frame-alignment and silence tests**

Use capacities that previously rounded 6144 bytes to 8192. Invoke consecutive callbacks and assert that accepted/dropped counts are whole frames, channel order is unchanged, signed/float silence is zero, and UInt8 silence is byte 128.

- [ ] **Step 3: Run RED callback suite**

Expected: non-interleaved guard corruption, UInt8 zero silence, and partial-frame queue transfer failures.

- [ ] **Step 4: Replace byte queue semantics with frame semantics**

Store `frame_capacity`, `frame_read`, `frame_write`, `channels`, and `sample_bytes`. Convert frames to bytes only through Task 1 helpers. Queue APIs accept/return frames and copy one complete logical frame per unit.

- [ ] **Step 5: Implement callback gather/scatter**

For interleaved buffers, copy complete frame spans. For `Pa::NonInterleaved`, validate the channel pointer array and gather/scatter `sample_bytes` for each `(frame, channel)` into/from the canonical queue. Never apply a contiguous `memset` to the pointer array.

- [ ] **Step 6: Implement format-aware underflow and measured drain**

Fill missing output frames with encoded silence and increment an atomic or mutex-protected consumed-frame counter only after callback transfer. Expose the counter to the test seam and hardware drain helper.

- [ ] **Step 7: Run GREEN under ASan**

Expected: all layout, guard, alignment, silence, overflow/drop, and callback-consumption assertions pass with zero tracked resources.

- [ ] **Step 8: Commit**

```powershell
git add pure-audio/audio.c pure-audio/audio.pure pure-audio/audio_test_api.h pure-audio/tests/audio_fault_harness.c
git commit -m "Support frame-safe PortAudio callback layouts"
```

### Task 3: Make Stream Lifecycle and Concurrent Close Deterministic

**Files:**
- Modify: `pure-audio/audio.c`
- Modify: `pure-audio/audio.pure`
- Modify: `pure-audio/tests/audio_fault_harness.c`
- Modify: `pure-audio/audio_test_api.h`

**Interfaces:**
- Extends `pure_audio_api` with initialize/device/open/start/stop/abort/close/query operations.
- Produces explicit stream states and activity/callback counts used by every public query and I/O operation.

- [ ] **Step 1: Add RED lifecycle failure matrix**

Inject failure at each PortAudio call and each owned allocation/synchronization initialization. Assert exact reverse-order cleanup, no destruction of uninitialized mutexes/conditions, no returned stream after failed start, and zero resource counters.

- [ ] **Step 2: Add RED invalid-device and alias tests**

Return null device info for default and explicit indexes. Assert error return without dereference. Create multiple Pure aliases/sentries, close through one, and assert every subsequent query/I/O rejects the stale native handle.

- [ ] **Step 3: Add RED concurrency tests**

Block reader and writer threads, trigger stop/close/callback failure/device loss, and require bounded wakeup. Race callback entry with close and assert synchronization objects are destroyed only after callback and operation counts reach zero.

- [ ] **Step 4: Implement explicit state and ownership flags**

Track allocated/opened/started/stopping/closed/failed, each initialized synchronization primitive, callback activity, and public operation activity. All state transitions occur under one stream mutex; queue indices use the same lock or documented C11 atomics.

- [ ] **Step 5: Implement checked open/start rollback**

Validate device indexes and `Pa_GetDeviceInfo` first. Check every native return. On start failure, close the opened stream, release only initialized resources, and return the native error without creating a sentry.

- [ ] **Step 6: Implement close/stop/restart protocol**

Mark closing, stop callback production, broadcast waiters, wait for callback and operation activity to drain, close the native stream, invalidate shared handle identity, then destroy synchronization and memory. Make repeated close and finalizer idempotent.

- [ ] **Step 7: Make blocking I/O state-aware**

Wait predicates include both queue progress and terminal state. On wake, recheck state before touching queue memory. Return an error on stop, close, callback failure, or device loss.

- [ ] **Step 8: Run GREEN and ThreadSanitizer-equivalent checks available on Windows**

Run ASan plus deterministic high-iteration concurrency tests. If TSan is unavailable, record that limitation and require exact state/resource/event counters.

- [ ] **Step 9: Commit**

```powershell
git add pure-audio/audio.c pure-audio/audio.pure pure-audio/audio_test_api.h pure-audio/tests/audio_fault_harness.c
git commit -m "Fix pure-audio stream lifecycle"
```

### Task 4: Replace Test Launchers with One Hermetic Native Runner

**Files:**
- Create: `pure-audio/tests/run_pure_test.c`
- Create: `pure-audio/tests/runner_contract.cmake`
- Create: `pure-audio/tests/cleanup_contract.cmake`
- Modify: `pure-audio/cmake/RunPureTest.cmake`
- Modify: `pure-audio/cmake/RunHardwareTest.cmake`
- Modify: `pure-audio/tests/load.pure`
- Modify: `pure-audio/tests/smoke.pure`
- Modify: `pure-audio/tests/hardware.pure`
- Modify: `pure-audio/CMakeLists.txt`
- Modify: `pure-audio/Makefile`

**Interfaces:**
- Produces `run_pure_test.exe --pure ... --script ... --token ... --timeout ... --cwd ... --path-entry ...` with exact exit propagation and captured streams.
- Produces root/sentinel cleanup helpers consumed by install and source-distribution contracts.

- [ ] **Step 1: Add RED runner false-positive tests**

Fixtures exit zero after parser diagnostics, throw before completion, print a forged/wrong token, duplicate the token, hang with filled stdout/stderr pipes, and spawn a child inheriting handles. Expected: every case fails boundedly except one pristine fixture.

- [ ] **Step 2: Add RED environment and path tests**

Poison inherited `PATH`, `PURELIB`, `PURE_INCLUDE`, and `PURE_LIBRARY`; place fake modules in each. Assert the runner loads only canonical module/runtime inputs and never launches an executable through a reparse component.

- [ ] **Step 3: Add RED cleanup tests**

Exercise empty, root, outside-root, missing/wrong sentinel, regular-file sentinel, symlink/junction/reparse ancestor, concurrent leaf, and valid owned leaf. Expected: only the valid owned leaf is removable.

- [ ] **Step 4: Implement the native runner**

Use Windows process creation with an explicit environment block, owned CWD, concurrent pipe readers, a Job Object or equivalent child-tree timeout, and wait-before-handle cleanup. Success requires exit zero, exactly one generated token at the final stdout position, and no unexpected stderr.

- [ ] **Step 5: Convert all Pure fixtures to final-token protocol**

Accept the generated token as an argument and print it only after every check, cleanup, and drain assertion. Hardware playback waits for the callback-consumed frame count before close; capture reports the actual requested/received channel count.

- [ ] **Step 6: Harden cleanup and Make targets**

Canonicalize roots and reject reparse ancestors before any recursive mutation. Replace broad `*$(DLL)*` removal with enumerated owned outputs and validate the exact suffix.

- [ ] **Step 7: Run GREEN contracts and baseline tests**

Run runner/cleanup mutation matrices, then run load and processing with a deliberately poisoned parent environment. Expected: all mandatory tests pass from explicit inputs only.

- [ ] **Step 8: Commit**

```powershell
git add pure-audio/CMakeLists.txt pure-audio/Makefile pure-audio/cmake pure-audio/tests
git commit -m "Make pure-audio tests hermetic"
```

### Task 5: Enforce Strict Toolchain and Exact PE Closure

**Files:**
- Modify: `pure-audio/CMakeLists.txt`
- Rewrite: `pure-audio/cmake/VerifyWindowsDependencies.cmake`
- Create: `pure-audio/tests/configure_contract.cmake`
- Create: `pure-audio/tests/runtime_verifier_contract.cmake`

**Interfaces:**
- Produces opt-in `PURE_AUDIO_STRICT_WINDOWS_AUDIT` and explicit cache inputs for every tool, SDK, header, import library, runtime DLL, and authoritative Windows directory.
- Produces exact recursive PE verifier used by Tasks 6–8.

- [ ] **Step 1: Add RED strict-configure mutation matrix**

Test missing/nonexistent/directory/symlink/junction/wrong-origin tools and inputs, wrong Clang major/target, non-AMD64 import library, malformed runtime list, duplicate names, altered MSYSTEM environment, and a pristine explicit configuration.

- [ ] **Step 2: Implement strict opt-in configuration**

Keep non-strict builds working. In strict mode canonicalize and compare every regular path, require Clang major 22 and target `x86_64-w64-windows-gnu`, freeze runtime sources at configure time, and reject undeclared environment fallback.

- [ ] **Step 3: Add RED PE parser/closure mutations**

Independently fixture unknown, missing, duplicate, mixed-case forbidden, delay, malformed/no-name/multiple-name imports, wrong machine/format, ambiguous origin, host fallback, missing transitive DLL, and extra staged PE. Expected: each mutation fails while one independently declared pristine manifest passes.

- [ ] **Step 4: Implement exact fail-closed verifier**

Parse complete `llvm-readobj --file-headers --coff-imports` blocks. Traverse the five modules, `libpure.dll`, and every recursively resolved non-system DLL. Require exact AMD64/PE32+ imports and a unique configured source/staged destination for each non-system dependency. Resolve system imports only below the authoritative Windows directory.

- [ ] **Step 5: Run GREEN contracts and direct PE target**

Record tool versions, exact PE count, import sets, origins, and negative-case count. Verify normal non-strict configure remains available.

- [ ] **Step 6: Commit**

```powershell
git add pure-audio/CMakeLists.txt pure-audio/cmake/VerifyWindowsDependencies.cmake pure-audio/tests/configure_contract.cmake pure-audio/tests/runtime_verifier_contract.cmake
git commit -m "Enforce pure-audio Windows PE contracts"
```

### Task 6: Make Installation Exact and Licensing Complete

**Files:**
- Rewrite: `pure-audio/cmake/Install.cmake`
- Rewrite: `pure-audio/cmake/VerifyInstalledPackage.cmake`
- Modify: `pure-audio/THIRD_PARTY.md`
- Create: `pure-audio/licenses/` exact license files for every distributed third-party runtime
- Create: `pure-audio/tests/install_contract.cmake`
- Modify: `pure-audio/CMakeLists.txt`

**Interfaces:**
- Produces disjoint `runtime` and `documentation` components, exact install manifests, baseline/hash verification, and a complete binary-to-license inventory.

- [ ] **Step 1: Inventory configured artifacts and licenses**

Map every installed module/interface/runtime/document/example/test/license to its exact configured source, destination, SHA-256, project, version, source URL, and license identifier. Source license texts only from installed MSYS2 package payloads or existing repository files; record absence as a RED preflight failure.

- [ ] **Step 2: Add RED install mutations**

Test source/build hash mismatch, pre-existing destination collision, overwritten baseline, extra file anywhere in the prefix, missing/duplicate/cross-component manifest entries, altered runtime, absent license, runtime-to-license mismatch, wrong PE origin, and host-rescued smoke.

- [ ] **Step 3: Implement collision preflight and component ownership**

Fail before installation when any declared destination conflicts with a non-identical file. Install runtime and documentation separately and preserve each generated manifest before the next component.

- [ ] **Step 4: Implement full-prefix exact verification**

Compare sorted pre/post manifests so the post tree equals the byte-identical baseline plus exactly the declared delta. Hash every delta file to its configured source and verify the complete installed PE closure through Task 5.

- [ ] **Step 5: Run installed smoke hermetically**

Use Task 4's runner with all inherited Pure paths removed. Require completion token and no unexpected diagnostics. Prove missing staged content cannot be loaded from the checkout or CLANG64 host.

- [ ] **Step 6: Run GREEN install matrix**

Record exact component counts, total delta count, staged PE count, license mappings, mutation count, and pristine run count.

- [ ] **Step 7: Commit**

```powershell
git add pure-audio/CMakeLists.txt pure-audio/cmake/Install.cmake pure-audio/cmake/VerifyInstalledPackage.cmake pure-audio/THIRD_PARTY.md pure-audio/licenses pure-audio/tests/install_contract.cmake
git commit -m "Verify the exact pure-audio package"
```

### Task 7: Complete and Verify the Source Distribution

**Files:**
- Modify: `pure-audio/Makefile`
- Create: `pure-audio/tests/source_dist_contract.cmake`
- Modify: `pure-audio/CMakeLists.txt`

**Interfaces:**
- Consumes every Task 1–6 source/build/test/install/verifier input.
- Produces a real self-contained archive contract consumed by Windows CI.

- [ ] **Step 1: Add a RED real-archive contract**

Run actual `make dist`, extract beneath `distribution source with spaces`, make checkout-side sources unavailable, and compare the extracted regular-file/hash set to an independent exact manifest. Expected pre-fix: CMake/tests/docs/licenses are missing.

- [ ] **Step 2: Add RED reparse and checkout-leak mutations**

Test endpoint and ancestor symlink/junction inputs, checkout-root junction, mixed-case checkout strings crossing scan chunks and appearing after 9 MiB in binary output, and unexpected archive files.

- [ ] **Step 3: Correct DISTFILES and safe archive construction**

Enumerate all required sources, interfaces, CMake helpers, native harness/runner, Pure fixtures/data, documentation, examples, package and third-party licenses. Reject non-regular/reparse inputs, quote paths, and avoid caller-controlled recursive deletion.

- [ ] **Step 4: Run extracted-source end to end**

From extracted files only, run strict configure, build and PE target with exactly four workers, all mandatory tests, both component installs, installed verifier, and checkout-leak scan of stdout/stderr/cache/generated files without a size limit.

- [ ] **Step 5: Commit**

```powershell
git add pure-audio/Makefile pure-audio/CMakeLists.txt pure-audio/tests/source_dist_contract.cmake
git commit -m "Include pure-audio Windows contracts in releases"
```

### Task 8: Add Windows CI and Audited Documentation

**Files:**
- Modify: `.github/workflows/non-linux-release-validation.yml`
- Modify: `.github/scripts/validate_non_linux_release_workflow.py`
- Modify: `.github/scripts/test_validate_non_linux_release_workflow.py`
- Rewrite: `pure-audio/WINDOWS.md`
- Modify: `pure-audio/README`
- Modify: `pure/todo/TODO-33-windows-pure-audio.md`

**Interfaces:**
- Consumes Tasks 4–7 explicit runner, strict configuration, PE, install, and source-distribution interfaces.
- Produces reproducible CI and closure documentation.

- [ ] **Step 1: Reopen TODO and establish RED YAML semantics**

Set `Status: Open`. Add PyYAML `BaseLoader` mutations proving both trigger filters, prerequisite packages, ordered pure-audio steps, strict explicit inputs, exact build targets/workers, sanitized environment, both components, and complete verifier arguments are absent or incomplete before the workflow change.

- [ ] **Step 2: Add Windows workflow coverage**

Cover `pure-audio/**`, TODO-33, workflow helpers, and workflow file on push and pull request. After portable Pure staging, configure strict Release, build and PE-check with two distinct `--parallel 4` commands, run the nonempty audio label without hardware, install both components into a fresh stage, invoke the full verifier, and run source distribution.

- [ ] **Step 3: Run GREEN YAML and command contracts**

Parse structures rather than grepping text. Mutate duplicate/substituted/conflicting worker commands, missing environment variables, reordered stages, incomplete arguments, and absent paths; require all mutations to fail and pristine workflow to pass.

- [ ] **Step 4: Rewrite Windows and README instructions**

Give exact prerequisites and standalone configure/build/test/install/verifier commands, explicit hardware-test boundaries, supported channel/sample layouts, exact package/license ownership, and version-sensitive closure. Remove obsolete Windows Makefile/import-name guidance.

- [ ] **Step 5: Append exact TODO audit evidence**

Preserve original history; record audit findings, commits, RED/GREEN commands, counts, timing, tool versions, hardware limitations, and residual risks. Keep TODO open pending Task 9.

- [ ] **Step 6: Run fresh Task 8 closure and commit**

Run strict clean configure, two four-worker targets, full audio CTest label, exact component install/verifier, source archive contract, YAML mutations/pristine validation, PowerShell command parsing, and `git diff --check`.

```powershell
git add .github pure-audio/WINDOWS.md pure-audio/README pure/todo/TODO-33-windows-pure-audio.md
git commit -m "Validate pure-audio in Windows CI"
```

### Task 9: Whole-Branch Review and Final Verification

**Files:**
- Modify only files required by confirmed whole-branch findings and the final TODO closure entry.

**Interfaces:**
- Consumes the full diff from `7c88827e` plus all task reports/review rulings.
- Produces a merge-ready reviewed branch with fresh evidence.

- [ ] **Step 1: Request whole-branch review**

Review `7c88827e..HEAD` against the design and plan. Triage native/FFI safety, callback layouts, concurrency and ownership, fake-backend fidelity, runner/destructive safety, exact PE/install/license/source closure, CI semantics, and documentation claims.

- [ ] **Step 2: Fix confirmed findings once**

Use one consolidated implementation wave for all confirmed Critical, Important, and Minor findings. Capture covering RED/GREEN evidence, commit, and perform exactly one scoped re-review.

- [ ] **Step 3: Run fresh final verification**

Use a never-before-used strict Release build directory. Run configure; build and PE target with exactly four workers; ASan native faults; all mandatory audio CTests; exact component install and installed smoke/PE verifier; extracted source archive end to end; YAML mutations and semantic validation; `git diff --check 7c88827e..HEAD`; and confirm only owned build artifacts remain.

- [ ] **Step 4: Close TODO only after GREEN evidence**

Set `Status: Closed on YYYY-MM-DD` using the system's actual local date at the moment closure verification finishes, and append exact final counts/timings/versions/limitations. Commit the closure separately.

- [ ] **Step 5: Present integration options**

Use `superpowers:finishing-a-development-branch`. Do not merge or push without the user's explicit choice.
