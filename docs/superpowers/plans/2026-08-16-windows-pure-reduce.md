# Windows pure-reduce Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and package the existing `pure-reduce` API on 64-bit Windows from pinned current REDUCE/CSL sources as a relocatable, MSYS2-independent `PureReduce` component.

**Architecture:** CMake verifies an explicit checkout of REDUCE commit `7efba90661139ae9c73c99fddd55f3fb2fabf69a`, drives the official complete CSL build, and links a narrow C++/C-ABI bridge to that build. A manifest-driven installer selects the matching image, bridge and audited PE/data closure; staged tests run the existing Pure API from paths with spaces under a sanitized environment.

**Tech Stack:** CMake 3.25+, Ninja, MSYS2/CLANG64, upstream REDUCE/CSL, C++17 bridge with C exports, Pure 0.68+, CTest, PowerShell, `llvm-readobj`, GitHub Actions.

## Global Constraints

- Support only Windows x86-64 and the CLANG64 Pure distribution in this work.
- Pin REDUCE to `7efba90661139ae9c73c99fddd55f3fb2fabf69a`; never resolve a moving branch during configure or build.
- MSYS2/CLANG64 may be used to build, but the installed runtime must not require MSYS2, a shell, compiler, or build tool.
- Preserve the existing in-process `PROC_*` integration and public `reduce.pure` API.
- Build a complete CSL system and package only artifacts produced by that exact source/build pair.
- Never publish an incomplete image, unresolved PE closure, or artifact with undocumented provenance/license.
- Keep `build/` and all pre-existing untracked content outside commits.

## Target File Structure

- `pure-reduce/CMakeLists.txt` — project options, bridge target, test registration and module composition.
- `pure-reduce/cmake/ReduceSource.cmake` — pinned source identity and `pure_reduce_verify_source(ROOT OUT_COMMIT OUT_TREE_SHA256)`.
- `pure-reduce/cmake/ReduceUpstream.cmake` — complete upstream configure/build contract and imported artifact paths.
- `pure-reduce/cmake/Install.cmake` — `PureReduce` component and authoritative inventory generation.
- `pure-reduce/cmake/AuditWindowsDependencies.cmake` — PE import parsing and closure validation.
- `pure-reduce/cmake/VerifyInstalledPackage.cmake` — install, inventory, relocation and sanitized runtime verification.
- `pure-reduce/cmake/RunPureReduceTest.cmake` — common build-tree/staged Pure test driver.
- `pure-reduce/bridge/reduce_bridge.cpp` — CSL lifecycle wrappers, callbacks, diagnostics and helper functions.
- `pure-reduce/bridge/reduce_bridge.h` — stable C ABI consumed by `reduce.pure`.
- `pure-reduce/reduce.pure` — existing public API adapted to bridge lifecycle and explicit image lookup.
- `pure-reduce/tests/source-contract.cmake` — source verification failure tests.
- `pure-reduce/tests/smoke.pure` — algebra, conversion, package-load and recovery contract.
- `pure-reduce/tests/lifecycle.pure` — lazy start, finish and supported restart behavior.
- `pure-reduce/tests/manifest-failures.cmake` — missing, extra, modified and unsafe inventory cases.
- `pure-reduce/tests/relocation.cmake` — copied-prefix and build-path leakage checks.
- `pure-reduce/WINDOWS.md` — build, component layout, diagnostics and removal guidance.
- `pure-reduce/THIRD_PARTY.md` — pinned upstream provenance and redistribution notices.
- `.github/workflows/non-linux-release-validation.yml` — clean Windows build, metrics, ZIP and artifact upload.
- `pure/todo/TODO-47-windows-pure-reduce.md` — measured progress and final packaging decision.

---

### Task 1: Pinned Source Contract

**Files:**
- Create: `pure-reduce/cmake/ReduceSource.cmake`
- Create: `pure-reduce/tests/source-contract.cmake`
- Create: `pure-reduce/CMakeLists.txt`

**Interfaces:**
- Consumes: cache path `PURE_REDUCE_SOURCE_DIR` naming an existing Git checkout.
- Produces: `pure_reduce_verify_source(ROOT OUT_COMMIT OUT_TREE_SHA256)`, returning the exact commit and a deterministic SHA-256 of sorted `git ls-files -s` records.

- [ ] **Step 1: Write the failing source-contract test**

