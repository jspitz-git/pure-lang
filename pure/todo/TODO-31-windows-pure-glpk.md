# TODO-31 - Windows pure-glpk Package

Status: Closed
Branch: todo/31-windows-pure-glpk

## Purpose

Build, validate, and package `pure-glpk` with a controlled Windows GLPK runtime.

## Scope

- Build against CLANG64 GLPK and its actual GMP, zlib, SuiteSparse, and OpenMP dependencies.
- Reuse compatible DLLs already present in the distribution.
- Validate model construction, solving, status reporting, and cleanup.

## Task List

1. [x] Build the native module against the staged runtime and GLPK.
2. [x] Resolve and deduplicate all transitive runtime DLLs.
3. [x] Add LP/MIP solution and failure-path smoke tests.
4. [x] Stage and validate the package outside MSYS2.

## Guardrails

- Do not bundle conflicting GMP or zlib versions.
- Solver handles and callbacks must remain valid across the native boundary.

## Validation Plan

- Solve small deterministic LP and MIP models and check objective and status.
- Inspect PE imports and repeat the test with a sanitized `PATH`.

## Progress Log

- 2026-07-25: Created as a scientific Windows package candidate.
- 2026-07-28: Installed the official CLANG64 GLPK 5.0 package and added a
  CMake/Clang 22 build against the staged Pure 0.68 SDK. A strict
  `-Wall -Wextra -Werror` build fixed 64-bit index types, removed obsolete
  dead code, and corrected two latent uses of uninitialized loop counters.
- 2026-07-28: Hardened the legacy `make clean` target. If `pure.pc` is not
  available and the DLL suffix is empty, it now fails safely instead of
  expanding its deletion pattern to the whole `pure-glpk` directory. The
  negative guard test passed.
- 2026-07-28: Audited the complete PE graph. `glpk.dll` imports staged Pure,
  GLPK, and GMP. GLPK imports AMD, COLAMD, GMP, and zlib; AMD/COLAMD import
  SuiteSparseConfig, which imports OpenMP. No MSYS, libgcc, libstdc++, ltdl,
  or ODBC DLL is present in the actual runtime closure.
- 2026-07-28: Verified that the existing staged `libgmp-10.dll` and
  `zlib1.dll` are byte-identical to their CLANG64 counterparts by SHA-256.
  The installer reuses them and adds only five DLLs: GLPK, AMD, COLAMD,
  SuiteSparseConfig, and OpenMP.
- 2026-07-28: Added deterministic solver tests. The LP optimum is
  `x=2, y=2, objective=10`; the MIP optimum has integer variables and
  objective 2. Tests also check solver and solution statuses, an
  out-of-bounds failure, explicit cleanup, and rejection of a stale handle.
- 2026-07-28: Installed and verified a 15-file package delta including the
  module, Pure interface, five new runtime DLLs, three dependency licenses,
  documentation, example, and installed solver smoke test.
- 2026-07-28: Launched staged `pure.exe` from `C:\Windows` with `PURELIB`
  empty and `PATH` restricted to staged `bin` plus Windows system
  directories. LP/MIP/error/cleanup validation and the staged PE audit
  passed. The complete portable-prefix audit reported 17 DLLs, 16 resolved
  non-system dependency paths, and 55 files without forbidden build/MSYS2
  path leakage.
- 2026-09-07: The follow-up audit found that a callback could retain its
  `tree` expression after the native `tree_obj` wrapper was freed, so a later
  `glp::ios_*` validation read freed memory. The callback wrapper now retains
  the Pure expression through cleanup, clears its pointer payload before
  freeing the native wrapper, and the smoke regression covers both retained
  and non-retained callbacks.
- 2026-09-07: The callback regression also exposed that `cb_info` declared a
  pointer contract but option conversion rejected pointer values before they
  reached GLPK. Pointer-valued `cb_info` now passes through unchanged, and the
  callback checks that it receives the configured pointer.
