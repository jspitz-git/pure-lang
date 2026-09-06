# TODO-31 Windows pure-glpk Audit Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the callback use-after-free and make every Windows pure-glpk build, runtime, installation, source-distribution, and CI claim executable as an automated contract.

**Architecture:** Preserve the existing Pure API while invalidating callback handles at the native boundary. Consolidate runtime test setup in one strict runner, use exact-data verifiers for PE imports and package manifests, and register all contracts in CTest and Windows CI.

**Tech Stack:** C11, Pure 0.68, GLPK 5.0, CMake 3.25+, CTest, MSYS2 CLANG64, LLVM `llvm-readobj`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-06-windows-pure-glpk-audit-design.md`

## Global Constraints

- The public callback remains `glp::mip_cb tree info`.
- A callback `tree` handle is valid only during that callback invocation.
- Installed executables must run with no MSYS2 directory in `PATH`.
- Existing compatible `libgmp-10.dll` and `zlib1.dll` are reused, never installed as package-owned duplicates.
- PE validation compares exact AMD64 import sets, including system/UCRT imports.
- Windows builds use at most four workers.
- No unrelated GLPK binding API or solver behavior is changed.

---

### Task 1: Make callback handles safely ephemeral

**Files:**
- Modify: `pure-glpk/tests/smoke.pure`
- Modify: `pure-glpk/glpk.c:1716-1731`

**Interfaces:**
- Consumes: existing `glp::mip_cb tree info`, `glp::ios_reason`, `glp::cb_func`, and `glp::cb_info` interfaces.
- Produces: a callback pointer expression whose payload becomes `NULL` before its native wrapper is freed.

- [ ] **Step 1: Write the failing callback regression**

Extend `tests/smoke.pure` with callback state in the `smoke` namespace. Define `glp::mip_cb tree info` to increment an invocation counter, verify that `info` is the configured pointer, call `glp::ios_reason tree` while valid, and retain `tree`. Enable `(glp::cb_func,glp::on)` and `(glp::cb_info,info)` for the deterministic MIP. After `intopt`, assert that the callback ran and that `glp::ios_reason retained_tree` no longer yields a valid symbolic reason.

- [ ] **Step 2: Run the regression against the current implementation and verify RED**

Configure a dedicated Clang AddressSanitizer build with
`-DCMAKE_C_FLAGS="-fsanitize=address -fno-omit-frame-pointer"` and
`-DCMAKE_SHARED_LINKER_FLAGS=-fsanitize=address`, then run only the callback
smoke test. Expected: AddressSanitizer reports a heap-use-after-free from
`is_tree_pointer`; it must not fail merely because runtime DLLs are absent.

- [ ] **Step 3: Implement minimal native invalidation**

In `mip_callback`, create and retain a named `pure_expr *treeptr = pure_pointer(treeobj)`, pass `treeptr` to `pure_app`, and after `pure_freenew(res)` execute `treeptr->data.p = NULL` before `free(treeobj)`. Do not introduce a global registry or extend the handle lifetime.

```c
pure_expr *treeptr = pure_pointer(treeobj);
res = pure_app(pure_app(pure_symbol(pure_sym("glp::mip_cb")), treeptr),
               pure_pointer(info));
