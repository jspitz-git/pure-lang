# TODO-25 - Windows pure-sockets Package

Status: Closed on 2026-07-27
Branch: todo/25-windows-pure-sockets

## Purpose

Build and validate `pure-sockets` using native Winsock in the portable Windows
distribution.

## Scope

- Exercise the existing Windows-specific implementation and `ws2_32` linkage.
- Cover address handling, TCP, UDP, cleanup, and error propagation.
- Avoid requiring Unix compatibility layers at runtime.

## Task List

1. [x] Build the module with CLANG64 and the staged runtime.
2. [x] Audit Winsock initialization, shutdown, handles, and error translation.
3. [x] Add loopback TCP and UDP smoke tests.
4. [x] Stage and validate the package outside MSYS2.

## Guardrails

- Tests must use loopback and must not depend on public network availability.
- Socket resources must be released on success and failure paths.

## Validation Plan

- Exchange data over loopback TCP and UDP with bounded timeouts.
- Repeat initialization and shutdown in one process and inspect PE imports.

## Installed Package Manifest

- `lib/pure/sockets.dll`
- `lib/pure/sockets.pure`
- `share/doc/pure-sockets/README`
- `share/doc/pure-sockets/COPYING`
- `share/doc/pure-sockets/COPYING.LESSER`
- `share/doc/pure-sockets/examples/dgram.pure`
- `share/doc/pure-sockets/examples/stream.pure`

## Runtime Dependencies

- `sockets.pure` loads `lib/pure/sockets.dll`.
- `sockets.dll` directly imports `WS2_32.dll` and `libpure.dll`, plus Windows
  system and UCRT libraries.
- Windows supplies Winsock, and the base portable runtime already supplies
  `libpure.dll`. The package therefore adds no dependency DLL copies.

## Progress Log

- 2026-07-25: Created as a base Windows package candidate.
- 2026-07-27: Built and loaded the native module with the CLANG64 toolchain.
  - The unchanged legacy Makefile builds against the portable Pure 0.68 SDK
    and links Winsock through `ws2_32`.
  - Added a reproducible CMake module target with an explicit `pure>=0.68`
    requirement and Windows-only `ws2_32` linkage.
  - The resulting PE32+ x86-64 DLL exports all 31 module entry points. Its only
    nonsystem direct imports are `WS2_32.dll` and `libpure.dll`.
  - Clang reports three inconsistent-`dllimport` warnings for the legacy manual
    declarations of `freeaddrinfo`, `getaddrinfo`, and `getnameinfo`; these are
    retained for the Winsock ABI and lifecycle audit in task 2.
  - Validation:
    - `C:\msys64\usr\bin\bash.exe -lc "export PATH=/clang64/bin:/usr/bin;
      export
      PKG_CONFIG_PATH=/c/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig;
      cd /c/pure-lang/pure-sockets; mingw32-make clean;
      mingw32-make CC=clang V=1"` passed with Clang 22.1.8 and the three noted
      declaration warnings.
    - A clean Ninja Release configuration in
      `C:\tmp\pure-sockets-build-step1-20260727` found Pure 0.68 and built
      `sockets.dll` with CLANG64 Clang 22.1.8.
    - `llvm-readobj --file-headers --coff-imports --coff-exports` confirmed
      x86-64 architecture, 31 exports, direct Winsock linkage, and no MSYS2
      runtime DLL dependency.
    - From `C:\Windows`, with `PURELIB` unset and `PATH` restricted to the
      portable runtime plus Windows system directories, Pure loaded the
      CMake-built module, resolved `127.0.0.1`, and emitted
      `PURE_SOCKETS_LOAD_OK`.
