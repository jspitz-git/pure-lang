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