pure_freenew(res);
treeptr->data.p = NULL;
free(treeobj);
```

- [ ] **Step 4: Verify GREEN and native warning cleanliness**

Build with `-Wall -Wextra -Werror`, run the smoke test repeatedly, and confirm in-callback access succeeds while retained access is rejected without a crash.

- [ ] **Step 5: Commit the callback fix**

```bash
git add pure-glpk/glpk.c pure-glpk/tests/smoke.pure
git commit -m "Invalidate pure-glpk callback handles safely"
```

### Task 2: Make build-tree tests hermetic and contractual

**Files:**
- Modify: `pure-glpk/CMakeLists.txt`
- Delete: `pure-glpk/cmake/RunLoadTest.cmake`
- Delete: `pure-glpk/cmake/RunSmokeTest.cmake`
- Create: `pure-glpk/cmake/RunPureTest.cmake`
- Create: `pure-glpk/tests/runner_contract.cmake`
- Create: `pure-glpk/tests/configure_contract.cmake`

**Interfaces:**
- Consumes: explicit `PURE_EXECUTABLE`, `PACKAGE_DIR`, `MODULE_DIR`, `RUNTIME_BIN_DIR`, and `TEST_SCRIPT` CMake definitions.
- Produces: `pure-glpk-load`, `pure-glpk-smoke`, `pure-glpk-runner-contract`, and `pure-glpk-configure-contract` CTests carrying the `glpk` label.

- [ ] **Step 1: Write runner and configure contract tests**

The runner contract must call `RunPureTest.cmake` once without every required variable and require failure naming the missing variable. It must also use a small probe script to print `PATH` and `PURELIB`, then assert that `PATH` contains only the supplied module/runtime/Pure directories plus Windows system directories and that `PURELIB` is absent. The configure contract must require explicit existing `PURE_EXECUTABLE` and `LLVM_READOBJ_EXECUTABLE` values on Windows and cover missing-path failures.

- [ ] **Step 2: Register the contracts and verify RED**

Add the two contract tests to `CMakeLists.txt` before changing the runners. Run `ctest -L glpk`; expected failures are ambient `PATH` leakage and acceptance of implicit tool lookup.

- [ ] **Step 3: Implement one strict runner**

`RunPureTest.cmake` must validate all five arguments, normalize their paths, derive the Pure executable directory, set Windows `PATH` to `MODULE_DIR;RUNTIME_BIN_DIR;<pure-bin>;C:/Windows/System32;C:/Windows`, unset `PURELIB`, execute Pure from `C:/Windows`, and fail on either nonzero status or nonempty stderr. On non-Windows, retain the platform runtime search path needed by the module without imposing Windows paths.

```cmake
foreach(required IN ITEMS PURE_EXECUTABLE PACKAGE_DIR MODULE_DIR
    RUNTIME_BIN_DIR TEST_SCRIPT)
  if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
    message(FATAL_ERROR "${required} is required")
  endif()
endforeach()
cmake_path(GET PURE_EXECUTABLE PARENT_PATH pure_bin)
if(WIN32)
  set(ENV{PATH}
    "${MODULE_DIR};${RUNTIME_BIN_DIR};${pure_bin};C:/Windows/System32;C:/Windows")
  unset(ENV{PURELIB})
endif()
```

- [ ] **Step 4: Make CMake inputs explicit**

Derive the GLPK runtime directory from the located `GLPK_RUNTIME_DLL`. Replace `find_program(LLVM_READOBJ ...)` with an existing-file cache contract named `LLVM_READOBJ_EXECUTABLE`. On Windows require an existing cache value for `PURE_EXECUTABLE`. Pass all strict-runner arguments to both functional tests and remove the two obsolete runners.

- [ ] **Step 5: Verify GREEN without ambient MSYS2 PATH**

Configure and build with tool paths supplied explicitly, then set the parent `PATH` to Windows system directories only and run `ctest -L glpk`. Expected: load, solver, callback, runner, and configure contracts all pass.

- [ ] **Step 6: Commit the hermetic runner**

```bash
git add pure-glpk/CMakeLists.txt pure-glpk/cmake pure-glpk/tests
git commit -m "Make pure-glpk tests hermetic"
```

### Task 3: Enforce exact PE and installed-package contracts

**Files:**
- Modify: `pure-glpk/cmake/VerifyWindowsDependencies.cmake`
- Modify: `pure-glpk/cmake/VerifyInstalledPackage.cmake`
- Modify: `pure-glpk/CMakeLists.txt`
- Create: `pure-glpk/tests/runtime_verifier_contract.cmake`
- Create: `pure-glpk/tests/install_contract.cmake`

**Interfaces:**
- Consumes: paths to the eight audited PE files, package build/source inputs, a portable Pure prefix, and a fresh stage directory.
- Produces: exact PE comparison and exact 15-file package ownership verification, exposed as CTest contracts.

- [ ] **Step 1: Write negative verifier tests**

Have `runtime_verifier_contract.cmake` generate a deterministic
`fake-llvm-readobj.cmd` in its test root. The command selects fixture output
by input filename. First emit the complete expected import names; then emit
the same names plus `libunexpected.dll` and require failure naming that
import. The install contract must stage a valid package, then independently
add an extra package-owned file and alter one installed artifact; require
exact-manifest and SHA-256 failures respectively.

- [ ] **Step 2: Register both contracts and verify RED**

Register `pure-glpk-runtime-verifier-contract` and `pure-glpk-install-contract` with `LABELS "glpk;contract"`. Expected: current partial import verifier accepts the injected import and current installed verifier accepts an extra file or altered package-owned artifact.

- [ ] **Step 3: Implement exact import comparison**

Parse every `Name:` line from `llvm-readobj --coff-imports`, lowercase and sort it, and compare it with an explicit sorted expected list per PE input. Populate the lists from the freshly built AMD64 binaries for `glpk.dll`, GLPK, AMD, COLAMD, SuiteSparseConfig, OpenMP, GMP, and zlib. Diagnostics must print missing and unexpected names.

```cmake
string(REGEX MATCHALL "Name: [^\r\n]+" import_lines "${output}")
foreach(line IN LISTS import_lines)
  string(REGEX REPLACE "^Name: " "" name "${line}")
  string(TOLOWER "${name}" name)
  list(APPEND actual "${name}")
