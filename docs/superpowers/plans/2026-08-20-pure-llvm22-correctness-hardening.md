# Pure LLVM 22 Correctness Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make LLVM 22 import, Faust reload, deferred materialization, and temporary evaluation failure-atomic while correcting the regression harness and using one Faust C/Clang pipeline.

**Architecture:** Every executable-state change uses a private prepare phase and a single commit point. Candidate LLVM modules and ephemeral ORC resource trackers are destroyed on failure; canonical retry data and live interpreter state remain untouched until success. Small RAII guards restore temporary interpreter state, and all Faust input is normalized through `pure.c` plus the configured Clang 22 compiler.

**Tech Stack:** C++17, LLVM/Clang 22 ORC LLJIT and IR APIs, Pure, CMake/CTest, POSIX shell, Faust `pure.c`, AddressSanitizer.

**Spec:** `docs/superpowers/specs/2026-08-20-pure-llvm22-correctness-hardening-design.md`

## Global Constraints

- Run all builds and tests sequentially; never pass a parallel build or CTest option greater than one.
- Preserve existing untracked `_deps/` and `build/` directories.
- Do not change Pure language syntax or public language semantics.
- Direct Faust-generated LLVM bitcode is unsupported and must not remain an automatic or documented route.
- A failed prepare phase must leave live IR, symbol tables, environments, cached values, Faust generations, and callable addresses unchanged.
- Every production change requires a focused test observed failing for the audited reason before implementation.
- Test doubles may inject failures only at an existing ORC/tool boundary; assertions must cover real interpreter behavior and successful recovery.

---

### Task 1: Make the Regression and Batch Harnesses Authoritative

**Files:**
- Modify: `pure/run-tests.in:101-111`
- Create: `pure/cmake/TestRegressionHarness.cmake`
- Modify: `pure/cmake/PureInstallAndTests.cmake:648-668`
- Modify: `pure/test/batch-smoke.pure`
- Modify: `pure/cmake/RunPureBatchTest.cmake`
- Modify: `pure/cmake/PureInstallAndTests.cmake:566-620`

**Interfaces:**
- Produces: `run-tests` cases pass only if the Pure child exits zero and normalized stdout matches the golden log.
- Produces: CTest `pure-regression-harness-contract` which invokes the generated harness with a fake Pure executable that prints golden output and exits 23.
- Produces: `RunPureBatchTest.cmake` inputs `PURE_EXPECTED_OUTPUT` and `PURE_OBJECT_INSPECTOR`; the driver checks literal stdout and x86-64 object identity.

- [ ] **Step 1: Add the failing regression-harness contract**

Create `TestRegressionHarness.cmake` so it builds an isolated one-case fixture, supplies a shell fake as `PURE` which emits the fixture's exact golden output then exits 23, invokes the generated `run-tests`, and fails unless the harness itself returns nonzero. Register it as `pure-regression-harness-contract` with the same shell and generated harness used by `pure-regression`.

- [ ] **Step 2: Run the contract and verify RED**

Run:

```powershell
ctest --test-dir pure/build/audit-llvm22-release -R '^pure-regression-harness-contract$' --output-on-failure -j 1
```

Expected: FAIL because the current `run-test | sed | diff` pipeline returns the successful `diff` status and accepts the fake interpreter's exit 23.

- [ ] **Step 3: Capture child status independently**

Change `run-tests.in` to run `./run-test` with stdout redirected to a uniquely owned file inside the per-process `rundir`, save `$?` immediately, normalize that file into a second owned file, and run `@PURE_DIFF_EXECUTABLE@ -u expected normalized`. Mark a case failed if either saved status is nonzero or diff is nonzero. Preserve verbose output and remove both files through the existing `rundir` cleanup path.

- [ ] **Step 4: Verify the harness contract GREEN**

Run the command from Step 2. Expected: PASS, with the controlled exit 23 reported as an interpreter failure.

- [ ] **Step 5: Add observable batch assertions and verify RED**