Create fixtures with a missing root, a non-Git directory, and an override commit. The success path uses `PURE_REDUCE_SOURCE_DIR`; the test must assert this exact pin:

```cmake
set(expected "7efba90661139ae9c73c99fddd55f3fb2fabf69a")
pure_reduce_verify_source(
  "${PURE_REDUCE_SOURCE_DIR}" actual tree_sha256)
if(NOT actual STREQUAL expected)
  message(FATAL_ERROR "unexpected verified commit: ${actual}")
endif()
if(NOT tree_sha256 MATCHES "^[0-9a-f]{64}$")
  message(FATAL_ERROR "invalid source tree SHA-256: ${tree_sha256}")
endif()
```

- [ ] **Step 2: Run the test and verify the contract is absent**

Run:

```powershell
cmake -DPURE_REDUCE_SOURCE_DIR=C:/pure-lang/build/deps/reduce-algebra -P pure-reduce/tests/source-contract.cmake
```

Expected: failure because `ReduceSource.cmake` or `pure_reduce_verify_source` does not exist.

- [ ] **Step 3: Implement strict source verification**

Run `git -C "${ROOT}" rev-parse HEAD`, reject a dirty tree with `git status --porcelain --untracked-files=no`, require the exact pin, hash the output of `git ls-files -s`, and never fetch/update. Expose these cache settings from the root project:

```cmake
set(PURE_REDUCE_SOURCE_DIR "" CACHE PATH
  "Existing checkout of pinned REDUCE sources")
set(PURE_REDUCE_UPSTREAM_COMMIT
  "7efba90661139ae9c73c99fddd55f3fb2fabf69a")
```

- [ ] **Step 4: Run success and mutation cases**

Run the test once against the clean pinned checkout and once against a temporary checkout with a tracked-file modification. Expected: clean PASS; mutation FAIL with `REDUCE source tree is dirty`.

- [ ] **Step 5: Commit**

```powershell
git add pure-reduce/CMakeLists.txt pure-reduce/cmake/ReduceSource.cmake pure-reduce/tests/source-contract.cmake
git commit -m "Pin REDUCE source contract"
```

### Task 2: Complete Upstream CSL Build Contract

**Files:**
- Create: `pure-reduce/cmake/ReduceUpstream.cmake`
- Modify: `pure-reduce/CMakeLists.txt`
- Create: `pure-reduce/tests/upstream-contract.cmake`

**Interfaces:**
- Consumes: verified source root, `PURE_REDUCE_MSYS2_BASH`, `PURE_REDUCE_MAKE`, and the CLANG64 environment.
- Produces: build target `pure-reduce-upstream`; absolute verified paths `PURE_REDUCE_CSL_IMAGE`, `PURE_REDUCE_CSL_LINK_INPUTS`, `PURE_REDUCE_RUNTIME_DATA`, and metrics file `reduce-upstream-metrics.json`.

- [ ] **Step 1: Write a failing upstream artifact-contract test**

The test includes the module, calls `pure_reduce_define_upstream_build()`, and requires every reported artifact to stay below the upstream binary root:

```cmake
foreach(path IN ITEMS "${PURE_REDUCE_CSL_IMAGE}" ${PURE_REDUCE_CSL_LINK_INPUTS})
  cmake_path(IS_PREFIX PURE_REDUCE_UPSTREAM_BINARY_DIR "${path}"
    NORMALIZE is_build_artifact)
  if(NOT is_build_artifact)
    message(FATAL_ERROR "artifact escapes upstream build: ${path}")
  endif()
endforeach()
```

- [ ] **Step 2: Run configure and observe the missing contract**

Run:

```powershell
cmake -S pure-reduce -B build/pure-reduce -G Ninja -DPURE_REDUCE_SOURCE_DIR=C:/pure-lang/build/deps/reduce-algebra
```

Expected: failure identifying the undefined upstream build function/artifacts.

- [ ] **Step 3: Encode the official full CSL build as one custom command**

Invoke the pinned tree's official `configure --with-csl` and complete `make` from `PURE_REDUCE_MSYS2_BASH`. Set `MSYSTEM=CLANG64`, prepend only `/clang64/bin:/usr/bin`, log configure/build transcripts, and stamp success only after the image and procedural link inputs exist. Do not maintain an old hand-written CSL object list.

- [ ] **Step 4: Add artifact discovery that fails closed**

Search only within the known upstream build directory. Require exactly one image selected for the procedural CSL build and require its producer/link inputs to share the verified build configuration. Reject zero or multiple candidates with a diagnostic listing candidates.

