# TODO-29 - Windows pure-xml Package

Status: Completed
Branch: todo/29-windows-pure-xml

## Purpose

Build, validate, and package `pure-xml` with libxml2 and libxslt on Windows.

## Scope

- Use controlled CLANG64 builds of libxml2 and libxslt.
- Bundle all required transitive DLLs and license material.
- Cover parsing, serialization, XPath, XSLT, encodings, and path handling.

## Task List

1. [x] Build the native module against the staged runtime.
2. [x] Audit libxml2/libxslt configuration and transitive dependencies.
3. [x] Add XML, XPath, and XSLT smoke tests.
4. [x] Stage and validate the package outside MSYS2.

## Guardrails

- Do not load dependency DLLs from MSYS2 or the current directory accidentally.
- Disable or constrain network access in parser tests.

## Validation Plan

- Parse and transform UTF-8 documents from a path containing spaces.
- Inspect PE imports and run with a sanitized environment.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
- 2026-07-28: Built `xml.dll` with Clang 22 against libxml2 2.15.3 and
  libxslt 1.1.45.
- 2026-07-28: Audited the PE closure through the existing bundle copies of
  iconv and zlib and added both upstream dependency licenses.
- 2026-07-28: Added smoke coverage for UTF-8 parsing, serialization,
  ISO-8859-2 round-tripping, XPath, XSLT, and paths containing spaces.
- 2026-07-28: Fixed `xml::load_string` to preserve UTF-8 instead of converting
  through the Windows system code page.
- 2026-07-28: Installed the complete 17-file manifest and passed the installed
  smoke test from `C:\Windows` with a sanitized environment and no MSYS2 path.
- 2026-07-28: Completed.
