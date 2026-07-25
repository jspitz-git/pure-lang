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

1. [ ] Build the native module against the staged runtime and SQLite.
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
