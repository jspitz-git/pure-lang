# TODO-45 - Windows pure-bonjour Package

Status: Open
Branch: todo/45-windows-pure-bonjour

## Purpose

Ship `pure-bonjour` on x86-64 Windows 10 and later through Microsoft's system
DNS Service Discovery API, without installing or redistributing Apple's
Bonjour for Windows product.

## Scope

- Use `DnsServiceRegister`, `DnsServiceBrowse`, and `DnsServiceResolve` from the
  Windows SDK and system `dnsapi.dll`.
- Build the bridge with CLANG64 and validate bounded registration, discovery,
  resolution, cancellation, relocation, and removal.
- Package only the exact optional `PureBonjour` component and document its
  local-link/firewall boundary and lack of a third-party service dependency.

## Task List

1. [x] Resolve SDK availability, licensing, and redistribution terms.
2. [x] Build the module against the selected Windows implementation.
3. [x] Add bounded loopback registration and discovery tests.
4. [ ] Decide whether to bundle, externally detect, or defer the package.

## Guardrails

- Do not copy Bonjour binaries without confirmed redistribution permission.
- Tests must not publish persistent services or rely on public networks.

## Validation Plan

- Register, discover, resolve, and remove a temporary local service.
- Verify bounded API rejection, cancellation, firewall/policy denial, and an
  empty no-result window; Windows has no optional Bonjour daemon to remove.

## Open Questions

- Final ship-or-defer remains gated on the clean `windows-2025` workflow and
  independent inspection of its `windows-pure-bonjour` artifact. The selected
  runtime is the Windows 10+ system `dnsapi.dll`; no redistributable third-party
  Bonjour runtime is part of the package.

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
    `InetNtopA`. Microsoft exposes the service port as an unqualified `WORD` and
    `DnsServiceConstructInstance` copies it unchanged, so registration and
    resolve use literal host-order values; deterministic regressions require
    `43210` at construction and `41000` in the Pure snapshot.
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
  - Fix round 1 strengthened callback and identity contracts. Browser cleanup now
    requires the terminal `ERROR_CANCELLED` browse callback, resolver cancellation
    receives the original resolver-owned cancel address, and case-insensitive
    per-FQDN generations prevent add/delete races and late old resolves while
    allowing remove/re-add. The Microsoft port `WORD` is now passed and read in
    host order. The expanded 25-function deterministic suite passed 10 consecutive
    runs in 23.69 seconds, and the exact seven-export audit remained unchanged.
- 2026-08-19: Added a bounded real-Pure registration/discovery/removal test for
  the Microsoft DNS-SD backend.
  - Windows DNS-SD has local-link mDNS but no Apple-style local-only interface
    constant. The test therefore browses `<type>.local` on interface scope 0 and
    advertises one process/time-unique ephemeral `.local` record. It uses no
    public endpoint and accepts the nonempty address returned by the local
    resolver; observed addresses included `172.30.128.1` and `192.168.50.248`.
  - The runner asks a loopback `TcpListener` bound to port 0 for an OS-selected
    ephemeral port, closes the listener, and passes that literal port to Pure.
    Both `check` and the independently resolved browse snapshot must report the
    exact same value, directly validating Microsoft's host-order `wPort` contract.
  - Real Windows callbacks exposed three API-contract corrections, each preceded
    by a deterministic fake regression: registration now supplies a nonempty
    `<computer>.local` host name, a PTR with TTL zero removes the service even
    when the version-1 callback omits its delete flag, and every non-null
    registration callback instance is freed inside callback quiescence.
  - The smoke runner stages only `bonjour.pure` and `bonjour.dll` in a unique
    temporary `PURELIB`, explicitly loads Pure's standard prelude, sanitizes
    `PATH` to exclude MSYS2, bounds the child at 25 seconds and CTest at 30
    seconds, and removes the temporary directory on success and handled failure.
    The local firewall and multicast policy permitted discovery; no policy-denial
    caveat was observed, and no Pure process remained after verification.
  - Validation:
    - The first clean `pure-bonjour-loopback` run passed in 4.45 seconds and
      emitted exactly `PURE_BONJOUR_LOOPBACK_OK` after explicit service removal
      and browser cleanup.
    - `ctest.exe --test-dir build/pure-bonjour -R
      "^pure-bonjour-loopback$" --repeat until-fail:5 --output-on-failure`
      passed five runs in 22.91 seconds (individual runs 4.47-4.66 seconds).
    - `ctest.exe --test-dir build/pure-bonjour -R
      "^pure-bonjour-(unit|lifecycle|loopback)$" --output-on-failure` passed all
      three tests in 7.54 seconds. The deterministic suites now contain 30 named
      test functions.
