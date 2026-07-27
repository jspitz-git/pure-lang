# TODO-30 - Windows pure-gsl Package

Status: Closed
Branch: todo/30-windows-pure-gsl

## Purpose

Build, validate, and package `pure-gsl` with the CLANG64 GSL implementation.

## Scope

- Build the native bridge and install all associated Pure modules.
- Bundle GSL, CBLAS, and their required runtime dependencies.
- Cover representative numerical subsystems rather than import-only validation.

## Task List

1. [x] Build the package against the staged Pure runtime and GSL.
2. [x] Inventory every installed Pure module and shared-library dependency.
3. [x] Add representative numerical and error-handling smoke tests.
4. [x] Validate the complete staged package outside MSYS2.

## Guardrails

- Do not silently omit modules that are part of the advertised package.
- Numerical results must use documented tolerances.

## Validation Plan

- Import every module and exercise vectors, roots, and special functions. The
  shipped 0.12 API has no numerical-integration or general nonlinear-root
  module; polynomial roots and every advertised numerical family are covered.
- Run with only the staged GSL/CBLAS DLLs on the loader search path.

## Progress Log

- 2026-07-25: Created as a scientific Windows package candidate.
- 2026-07-28: Added a CMake/Clang 22 build against the staged Pure 0.68 SDK
  and CLANG64 GSL 2.8. A strict `-Wall -Wextra -Werror` build found and fixed
  two 64-bit signed/unsigned index mismatches. The Windows loader condition
  now recognizes the `x86_64-w64-windows-gnu` target and loads
  `libgsl-28.dll`.
- 2026-07-28: Inventoried and load-tested `gsl.pure`, `gsl.dll`, and all ten
  namespace modules: `common`, `utils`, `matrix`, `sort`, `randist`, `stats`,
  `poly`, `fit`, `sf`, and the separately imported experimental `complex`.
  The PE audit proves `gsl.dll -> libgsl-28.dll -> libgslcblas-0.dll`, with
  `libpure.dll` supplied by the staged runtime and no MSYS, libgcc, or
  libstdc++ dependency.
- 2026-07-28: Added behavioral tests with explicit tolerances for matrix
  multiplication, an SVD solve, vector sorting, Gaussian PDF/CDF, statistics,
  polynomial evaluation and roots, linear fitting, Bessel values and error
  estimates, domain guarding, and complex square roots. Both the import test
  and numerical CTest pass.
- 2026-07-28: Added complete install rules. The package delta contains 21
  verified files: the native module, umbrella module, all ten namespace
  modules, GSL and CBLAS DLLs, package and dependency licenses, Windows
  documentation, two examples, and the installed smoke test.
- 2026-07-28: Copied the current portable Pure prefix, installed `pure-gsl`,
  and launched its staged `pure.exe` from `C:\Windows` with `PURELIB` empty
  and `PATH` restricted to staged `bin` plus Windows system directories. The
  numerical test and staged PE audit passed. The complete portable-prefix
  audit resolved every non-system dependency within the stage and reported
  14 DLLs, 13 dependency paths, and 61 files with no forbidden build/MSYS2
  path leakage.