Change `batch-smoke.pure` to define the batch entry point so the produced executable prints exactly `PURE_BATCH_SMOKE=42` followed by one newline. Extend `RunPureBatchTest.cmake` to require `PURE_EXPECTED_OUTPUT`, compare exact stdout, and invoke the configured LLVM object inspector (`llvm-readobj --file-headers`) on the object. Require COFF, x86-64/AMD64 machine identity, and reject empty or mismatched reports. Pass the literal and `${LLVM_TOOLS_BINARY_DIR}/llvm-readobj` from both batch CTests.

Before changing the driver, run:

```powershell
ctest --test-dir pure/build/audit-llvm22-release -R '^pure-batch-(object|executable)$' --output-on-failure -j 1
```

Expected RED after adding the new call-site arguments but before checks: a deliberately substituted `PURE_EXPECTED_OUTPUT=WRONG` or non-x86 fixture is incorrectly accepted.

- [ ] **Step 6: Implement and verify batch checks GREEN**

Run the focused batch command again with the production literal and inspector. Expected: both tests PASS, exact stdout is present, and the object report identifies x86-64 COFF.

- [ ] **Step 7: Commit the harness correction**

```powershell
git add pure/run-tests.in pure/cmake/TestRegressionHarness.cmake pure/cmake/PureInstallAndTests.cmake pure/test/batch-smoke.pure pure/cmake/RunPureBatchTest.cmake
git commit -m "Make Pure test harness failures authoritative"
```

---

### Task 2: Preserve Deferred Materialization State Until Lookup Commits

**Files:**
- Modify: `pure/interpreter.cc:1330-1460`
- Create: `pure/test/jit-deferred-retry.pure`
- Create: `pure/test/jit-deferred-retry.log`
- Modify: `pure/cmake/PureInstallAndTests.cmake:346-365`

**Interfaces:**
- Produces: `DeferredGeneration::snapshot` remains canonical retry data until a symbol lookup succeeds.
- Produces: helper `std::unique_ptr<llvm::MemoryBuffer> clone_snapshot(const llvm::MemoryBuffer&)` returning a fresh buffer with identical bytes and identifier.
- Produces: CTest `pure-jit-deferred-retry` using the existing `RunPureLifetimeStress.cmake` driver.

- [ ] **Step 1: Write the deferred retry behavior**

Add a Pure program which retains an uncalled closure whose body references a definition unavailable at first invocation. Its first forced call must produce the expected lookup failure without terminating the session; after defining the missing dependency, forcing the same retained closure must print a hand-authored success value. Put only the expected diagnostics and value in `jit-deferred-retry.log` and register the focused CTest.

- [ ] **Step 2: Run and verify RED**

```powershell
ctest --test-dir pure/build/audit-llvm22-release -R '^pure-jit-deferred-retry$' --output-on-failure -j 1
```

Expected: FAIL on the second invocation because the first add/lookup moved or committed the sole snapshot and the generation cannot retry cleanly.

- [ ] **Step 3: Submit a copy through an ephemeral tracker**

Implement `clone_snapshot` using `llvm::MemoryBuffer::getMemBufferCopy`. In deferred materialization, leave `generation->snapshot` in place, create a fresh copy, add it through a new resource tracker, and perform lookup. On add or lookup failure, remove the ephemeral tracker and return the error without altering the generation. On success, assign the tracker/address first and then reset the canonical snapshot.

- [ ] **Step 4: Verify retry and existing generation behavior GREEN**

```powershell
ctest --test-dir pure/build/audit-llvm22-release -R '^pure-jit-(deferred-retry|deferred-generation|lifetime-stress)$' --output-on-failure -j 1
```

Expected: all focused tests PASS and no removal, sanitizer, or runtime diagnostic appears.

- [ ] **Step 5: Commit deferred retry safety**

```powershell
git add pure/interpreter.cc pure/test/jit-deferred-retry.pure pure/test/jit-deferred-retry.log pure/cmake/PureInstallAndTests.cmake
git commit -m "Keep deferred JIT snapshots retryable"
```

---

### Task 3: Restore Temporary Evaluation State with RAII

