# TODO-36 - Windows pure-liblo Package

Status: Closed on 2026-07-28
Branch: todo/36-windows-pure-liblo

## Purpose

Build, validate, and package `pure-liblo` for OSC communication on Windows.

## Scope

- Use a controlled CLANG64 liblo build and native Winsock dependencies.
- Cover OSC messages, bundles, servers, callbacks, errors, and shutdown.
- Keep all automated network traffic on loopback.

## Task List

1. [x] Build the package against the staged Pure runtime and liblo.
2. [x] Audit socket, thread, GMP, and transitive DLL dependencies.
3. [x] Add loopback client/server and callback smoke tests.
4. [x] Stage and validate the package outside MSYS2.

## Guardrails

- Tests must use bounded timeouts and release server threads reliably.
- Do not require public network access or firewall exceptions.

## Validation Plan

- Exchange OSC messages and bundles over loopback and verify callback data.
- Inspect PE imports and run with a sanitized environment.

## Progress Log

- 2026-07-25: Created as an optional networking Windows package candidate.
- 2026-07-28: Added a controlled CLANG64 build for pure-liblo.
  - CMake downloads official liblo 0.36 and verifies SHA-256
    `c08d14832e8dcf8f06840405824a4f9611a0cb3daed0198946326c740941c8b6`.
  - The wrapper was adapted to the pinned liblo 0.36 opaque structure layout
    and compiles as a COFF x86-64 `lo.dll` with strict warnings.
  - Commit: `3ee6eb1a` (`Build pure-liblo on Windows`).
- 2026-07-28: Audited the Windows dependency closure.
  - `lo.dll` imports `liblo.dll`, the shared `libpure.dll` and
    `libgmp-10.dll`, UCRT, and Windows system APIs.
  - `liblo.dll` uses native Winsock and IP Helper APIs. Neither binary imports
    an MSYS, GCC, or C++ runtime; the only package-specific runtime delta is
    `liblo.dll`.
  - Commit: `2c834cac` (`Audit pure-liblo Windows dependencies`).
- 2026-07-28: Added bounded OSC loopback coverage.
  - The test exchanges a mixed message and an immediate bundle through
    `127.0.0.1`, verifies callback data and error reporting, and explicitly
    stops and frees the server thread.
  - CTest enforces a 30-second outer timeout and the runner enforces a
    25-second inner timeout.
  - Commit: `c7533757` (`Test pure-liblo OSC loopback`).
- 2026-07-28: Staged and inspected the portable Windows package.
  - Installing into a fresh 40-file runtime added exactly 14 files and removed
    none: `lo.dll`, two Pure interfaces, `liblo.dll`, package/upstream licenses,
    Windows notes, four examples, and the loopback test.
  - The installed verifier passed with `PURELIB` unset and `PATH` restricted
    to the staged `bin` and Windows system directories. It rechecked the
    Pure/GMP hashes, loopback behavior, shutdown, and complete PE closure.
  - A negative configure test rejected `PURE_LIBRARY_INSTALL_DIR=../escape`.