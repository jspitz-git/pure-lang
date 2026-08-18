# TODO-45 - Windows pure-bonjour Package

Status: Open
Branch: todo/45-windows-pure-bonjour

## Purpose

Determine whether `pure-bonjour` can be legally and technically supported with
an available Windows Bonjour implementation.

## Scope

- Identify a redistributable `dns_sd` SDK/runtime and its supported architectures.
- Build the bridge and validate service registration and discovery.
- Document any external Bonjour installation requirement.

## Task List

1. [ ] Resolve SDK availability, licensing, and redistribution terms.
2. [ ] Build the module against the selected Windows implementation.
3. [ ] Add bounded loopback registration and discovery tests.
4. [ ] Decide whether to bundle, externally detect, or defer the package.

## Guardrails

- Do not copy Bonjour binaries without confirmed redistribution permission.
- Tests must not publish persistent services or rely on public networks.

## Validation Plan

- Register, discover, resolve, and remove a temporary local service.
- Verify clean behavior when the Bonjour service is absent.

## Open Questions

- Which maintained and redistributable Windows Bonjour runtime is suitable.

## Progress Log

- 2026-07-25: Created as an optional networking Windows package investigation.
- 2026-08-18: Added the Windows-only CMake module target, private UTF/name/status
  helpers, and deterministic native unit-test target for the Microsoft DNS-SD backend.
  - Validation:
    - `C:\msys64\clang64\bin\cmake.exe --version` reported 4.4.0;
      `clang.exe --version` reported 22.1.8; `ninja.exe --version` reported
      1.13.2; and `pkg-config.exe --version` reported 3.0.4.
    - With `PKG_CONFIG_PATH=C:\pure-lang\pure\build\windows-clang64-prefix\lib\pkgconfig`,
      `C:\msys64\clang64\bin\pkg-config.exe --modversion pure` reported 0.68.
    - `clang.exe -std=c11 -Wall -Wextra -Werror -D_WIN32_WINNT=0x0A00
      -DBONJOUR_WINDOWS_TESTING -Ipure-bonjour -fsyntax-only
      pure-bonjour/tests/unit.c pure-bonjour/bonjour_windows.c` passed without
      diagnostics.
    - `cmake.exe -S pure-bonjour -B build/pure-bonjour -G "MinGW Makefiles"
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe
      -DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/mingw32-make.exe
      -DPKG_CONFIG_EXECUTABLE=C:/msys64/clang64/bin/pkg-config.exe`, followed by
      `cmake.exe --build build/pure-bonjour --verbose` and
      `ctest.exe --test-dir build/pure-bonjour --output-on-failure`, passed:
      `1/1` deterministic tests passed without warnings.
    - `llvm-readobj.exe --file-headers --coff-imports --coff-exports
      build/pure-bonjour/bonjour.dll` reported PE32+ x86-64. Its initial imports
      are `KERNEL32.dll` and UCRT API-set DLLs; it has no exports. This is
      expected before the later native bridge functions reference Pure/DNS-SD
      symbols; the private helpers remain unexported.
    - The requested Ninja-generator configuration still stalls after compiling
      CMake's ABI object and before the link/archive child process. The CLANG64
      MinGW Makefiles generator is the validated local workaround.
- 2026-08-18: Implemented bounded Microsoft DNS-SD registration and cleanup.
  - The deterministic fake-API lifecycle test covers immediate registration
    rejection, `PENDING -> REGISTERED` callback completion with an effective
    conflict-renamed instance, a bounded `check` timeout, pending cancellation,
    `REGISTERED -> STOPPING -> STOPPED` deregistration, callback completion
    during cancellation, instance release ordering, and repeated null cleanup.
  - Registration callback state is synchronized with one SRW lock, one
    manual-reset completion event, a callback counter, and a condition variable.
    Production `check` waits at most 10 seconds. Shutdown calls cancellation or
    deregistration without holding the lock, bounds both completion and callback
    waits, and retains callback-visible state with an explicit diagnostic if
    quiescence cannot be established safely.
  - The CLANG64 MinGW Makefiles build completed with strict warnings, and both
    deterministic tests passed. The lifecycle test passed 10 consecutive runs
    in 28.82 seconds with CTest's 10-second per-test timeout enabled.
- 2026-08-18: Implemented Microsoft DNS-SD browse, resolve, snapshot, removal,
  and bounded discovery shutdown.
  - Results are deep-owned and keyed by resolved service FQDN plus the documented
    `DNS_SERVICE_INSTANCE.dwInterfaceIndex`; identical resolves do not signal a
    change. Because the version-1 browse callback has no interface field, its
    resolver uses interface scope 0 and PTR deletion removes every resolved
    interface entry for the matching FQDN.
  - Every non-null browse RR list is freed exactly once, and every non-null
    resolve instance is freed exactly once. IPv4 and IPv6 addresses use
    `InetNtopA`. The installed Windows SDK declares `wPort` as the same `WORD`
    used by construction and resolve; the registration fixture observes network
    order and the resolve regression requires `ntohs(htons(41000)) == 41000` in
    the Pure snapshot.
  - Discovery cancellation marks closing under the SRW lock, invokes browse and
    resolver cancellation without the lock, and waits with a production limit of
    10 seconds for dispatches, callbacks, and resolver contexts to quiesce.
    Timeout or cancellation failure emits a diagnostic and retains all
    callback-visible state; repeated close does not retry or free retained state.
  - The strict CLANG64 MinGW Makefiles build passed. The two deterministic CTests
    contain 21 named test functions (10 added for result/discovery behavior) and
    passed 10 consecutive runs in 30.85 seconds. The DLL exports exactly the
    seven bridge symbols: `bonjour_avail`, `bonjour_browse`, `bonjour_check`,
    `bonjour_close`, `bonjour_get`, `bonjour_publish`, and `bonjour_unpublish`.
