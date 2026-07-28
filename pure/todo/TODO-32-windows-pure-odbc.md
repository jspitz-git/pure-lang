# TODO-32 - Windows pure-odbc Package

Status: Closed
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
