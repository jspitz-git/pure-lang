# Windows pure-odbc Audit Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make TODO-32's native Windows ODBC binding memory-safe and enforce every build, test, package, portability, and CI claim with executable contracts.

**Architecture:** Production ODBC calls pass through a narrow internal dispatch table so a native harness can inject exact return values while exercising production logic. CMake contracts share fail-closed cleanup roots and validate exact PE imports, full-prefix install deltas, and real source archives before Windows CI documents and consumes those interfaces.

**Tech Stack:** C11, Windows ODBC API, Pure 0.68, CMake 3.25+, Clang 22 CLANG64, Ninja, MSYS make, llvm-readobj, PowerShell, GitHub Actions YAML.

**Spec:** `docs/superpowers/specs/2026-09-07-windows-pure-odbc-audit-design.md`

## Global Constraints

- Preserve public Pure symbols, tuple shapes, and error constructors.
- Keep Pure `int` for values in 32-bit range; use `pure_int64` only outside that range.
- Production Windows uses the native 64-bit Microsoft ODBC Driver Manager; never install unixODBC, `odbc32.dll`, or a database driver.
- Mandatory tests require no credentials, DSN, network service, or third-party database driver.
- The exact Access Text Driver test is optional and must report a real CTest skip when unavailable.
- Strict audit configuration uses Clang 22, x86-64 Windows, CLANG64 dependencies, Ninja, MSYS make, and exactly four build workers.
- Pure child processes replace `PATH`, unset `PURELIB`, use owned/neutral working directories, and reject unexpected stderr.
- Recursive cleanup is allowed only beneath an internally derived, validated build leaf with an exact ownership sentinel and no reparse components.
- Exact PE import sets and package manifests are intentionally version-sensitive and fail closed.
- Preserve the historical TODO log; append dated audit evidence and close only after final verification.

---

### Task 1: ODBC Dispatch Seam and Critical Read Safety

**Files:**
- Create: `pure-odbc/odbc_api.h`
- Create: `pure-odbc/tests/odbc_fault_harness.c`
- Modify: `pure-odbc/odbc.c:1-120,520-550,1090-1160`
- Modify: `pure-odbc/CMakeLists.txt`

**Interfaces:**
- Produces: `struct pure_odbc_api` containing the ODBC entry points used by `odbc.c` and `pure_odbc_set_api_for_test(const struct pure_odbc_api *)` under `PURE_ODBC_TESTING`.
- Produces: checked text-info loader and `SQLGetData` conversion helpers exercised by the harness.
- Consumes: real `SQL*` functions as the immutable production default table.

- [ ] **Step 1: Add RED fault-injection cases**

Add table-driven harness cases for integer, double, string, and binary `SQLGetData`: `SQL_ERROR` and `SQL_NO_DATA` must not read poisoned outputs; `SQL_SUCCESS_WITH_INFO` is accepted only according to the branch contract. Add `SQLGetInfo` cases for a 2048-byte value, negative length, `SQL_NO_TOTAL`, retry failure, and allocator failure. Track every allocation and forbid a net leak.

- [ ] **Step 2: Prove the historical code fails**

Run:

```powershell
& C:/msys64/clang64/bin/cmake.exe -S pure-odbc -B build/task1-red -G Ninja `
  -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DBUILD_TESTING=ON `
  -DPURE_ODBC_BUILD_FAULT_TESTS=ON
& C:/msys64/clang64/bin/cmake.exe --build build/task1-red --target pure-odbc-fault-tests --parallel 4
& C:/msys64/clang64/bin/ctest.exe --test-dir build/task1-red -R pure-odbc-fault --output-on-failure
```

Expected: precedence cases accept injected failures and the long-info case reports an out-of-bounds read under ASan or a poisoned-copy assertion.

- [ ] **Step 3: Introduce the minimal dispatch seam**

Declare every used function pointer with the exact Windows ODBC signature. Initialize a file-local production table to the real `SQL*` symbols; compile the setter only for the harness. Replace direct calls mechanically without changing public wrappers.

- [ ] **Step 4: Correct `SQLGetData` and `SQLGetInfo`**

