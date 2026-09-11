# TODO-35 Windows pure-gl Audit Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Windows `pure-gl` build, runtime, installation, source-distribution, dependency, and CI claim reproducible as an automated contract.

**Architecture:** Preserve the seven existing Pure interfaces and single native module while replacing ambient discovery and partial checks with explicit immutable inputs. Run Pure through one bounded native Windows supervisor, validate exact recursive PE imports and sealed install ownership, and connect all contracts to CTest and the existing Windows release workflow.

**Tech Stack:** C11, Pure 0.68, FreeGLUT 3.8.0, CMake 3.25+, CTest, MSYS2 CLANG64, LLVM `llvm-readobj`/`llvm-strings`, PowerShell, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-11-windows-pure-gl-audit-hardening-design.md`

## Global Constraints

- The public `GL`, `GL_ARB`, `GL_EXT`, `GL_NV`, `GL_ATI`, `GLU`, and `GLUT` interfaces remain compatible.
- The package remains one AMD64 `pure-gl.dll` plus one bundled `libfreeglut.dll`.
- `opengl32.dll`, `glu32.dll`, `gdi32.dll`, `user32.dll`, and `winmm.dll` remain Windows system dependencies and are never bundled.
- Noninteractive tests run without user input, clear `PURELIB`, exclude MSYS2 directories from runtime `PATH`, and have nested deadlines.
- FreeGLUT 3.8.0 runtime and license inputs come from one explicit CLANG64 prefix and are hash-pinned.
- PE validation compares exact recursively resolved AMD64 import sets.
- The installed prefix must equal an unchanged canonical Pure baseline plus a sealed, disjoint package delta.
- Windows builds use exactly four workers.
- The visible desktop test remains optional and is not registered as an ordinary CTest.

---

### Task 1: Establish strict configure and runner contracts

**Files:**
- Modify: `pure-gl/CMakeLists.txt`
- Replace: `pure-gl/cmake/RunPureTest.cmake`
- Create: `pure-gl/cmake/pure_gl_runner.c`
- Create: `pure-gl/tests/runner_contract.cmake`
- Create: `pure-gl/tests/configure_contract.cmake`
- Create: `pure-gl/tests/runner_probe.pure`

**Interfaces:**
- Consumes: explicit `PURE_EXECUTABLE`, `PKG_CONFIG_EXECUTABLE`, `LLVM_READOBJ_EXECUTABLE`, `LLVM_STRINGS_EXECUTABLE`, `GNU_MAKE_EXECUTABLE`, `PURE_GL_PURE_PREFIX`, `PURE_GL_CLANG64_PREFIX`, and `PURE_GL_WINDOWS_SYSTEM_DIRECTORY` cache values.
- Produces: `pure-gl-test-runner.exe`, a `RunPureTest.cmake` adapter, and `pure-gl-runner-contract`/`pure-gl-configure-contract` CTests labeled `gl;contract`.

- [ ] **Step 1: Write the configure contract and verify RED**

Create an isolated driver that configures `pure-gl` with strict audit mode enabled and independently omits each required cache value, supplies a directory where a regular executable is required, supplies a Pure prefix inconsistent with `pure.exe`, and aliases the FreeGLUT prefix through a junction. Require each configure to fail with the variable name and reason. Register the test, run `ctest -R pure-gl-configure-contract --output-on-failure`, and confirm the current implicit `find_program`/`MSYSTEM_PREFIX` behavior is accepted and therefore RED.

- [ ] **Step 2: Write the runner contract and verify RED**

Make `runner_probe.pure` print its working directory and the effective `PATH`/`PURELIB`. The contract invokes the runner adapter with one required argument omitted, with a zero-exit fixture that writes stderr, with a fixture that prints a wrong token, with a fixture that spawns a child and exceeds the deadline, and with paths containing spaces. Require named-input diagnostics, stderr rejection, authenticated completion rejection, complete process-tree termination, `C:/Windows` as working directory, absent `PURELIB`, and an exact supplied `PATH`. The old CMake-only runner must fail at least the inherited-`PATH` case.

- [ ] **Step 3: Implement explicit configuration authority**

Add `PURE_GL_STRICT_AUDIT` and validate all strict inputs as normalized absolute regular files/directories. In strict mode do not call `find_program`, read `MSYSTEM_PREFIX`, or accept environment-derived package roots. Verify that `pure.exe` is below `PURE_GL_PURE_PREFIX`, that FreeGLUT headers/import library/runtime/license are below `PURE_GL_CLANG64_PREFIX`, and that the Windows system directory is not below either package prefix. Retain convenient discovery only when strict mode is off.

- [ ] **Step 4: Implement the bounded native supervisor**

Implement a Windows C11 runner with a unique random completion token, redirected stdout/stderr pipes, a Job Object configured with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, explicit environment block, explicit working directory, and millisecond timeout. Accept repeated `--include`, `--library`, `--input`, and `--path-entry` arguments; reject duplicate or missing options. Success requires zero exit, empty stderr, and exactly one terminal line `PURE_GL_TEST_OK <token>` after ordinary captured stdout. Build with `-Wall -Wextra -Werror`.

- [ ] **Step 5: Replace the CMake runner adapter**

Make `RunPureTest.cmake` validate explicit paths and invoke the native supervisor with the Pure executable, script, seven interfaces, module, FreeGLUT DLL, include/library roots, timeout, and working directory. Construct runtime `PATH` exclusively from staged Pure `bin`, package module/runtime directories, and `PURE_GL_WINDOWS_SYSTEM_DIRECTORY`; unset `PURELIB` in the supervisor environment.

- [ ] **Step 6: Convert build-tree and interactive calls**

Pass every required runner input to the load, hidden-render, and opt-in interactive target. Give automated tests both a 45-second supervisor deadline and 55-second CTest timeout; keep `RUN_SERIAL TRUE`. Run both new contracts plus the current functional tests under a parent environment containing only Windows system paths and verify GREEN.

- [ ] **Step 7: Commit strict execution**

```powershell
git add pure-gl/CMakeLists.txt pure-gl/cmake/RunPureTest.cmake pure-gl/cmake/pure_gl_runner.c pure-gl/tests/runner_contract.cmake pure-gl/tests/configure_contract.cmake pure-gl/tests/runner_probe.pure
git commit -m "Make pure-gl tests hermetic"
```

### Task 2: Strengthen deterministic OpenGL behavior tests

**Files:**
- Modify: `pure-gl/tests/load.pure`
- Modify: `pure-gl/tests/hidden-render.pure`
- Modify: `pure-gl/tests/interactive.pure`
- Create: `pure-gl/tests/render_contract.cmake`
- Modify: `pure-gl/CMakeLists.txt`

**Interfaces:**
- Consumes: the authenticated runner from Task 1 and existing GL/GLU/GLUT APIs.
- Produces: deterministic completion protocol and a mutation contract demonstrating that missing rendering/event/cleanup checks fail.

- [ ] **Step 1: Add a failing semantic mutation contract**

Create copies of each Pure test and remove, one mutation at a time, the all-family marker, context-string assertion, pixel assertion, OpenGL error assertion, display-event call, window destruction, and completion record. Run each copy through the Task 1 supervisor and require failure naming the missing semantic marker or completion record. Confirm the existing tests are RED because they do not emit authenticated completion and the hidden test does not check `GL::GetError` boundaries.

- [ ] **Step 2: Add authenticated completion to every script**

Have the runner pass the token as a script argument. Each script validates that exactly one token argument exists and emits `PURE_GL_TEST_OK <token>` only after every assertion and cleanup operation has succeeded.

- [ ] **Step 3: Complete hidden-render error and cleanup coverage**

Capture `GL::GetError` after setup, clear, finish, and readback and require every value to equal `GL::NO_ERROR`. Put allocation and window ownership on explicit success/failure cleanup paths so the pixel buffer is freed and `GLUT::DestroyWindow window` executes before the completion record.

- [ ] **Step 4: Keep interactive validation bounded**

Retain the one-second visible triangle and `GLUT::MainLoopEvent`; require the event callback to increment a Pure-visible marker, check each GL error boundary, destroy the window, and emit completion. Do not add it to CTest.

- [ ] **Step 5: Verify the semantic contract GREEN**

Run `pure-gl-render-contract`, `pure-gl.load-all-modules`, and `pure-gl.hidden-render`. Confirm every individual mutation fails, pristine scripts pass, and no `pure.exe` or FreeGLUT child remains after the tests.

- [ ] **Step 6: Commit rendering contracts**

```powershell
git add pure-gl/CMakeLists.txt pure-gl/tests/load.pure pure-gl/tests/hidden-render.pure pure-gl/tests/interactive.pure pure-gl/tests/render_contract.cmake
git commit -m "Enforce pure-gl rendering completion"
```

### Task 3: Replace partial PE checks with exact recursive closure

**Files:**
- Replace: `pure-gl/cmake/VerifyWindowsDependencies.cmake`
- Create: `pure-gl/cmake/PeHelpers.cmake`
- Create: `pure-gl/tests/runtime_verifier_contract.cmake`
- Create: `pure-gl/tests/fixtures/pure-gl-imports.txt`
- Create: `pure-gl/tests/fixtures/freeglut-imports.txt`
- Modify: `pure-gl/CMakeLists.txt`

**Interfaces:**
- Consumes: pinned `llvm-readobj.exe`, `pure-gl.dll`, `libfreeglut.dll`, explicit Pure/FreeGLUT/system roots, and literal normalized import fixtures.
- Produces: `verify-windows-dependencies` and `pure-gl-runtime-verifier-contract`, with complete expected/actual/missing/unexpected diagnostics.

- [ ] **Step 1: Capture pristine import fixtures**

Run the pinned LLVM tool against freshly built AMD64 `pure-gl.dll` and the pinned FreeGLUT 3.8.0 DLL. Record every normal `Name:` import in lowercase sorted order in the two fixture files; include direct system/UCRT dependencies and `libpure.dll`. Record SHA-256 of `llvm-readobj.exe` as a strict configure input.

- [ ] **Step 2: Write the negative PE fixture contract and verify RED**

Create a deterministic fake reader whose output is selected by input filename. Test case/order normalization, then inject `libunexpected.dll`, omit `libpure.dll`, report an unknown top-level record, produce a malformed import line, return two candidate resolution paths, and identify one input as non-AMD64. Require the binary filename and `expected`, `actual`, `missing`, and `unexpected` labels where applicable. The current selected-import verifier must accept at least the injected-import case.

- [ ] **Step 3: Implement strict import parsing**

In `PeHelpers.cmake`, parse only the documented `File:`/`Format:`/`Import`/`Name:` structure from `llvm-readobj --file-headers --coff-imports`; reject duplicate, malformed, or unknown records. Lowercase, deduplicate, and sort imports before exact comparison with the literal fixture for that binary.

- [ ] **Step 4: Implement recursive path resolution**

Resolve package DLLs first in the module and staged runtime directories, Pure runtime DLLs only in the explicit Pure prefix, FreeGLUT only in the explicit CLANG64/staged source selected for the audit mode, and system DLLs only in the explicit Windows system directory. Reject zero or multiple matches, reparse components, path escapes, wrong architecture, and imports matching `msys-2.0.dll`, `libgcc*`, or `libstdc++*`. Traverse until no unresolved non-system import remains and compare the complete visited set with the approved binary inventory.

- [ ] **Step 5: Preserve the generated loader-name regression**

Keep `llvm-strings` pinned by SHA-256 and require `pure-gl.dll` to contain a line-exact `libfreeglut.dll` reference and no line-exact obsolete `freeglut.dll`. Treat tool errors, decoding failures, or ambiguous strings as failures.

- [ ] **Step 6: Verify RED-to-GREEN behavior**

Run the fixture contract, the pristine build-tree PE target, and the two functional Pure tests with sanitized runtime `PATH`. Confirm each mutation is rejected and the pristine recursive closure reports exact AMD64 binary and import counts.

- [ ] **Step 7: Commit exact PE validation**

```powershell
git add pure-gl/CMakeLists.txt pure-gl/cmake/VerifyWindowsDependencies.cmake pure-gl/cmake/PeHelpers.cmake pure-gl/tests/runtime_verifier_contract.cmake pure-gl/tests/fixtures
git commit -m "Enforce pure-gl PE contracts"
```

### Task 4: Seal installation ownership and third-party provenance

**Files:**
- Replace: `pure-gl/cmake/Install.cmake`
- Replace: `pure-gl/cmake/VerifyInstalledPackage.cmake`
- Create: `pure-gl/cmake/pure_gl_install_guard.c`
- Create: `pure-gl/tests/install_contract.cmake`
- Create: `pure-gl/tests/install_guard_contract.cmake`
- Modify: `pure-gl/CMakeLists.txt`
- Modify: `pure-gl/THIRD_PARTY.md`

**Interfaces:**
- Consumes: canonical portable Pure baseline; frozen package source, generated README, FreeGLUT DLL, and FreeGLUT license identities.
- Produces: disjoint `runtime`/`documentation` component manifests, exact staged verification, and `pure-gl-install-contract`/`pure-gl-install-guard-contract` CTests.

- [ ] **Step 1: Write failing install mutations**

Build a contract root with an ownership sentinel and copy a canonical Pure prefix. Independently test an extra file under and outside historical `pure-gl` globs, a missing file, altered installed bytes, a pre-existing destination collision, a case-only duplicate, a runtime/documentation overlap, a FreeGLUT DLL from the wrong prefix, a license from the wrong package path, changed baseline bytes, a junction in the stage, and a protected descendant beneath the cleanup leaf. Confirm the old existence-only verifier accepts the extra/altered cases.

- [ ] **Step 2: Define and freeze the artifact inventory**

For every installed file record component, slash-normalized relative destination, canonical source, source SHA-256, project `pure-gl` or `FreeGLUT`, exact version, source URL, SPDX/license name, and installed license mapping. Require exactly the seven interfaces, module, FreeGLUT DLL, generated README, package/license docs, examples, and test scripts declared by policy; derive rather than hand-count directory entries.

- [ ] **Step 3: Implement guarded component installation**

Compile a Windows helper that canonicalizes handles, rejects reparse components and case-folded aliases, obtains exclusive stage authority with a named mutex, performs hash-checked atomic copies, and publishes manifests only after success. Anchor its build/source identity to trusted configure output. Derive fixed audit leaves internally and require exact sentinel contents before any recursive cleanup.

- [ ] **Step 4: Enforce baseline-plus-delta equality**

Snapshot the canonical baseline as sorted `relative|type|size|sha256` rows, freeze its manifest identity at configure time, and require the stage before/after each component install to equal the unchanged baseline plus only previously published disjoint deltas. Reject `DESTDIR`, symlinks/junctions, undeclared files, collisions, and mutation of baseline files.

- [ ] **Step 5: Bind FreeGLUT runtime to its license**

Require the DLL source to be exactly `<PURE_GL_CLANG64_PREFIX>/bin/libfreeglut.dll` and the notice to be exactly `<PURE_GL_CLANG64_PREFIX>/share/licenses/freeglut/COPYING`. Pin both SHA-256 values and require the inventory metadata for the runtime to map to the installed `share/doc/pure-gl/licenses/FreeGLUT.txt` payload with matching FreeGLUT 3.8.0 identity.

- [ ] **Step 6: Run installed functional and PE checks**

From `C:/Windows`, run staged load and hidden-render through the native supervisor with only staged inputs and system paths. Repeat Task 3's exact recursive PE audit against staged binaries, then resnapshot the prefix and require no test-created residue.

- [ ] **Step 7: Verify every mutation and pristine case**

Run both install contracts individually and then with `ctest -L gl`. Each destructive probe must first fail without changing the protected tree, restore its fixture, and finish with a passing pristine install. Record exact baseline, delta-file, delta-directory, PE-binary, and installed-test counts.

- [ ] **Step 8: Commit sealed installation**

```powershell
git add pure-gl/CMakeLists.txt pure-gl/cmake/Install.cmake pure-gl/cmake/VerifyInstalledPackage.cmake pure-gl/cmake/pure_gl_install_guard.c pure-gl/tests/install_contract.cmake pure-gl/tests/install_guard_contract.cmake pure-gl/THIRD_PARTY.md
git commit -m "Seal pure-gl package ownership"
```

### Task 5: Make the public source archive self-contained and cleanup safe

**Files:**
- Modify: `pure-gl/Makefile`
- Create: `pure-gl/tests/source_dist_contract.cmake`
- Create: `pure-gl/tests/cleanup_contract.cmake`
- Modify: `pure-gl/CMakeLists.txt`

**Interfaces:**
- Consumes: public GNU Make `dist`/`distcheck` recipes and the strict build inputs from Tasks 1-4.
- Produces: exact, independently configurable source archive plus guarded legacy cleanup contracts.

- [ ] **Step 1: Write the source archive contract and verify RED**

Run the real `make dist` from a copied source directory whose path contains spaces. Delete the copied source after archive creation; extract the archive elsewhere and require regular non-symlink files whose hashes match checkout inputs. Require `CMakeLists.txt`, `WINDOWS.md`, `THIRD_PARTY.md`, every CMake/helper source, all three Pure tests, and every contract fixture. The present `DISTFILES` must fail on `CMakeLists.txt`.

- [ ] **Step 2: Write non-destructive cleanup probes and verify RED**

Exercise `clean`, `realclean`, `generate`, `dist`, and `distcheck` with missing `pure.pc`, empty DLL suffix, a case-only alias, a junctioned work leaf, an invalid sentinel, and a protected descendant. Require rejection before deletion and verify byte hashes of protected fixtures. Demonstrate the current `rm -Rf *$(DLL)*` expansion is unsafe when `DLL` is empty.

- [ ] **Step 3: Complete the distribution manifest**

Add all CMake, Windows documentation, helper C sources, tests, and fixture data to `DISTFILES`; create every archive subdirectory explicitly. Preserve README version/date substitution. Make the contract compare an exact sorted archive inventory so future missing and extra inputs both fail.

- [ ] **Step 4: Harden legacy destructive recipes**

Replace broad glob deletion with a guarded helper target that accepts only fixed package-owned outputs inside the canonical source/build leaf. Require the source sentinel, reject reparse/protected descendants and case aliases, and keep generated wrapper sources unless `realclean` is explicitly requested. Do not derive deletion roots from `DLL`, `DESTDIR`, or shell expansion.

- [ ] **Step 5: Prove extracted-tree reproducibility**

With checkout-only driver files unavailable, configure the extracted archive in strict mode, build with four workers, run the PE target and noninteractive tests, and verify the package inventory can be sealed from archive contents plus explicit external dependencies.

- [ ] **Step 6: Commit release contracts**

```powershell
git add pure-gl/Makefile pure-gl/CMakeLists.txt pure-gl/tests/source_dist_contract.cmake pure-gl/tests/cleanup_contract.cmake
git commit -m "Verify pure-gl source releases"
```

### Task 6: Make pure-gl mandatory in Windows CI

**Files:**
- Modify: `.github/workflows/non-linux-release-validation.yml`
- Modify: `.github/scripts/validate_non_linux_release_workflow.py`
- Modify: `.github/scripts/test_validate_non_linux_release_workflow.py`
- Create: `pure-gl/tests/workflow_contract.cmake`
- Modify: `pure-gl/CMakeLists.txt`

**Interfaces:**
- Consumes: portable Pure SDK from the existing Windows 2025 job and all Task 1-5 contracts.
- Produces: required four-worker `pure-gl` CI gate plus semantic workflow validation.

- [ ] **Step 1: Add failing semantic workflow tests**

Extend the Python validator unit fixtures and add the package-local contract to require push and pull-request filters for `pure-gl/**`, TODO-35, the design, and plan; the CLANG64 FreeGLUT prerequisite; explicit strict tools/prefixes/system directory; four-worker build; exact PE target; noninteractive `ctest -L gl --no-tests=error`; source archive validation; separate final stage; complete installed verifier; and retained logs. Mutate each required field independently and require a specific diagnostic. Run the tests against the current YAML and confirm RED.

- [ ] **Step 2: Add CI prerequisites and explicit variables**

Install `mingw-w64-clang-x86_64-freeglut` and retain GNU `make`. Define absolute source, build, Pure prefix, CLANG64 prefix, Windows system, package stage, tool, and log paths. Supply every strict cache value and pinned tool hash during configuration; do not use `MSYSTEM_PREFIX` as package authority.

- [ ] **Step 3: Add the build-tree gate**

Configure a fresh Release directory from the checkout path, build with `--parallel 4`, run `verify-windows-dependencies`, and run all `gl`-label tests with `PURELIB` removed and the PowerShell parent `PATH` restricted to Windows system directories. Tee each command to a package-specific log and throw on nonzero status.

- [ ] **Step 4: Add source and final-package gates**

Run the public source-distribution contract independently. Copy the canonical portable Pure prefix to a fresh stage whose path contains spaces and non-ASCII characters, install runtime and documentation separately through the guarded flow, and invoke the complete verifier with every explicit runtime, tool, source, license, manifest, and supervisor input.

- [ ] **Step 5: Verify YAML semantics GREEN**

Run the Python validator unit suite, validator CLI, a real YAML parse, the package workflow contract, and `git diff --check`. Confirm path filters and command semantics cannot be removed or weakened without a failing validator test.

- [ ] **Step 6: Commit CI integration**

```powershell
git add .github/workflows/non-linux-release-validation.yml .github/scripts/validate_non_linux_release_workflow.py .github/scripts/test_validate_non_linux_release_workflow.py pure-gl/CMakeLists.txt pure-gl/tests/workflow_contract.cmake
git commit -m "Validate pure-gl in Windows CI"
```

### Task 7: Document, independently review, and close the follow-up audit

**Files:**
- Modify: `pure-gl/WINDOWS.md`
- Modify: `pure-gl/THIRD_PARTY.md`
- Modify: `pure/todo/TODO-35-windows-pure-gl.md`
- Review: all changes after design commit `5a8baeab`

**Interfaces:**
- Consumes: all passing contracts and fresh final-stage evidence.
- Produces: accurate operator documentation, dated TODO evidence, resolved review findings, and final clean verification.

- [ ] **Step 1: Update operator documentation**

Document exact prerequisite versions and paths, strict configure cache values, four-worker build, CTest labels, hermetic runtime policy, interactive target, source archive, component installation, exact inventory, FreeGLUT provenance, PE closure, and system-DLL exclusions. Explain that the visible desktop check is optional while load and hidden rendering are mandatory.

- [ ] **Step 2: Run the first complete clean verification**

From a new Release build directory configure strict inputs, build with exactly four workers, run the exact PE target, all `gl` tests, public source archive contract, separate Unicode-and-space stage installation, and installed verifier. Preserve elapsed time, versions, hashes, file/directory counts, test count, and PE binary/import counts; do not update TODO-35 before this run passes.

- [ ] **Step 3: Append evidence to TODO-35**

Add dated 2026-09-12 entries describing each original audit gap, its executable regression contract, exact CI integration, and the measured clean verification results from Step 2. Keep historical 2026-07 entries intact and do not claim interactive desktop validation was rerun unless it actually was.

- [ ] **Step 4: Commit documentation evidence**

```powershell
git add pure-gl/WINDOWS.md pure-gl/THIRD_PARTY.md pure/todo/TODO-35-windows-pure-gl.md
git commit -m "Close TODO-35 pure-gl audit"
```

- [ ] **Step 5: Request independent code review**

Use `superpowers:requesting-code-review` against base `5a8baeab`, the approved spec, and this plan. Treat every Critical or Important finding as a new RED/GREEN cycle, commit focused fixes, and request follow-up review until no such findings remain.

- [ ] **Step 6: Run verification-before-completion**

Use `superpowers:verification-before-completion`. Recreate a clean strict Release tree and a distinct final stage, then rerun four-worker build, exact PE target, all `gl` CTests, source archive, installed verifier, Python workflow tests, YAML parse, and `git diff --check`. Inspect `git status --short` and distinguish intended tracked changes from pre-existing untracked audit artifacts.

- [ ] **Step 7: Record any review-fix evidence**

If review changed behavior, append only the newly verified facts and measurements to TODO-35 and commit them with the relevant fix. Finish with no uncommitted tracked changes.