- [ ] **Step 5: Build and record metrics**

Run:

```powershell
cmake --build build/pure-reduce --target pure-reduce-upstream -- -j1
```

Expected: complete CSL build succeeds; JSON records commit, source-tree hash, tool versions, configure arguments, elapsed seconds, source bytes and build-tree bytes.

- [ ] **Step 6: Commit**

```powershell
git add pure-reduce/CMakeLists.txt pure-reduce/cmake/ReduceUpstream.cmake pure-reduce/tests/upstream-contract.cmake
git commit -m "Add complete pinned CSL build"
```

### Task 3: Current CSL Bridge and Stable C ABI

**Files:**
- Create: `pure-reduce/bridge/reduce_bridge.h`
- Create: `pure-reduce/bridge/reduce_bridge.cpp`
- Delete: `pure-reduce/proc-add.c`
- Modify: `pure-reduce/CMakeLists.txt`
- Create: `pure-reduce/tests/bridge-contract.cpp`

**Interfaces:**
- Consumes: current `CSL_LISP` declarations from pinned `csl/cslbase/proc.h` and upstream procedural link inputs.
- Produces: module `reduce.dll` and C exports `pure_reduce_start`, `pure_reduce_finish`, `pure_reduce_state`, `pure_reduce_last_error`, `PROC_capture_output`, `PROC_get_output`, `PROC_clear_output`, `PROC_feed_input`, `PROC_make_cons`, `PROC_checksym`.

- [ ] **Step 1: Define and test the C ABI header**

Use this lifecycle surface:

```cpp
enum pure_reduce_state {
  PURE_REDUCE_UNINITIALIZED = 0,
  PURE_REDUCE_RUNNING = 1,
  PURE_REDUCE_FINISHED = 2,
  PURE_REDUCE_FAILED = 3
};

PURE_REDUCE_API int pure_reduce_start(const char *image_utf8);
PURE_REDUCE_API int pure_reduce_finish(void);
PURE_REDUCE_API int pure_reduce_state(void);
PURE_REDUCE_API const char *pure_reduce_last_error(void);
```

The initial native test asserts null/empty image rejection, stable error text, and idempotent `finish` before initialization.

- [ ] **Step 2: Run the native test and verify link failure**

Run `cmake --build build/pure-reduce` followed by `ctest --test-dir build/pure-reduce -R pure-reduce-bridge-contract --output-on-failure`.

Expected: compile/link failure because bridge exports are not implemented.

- [ ] **Step 3: Port lifecycle and callback helpers to C++17**

Call `CSL_LISP::cslstart` using `{"pure-reduce", "-i", image_utf8}` and a bridge writer callback. Guard all exports with `try/catch`, store diagnostics in bridge-owned `std::string`, and make `finish` idempotent. Replace `strdup`/raw global ownership with `std::string` and `std::vector<char>` while returning only `const char *` views whose lifetime lasts until the next matching bridge call.

- [ ] **Step 4: Port expression helpers without exposing CSL internals**

Implement `PROC_make_cons` and string extraction using current public procedural operations where available. If the old helper needs private `Lisp_Object` access, isolate that code in this file and verify its exact pinned header dependency. Keep all helper exports `extern "C"`.

- [ ] **Step 5: Link only against the verified upstream build**

Create the `reduce` module with `PREFIX ""`, `OUTPUT_NAME "reduce"`, `WINDOWS_EXPORT_ALL_SYMBOLS OFF`, explicit exports, and a dependency on `pure-reduce-upstream`. Add `-Wl,--no-undefined`; do not resolve any CSL input from host library paths.

- [ ] **Step 6: Run native contract and export audit**

Run the native CTest and:

```powershell
llvm-readobj --coff-exports build/pure-reduce/reduce.dll
```

Expected: PASS; every declared bridge/required `PROC_*` entry is exported, and no C++-mangled lifecycle function is part of the public contract.

- [ ] **Step 7: Commit**

```powershell
git add pure-reduce/CMakeLists.txt pure-reduce/bridge pure-reduce/tests/bridge-contract.cpp
git rm pure-reduce/proc-add.c
git commit -m "Port pure-reduce bridge to current CSL"
```

### Task 4: Relocatable Pure Module and Functional Smoke Tests