Use this control shape in every conversion branch:

```c
SQLRETURN ret = api->SQLGetData(...);
if (!SQL_SUCCEEDED(ret)) return odbc_error(...);
```

For textual `SQLGetInfo`, retry after truncation into an overflow-checked dynamic buffer. Numeric info values use their documented fixed-width result type and never pass through the text buffer.

- [ ] **Step 5: Run GREEN and production regression tests**

Run the fault harness with ASan and the ordinary strict Release build/load/smoke tests. Expected: all injected failures are rejected, the long string round-trips exactly, allocation count returns to zero, and production tests pass.

- [ ] **Step 6: Commit**

```powershell
git add pure-odbc/odbc_api.h pure-odbc/odbc.c pure-odbc/tests/odbc_fault_harness.c pure-odbc/CMakeLists.txt
git commit -m "Fix critical pure-odbc read safety"
```

### Task 2: Resource Ownership and Result Transitions

**Files:**
- Modify: `pure-odbc/odbc.c:360-440,930-1050,1270-1360`
- Modify: `pure-odbc/tests/odbc_fault_harness.c`

**Interfaces:**
- Consumes: Task 1 dispatch table and allocation/resource counters.
- Produces: single cleanup ladders for connection and execution setup; deterministic ownership transfer for `argv`, statement handles, cursors, and `coltype`.

- [ ] **Step 1: Add RED resource-state tests**

Inject failure after environment allocation, connection allocation, driver connect, parameter conversion, parameter bind, prepare, execute, and result metadata allocation. Assert exact matching free/disconnect/close counts. Add both `update-count -> result-set` and `result-set -> update-count` sequences and assert the next fetch/row count succeeds.

- [ ] **Step 2: Run RED tests**

Run `ctest -R pure-odbc-fault --output-on-failure`. Expected: leaked connection storage, retained arguments/cursor after execute failure, or lost `coltype` ownership is reported.

- [ ] **Step 3: Implement cleanup ladders**

Initialize all handles and owned pointers before acquisition. Route every failure through one reverse-order cleanup block per operation. A failed `SQLExecute` must free converted arguments and close/reset the statement before returning an error.

- [ ] **Step 4: Correct result metadata transfer**

Free the old descriptor when present, then assign the newly allocated descriptor unconditionally. Clear the source pointer immediately after ownership transfer so every exit has one owner.

- [ ] **Step 5: Run fault and Pure smoke tests**

Expected: zero leaked resources for every injected failure, both multiple-result sequences pass, and repeated missing-driver connections remain stable.

- [ ] **Step 6: Commit**

```powershell
git add pure-odbc/odbc.c pure-odbc/tests/odbc_fault_harness.c
git commit -m "Harden pure-odbc resource ownership"
```

### Task 3: Width-Safe Values, Enumeration, Binding, and Diagnostics

**Files:**
- Modify: `pure-odbc/odbc.c:50-320,560-900,960-1000,1180-1260`
- Modify: `pure-odbc/tests/odbc_fault_harness.c`
- Modify: `pure-odbc/tests/smoke.pure`

**Interfaces:**
- Consumes: Tasks 1-2 dispatch and cleanup helpers.
- Produces: `pure_odbc_integer(SQLLEN)` which returns `pure_int` inside `INT32_MIN..INT32_MAX` and `pure_int64` otherwise; checked `SQLULEN` and `SQLUSMALLINT` conversions; growing enumeration and diagnostic collectors.

- [ ] **Step 1: Add RED boundary tests**

Cover `INT32_MIN`, `INT32_MAX`, adjacent 64-bit row counts, negative and overflowing sizes, parameter indices 65535/65536, bigint values outside `int64_t`, long names/attributes, registry growth between enumeration calls, truncated multi-record diagnostics, every failed `SQLBindCol`, and allocator failure during growth.

- [ ] **Step 2: Run RED tests**

Expected: truncation or ignored-bind assertions fail while in-range compatibility cases still pass.

- [ ] **Step 3: Replace legacy widths and conversions**

