# TODO-36 - Windows pure-liblo Package

Status: Open
Branch: todo/36-windows-pure-liblo

## Purpose

Build, validate, and package `pure-liblo` for OSC communication on Windows.

## Scope

- Use a controlled CLANG64 liblo build and native Winsock dependencies.
- Cover OSC messages, bundles, servers, callbacks, errors, and shutdown.
- Keep all automated network traffic on loopback.

## Task List

1. [ ] Build the package against the staged Pure runtime and liblo.
2. [ ] Audit socket, thread, GMP, and transitive DLL dependencies.
3. [ ] Add loopback client/server and callback smoke tests.
4. [ ] Stage and validate the package outside MSYS2.

## Guardrails

- Tests must use bounded timeouts and release server threads reliably.
- Do not require public network access or firewall exceptions.

## Validation Plan

- Exchange OSC messages and bundles over loopback and verify callback data.
- Inspect PE imports and run with a sanitized environment.

## Progress Log

- 2026-07-25: Created as an optional networking Windows package candidate.
