# TODO-32 - Windows pure-odbc Package

Status: Closed on 2026-09-08
Branch: todo/32-windows-pure-odbc

## Purpose

Build and validate `pure-odbc` against an explicitly selected Windows ODBC layer.

## Scope

- Decide whether to use native Windows ODBC or bundled unixODBC.
- Validate connection, statements, parameters, result conversion, and diagnostics.
- Avoid requiring a particular external database server for basic tests.

## Task List

1. [x] Select and document the supported Windows ODBC implementation.
2. [x] Build the module and audit its runtime dependencies.
3. [x] Add self-contained driver or mock-based smoke tests where practical.
4. [x] Stage and validate the package outside MSYS2.

## Guardrails

- Do not claim support for untested third-party database drivers.
- Keep credentials and machine-specific DSNs out of tests and artifacts.

## Validation Plan

- Exercise allocation, diagnostics, parameter binding, and result conversion.
- Test against a documented local driver when available and inspect PE imports.

## Decision

- Use the native Microsoft ODBC Driver Manager supplied by Windows. Do not
  bundle unixODBC or `odbc32.dll`; database drivers remain optional,
  architecture-matched user or system components.

## Progress Log

- 2026-07-25: Created as a database Windows package candidate.
- 2026-07-28: Selected the native 64-bit Microsoft ODBC Driver Manager
  (`C:\Windows\System32\odbc32.dll`) and documented its ABI, driver
  architecture, and packaging boundary. No unixODBC compatibility claim or
  third-party database driver is included in the bundle.
- 2026-07-28: Added a CMake/Clang 22 build against the staged Pure 0.68 SDK
  and CLANG64 headers/import libraries. A strict `-Wall -Wextra -Werror`
  build fixed signed/unsigned loop bounds and guarded the parameter count
  before narrowing it to the native API type.
- 2026-07-28: Hardened legacy `make clean` against an empty Pure DLL suffix.
  The negative test confirms that it refuses the potentially broad deletion
  pattern when `pure.pc` is unavailable.
- 2026-07-28: Audited the module's PE imports. `odbc.dll` imports staged
  `libpure.dll` and `libgmp-10.dll`, native `ODBC32.dll`, and Windows UCRT
  components only; it imports no MSYS, libgcc, or libstdc++ runtime.
- 2026-07-28: Added self-contained tests which always enumerate drivers and
  data sources and verify an `IM002` diagnostic without credentials or a
  machine DSN. When the exact 64-bit Microsoft Access Text Driver is
  available, an isolated semicolon-delimited fixture also validates
  DSN-less connection, statement execution, integer parameters, integer,
  string, and SQL NULL results, low-level fetch, and handle cleanup.
- 2026-07-28: Installed and verified a 10-file package delta containing the
  module, Pure interface, documentation, example, and reproducible smoke
  fixture. The installer reuses the byte-identical staged GMP runtime and
  explicitly rejects any bundled ODBC manager.
- 2026-07-28: Launched staged `pure.exe` with `PURELIB` empty and `PATH`
  restricted to staged `bin` plus Windows system directories. The installed
  smoke test and staged PE audit passed. The complete portable-prefix audit
  reported 12 DLLs, 12 resolved non-system dependency paths, and 50 files
  without forbidden build/MSYS2 path leakage.
- 2026-09-07: Reopened for a SuperPowers audit of native memory safety,
  hermetic tests, exact package/runtime closure, source distribution, and CI.
- 2026-09-07: Audited the native binding with a production-default ODBC
  dispatch seam and fault injection. Fixed unsafe `SQLGetData`/`SQLGetInfo`
  reads, width truncation, unchecked binds, enumeration/diagnostic truncation,
  partial connection/execution cleanup, and result-metadata ownership. The
  public Pure symbols and tuple shapes remain unchanged; row counts outside the
  32-bit Pure `int` range now use `int64` instead of narrowing.
- 2026-09-07: Replaced inherited-environment smoke helpers with one strict
  runner. Mandatory manager/enumeration/`IM002` coverage is separate from the
  exact Access Text Driver test; only absence of that exact 64-bit driver maps
  to CTest skip 77. Root/sentinel/reparse contracts protect recursive cleanup,
  and legacy `make clean` accepts only an explicit module suffix and owned
  generated files.
