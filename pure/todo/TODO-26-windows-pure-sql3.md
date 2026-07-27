# TODO-26 - Windows pure-sql3 Package

Status: Closed on 2026-07-27
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
2. [x] Add focused database lifecycle and query smoke tests.
3. [x] Audit DLL loading and package installation paths.
4. [x] Validate the staged package outside MSYS2.

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
- 2026-07-27: Added a CTest smoke test covering a database path with spaces
  and non-ASCII characters, prepared inserts and selects, Unicode text,
  SQL NULL, serialized blobs, commit, rollback, update, reopen, invalid SQL,
  and deterministic statement/database release.
- 2026-07-27: Declared the public `sql3::SQLNULL` symbol used by the native
  value converter.
- 2026-07-27: Fixed statement sentries so a statement already finalized by
  explicit cleanup or database close is not finalized again after its
  database has closed. The strict CLANG64 CTest run passes.
- 2026-07-27: Added prefix-contained install rules for the module, Pure
  source, seven examples, generated README, package license, the controlled
  SQLite DLL, and its license. The exact install manifest contains 13 files.
- 2026-07-27: Verified that the installed SQLite DLL is byte-identical to the
  controlled CLANG64 input and that both installed PE files are x86-64 with
  no MSYS runtime import. A negative `../escape` configuration is rejected.
- 2026-07-27: Ran the installed package from `C:\Windows` with a restricted
  `PATH` containing only its SQLite directory, the portable Pure runtime, and
  Windows. The complete database smoke test passed.
- 2026-07-27: Created a fresh full portable runtime copy and installed the
  package into it. The exact delta was the expected 13 files, for 53 files in
  the completed staged tree.
- 2026-07-27: Launched the staged `bin/pure.exe` directly from PowerShell in
  `C:\Windows`, with `PURELIB` unset and `PATH` restricted to the bundle plus
  Windows system directories. The marker-checked smoke test passed, exited
  zero, and created and reopened its database below a path containing spaces
  and non-ASCII characters.
- 2026-07-27: The final source/build-path leak scan was clean, all direct
  nonsystem DLL imports were present in the portable tree, and installed
  binary hashes matched the audited build and controlled SQLite input.