**Files:**
- Modify: `pure-reduce/reduce.pure`
- Create: `pure-reduce/cmake/RunPureReduceTest.cmake`
- Create: `pure-reduce/tests/smoke.pure`
- Create: `pure-reduce/tests/lifecycle.pure`
- Modify: `pure-reduce/CMakeLists.txt`

**Interfaces:**
- Consumes: `reduce.dll`, `reduce.img`, `PURE_EXECUTABLE`, and explicit test module directory.
- Produces: preserved `reduce` namespace API plus deterministic bridge exceptions `reduce::initialization_error`, `reduce::evaluation_error`, and `reduce::finished_error`.

- [ ] **Step 1: Write failing Pure smoke and lifecycle cases**

Cover fixed results including:

```pure
using reduce;
assert (simplify ((x^2-1)/(x-1)) === x+1);
assert (df (x+1)^3 x === 3*(x+1)^2);
assert (int (2*x) x === x^2);
assert (lispval '(plus 20 22) === 42);
```

Also cover big integers, floats, strings, lists, factor/expand, package load, output capture, a recoverable invalid evaluation followed by `1+1`, lazy start, two `finish` calls, and the pinned runtime's tested restart policy.

- [ ] **Step 2: Run tests and verify legacy lookup/signature failures**

Run:

```powershell
ctest --test-dir build/pure-reduce -R "pure-reduce-(smoke|lifecycle)" --output-on-failure
```

Expected: failure from legacy `cslstart` declarations and `/usr/lib/pure`/working-directory image lookup.

- [ ] **Step 3: Replace direct CSL lifecycle declarations**

Declare and call only the bridge lifecycle API:

```pure
extern int pure_reduce_start(char *image);
extern int pure_reduce_finish();
extern int pure_reduce_state();
extern char *pure_reduce_last_error();
```

Remove the direct `cslstart`/`cslfinish` calls and `REDUCE_PATH = ".:/usr/lib/pure"` behavior.

- [ ] **Step 4: Implement explicit relocatable image selection**

Resolve `reduce.img` from the directory containing the selected `reduce.dll`, normalize the path, verify it is a regular file, and pass its UTF-8 path to `pure_reduce_start`. Do not inspect `PATH` or the current directory. Translate nonzero bridge results into the three stable Pure exception categories.

- [ ] **Step 5: Implement the common test driver**

`RunPureReduceTest.cmake` sets `PATH` to the selected module/runtime directories plus Windows system directories, clears `PURELIB`, runs Pure with `--norc`, explicit `-I`/`-L`, and `WORKING_DIRECTORY C:/Windows`, and fails on nonzero status or missing `pure-reduce smoke passed`/`lifecycle passed` marker.

- [ ] **Step 6: Run functional tests repeatedly**

Run smoke once and lifecycle ten times. Expected: all pass without crashes, hangs, stale callbacks, or build-directory-dependent lookup.

- [ ] **Step 7: Commit**

```powershell
git add pure-reduce/CMakeLists.txt pure-reduce/reduce.pure pure-reduce/cmake/RunPureReduceTest.cmake pure-reduce/tests/smoke.pure pure-reduce/tests/lifecycle.pure
git commit -m "Make pure-reduce runtime relocatable"
```

### Task 5: Runtime Closure, Provenance and Component Installation

**Files:**
- Create: `pure-reduce/cmake/AuditWindowsDependencies.cmake`
- Create: `pure-reduce/cmake/Install.cmake`
- Create: `pure-reduce/THIRD_PARTY.md`
- Create: `pure-reduce/licenses/REDUCE-LICENSE.txt`
- Modify: `pure-reduce/CMakeLists.txt`

**Interfaces:**
- Consumes: verified bridge/image/data artifacts, `llvm-readobj`, upstream license, source commit/tree hash and metrics.
- Produces: `PureReduce` component and authoritative `${binary_dir}/PureReduceExpected.sha256` lines formatted as `<64 lowercase hex><two spaces><relative/path>`.

- [ ] **Step 1: Write a failing PE closure test**

Require `pure_reduce_audit_pe(ROOT_FILES SEARCH_DIRS OUT_FILES)` to reject an unresolved synthetic import and to return a sorted, duplicate-free closure for `reduce.dll`. System DLLs must be matched against an explicit case-insensitive allowlist; `msys-2.0.dll`, `cygwin1.dll`, shells, import libraries and executables are forbidden.

- [ ] **Step 2: Run audit test before implementation**

Expected: failure because `AuditWindowsDependencies.cmake` does not exist.