**Files:**
- Modify: `pure/CMakeLists.txt`
- Modify: `pure/interpreter.cc:4750-4860`
- Modify: `pure/interpreter.cc:14980-15330`
- Create: `pure/test/jit-eval-failure-recovery.pure`
- Create: `pure/test/jit-eval-failure-recovery.log`
- Modify: `pure/cmake/PureInstallAndTests.cmake`

**Interfaces:**
- Produces: local `temporary_eval_guard` which records the pre-call interpreter/environment pointers, `fptr`, temporary IR values, cached expression ownership, and optional ORC tracker.
- Produces: `temporary_eval_guard::commit()` which disarms rollback only after permanent ownership transfer.
- Consumes: existing ORC error path; when CMake `BUILD_TESTING` is true, target `pure` receives private definition `PURE_ENABLE_TEST_HOOKS=1`. Under that definition only, environment variable `PURE_TEST_ORC_FAILURE` names `doeval-add`, `doeval-lookup`, `dodefn-add`, or `dodefn-lookup` and fails once per process at that exact boundary.
- Produces: CTest `pure-jit-eval-failure-recovery`.

- [ ] **Step 1: Add deterministic failure/recovery cases**

Write one test driver that starts a fresh Pure child for each injection value, triggers the named failure, catches/reports it through normal Pure diagnostics, then evaluates `6*7` or defines and calls `recovered x = x+1`. Expected output must prove the later operation returns 42 and that the failed definition is not visible.

- [ ] **Step 2: Verify RED for each boundary**

Run the focused test once for all four child cases. Expected: at least one child fails its recovery assertion or exits abnormally because `fptr`, environment state, temporary tracker, or IR ownership was restored only on the normal path.

- [ ] **Step 3: Implement the smallest RAII rollback guard**

Add `temporary_eval_guard` in `interpreter.cc` near `doeval`/`dodefn`. Its destructor must be `noexcept`, restore fields in reverse acquisition order, and consume/log tracker-removal errors without throwing during stack unwinding. Replace normal-path-only restoration in both functions with guard ownership; call `commit()` only after the result/definition has taken permanent ownership.

- [ ] **Step 4: Verify all injected failures recover GREEN**

```powershell
ctest --test-dir pure/build/audit-llvm22-release -R '^pure-jit-(eval-failure-recovery|eager|smoke)$' --output-on-failure -j 1
```

Expected: all tests PASS; every injected failure is followed by the literal 42 result.

- [ ] **Step 5: Commit exception-safe evaluation**

```powershell
git add pure/interpreter.cc pure/test/jit-eval-failure-recovery.pure pure/test/jit-eval-failure-recovery.log pure/cmake/PureInstallAndTests.cmake
git commit -m "Restore Pure JIT state after ORC errors"
```

---

### Task 4: Make Generic Batch Bitcode Import Transactional

**Files:**
- Modify: `pure/interpreter.cc:3990-4120`
- Create: `pure/test/bitcode/transaction-valid.c`
- Create: `pure/test/bitcode/transaction-invalid.c`
- Create: `pure/test/bitcode/transaction-recovery.pure`
- Modify: `pure/cmake/RunPureBitcodeTest.cmake`
- Modify: `pure/cmake/PureInstallAndTests.cmake`

**Interfaces:**
- Produces: `std::unique_ptr<llvm::Module> prepare_linked_module(const llvm::Module& live, std::unique_ptr<llvm::Module> imported, std::string& error)`; it clones `live`, links into the clone, verifies it, and never mutates `live`.
- Produces: `commit_module_candidate(std::unique_ptr<llvm::Module>)` which replaces the live module only after export discovery and wrapper preparation succeed.
- Produces: CTest `pure-bitcode-transaction-recovery`.

- [ ] **Step 1: Add failed-import-then-valid behavior**

Create an invalid bitcode fixture whose exported function references the absent symbol `pure_transaction_missing`, and a valid fixture exporting `pure_transaction_value()` with literal return value 42. The Pure script first imports the invalid fixture and confirms the unresolved-symbol error, then imports the valid fixture in the same batch compilation and calls `pure_transaction_value`. Extend `RunPureBitcodeTest.cmake` with explicit `PURE_SECOND_C_SOURCE` and `PURE_SECOND_BITCODE_OUTPUT` inputs; compile both fixtures with the configured Clang 22 before invoking Pure.