Store ODBC sizes as `SQLLEN`/`SQLULEN`, validate sign and `SIZE_MAX` before allocation, use `SQLUSMALLINT` for parameter numbering, reject non-representable Pure bigints, and use `pure_odbc_integer` for row counts.

- [ ] **Step 4: Implement growing single-pass collectors**

Append driver/DSN records without a preliminary count, grow arrays with checked multiplication, retry truncated values, and terminate only on `SQL_NO_DATA`. Collect diagnostic records while `SQL_SUCCEEDED`, including `SQL_SUCCESS_WITH_INFO`.

- [ ] **Step 5: Check every bind result**

Route failed `SQLBindCol` through the operation's cleanup path before any bound storage is read. Use the same checked helper in tables, columns, keys, type-info, and query result setup.

- [ ] **Step 6: Run harness, smoke, and strict warnings**

Compile with `-Wall -Wextra -Werror -Wconversion -Wsign-conversion`. Expected: boundary representations match the compatibility rule, all failure resources balance, and ordinary smoke tests pass.

- [ ] **Step 7: Commit**

```powershell
git add pure-odbc/odbc.c pure-odbc/tests/odbc_fault_harness.c pure-odbc/tests/smoke.pure
git commit -m "Use width-safe ODBC values and diagnostics"
```

### Task 4: Hermetic Runners and Cleanup Contracts

**Files:**
- Create: `pure-odbc/cmake/RunPureTest.cmake`
- Create: `pure-odbc/tests/ContractTestRoot.cmake`
- Create: `pure-odbc/tests/runner_contract.cmake`
- Create: `pure-odbc/tests/cleanup_contract.cmake`
- Create: `pure-odbc/tests/access_smoke.pure`
- Modify: `pure-odbc/CMakeLists.txt`
- Modify: `pure-odbc/Makefile`
- Modify: `pure-odbc/tests/smoke.pure`
- Delete: `pure-odbc/cmake/RunLoadTest.cmake`
- Delete: `pure-odbc/cmake/RunSmokeTest.cmake`

**Interfaces:**
- Produces: one strict runner accepting explicit `PURE_EXECUTABLE`, `PURE_SOURCE_DIR`, `MODULE_DIR`, `SCRIPT`, and owned `WORK_DIRECTORY`.
- Produces: fixed leaves `runner`, `cleanup`, and `access` beneath `${BINARY_DIR}/pure-odbc-contract`, protected by exact sentinels.
- Produces: separate CTests `pure-odbc-manager-smoke` and `pure-odbc-access-text-smoke`; the latter uses `SKIP_RETURN_CODE 77`.

- [ ] **Step 1: Add RED runner and cleanup probes**

Use a fake Pure executable to assert exact child `PATH`, absent `PURELIB`, working directory, stdout preservation, nonempty-stderr rejection, missing-file rejection, and exit propagation. Safely probe source descendant, case alias, junction alias, damaged sentinel, missing `pure.pc`, empty DLL suffix, wildcard suffix, and unexpected clean targets.

- [ ] **Step 2: Run RED contracts**

Expected: inherited MSYS path, ignored stderr, arbitrary recursive deletion, or broad Make cleanup is detected without deleting outside disposable roots.

- [ ] **Step 3: Implement shared root safety and runner**

Derive source identity from the helper location, validate the build cache, reject source-contained/reparse paths, derive fixed leaves internally, and require the exact sentinel before reset. Replace both legacy runners with `RunPureTest.cmake`.

- [ ] **Step 4: Split mandatory and optional Pure tests**

Keep enumeration and IM002 in `smoke.pure`. Move CSV behavior to `access_smoke.pure`; return 77 only when the exact driver name is absent, otherwise any test failure is fatal and visible.

- [ ] **Step 5: Restrict `make clean`**

Accept only `.dll`, `.so`, or `.dylib` as the resolved module suffix and delete explicit package-generated files, never a suffix-derived wildcard with missing metadata.

- [ ] **Step 6: Run all runner/cleanup/manager/access tests**

Expected: contract probes pass, mandatory smoke passes, and Access either passes or appears as one explicit skipped test.

- [ ] **Step 7: Commit**