- 2026-09-07: Added opt-in strict Release configuration for Clang 22 CLANG64,
  exact regular-file tool/SDK/header/import inputs, recursive AMD64 PE closure,
  and a full-prefix installation contract. The PE check covered 14 staged
  binaries and resolved `ODBC32.dll` only to the native 64-bit System32 file.
  The install check proved the exact documented ten-file component delta,
  unchanged baseline files, byte-identical staged Pure/GMP runtimes, and no
  packaged manager or database driver.
- 2026-09-07: Made the real 36-input `make dist` archive self-contained. Its
  contract extracts under a path containing spaces, removes the checkout-side
  driver, rejects symlink/reparse inputs and checkout-path leakage, then runs
  strict configure, four-worker build, tests, installation, and verification
  solely from extracted sources. Closure testing exposed a CMake regex group
  limit in the arbitrary-case binary path scanner for long checkout paths; the
  scanner now folds delimiter-aligned ASCII byte tokens without regex groups.
  The >9 MiB mixed-case boundary fixture passed in 11.65 s and the full archive
  contract passed in 585.05 s.
- 2026-09-07: Added both `pure-odbc/**` and this TODO to push and pull-request
  workflow filters. Windows CI installs `make` and PyYAML, consumes every strict
  input explicitly after portable Pure staging, builds and PE-checks with
  exactly four workers, runs the complete sanitized `odbc` label, installs
  runtime and documentation components into a fresh stage, directly invokes
  the installed verifier, and validates workflow structure with PyYAML 6.0.3
  `BaseLoader`.
- 2026-09-07: Fresh closure used CMake 4.4.0, Clang 22.1.8 targeting
  `x86_64-w64-windows-gnu`, pkgconf 3.0.4, Pure 0.68, and GMP 6.3.0. Strict
  configure completed in 8.6 s; the eight-edge build and exact PE target passed
  with `--parallel 4`; all 9/9 ODBC tests passed in 983.15 s with no skip
  (manager 6.04 s, Access 4.56 s, configure mutations 58.23 s, PE mutations
  87.82 s, source distribution 585.05 s, ASan fault harness 23.21 s, install
  136.07 s). A separate fresh-stage two-component install added exactly ten
  files and the direct installed manager/IM002/PE verifier passed. PyYAML
  semantic validation and `git diff --check` also passed.
- 2026-09-07: Residual limits are intentional: no third-party database driver
  or external database server is certified; Access coverage is optional and
  host-dependent; System32 `odbc32.dll` internal imports may change through
  Windows servicing; and exact CLANG64/Pure import manifests require a new
  audit when the audited toolchain or SDK changes.
- 2026-09-08: Task 7 CI and documentation review completed. The TODO remains
  open deliberately; `Status: Closed on YYYY-MM-DD` may be set only after Task
  8 whole-branch review and final clean verification have both passed.
- 2026-09-08: The Task 8 whole-branch review found and fixed three remaining
  defects: the public `odbc_info` path now shares the bounded `SQLGetInfo`
  loader and releases partially constructed Pure values; text `SQLGetData`
  distinguishes unrelated short warnings, rejects invalid negative indicators,
  and bounds repeated continuation; and a partial capture-thread startup
  failure now terminates the child, closes parent write ends, and waits for the
  child and every started reader before releasing handles or stack state. The
  scoped re-review found no remaining Critical, Important, or Minor issue.
- 2026-09-08: Final verification used a never-before-used strict Release build
  and stage. Configure found Clang 22.1.8, Pure 0.68, and GMP 6.3.0; the
  eight-edge build and exact PE target passed with `--parallel 4`, covering 14
  AMD64 binaries and resolving `ODBC32.dll` only to
  `C:/Windows/System32/odbc32.dll`. All 9/9 ODBC tests passed with no skip in
  990.92 s (source distribution 593.27 s, ASan fault harness 23.18 s, install
  contract 136.75 s). The PyYAML mutation and pristine semantic checks passed.
  A separate fresh-stage two-component install and direct verifier confirmed
  the exact ten-file delta, unchanged full-prefix baseline, byte-identical
  Pure/GMP runtimes, no bundled manager or driver, installed manager/IM002
  smoke, and exact staged PE closure. The branch diff check was clean.
- 2026-09-08: Remaining limits are explicit: GitHub-hosted execution is pending
  the future push; Windows LeakSanitizer is unavailable, so the ASan harness
  also requires zero explicit tracked allocations; Access success is
  host-dependent with exact absence skip 77; no external database/server is
  certified; and the strict import manifests require re-audit after relevant
  toolchain, SDK, or Windows ABI changes.
