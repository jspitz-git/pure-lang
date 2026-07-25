# TODO-25 - Windows pure-sockets Package

Status: Open
Branch: todo/25-windows-pure-sockets

## Purpose

Build and validate `pure-sockets` using native Winsock in the portable Windows
distribution.

## Scope

- Exercise the existing Windows-specific implementation and `ws2_32` linkage.
- Cover address handling, TCP, UDP, cleanup, and error propagation.
- Avoid requiring Unix compatibility layers at runtime.

## Task List

1. [ ] Build the module with CLANG64 and the staged runtime.
2. [ ] Audit Winsock initialization, shutdown, handles, and error translation.
3. [ ] Add loopback TCP and UDP smoke tests.
4. [ ] Stage and validate the package outside MSYS2.

## Guardrails

- Tests must use loopback and must not depend on public network availability.
- Socket resources must be released on success and failure paths.

## Validation Plan

- Exchange data over loopback TCP and UDP with bounded timeouts.
- Repeat initialization and shutdown in one process and inspect PE imports.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