- [ ] **Step 3: Implement recursive PE import closure**

Parse `llvm-readobj --coff-imports`, resolve non-system imports only within the verified upstream build and CLANG64 runtime directories, fail on ambiguity, and return absolute canonical files. Record for every selected file its importing parent.

- [ ] **Step 4: Add license/provenance material**

Copy the exact license from the pinned source into `licenses/REDUCE-LICENSE.txt`. `THIRD_PARTY.md` records official repository URL, commit, verified tree hash generation method, CSL role, every bundled third-party runtime family, its license location, and source retrieval command using the exact commit.

- [ ] **Step 5: Generate the authoritative inventory and install component**

Install `reduce.dll`, `reduce.img` and required CSL data beside `reduce.pure` under `lib/pure`; install dependent runtime DLLs under `bin`; install tests/docs/licenses/metrics under `share/doc/pure-reduce`. Hash each source before installation, reject absolute/`..` destinations, and install only with `COMPONENT PureReduce EXCLUDE_FROM_ALL`.

- [ ] **Step 6: Verify the closure contains no build tool**

Run the audit and inspect `PureReduceExpected.sha256`. Expected: no `.a`, `.lib`, `.o`, compiler, shell, `make`, package manager, full REDUCE frontend, or source-tree file.

- [ ] **Step 7: Commit**

```powershell
git add pure-reduce/CMakeLists.txt pure-reduce/cmake/AuditWindowsDependencies.cmake pure-reduce/cmake/Install.cmake pure-reduce/THIRD_PARTY.md pure-reduce/licenses/REDUCE-LICENSE.txt
git commit -m "Package audited pure-reduce closure"
```

### Task 6: Installed Package, Mutation and Relocation Verification

**Files:**
- Create: `pure-reduce/cmake/VerifyInstalledPackage.cmake`
- Create: `pure-reduce/tests/manifest-failures.cmake`
- Create: `pure-reduce/tests/relocation.cmake`
- Modify: `pure-reduce/CMakeLists.txt`

**Interfaces:**
- Consumes: build dir, staged Pure prefix, authoritative manifest, `PURE_EXECUTABLE`, and `llvm-readobj`.
- Produces: CTests `pure-reduce-installed`, `pure-reduce-manifest-failures`, and `pure-reduce-relocation` labeled `reduce;runtime`.

- [ ] **Step 1: Write manifest mutation tests**

Create copies of a valid stage and independently delete a file, add an extra file, modify one byte, replace a manifest path with `../escape`, and remove a required license. Each verifier invocation must fail for the specific reason.

- [ ] **Step 2: Run mutation tests before verifier exists**

Expected: all fixture invocations fail because installed verification is absent, and the harness itself reports failure rather than treating any nonzero result as sufficient.

- [ ] **Step 3: Implement authoritative installed verification**

Install `PureReduce` into a path containing spaces, compare its sorted file set and SHA-256 values to the build-tree authoritative manifest, require the manifest's own expected path, re-run PE audit against the staged tree, and reject forbidden filenames/content.

- [ ] **Step 4: Run sanitized staged smoke tests**

Set:

```cmake
set(ENV{PATH} "${stage}/bin;C:/Windows/System32/WindowsPowerShell/v1.0;C:/Windows/System32;C:/Windows")
set(ENV{PURELIB} "")
```

Run staged smoke/lifecycle scripts from `C:/Windows`. Expected: PASS without any MSYS2 directory visible at runtime.

- [ ] **Step 5: Add relocation and prefix-leak test**

Copy the complete staged prefix to a differently named path with spaces, rescan installed text/metadata for source, build and original-stage prefixes, and repeat smoke/lifecycle tests. Expected: no leak and PASS from the copied prefix.

- [ ] **Step 6: Add install/upgrade/removal ownership test**

Seed an unrelated sentinel under the staged Pure prefix, install `PureReduce`, overlay the same component, then remove exactly the manifest-owned paths. Verify the sentinel and other Pure files retain their hashes and no owned file remains.

- [ ] **Step 7: Run all reduce-labeled tests**

```powershell
ctest --test-dir build/pure-reduce -L reduce --output-on-failure
```

Expected: source, bridge, smoke, lifecycle, manifest failure, installed and relocation tests all pass.

- [ ] **Step 8: Commit**