```powershell
git add pure-odbc/CMakeLists.txt pure-odbc/Makefile pure-odbc/cmake pure-odbc/tests
git commit -m "Make pure-odbc tests hermetic"
```

### Task 5: Exact Toolchain, PE, and Install Contracts

**Files:**
- Create: `pure-odbc/tests/configure_contract.cmake`
- Create: `pure-odbc/tests/runtime_verifier_contract.cmake`
- Create: `pure-odbc/tests/install_contract.cmake`
- Modify: `pure-odbc/CMakeLists.txt`
- Modify: `pure-odbc/cmake/Install.cmake`
- Modify: `pure-odbc/cmake/VerifyWindowsDependencies.cmake`
- Modify: `pure-odbc/cmake/VerifyInstalledPackage.cmake`

**Interfaces:**
- Produces: `PURE_ODBC_STRICT_WINDOWS_AUDIT` cache option and explicit file inputs for Clang, pkgconf, llvm-readobj, Ninja, make, Pure, GMP, Windows headers/import library, staged PE files, and System32 ODBC manager.
- Produces: exact 10-file manifest and full-prefix before/after SHA-256 snapshot contract.
- Consumes: Task 4 strict runner and cleanup root.

- [ ] **Step 1: Add RED configure, PE, and install mutation fixtures**

Reject wrong/missing/directory tools, non-Clang or wrong Clang major, non-x86-64 target, import library outside CLANG64, malformed/duplicate/unknown `llvm-readobj` records, wrong architecture, each missing/extra import, staged ODBC managers, non-System32 resolution, missing/extra/altered package files, and overwritten baseline files.

- [ ] **Step 2: Run RED contracts**

Expected: current inclusive verifiers accept at least an extra import and an extra installed file; strict configure interface is absent.

- [ ] **Step 3: Implement strict configure mode**

Validate every explicit path as an existing regular file, compiler ID/version/target, CLANG64 provenance, and exact native import-library/header inputs. Leave strict mode off for ordinary non-Windows/upstream builds.

- [ ] **Step 4: Implement exact recursive PE verification**

Parse file headers and imports, normalize names case-insensitively, sort and compare exact sets, resolve every staged non-system dependency, require AMD64, and prove `ODBC32.dll` is the 64-bit System32 file. Diagnostics must name expected, actual, missing, and unexpected entries.

- [ ] **Step 5: Implement exact installation verification**

Snapshot the whole portable prefix, install runtime and documentation separately, validate component manifests, compare the exact ten-file delta and every hash, prove all baseline files unchanged, reuse GMP byte-for-byte, and reject every bundled manager/driver anywhere in the stage.

- [ ] **Step 6: Run strict build and all mutation contracts**

Run a fresh Release configure, `cmake --build ... --parallel 4`, exact PE target, and the configure/runtime/install contracts. Expected: all positive and negative fixtures pass.

- [ ] **Step 7: Commit**

```powershell
git add pure-odbc/CMakeLists.txt pure-odbc/cmake pure-odbc/tests
git commit -m "Enforce pure-odbc Windows package contracts"
```

### Task 6: Complete and Verify the Source Distribution

**Files:**
- Modify: `pure-odbc/Makefile`
- Create: `pure-odbc/tests/source_dist_contract.cmake`
- Modify: `pure-odbc/CMakeLists.txt`

**Interfaces:**
- Consumes: Tasks 1-5 build, tests, install, and verifier inputs.
- Produces: a declared archive containing every Windows build/test/install asset and an extracted-source end-to-end contract.

- [ ] **Step 1: Add a RED real-archive contract**

Run actual `make dist`, extract beneath `distribution source with spaces`, remove the checkout-side driver, reject symlinks, compare required hashes, and attempt strict configure/build/test/install/verification using only extracted files.

- [ ] **Step 2: Confirm the current archive fails**

Expected: `CMakeLists.txt`, `WINDOWS.md`, `cmake/`, or `tests/` is absent and extracted configure cannot start.

- [ ] **Step 3: Correct `DISTFILES` and path quoting**