- 2026-08-19: Added exact optional-component packaging and a fail-closed
  recursive PE dependency audit.
  - A default install owns none of the PureBonjour paths. Installing component
    `PureBonjour` owns exactly eight files; its seven non-inventory payloads are
    described by `PureBonjourInventory.tsv`, while the non-installed trusted
    `PureBonjourExpected.sha256` oracle authenticates all eight paths, including
    the inventory itself.
  - Installed size and SHA-256 evidence:

    | Relative path | Bytes | SHA-256 |
    | --- | ---: | --- |
    | `lib/pure/bonjour.dll` | 65536 | `313dd0c4578e2d3ce3587b57da93bea4e3c7cfc5ef01a581ff5ad4138cfb7921` |
    | `lib/pure/bonjour.pure` | 3430 | `c8e5413133079718936c19fafbcb1c84d44af02f778f79f949657760b5bd2a75` |
    | `share/doc/pure-bonjour/COPYING` | 35821 | `0b383d5a63da644f628d99c33976ea6487ed89aaa59f0b3257992deac1171e6b` |
    | `share/doc/pure-bonjour/COPYING.LESSER` | 7802 | `03c570a068086ee577dcd795519ea93462b2ed2fcb6dcc4dfce56a71a2fd6e5a` |
    | `share/doc/pure-bonjour/examples/bonjour_examp.pure` | 1944 | `0953f2a348248c1f9fb50c357af3bcb989cc62d9658a143399bd56c7f26596cd` |
    | `share/doc/pure-bonjour/PureBonjourInventory.tsv` | 1356 | `743c1066d158ef4cfa19cf1dfdea45a656ad4b2e1769c1fb14952665e03f2e6c` |
    | `share/doc/pure-bonjour/README` | 10192 | `6a49982a6933b75933e2cc774ee9450da1cd7cadd7f88acc0200a565f04efe32` |
    | `share/doc/pure-bonjour/WINDOWS.md` | 269 | `1314752f1538d03dac9b9071c7e241a8ed123dd51ad314228b2d3adda3689552` |
  - The recursive audit traversed 11 PE files and 126 import edges rooted at
    `bonjour.dll`. Every non-system import resolved case-insensitively beneath
    the staged Pure `bin` directory, no Apple Bonjour or MSYS2 runtime was found,
    and the module retained exactly its seven public bridge exports.
  - Synthetic parser mutations reject a malformed llvm-readobj header,
    undeclared DLL, `dnssd.dll`, and ambiguous case-folded duplicate with the
    stable `IMPORTS_MALFORMED`, `IMPORT_UNKNOWN`, `IMPORT_FORBIDDEN`, and
    `IMPORT_AMBIGUOUS` categories. Absolute and parent-traversing values are
    rejected for all three install destination variables.
  - Validation:
    - `ctest.exe --test-dir build/pure-bonjour -R
      "^pure-bonjour-(install-component|dependency-parser|install-destinations)$"
      --output-on-failure` passed all three packaging tests in 2.37 seconds.
    - `cmake.exe --build build/pure-bonjour --target
      verify-windows-dependencies` passed with 11 PE files, 126 import edges,
      and exactly seven exports.
    - `ctest.exe --test-dir build/pure-bonjour -R
      "^pure-bonjour-install-component$" --output-on-failure` passed in 1.51
      seconds, and the full seven-test suite passed in 11.69 seconds.
