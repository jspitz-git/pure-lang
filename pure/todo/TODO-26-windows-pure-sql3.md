# TODO-26 - Windows pure-sql3 Package

Status: Open
Branch: todo/26-windows-pure-sql3

## Purpose

Build, validate, and package `pure-sql3` with SQLite for the portable Windows
distribution.

## Scope

- Use a controlled CLANG64 SQLite build and bundle its runtime dependency.
- Cover databases, prepared statements, transactions, nulls, blobs, and Unicode paths.
- Stage the module, Pure sources, examples, and licenses.

## Task List

1. [x] Build the native module against the staged runtime and SQLite.
2. [ ] Add focused database lifecycle and query smoke tests.
3. [ ] Audit DLL loading and package installation paths.
4. [ ] Validate the staged package outside MSYS2.

## Guardrails

- Do not depend on a system-installed `sqlite3.dll`.
- Ensure statements and database handles are released deterministically.

## Validation Plan

- Create, query, update, and reopen a temporary database in a path containing spaces.
- Exercise transactions, parameter binding, blobs, nulls, and failure handling.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
- 2026-07-27: Added a CMake build for `sql3util.dll` and verified both the
  legacy Makefile and a clean CMake build with Clang 22.1.8 using
  `-Wall -Wextra -Werror`.
- 2026-07-27: Loaded the staged module from `C:\Windows` with MSYS2 excluded
  from `PATH`, then opened an in-memory database, ran a prepared query,
  finalized the statement, and closed the database.
- 2026-07-27: Audited the PE dependencies: `sql3util.dll` is x86-64 and imports
  `libpure.dll`, `libsqlite3-0.dll`, and `libgmp-10.dll`, with no MSYS runtime.
  The controlled SQLite 3.53.3 DLL is x86-64, depends only on Windows/UCRT
  components, and has SHA-256
  `91240F2E86A7648A408D2B3EA4F851C1DB0FB9A778F775A823FF81978ABB14F7`.