- 2026-09-07: Build-tree tests inherited the developer's ambient `PATH`, so
  their passing result did not prove that the module was independent of
  MSYS2. One strict runner now requires explicit Pure, package, module,
  runtime, and test paths; clears `PURELIB`; and constructs its Windows
  `PATH` solely from those runtime inputs and Windows system directories.
  Runner and configure contracts reject missing inputs and implicit tool
  lookup.
- 2026-09-07: The installed-package verifier existed outside the normal test
  graph, leaving its result dependent on a manual invocation. The registered
  install contract now copies a clean portable Pure prefix, installs only the
  runtime and documentation components, verifies the exact 15-file ownership
  and source hashes, confirms reused GMP/zlib hashes, runs the solver/callback
  regression, and repeats the staged PE audit. Its negative paths reject a
  contaminated input prefix, an extra owned file, and altered installed
  bytes.
- 2026-09-07: PE validation previously checked only selected forbidden or
  required imports and could accept an unreviewed dependency. It now compares
  the complete normalized import sets of all eight AMD64 binaries and reports
  missing and unexpected names. The fixture contract demonstrates rejection
  of an injected import and preserves case/order canonicalization coverage;
  the literal expectations remain intentionally package-version-sensitive.
- 2026-09-07: The legacy source archive omitted its CMake build and validation
  inputs. `make dist` now includes `CMakeLists.txt`, `WINDOWS.md`, every CMake
  helper, both Pure tests, and all contract scripts. The source-dist contract
  executes the real archive recipe from a path containing spaces, deletes its
  source copy, and configures the extracted tree without checkout-only files.
- 2026-09-07: Windows CI now installs the CLANG64 GLPK prerequisite, supplies
  explicit tool and pkg-config inputs, builds pure-glpk with four workers,
  executes exact PE and all `glpk`-label contracts with no MSYS2 directory in
  the runtime `PATH`, and verifies a separate fresh final package stage with
  every declared source, runtime, and license input.
- 2026-09-07: Fresh audit verification used Clang 22.1.8, strict Release
  warnings, and exactly four build workers. Exact imports passed for eight
  AMD64 binaries, and all seven `glpk` CTests passed in 52.00 seconds with the
  parent `PATH` limited to Windows system directories and `PURELIB` absent.
  The seven comprise load, solver/callback smoke, runner, configure,
  source-dist, PE-verifier, and installed-package contracts.
- 2026-09-07: A separate final stage was installed at the physical path
  `task 5 závěrečná instalace`. Pure 0.68 produced parser errors when launched
  directly below the non-ASCII prefix; using that same directory's Windows
  8.3 alias isolated the limitation to Pure's executable-prefix handling. The
  complete verifier then passed for the physical Unicode-and-space stage: 15
  exact package-owned files and hashes, deduplicated GMP/zlib, solver and
  callback smoke coverage, and exact staged PE imports.
- 2026-09-07: Review found that the Windows job installed no MSYS `make`
  package even though `BUILD_TESTING=ON` registers a source-distribution
  contract whose configure requires `find_program(make)`. CI now installs
  `make` explicitly, and the Windows guide lists it as a prerequisite.
- 2026-09-07: Review also traced `libomp.dll` to
  `mingw-w64-clang-x86_64-llvm-openmp 22.1.8-1`. Its owning notice is
  `share/licenses/openmp/LICENSE`; the previously staged LLVM notice belongs
  to a different package and has a different SHA-256. Installation, manifest,
  hash, contract, CI, and documentation inputs now use the OpenMP notice under
  `openmp-LICENSE`. The install contract rejects a wrong-package license
  source with an exact OpenMP-license hash diagnostic.
- 2026-09-07: Fresh review-fix verification configured a clean strict Release
  tree with Clang 22.1.8, built with four workers, verified exact imports for
  eight AMD64 binaries, and passed all seven sanitized `glpk` tests in 52.82
  seconds. A newly recreated Unicode-and-space final stage passed its complete
  verifier through the documented short-path helper; its installed
  `openmp-LICENSE` SHA-256 was
  `fdad1758a9e1f9d5a81e18879b3406772115edc92c24bfa36b70c654f325e8e4`,
  equal to the owner package source, and the obsolete conflated notice was
  absent.
