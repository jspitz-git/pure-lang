# TODO-32 - Windows pure-odbc Package

Status: Open
Branch: todo/32-windows-pure-odbc

## Purpose

Build and validate `pure-odbc` against an explicitly selected Windows ODBC layer.

## Scope

- Decide whether to use native Windows ODBC or bundled unixODBC.
- Validate connection, statements, parameters, result conversion, and diagnostics.
- Avoid requiring a particular external database server for basic tests.

## Task List

1. [ ] Select and document the supported Windows ODBC implementation.
2. [ ] Build the module and audit its runtime dependencies.
3. [ ] Add self-contained driver or mock-based smoke tests where practical.
4. [ ] Stage and validate the package outside MSYS2.

## Guardrails

- Do not claim support for untested third-party database drivers.
- Keep credentials and machine-specific DSNs out of tests and artifacts.

## Validation Plan

- Exercise allocation, diagnostics, parameter binding, and result conversion.
- Test against a documented local driver when available and inspect PE imports.

## Open Questions

- Whether native Windows ODBC or unixODBC gives the more maintainable ABI and packaging.

## Progress Log

- 2026-07-25: Created as a database Windows package candidate.