- [ ] **Step 2: Run and verify RED**

```powershell
ctest --test-dir pure/build/audit-llvm22-release -R '^pure-bitcode-transaction-recovery$' --output-on-failure -j 1
```

Expected: FAIL because the invalid `Linker::linkModules(*module, ...)` attempt partially mutates the live batch module, preventing the valid continuation or contaminating its exports.

- [ ] **Step 3: Prepare against a clone and commit once**

Implement `prepare_linked_module` with `llvm::CloneModule`, link and verify the candidate, and run export discovery plus wrapper preparation without writing live metadata. Transfer the candidate and prepared metadata only after all steps succeed. Destroy the candidate on every error path.

- [ ] **Step 4: Verify focused batch/bitcode behavior GREEN**

```powershell
ctest --test-dir pure/build/audit-llvm22-release -R '^(pure-bitcode-transaction-recovery|pure-bitcode-.*|pure-batch-object)$' --output-on-failure -j 1
```

Expected: the transaction test and all existing bitcode tests PASS.

- [ ] **Step 5: Commit transactional batch import**

```powershell
git add pure/interpreter.cc pure/test/bitcode/transaction-valid.c pure/test/bitcode/transaction-invalid.c pure/test/bitcode/transaction-recovery.pure pure/cmake/RunPureBitcodeTest.cmake pure/cmake/PureInstallAndTests.cmake
git commit -m "Make batch bitcode imports transactional"
```

---

### Task 5: Commit Faust Reload Only After Full Replacement Success

**Files:**
- Modify: `pure/interpreter.cc:2680-3545`
- Modify: `pure/test/faust/lifecycle.pure.in`
- Modify: `pure/cmake/RunPureFaustTest.cmake`
- Modify: `pure/cmake/PureInstallAndTests.cmake:507-565`

**Interfaces:**
- Produces: `prepared_faust_reload`, an internal owner of the candidate module, prepared export maps, wrappers, slot addresses, ORC tracker, and generation number.
- Produces: `prepare_faust_reload(...) -> prepared_faust_reload`; it cannot edit `loaded_dsps` or erase live functions/globals.
- Produces: `commit_faust_reload(prepared_faust_reload&&)`; it publishes the complete replacement and only then retires the old generation.
- Consumes: transactional candidate helpers from Task 4.

- [ ] **Step 1: Strengthen lifecycle with A/B/C recovery**

Extend the existing lifecycle fixture so A is loaded and called, B is copied from `reload-unresolved.bc` and rejected, A is called again, then C is copied from `reload-b.bc`, loaded, and called. Keep a callable A instance across the failed B attempt and assert exact input counts/results before deleting it. Ensure `RunPureFaustTest.cmake` stages each fixture under a distinct name.

- [ ] **Step 2: Verify RED, including sanitizer evidence**

Run the Release lifecycle test first. Then configure the existing LLVM 22 ASan preset/build sequentially and run only `pure-faust-lifecycle`.

Expected: current code either loses A/blocks C in Release or reports invalid access under ASan because it erased old IR before candidate B completed.

- [ ] **Step 3: Introduce prepared reload ownership**

Move all candidate export renaming, wrapper construction, verification, ORC add, lookup, slot resolution, and generation retention into `prepared_faust_reload`. Do not erase any pointer stored by `loaded_dsps` during prepare. Make destruction remove the private tracker if commit has not transferred it.

- [ ] **Step 4: Publish replacement, then retire old state**

At the commit point, install the new DSP metadata and generation as the authoritative entry. Detach the old entry into an owning local retirement record, erase old functions/globals only after no live map points to them, and release its tracker/generation. Preserve the retirement record until removal succeeds; report cleanup errors without reintroducing stale pointers.

- [ ] **Step 5: Verify Release and ASan GREEN**

```powershell
ctest --test-dir pure/build/audit-llvm22-release -R '^pure-(faust-lifecycle|batch-faust)$' --output-on-failure -j 1
```