```powershell
git add pure-reduce/CMakeLists.txt pure-reduce/cmake/VerifyInstalledPackage.cmake pure-reduce/tests/manifest-failures.cmake pure-reduce/tests/relocation.cmake
git commit -m "Verify installed pure-reduce package"
```

### Task 7: Documentation, CI Artifact and TODO Evidence

**Files:**
- Create: `pure-reduce/WINDOWS.md`
- Modify: `pure-reduce/README`
- Modify: `.github/workflows/non-linux-release-validation.yml`
- Modify: `pure/todo/TODO-47-windows-pure-reduce.md`

**Interfaces:**
- Consumes: verified configure/build/test commands, metrics JSON and staged `PureReduce` component.
- Produces: uploaded `windows-pure-reduce.zip`, SHA-256 evidence, installation contract for TODO-49 and an accurate TODO status.

- [ ] **Step 1: Document the supported build and runtime contract**

`WINDOWS.md` gives the exact pin, prerequisite MSYS2/CLANG64 packages, explicit source checkout command, configure/build/test/install commands, installed layout, relocation behavior, diagnostics, upgrade/removal procedure, license/source location and unsupported full REDUCE frontend.

- [ ] **Step 2: Replace historical README instructions for Windows**

Keep Unix history clearly separated. Direct Windows users to CMake and state that r2204 binaries under `reduce-files` are not Windows inputs and are not the supported upstream baseline.

- [ ] **Step 3: Add the clean Windows CI job**

Extend `non-linux-release-validation.yml` path filters and add a job that checks out into `source with spaces`, obtains the exact upstream commit, verifies it, configures/builds with CLANG64, runs `ctest -L reduce`, installs only `PureReduce`, verifies the staged package, creates `windows-pure-reduce.zip`, computes SHA-256, and uploads it with `actions/upload-artifact@v4`.

- [ ] **Step 4: Record metrics and packaging decision**

Append measured fetch/source/build/stage/archive bytes, file count, elapsed build seconds, worker count, inner ZIP SHA-256 and CI artifact digest to TODO-47. Mark each checklist item complete only when its corresponding evidence passed. Record `PureReduce` as a separate optional installer component/artifact consumed by TODO-49.

- [ ] **Step 5: Run final local verification**

Run:

```powershell
cmake --build build/pure-reduce
ctest --test-dir build/pure-reduce -L reduce --output-on-failure
cmake --install build/pure-reduce --prefix 'C:/tmp/pure reduce final' --component PureReduce
cmake -DBUILD_DIR=build/pure-reduce -DSTAGE_PREFIX='C:/tmp/pure reduce final' -P pure-reduce/cmake/VerifyInstalledPackage.cmake
git diff --check
```

Expected: every command succeeds, the staged verifier reports the file count and inventory hash, and `git diff --check` is silent.

- [ ] **Step 6: Commit**

```powershell
git add pure-reduce/WINDOWS.md pure-reduce/README .github/workflows/non-linux-release-validation.yml pure/todo/TODO-47-windows-pure-reduce.md
git commit -m "Validate Windows pure-reduce package"
```

### Task 8: Clean-Runner Evidence and Final Status

**Files:**
- Modify: `pure/todo/TODO-47-windows-pure-reduce.md`

**Interfaces:**
- Consumes: completed GitHub Actions run and downloaded artifact metadata.
- Produces: final clean-runner evidence and either `Status: Closed` or an explicit open blocker with reproducible evidence.

- [ ] **Step 1: Trigger and inspect the Windows validation run**

Push the implementation branch, run the workflow, and require the complete upstream build, all reduce-labeled tests, staged verifier and artifact upload to pass on a clean runner.

- [ ] **Step 2: Verify downloaded artifact independently**

Download `windows-pure-reduce.zip`, compare its SHA-256 with the workflow transcript, extract into a new path containing spaces, and run the installed verifier/smoke without MSYS2 on `PATH`.

- [ ] **Step 3: Record immutable evidence**

Add the implementation commit, workflow run URL, elapsed time, ZIP SHA-256, uploaded artifact digest, installed size/file count and authoritative inventory SHA-256 to the TODO progress log.

- [ ] **Step 4: Set final TODO state honestly**

Close TODO-47 only if every completion criterion in the approved design has evidence. Otherwise leave it open and record the exact failed gate; do not ship or describe a partial runtime as supported.

- [ ] **Step 5: Commit**

```powershell
git add pure/todo/TODO-47-windows-pure-reduce.md
git commit -m "Record Windows pure-reduce validation"
```