List every new source, CMake helper, native harness, Pure fixture, documentation, example, and license. Quote source/output paths so both checkout and extraction directories may contain spaces.

- [ ] **Step 4: Run the complete extracted-source contract**

Expected: regular files only, matching hashes, strict four-worker build, full tests with explicit Access skip if needed, exact PE and install verification, and no checkout path in cache or outputs.

- [ ] **Step 5: Commit**

```powershell
git add pure-odbc/Makefile pure-odbc/CMakeLists.txt pure-odbc/tests/source_dist_contract.cmake
git commit -m "Include pure-odbc Windows contracts in releases"
```

### Task 7: Windows CI and Audited Documentation

**Files:**
- Modify: `.github/workflows/non-linux-release-validation.yml`
- Modify: `pure-odbc/WINDOWS.md`
- Modify: `pure/todo/TODO-32-windows-pure-odbc.md`

**Interfaces:**
- Consumes: all explicit Task 4-6 configure, runner, verifier, component, and source-distribution interfaces.
- Produces: Windows CI coverage and reproducible closure evidence.

- [ ] **Step 1: Reopen TODO and structurally validate pre-change workflow**

Change status to `Open` before implementation evidence is added. Parse workflow YAML with PyYAML `BaseLoader` and assert both trigger path arrays lack the required entries and no ordered `pure-odbc` validation steps exist. Expected RED: missing path filters/job semantics.

- [ ] **Step 2: Add Windows workflow coverage**

Add `pure-odbc/**` and `pure/todo/TODO-32-windows-pure-odbc.md` to push and pull-request filters. After portable Pure staging, configure strict Release with every explicit tool/input, build and PE-check with exactly four workers, run the full `odbc` label under sanitized runtime environment, install both components into a fresh stage, and invoke installed verification with all explicit inputs.

- [ ] **Step 3: Validate YAML semantics**

Use a real YAML parser to check mappings/lists, filters, prerequisite packages, step order, exact four-worker commands, sanitized environment, both components, and complete verifier arguments. Do not add a brittle source-text grep test.

- [ ] **Step 4: Rewrite Windows instructions and append audit history**

Document exact prerequisites and commands, clarify that the bundle relies on but does not contain the system manager, record skip behavior and ten-file ownership, and append dated findings/fixes/validation. Preserve original history and use `Status: Closed on 2026-09-07` only after every command below passes.

- [ ] **Step 5: Run fresh closure verification**

Run strict clean configure, build and PE target with `--parallel 4`, all `odbc` tests, component install and installed verifier, source distribution contract, YAML validation, and `git diff --check`. Record exact counts, skips, timing, tool versions, and limitations in TODO-32.

- [ ] **Step 6: Commit**

```powershell
git add .github/workflows/non-linux-release-validation.yml pure-odbc/WINDOWS.md pure/todo/TODO-32-windows-pure-odbc.md
git commit -m "Validate pure-odbc in Windows CI"
```

### Task 8: Whole-Branch Review and Final Verification

**Files:**
- Modify only files required by confirmed review findings.

**Interfaces:**
- Consumes: complete implementation and every task report/review ruling.
- Produces: merge-ready reviewed branch with fresh evidence.

- [ ] **Step 1: Request whole-branch review**

Review the full diff from `31a85dcb` to `HEAD` against the design and this plan. Triage native safety, public compatibility, test fidelity, destructive operations, exact package/PE closure, source self-containment, CI semantics, and documentation claims.

- [ ] **Step 2: Fix confirmed findings in one wave**

Use one implementation agent for the complete final findings list, rerun covering RED/GREEN tests, commit, and perform exactly one scoped re-review.

- [ ] **Step 3: Run final clean verification**

Create a never-before-used build directory. Run strict Release configure, build and PE target with exactly four workers, ASan fault harness, all `odbc` CTests, exact component install, installed smoke/PE verifier, source archive end-to-end contract, YAML semantic validation, `git diff --check 31a85dcb..HEAD`, and confirm only ignored build artifacts remain.

- [ ] **Step 4: Present integration options**

Use `superpowers:finishing-a-development-branch`; do not merge or push without the user's explicit choice.