Then run the same focused lifecycle test in the ASan build. Expected: A survives B, C installs, all exact assertions pass, and ASan reports no invalid access, leak, or runtime error.

- [ ] **Step 6: Commit transactional Faust reload**

```powershell
git add pure/interpreter.cc pure/test/faust/lifecycle.pure.in pure/cmake/RunPureFaustTest.cmake pure/cmake/PureInstallAndTests.cmake
git commit -m "Make Faust reload failure atomic"
```

---

### Task 6: Route Inline Faust Through pure.c and Clang 22

**Files:**
- Modify: `pure/interpreter.cc:4130-4400`
- Create: `pure/test/faust/inline-dsp.pure.in`
- Create: `pure/cmake/RunPureInlineFaustTest.cmake`
- Modify: `pure/cmake/PureInstallAndTests.cmake:507-565`
- Modify: `pure/INSTALL:390-420`
- Modify: `pure/pure.txt`

**Interfaces:**
- Produces: one internal Faust command builder that invokes configured Faust with `-double -a <pure.c> -lang c`, followed by configured Clang 22 compilation.
- Produces: CTest `pure-faust-inline-dsp`, exercising actual inline DSP syntax and a callable result.
- Removes: automatic/direct `faust -lang llvm` selection and its documentation.

- [ ] **Step 1: Add a real inline DSP integration test**

Create `inline-dsp.pure.in` containing a minimal inline Faust processor with one deterministic input/output behavior, instantiate it, assert input/output arity, exercise one callable operation, and delete it. The CMake driver must provide paths containing spaces and capture exact output plus exit status.

- [ ] **Step 2: Run and verify RED against Faust 2.85.9**

```powershell
ctest --test-dir pure/build/audit-llvm22-release -R '^pure-faust-inline-dsp$' --output-on-failure -j 1
```

Expected: FAIL with the direct Faust LLVM output rejected as incompatible (`Invalid bitcode signature` or equivalent loader failure).

- [ ] **Step 3: Replace the direct backend with the supported pipeline**

Make inline DSP use the same `pure.c` architecture and configured Clang path already used by the working file-based Faust fixtures. Use unique owned temporary paths, quote executable/file arguments, capture both tool exit statuses, and remove all owned intermediate C/LLVM/object files on success and failure. Feed the Clang-produced LLVM artifact into the transactional loader.

- [ ] **Step 4: Verify inline and existing Faust tests GREEN**

```powershell
ctest --test-dir pure/build/audit-llvm22-release -R '^pure-(faust-inline-dsp|faust-lifecycle|batch-faust)$' --output-on-failure -j 1
```

Expected: all tests PASS with configured Clang 22 and no direct Faust bitcode parsing.

- [ ] **Step 5: Update documentation and scan it**

Remove direct `faust -lang llvm` recommendations from `INSTALL` and `pure.txt`. State that `pure.c` plus the configured Clang matching Pure's LLVM major is the supported route.

Run:

```powershell
rg -n -- '-lang llvm|Faust.*LLVM bitcode|direct.*bitcode' pure/INSTALL pure/pure.txt pure/interpreter.cc
```

Expected: no supported command or automatic direct-backend branch remains; any historical incompatibility statement is explicitly marked unsupported.

- [ ] **Step 6: Commit the unified Faust pipeline**

```powershell
git add pure/interpreter.cc pure/test/faust/inline-dsp.pure.in pure/cmake/RunPureInlineFaustTest.cmake pure/cmake/PureInstallAndTests.cmake pure/INSTALL pure/pure.txt
git commit -m "Compile inline Faust through Clang 22"
```

---

### Task 7: Run Complete Sequential Closure Gates

**Files:**
- Modify only if evidence reveals a scoped defect: files already listed in Tasks 1-6
- Update: `docs/superpowers/plans/2026-08-20-pure-llvm22-correctness-hardening.md` checkbox state during execution

**Interfaces:**
- Consumes: all focused tests and production contracts from Tasks 1-6.
- Produces: fresh Release, corpus, repeated lifetime, ASan, documentation, and cleanup evidence at one exact commit.