- 2026-07-27: Audited and corrected the Windows socket ABI and lifecycle.
  - Socket handles now use `int64_t` in the C wrappers and `int64` in the Pure
    declarations, preserving the pointer-sized Winsock `SOCKET` value on
    64-bit Windows. All wrappers convert through `uintptr_t`.
  - `recv`, `send`, `recvfrom`, and `sendto` now return signed 64-bit counts,
    so `SOCKET_ERROR` remains `-1` instead of becoming a large `size_t` value.
    Oversized Winsock buffer lengths fail with `WSAEMSGSIZE`.
  - Winsock startup is idempotent, checks the requested 2.2 initialization,
    registers one process-exit cleanup, and pairs it with a locked,
    repeat-safe cleanup operation. Address resolution and socket creation
    ensure that Winsock is active.
  - Removed obsolete manual declarations already supplied by `ws2tcpip.h`;
    the module now compiles cleanly with strict warnings.
  - Added `socket_errno` and `socket_strerror` so Windows callers use
    `WSAGetLastError` and readable system messages instead of POSIX `errno`.
  - Validation:
    - A clean Ninja Release build in
      `C:\tmp\pure-sockets-build-step2-20260727` passed with CLANG64 Clang
      22.1.8 and `-Wall -Wextra -Werror`.
    - `pure-sockets-winsock-audit` passed in 0.10 seconds with `PATH`
      restricted to the portable runtime and Windows system directories. It
      verified two startup calls, two cleanup calls, restart, UDP and TCP
      handle open/close, unconnected socket shutdown, `WSAENOTCONN`, and
      `WSAENOTSOCK` translation in one process.
    - The legacy Makefile also rebuilt with
      `CFLAGS="-O3 -Wall -Wextra -Werror"` without warnings.
    - From `C:\Windows`, Pure loaded the audited module, opened and closed a
      socket through the 64-bit declarations, preserved a `recv` failure as
      `-1`, translated its Winsock error, and emitted
      `PURE_SOCKETS_ABI_AUDIT_OK`.
    - `llvm-readobj` confirmed a PE32+ x86-64 DLL with 35 exports, including
      the four lifecycle/error audit functions; its only nonsystem imports
      remain `WS2_32.dll` and `libpure.dll`.
- 2026-07-27: Added bounded TCP and UDP loopback smoke coverage.
  - The Pure test binds IPv4 listeners to `127.0.0.1` with port zero and reads
    back each OS-assigned ephemeral port; it contains no public network
    address or fixed port dependency.
  - The TCP path listens, connects, accepts, validates the peer address,
    exchanges serialized request and response payloads in both directions,
    and closes all three socket handles.
  - The UDP path sends a serialized datagram to the bound receiver, validates
    both payload and sender address, and closes both handles.
  - Every socket has 2-second send and receive timeouts. The CMake runner also
    terminates Pure after 25 seconds, while CTest enforces a 30-second limit.
    Failure paths close every handle opened by the current phase before
    reporting the platform socket error.
  - Validation:
    - A clean Ninja Release build in
      `C:\tmp\pure-sockets-build-step3-20260727` found Pure 0.68 and passed
      with CLANG64 Clang 22.1.8 and `-Wall -Wextra -Werror`.
    - From `C:\Windows`, with `PURELIB` unset and `PATH` restricted to the
      portable runtime plus Windows system directories,
      `ctest --output-on-failure -V` passed both
      `pure-sockets-winsock-audit` and `pure-sockets-loopback` (2/2).
    - The loopback test completed in 5.50 seconds and emitted
      `PURE_SOCKETS_LOOPBACK_OK`; the native audit completed in 0.12 seconds.
    - `ctest -R "^pure-sockets-loopback$" --repeat until-fail:3
      --output-on-failure` passed three consecutive loopback runs in 17.47
      seconds, confirming that dynamic ports and socket resources are released
      between processes.
- 2026-07-27: Added a prefix-contained installation and closed TODO-25.
  - The installation adds exactly the seven files listed in the package
    manifest: the Pure source and native module, generated README, both license
    files, and two examples.
  - The README records version 0.8 and the installation date, with no remaining
    template markers or build-machine paths.
  - A file-by-file comparison with the base portable runtime confirmed that no
    existing file was removed or replaced. The only new DLL is the
    `sockets.dll` module itself; no dependency DLL is duplicated.
  - All install destinations must be relative and remain below
    `CMAKE_INSTALL_PREFIX`; separate negative configurations rejected both a
    parent-directory component and an absolute documentation path.
  - Validation:
    - A clean Release build in
      `C:\tmp\pure-sockets-package-build-step4-20260727` passed with CLANG64
      Clang 22.1.8 and `-Wall -Wextra -Werror`.
    - With `PATH` restricted to a fresh portable runtime plus Windows system
      directories, both CTests passed before installation: the native audit in
      0.11 seconds and the TCP/UDP loopback test in 5.29 seconds.
    - The same native audit and full marker-checked loopback test passed from
      `C:\Windows` against the installed `lib/pure/sockets.dll` and
      `lib/pure/sockets.pure`, with `PURELIB` unset and no MSYS2 directory in
      `PATH`.
    - `llvm-readobj` confirmed a PE32+ x86-64 module with 35 exports and only
      `WS2_32.dll`, `libpure.dll`, Windows system libraries, and UCRT imports.
      The staged `bin/libpure.dll` satisfies the only nonsystem runtime
      dependency.