endforeach()
list(SORT actual)
if(NOT actual STREQUAL expected)
  message(FATAL_ERROR
    "${module} import mismatch\nexpected: ${expected}\nactual: ${actual}")
endif()
```

- [ ] **Step 4: Implement exact install ownership and hashes**

Pass the module, interface, generated README, static documentation, example, test, five installed DLLs, and three license source paths into `VerifyInstalledPackage.cmake`. Enumerate package-owned namespaces and compare the exact normalized relative list with the 15 expected entries. Compare SHA-256 for every installed entry to its declared source; separately verify reused GMP/zlib against the CLANG64 sources.

- [ ] **Step 5: Automate isolated staging**

In `install_contract.cmake`, copy the existing portable Pure prefix to a fresh stage, invoke `cmake --install` with only the pure-glpk runtime and documentation components, and then call the installed verifier. Use the strict runner environment for the staged solver/callback test and the exact PE verifier for staged binaries.

- [ ] **Step 6: Verify RED-to-GREEN contract coverage**

Run the two new contract tests individually, then all tests with `-L glpk`. Confirm each mutation is rejected for its intended reason and the untouched stage passes.

- [ ] **Step 7: Commit exact package validation**

```bash
git add pure-glpk/CMakeLists.txt pure-glpk/cmake pure-glpk/tests
git commit -m "Enforce pure-glpk package contracts"
```

### Task 4: Repair the source distribution contract

**Files:**
- Modify: `pure-glpk/Makefile:40-90`
- Create: `pure-glpk/tests/source_dist_contract.cmake`
- Modify: `pure-glpk/CMakeLists.txt`

**Interfaces:**
- Consumes: the legacy `make dist` file selection and the package source tree.
- Produces: a source archive containing every input needed by the CMake Windows build and validation flow.

- [ ] **Step 1: Write a failing source-distribution test**

Have the CMake test create an isolated source staging tree using the declared distribution inputs. Require `CMakeLists.txt`, `WINDOWS.md`, every `cmake/*.cmake` file, `tests/load.pure`, `tests/smoke.pure`, and all contract scripts. Configure the staged tree with `BUILD_TESTING=OFF` and explicit toolchain paths. Expected: current manifest omits the required files.

- [ ] **Step 2: Register and verify RED**

Register `pure-glpk-source-dist-contract` with `LABELS "glpk;contract;dist"` and run it alone. Confirm failure identifies `CMakeLists.txt` or the first omitted validation asset.

- [ ] **Step 3: Update the legacy distribution manifest**

Add `CMakeLists.txt`, `WINDOWS.md`, `cmake/*.cmake`, and `tests/*` to `DISTFILES`. Create the `cmake` and `tests` directories in the `dist` recipe before linking entries. Preserve README version/date substitution and existing Debian/example content.

- [ ] **Step 4: Verify GREEN**

Run the source-distribution contract and inspect the generated archive/stage list. Confirm configuration reads no path outside the staged source tree.

- [ ] **Step 5: Commit the source distribution fix**

```bash
git add pure-glpk/Makefile pure-glpk/CMakeLists.txt pure-glpk/tests/source_dist_contract.cmake
git commit -m "Include Windows pure-glpk build assets in releases"
```

### Task 5: Add Windows CI and close the audited documentation gaps

**Files:**
- Modify: `.github/workflows/non-linux-release-validation.yml`
- Modify: `pure-glpk/WINDOWS.md`
- Modify: `pure/todo/TODO-31-windows-pure-glpk.md`
- Create: `pure-glpk/tests/workflow_contract.cmake`
- Modify: `pure-glpk/CMakeLists.txt`

**Interfaces:**
- Consumes: portable Pure SDK produced by the existing Windows job and all CTest contracts from Tasks 1-4.
- Produces: reproducible Windows CI evidence and accurate user-facing build/install instructions.

- [ ] **Step 1: Add workflow assertions before the CI implementation**

Create `pure-glpk/tests/workflow_contract.cmake`. Read
`.github/workflows/non-linux-release-validation.yml` as text and fail unless
it contains both `pure-glpk/**` and TODO-31 path filters, the
`mingw-w64-clang-x86_64-glpk` prerequisite, explicit Pure/LLVM tool
arguments, `--parallel 4`, the PE target, `ctest -L glpk`, isolated install,
and the installed verifier invocation. Register it as
`pure-glpk-workflow-contract`, run it against the current workflow, and
verify RED.

- [ ] **Step 2: Implement the Windows CI package stage**

Add GLPK to `msys2/setup-msys2`. Configure `../pure-glpk` with the installed Pure SDK pkg-config directory, absolute compiler/pkgconf/Pure/llvm-readobj paths, and `BUILD_TESTING=ON`. Build with `--parallel 4`, run `verify-windows-dependencies`, then `ctest -L glpk --output-on-failure --no-tests=error`. Install into a fresh package stage and run `VerifyInstalledPackage.cmake` with all explicit source inputs.

- [ ] **Step 3: Update Windows documentation**

Document exact configuration variables, the four-worker commands, hermetic CTest behavior, package components, exact PE validation, isolated install verification, callback handle lifetime, and complete source archive contents. Remove wording that implies a manual historical check is an automated guarantee.

- [ ] **Step 4: Update TODO-31 evidence**

Append dated audit entries describing the callback UAF, ambient-PATH failure, orphan verifier, partial PE check, incomplete source distribution, and their fixes. Record fresh build/test counts and sanitized installed-runtime results only after those commands have actually passed.

- [ ] **Step 5: Validate workflow and complete test suite**

Parse the workflow as YAML, run `git diff --check`, perform a clean strict Release configure/build, run exact PE validation, run all `glpk` tests with sanitized parent `PATH`, and repeat installed-package verification from a path containing spaces and non-ASCII characters.

- [ ] **Step 6: Commit CI and documentation**

```bash
git add .github/workflows/non-linux-release-validation.yml pure-glpk/WINDOWS.md pure/todo/TODO-31-windows-pure-glpk.md
git commit -m "Validate pure-glpk in Windows CI"
```

### Task 6: Independent review and final verification

**Files:**
- Review: all changes since commit `17f578b3`

**Interfaces:**
- Consumes: the complete implementation and the approved design.
- Produces: reviewer findings resolved and a fully evidenced handoff.

- [ ] **Step 1: Request code review**

Use `superpowers:requesting-code-review` with base `17f578b3`, current HEAD, this plan, and the approved design. Fix every Critical and Important finding through a new RED/GREEN cycle.

- [ ] **Step 2: Run final clean verification**

From a new build directory run strict configure, four-worker build, exact PE target, all `glpk` CTests, isolated install, exact package verifier, source-distribution contract, YAML parsing, and `git diff --check`. Preserve complete command output for the final report.

- [ ] **Step 3: Inspect repository state**

Confirm only intended tracked files changed, build products remain untracked, and every implementation commit is based on `codex/todo31-audit`.