- [ ] **Step 1: Configure and build a fresh Release tree sequentially**

Create a new build directory rather than reusing `audit-llvm22-release`. Run:

```powershell
cmake -S pure -B pure/build/llvm22-hardening-release -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DCMAKE_CXX_COMPILER=C:/msys64/clang64/bin/clang++.exe -DLLVM_DIR=C:/msys64/clang64/lib/cmake/llvm -DBISON_EXECUTABLE=C:/msys64/usr/bin/bison.exe -DFLEX_EXECUTABLE=C:/msys64/usr/bin/flex.exe "-DPURE_FAUST_EXECUTABLE=C:/Program Files/Faust/bin/faust.exe" -DPURE_DIFF_EXECUTABLE=C:/msys64/usr/bin/diff.exe -DBUILD_TESTING=ON
cmake --build pure/build/llvm22-hardening-release --parallel 1
```

Record every warning and reject new warnings introduced by these changes.

- [ ] **Step 2: Run the full CTest suite sequentially**

```powershell
ctest --test-dir pure/build/llvm22-hardening-release --output-on-failure -j 1
```

Expected: 100% PASS, including the new harness, retry, recovery, transaction, inline Faust, and batch architecture tests.

- [ ] **Step 3: Run the complete regression corpus**

From the fresh build directory, run generated `run-tests` with `TEST_JOBS=1`, the validated MSYS2 diff executable, and timing/verbose output. Expected: `prelude.pure` and every `test001.pure` through `test096.pure` PASS; no interpreter nonzero status is masked.

- [ ] **Step 4: Repeat lifetime tests**

```powershell
ctest --test-dir pure/build/llvm22-hardening-release -R '^pure-jit-(lifetime-stress|deferred-generation|deferred-retry)$' --repeat until-fail:20 --output-on-failure -j 1
```

Expected: every repetition PASS without removal or runtime diagnostics.

- [ ] **Step 5: Run the ASan transaction gate**

Configure/build the supported LLVM 22 ASan tree sequentially:

```powershell
cmake -S pure -B pure/build/llvm22-hardening-asan -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DCMAKE_CXX_COMPILER=C:/msys64/clang64/bin/clang++.exe -DLLVM_DIR=C:/msys64/clang64/lib/cmake/llvm -DBISON_EXECUTABLE=C:/msys64/usr/bin/bison.exe -DFLEX_EXECUTABLE=C:/msys64/usr/bin/flex.exe "-DPURE_FAUST_EXECUTABLE=C:/Program Files/Faust/bin/faust.exe" -DPURE_DIFF_EXECUTABLE=C:/msys64/usr/bin/diff.exe -DPURE_SANITIZERS=address -DBUILD_TESTING=ON
cmake --build pure/build/llvm22-hardening-asan --parallel 1
ctest --test-dir pure/build/llvm22-hardening-asan -R '^pure-(faust-lifecycle|bitcode-transaction-recovery|jit-deferred-retry|jit-eval-failure-recovery)$' --output-on-failure -j 1
```

Expected: all focused tests PASS with no AddressSanitizer, LeakSanitizer, or undefined-runtime diagnostic.

- [ ] **Step 6: Audit owned resources and tracked changes**

Verify no Pure/Faust/Clang child remains, remove only uniquely owned temporary fixtures after canonical containment checks, and preserve `_deps/` plus existing `build/`. Run `git diff --check`, inspect every changed hunk, and confirm the documentation scan from Task 6.

- [ ] **Step 7: Request independent code review**

Dispatch a read-only reviewer over the complete implementation range. Require it to inspect transactional commit boundaries, retry ownership, exception paths, test mutation strength, actual Faust tool commands, and all unsupported claims. Address every Critical or Important finding with a fresh RED/GREEN cycle before proceeding.

- [ ] **Step 8: Final verification and commit**

After review fixes, rerun every affected focused test and the complete sequential Release suite. Commit the final review corrections and evidence documentation without pushing or merging unless the user explicitly requests it.