- 2026-08-19: Added installed and relocated PureBonjour ownership verification.
  - The callable verifier accepts `STAGE_PREFIX`, `SOURCE_PREFIX`,
    `BUILD_PREFIX`, and `PURE_PREFIX`. It rejects reparse points before stage
    traversal, parses the installed inventory and external oracle independently,
    normalizes paths case-insensitively, and requires the exact eight-file
    external ownership set and exact seven-row installed payload set. The
    external `PureBonjourExpected.sha256` remains outside the mutable stage and
    is the only removal authority.
  - The accepted package contains exactly 8 owned files totaling 126350 bytes.
    `PureBonjourInventory.tsv` has SHA-256
    `743c1066d158ef4cfa19cf1dfdea45a656ad4b2e1769c1fb14952665e03f2e6c`.
    Prefix scanning covers source, build, and canonical stage spellings in
    UTF-8/ASCII and UTF-16LE, with forward/backslash and ASCII-case variants.
  - Twenty-two independent fresh-copy mutations are rejected: changed and
    missing payloads, undeclared package files, forged inventory metadata,
    duplicate/case-colliding/absolute/parent-traversing/malformed inventory and
    oracle rows, all three prefixes in both encodings, a mixed-case spelling,
    and a directory junction. Mutation cleanup never targets the original stage
    or any unrelated file.
  - A complete Pure runtime plus component was installed at
    `Relocation Ownership/Installed Pure Č`, copied to
    `Relocation Ownership/Relocated Pure Ž`, verified and smoke-tested at both
    locations, and overlaid at the relocated prefix. Pure 0.68 passes script
    paths through the active narrow Windows code page, so the smoke runner uses
    scoped ASCII junction aliases outside the audited stage for the same
    physical relocated files; every alias is explicitly removed after the run.
  - Exact removal driven only by the external oracle preserves byte-identical
    unrelated sentinels and an unrelated empty directory. The same result holds
    after the installed inventory is forged to claim an unrelated sentinel.
    Only now-empty `share/doc/pure-bonjour` directories are removed.
  - The recursive dependency audit remains 11 PE files and 126 import edges,
    with the exact seven bridge exports and the previously recorded exact API-set
    allowlist.
  - Validation:
    - `ctest.exe --test-dir build/pure-bonjour -R
      "^pure-bonjour-(package-verifier|package-mutations|relocation-ownership)$"
      --output-on-failure` passed all three focused tests in 50.07 seconds before
      the additional mixed-case regression; the mutation and relocation tests
      then passed independently in 27.81 and 56.23 seconds.
    - The final fresh focused run passed 3/3 in 92.58 seconds, and
      `ctest.exe --test-dir build/pure-bonjour --output-on-failure` passed the
      complete 10/10 suite in 89.69 seconds of summed test time.
- 2026-08-19: Task 6 security fix round 1 hardened removal and temporary
  ownership boundaries.
  - Exact removal now uses a standalone remover and the same strict external
    oracle parser as verification. It completes a no-follow preflight before
    deleting anything, then revalidates canonical containment and every parent
    immediately before deleting each exact file. Only verified ordinary empty
    `share/doc/pure-bonjour/examples` and `share/doc/pure-bonjour` directories
    are removed, non-recursively.
  - The oracle must be an ordinary non-reparse file with a canonical path
    outside the protected prefix. Noncanonical spellings, in-prefix authority,
    and an authority reached through a junction all fail before removal.
  - Verifier scratch and smoke state is created beneath audited canonical roots
    in unpredictable, non-preexisting children. Preexisting scratch junctions
    are unlinked without following and rejected; cleanup performs no-follow
    revalidation and reports any controlled leftover on every alias failure.
    Both aliases must resolve canonically to their intended audited targets.
  - Prefix scanning retains raw UTF-8/UTF-16LE byte detection and additionally
    decodes valid text with .NET `OrdinalIgnoreCase`, covering non-ASCII Windows
    case changes such as `Č`/`č` and `Ž`/`ž` for source, build, and stage paths.
  - The expanded verifier matrix has 32 fresh-copy mutation cases. Removal adds
    adversarial `lib/pure` and package-document junctions, noncanonical,
    in-prefix, and reparse oracle cases; every case hashes isolated unrelated
    sentinels and proves no owned file was deleted before rejection.
  - A self-review leftover assertion exposed a scoped scratch variable collision
    with the dependency verifier. The regression failed first, then passed after
    the package-owned scratch child received a distinct variable and was
    centrally cleaned.
  - Fresh post-review focused validation passed all three installed-package
    tests in 170.05 seconds (10.99, 69.98, and 89.07 seconds respectively).
    The subsequent full suite passed 10/10 in 178.61 seconds of summed test
    time; relocation/removal took 88.72 seconds and local-link loopback 3.79.
