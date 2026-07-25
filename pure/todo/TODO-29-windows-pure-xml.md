# TODO-29 - Windows pure-xml Package

Status: Open
Branch: todo/29-windows-pure-xml

## Purpose

Build, validate, and package `pure-xml` with libxml2 and libxslt on Windows.

## Scope

- Use controlled CLANG64 builds of libxml2 and libxslt.
- Bundle all required transitive DLLs and license material.
- Cover parsing, serialization, XPath, XSLT, encodings, and path handling.

## Task List

1. [ ] Build the native module against the staged runtime.
2. [ ] Audit libxml2/libxslt configuration and transitive dependencies.
3. [ ] Add XML, XPath, and XSLT smoke tests.
4. [ ] Stage and validate the package outside MSYS2.

## Guardrails

- Do not load dependency DLLs from MSYS2 or the current directory accidentally.
- Disable or constrain network access in parser tests.

## Validation Plan

- Parse and transform UTF-8 documents from a path containing spaces.
- Inspect PE imports and run with a sanitized environment.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