- 2026-08-19: Task 6 security fix round 2 closed binary prefix and scratch
  pre-mutation gaps.
  - Unicode prefix scanning now uses replacement fallback rather than skipping
    an entire arbitrary/binary file after one invalid byte. Every file is
    decoded as UTF-8 and as UTF-16LE at both byte alignments; odd tails are
    trimmed safely, while exact raw-byte matching remains in place.
  - New fresh-copy cases embed a Czech case-changed canonical prefix between
    invalid UTF-8 bytes and after one leading byte before UTF-16LE. Both are
    rejected as `PACKAGE_PREFIX`, expanding the verifier matrix to 37 cases.
  - Scratch protection is now decided before unlink or creation. The verifier
    checks the normalized lexical location, canonicalizes an ordinary no-follow
    parent and combines only the basename, read-only probes an existing entry,
    and checks a reparse target canonically before any permitted unlink.
    A junction under a protected runtime remains present and byte-identical on
    rejection; missing children under stage and runtime are never created.
  - An explicitly enabled test-only post-preflight hook replaces `lib/pure`
    after the complete removal preflight. The first exact file deletion's fresh
    no-follow walk rejects that junction as `PACKAGE_PATH`; unrelated and owned
    sentinels remain byte-identical, directly proving removal-time revalidation.
  - Fresh focused validation passed 3/3 in 214.58 seconds (12.27, 89.73, and
    112.57 seconds). The subsequent full suite passed 10/10 in 223.23 seconds;
    the local-link loopback remained bounded at 3.80 seconds.
- 2026-08-19: Documented the Windows backend and added the clean-runner CI
  contract and `windows-pure-bonjour` job without triggering remote CI.
  - The source-owned `WINDOWS.md` now records the Windows 10+ x86-64 baseline,
    CLANG64 commands, Microsoft `dnsapi.dll` backend, exact eight-path manifest,
    local-link/firewall scope, API/no-result/cancellation diagnostics, installed
    verification, licensing boundary, and exact removal behavior. Pure 0.68
    Unicode relocation is documented as using target-verified scoped ASCII
    junction aliases which are explicitly removed after use.
  - `Install.cmake` installs and hashes that full source document instead of
    generating the former concise file. The exact path set remains eight files;
    the refreshed component is 132678 bytes and its inventory is 1357 bytes
    with SHA-256
    `bbd17101a1175ed342f515ccd05feb751c5e2c8f1bd0d4327e93947edcb7ff36`.
  - The workflow contract was run before the YAML edit and failed with the
    expected `CI_CONTRACT_JOB` token because the job was absent. It now locks
    the five path triggers, job identity, checkout path containing spaces,
    exact CLANG64 prerequisite block, matching staged Pure build, absolute
    `PURE_PREFIX`, Ninja build, Bonjour-labeled CTest, component-only install,
    MSYS2/PURELIB-sanitized verifier, two stable-metadata ordinal ZIP builds,
    equal SHA-256, and the `windows-pure-bonjour` v4 artifact plus summary.
  - Fresh local validation passed the CI contract alone in 0.88 seconds and the
    complete Bonjour-labeled suite in 223.15 seconds. All ten pre-existing tests
    remained green and the new contract made the result 11/11. The real
    local-link test then passed five consecutive runs in 19.09 seconds.
  - The recursive audit still reports 11 PE files, 126 import edges, and exactly
    seven public exports. Source README matches are limited to its two intentional
    `@version@` occurrences and one `|today|` template marker; fresh generated
    and staged README/WINDOWS files contain no unresolved marker. The fresh
    staged Windows notes hash exactly matches the source at
    `74a9737a75fb9c84ea2417071a83ab10f8d78baa9b8e0e36c0ab242b05a495f4`.
  - Self-review found that the setup action's installed MSYS tools were probed
    by absolute path but not explicitly placed on later PowerShell-step search
    paths. A new contract assertion first failed with `CI_CONTRACT_TOOLS`; the
    workflow now writes both roots to `GITHUB_PATH`, keeps CLANG64 first, and the
    contract passes in 0.92 seconds. PowerShell's parser then accepted all six
    Windows job script blocks without syntax errors. The final post-review full
    suite passed 11/11 in 223.27 seconds.
  - Remote clean-runner execution and independent artifact inspection remain a
    Task 8 gate, so this TODO stays open and no ship decision is recorded yet.
