# TODO-45 - Windows pure-bonjour Package

Status: Closed on 2026-08-19
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
4. [x] Ship the optional package with the Microsoft system DNS-SD backend.

## Guardrails

- Do not copy Bonjour binaries without confirmed redistribution permission.
- Tests must not publish persistent services or rely on public networks.

## Validation Plan

- Register, discover, resolve, and remove a temporary local service.
- Verify bounded API rejection, cancellation, firewall/policy denial, and an
  empty no-result window; Windows has no optional Bonjour daemon to remove.

## Final Decision

- Ship `PureBonjour` as an optional Windows component. It uses the Windows 10+
  system `dnsapi.dll`; no Apple Bonjour or other third-party service runtime is
  installed or redistributed. The exact Windows clean-runner job and its
  independently downloaded artifact passed the release gate described below.

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
- 2026-08-19: Task 7 fix round 1 removed persistent toolchain state and made
  the workflow contract indentation-aware and exclusivity-sensitive.
  - The first strengthened contract run failed with `CI_CONTRACT_PATH` because
    the job wrote CLANG64 and MSYS2 directories to `GITHUB_PATH`. The job no
    longer changes persistent PATH state. Tool discovery, Pure SDK build, and
    PureBonjour configure/build prepend CLANG64/MSYS2 only in their own
    PowerShell processes. CTest, component install/verifier, deterministic ZIP,
    and upload start with the staged Pure `bin` plus Windows system directories
    only; `PURELIB` is removed in every runtime-capable run step.
  - Pure SDK installation now uses the explicit build-system `install` target,
    leaving exactly one `cmake --install` in the job: the one install bounded by
    `--component PureBonjour`. The PureBonjour build command has no `--target`
    and therefore builds all configured targets. The artifact contains exactly
    one path, `windows-pure-bonjour.zip`; its concise hash/size evidence remains
    in the GitHub step summary rather than a second uploaded file.
  - The CMake contract explicitly describes itself as an indentation-aware
    parser for the exercised workflow subset, not a general YAML semantic
    parser. It extracts the job and named steps by indentation, validates exact
    properties inside the correct block, independently checks the exact six
    push and pull-request paths, compares the exact 13-package prerequisite set,
    and rejects persistent PATH, extra/targeted builds, unrestricted/duplicate
    installs, and extra or replacement upload paths. Twenty-four mutations
    cover comments, cross-step token moves, malformed indentation, both trigger
    mappings, missing/extra packages, PATH persistence/sanitization, build and
    install exclusivity, and ZIP upload exclusivity; every mutation must fail
    with its intended stable category.
  - No dependency-free YAML semantic parser is installed (`ConvertFrom-Yaml`
    and Ruby are absent, and Python has no `yaml` module). PowerShell's parser
    accepted all six Windows job script blocks. The Windows guide now uses an
    absolute CLANG64 Ninja path, scopes the build PATH in `try`/`finally`, and
    explicitly restores it before component installation or runtime checks.
  - Focused component/verifier validation passed 2/2 in 13.11 seconds. The final
    full Bonjour suite passed 11/11 in 237.76 seconds; the strengthened contract
    took 6.60 seconds, relocation/removal 119.14 seconds, and the real local-link
    smoke 3.85 seconds. The unchanged exact eight-file package is 133095 bytes;
    its inventory SHA-256 is
    `fcf6e0bf00169f97c6e5d591837c7de6d97de5ef9ce378471354f5abafb3721d`,
    and source/staged `WINDOWS.md` share SHA-256
    `6b89ee56e54e68f56ecb0bb9ea3600d7fdabb249efcba792ec63e30a42dd5559`.
- 2026-08-19: Task 8 local-final validation completed; the clean-runner gate
  remains pending.
  - The binding fresh Ninja configure used `build/pure-bonjour-final` with
    Release, CLANG64 Clang, CLANG64 `pkg-config`, and the staged Pure prefix.
    It again stalled after `The C compiler identification is Clang 22.1.8` at
    `Detecting C compiler ABI info`. A bounded wrapper killed the complete
    process tree after 45.408 seconds; stderr was empty and a subsequent
    executable-name check found no remaining `cmake`, `ninja`, `clang`, linker,
    or LLVM archive process. Ninja did not pass.
  - The partial Ninja directory was removed after verifying its absolute path
    was the intended worktree `build/pure-bonjour-final`. The first fresh
    MinGW Makefiles fallback configure, matching the plan arguments, failed
    because the new shell did not have `PKG_CONFIG_PATH` and therefore could
    not locate `pure>=0.68`. That incomplete directory was also removed. With
    `PKG_CONFIG_PATH` scoped to
    `C:/pure-lang/pure/build/windows-clang64-prefix/lib/pkgconfig`, the fresh
    fallback configure found Pure 0.68 and completed configuration/generation
    in 1.4/0.4 seconds.
  - `C:\msys64\clang64\bin\cmake.exe --build
    build/pure-bonjour-final --verbose` completed at 100%. Every native compile
    used `-Wall -Wextra -Werror`, and the full output contained no diagnostics.
  - `C:\msys64\clang64\bin\ctest.exe --test-dir
    build/pure-bonjour-final -L bonjour --output-on-failure
    --no-tests=error` passed 11/11 in 237.32 seconds. This included the CI
    contract, packaging security matrices, installed/relocation ownership, and
    the real local-link loopback smoke, which passed in 3.81 seconds.
  - `C:\msys64\clang64\bin\cmake.exe --build
    build/pure-bonjour-final --target verify-windows-dependencies` passed with
    11 recursively inspected PE files, 126 import edges, and exactly seven
    exports.
  - Component-only install to the fresh spaces-and-Unicode path
    `build/PureBonjour final stage Č` produced exactly eight files. An
    independent `VerifyInstalledPackage.cmake` invocation accepted all eight,
    totaling 133095 bytes, with inventory SHA-256
    `86aa862c441591227c29d083360daa6c3e7dcdc515bd0b9085304df158d6dc81`;
    it repeated the 11-PE/126-edge dependency closure and passed the installed
    smoke with its sanitized child environment.
  - No branch push, workflow run, artifact download, or other external action
    was performed. Successful `windows-pure-bonjour` clean-runner job evidence
    and independent inspection of its `windows-pure-bonjour` artifact remain
    required. The final ship decision stays unchecked and TODO-45 stays Open.
- 2026-08-19: Completed the clean-runner and independent artifact gate for
  commit `1f05af6f75a7d4ca2a0e94a83096e4446f50b68c`.
  - Workflow run `32276057210` is at
    <https://github.com/jspitz-git/pure-lang/actions/runs/32276057210>.
    The successful Windows job is at
    <https://github.com/jspitz-git/pure-lang/actions/runs/32276057210/job/96143650236>.
    Its `Windows PureBonjour package` job `96143650236` succeeded in 9 minutes
    10 seconds with every step green: exact toolchain/Pure SDK staging,
    PureBonjour build, the complete test label, installed verifier,
    deterministic ZIP creation, and artifact upload. The complete label passed
    13/13 tests in 261.96 seconds. The installed verifier accepted exactly 8
    files totaling 131706 bytes, inventory SHA-256
    `7478c25b14d62976be7bf271cd10c91d01560e03d252c5aad653a5c89624170e`,
    11 PE files, 126 import edges, and exactly seven exports.
  - The overall workflow conclusion is red only because the parallel
    `macOS 15 arm64` job `96143650667` failed its complete Release tests. That
    job is outside TODO-45; the Windows job did not fail, skip, or depend on it.
  - The authenticated `windows-pure-bonjour` artifact was downloaded to the
    new controlled path `build/Task 8 artifact download 1f05 Č`. Before
    extraction, its sole payload ZIP was opened read-only and accepted exactly
    the eight ordinal package paths, with no directory, empty, rooted, UNC,
    drive, backslash, dot-segment, duplicate, or case-colliding entry. The ZIP
    is 52091 bytes with SHA-256
    `d2505ba8c2e0996a348cf45cd06a854cf61ed0beb8c39dc18ff293366001eedd`.
    GitHub's job log exposes the uploaded artifact wrapper size (51668 bytes)
    and wrapper digest, but not the expanded step-summary values, so the inner
    ZIP size/hash could not be compared to that summary through `gh`.
    Artifact metadata is identified by ID `9374344930` at
    <https://api.github.com/repos/jspitz-git/pure-lang/actions/artifacts/9374344930>;
    its authenticated archive endpoint is
    <https://api.github.com/repos/jspitz-git/pure-lang/actions/artifacts/9374344930/zip>.
  - Safe streaming extraction to the fresh spaces-and-Unicode path
    `build/Task 8 artifact inspection Ž/Extracted package Č` produced exactly
    the same eight files. All seven inventory payload rows matched their file
    sizes and SHA-256 values. The inventory's independently computed SHA-256
    exactly matches the clean job value above, binding the downloaded bytes to
    the verifier that passed on the runner.
  - A local build oracle is intentionally byte-specific and therefore rejected
    the remote DLL/docs. Using a temporary oracle made from the already
    runner-bound artifact inventory only for the remaining structural checks,
    `VerifyInstalledPackage.cmake` accepted 8 files/131706 bytes and repeated
    the 11-PE/126-edge/seven-export result. This temporary oracle was not used
    as the independent hash authority; that authority is the clean job's exact
    logged inventory SHA-256 and successful external-oracle verification.
  - A separate fresh dependency work directory repeated the 11 PE files, 126
    import edges, no forbidden/unresolved imports, and exact seven exports.
    Direct loading from the Unicode spelling produced Windows loader error
    `0x7E`, the documented Pure 0.68 narrow-path limitation. The verifier's
    target-checked ASCII junction strategy and a second independent sanitized
    smoke both exercised the same canonical extracted files successfully with
    `PATH` limited to the matching Pure `bin` plus Windows system directories,
    no MSYS2 segment, and zero Pure processes before and after cleanup.
  - The Windows-specific release boundary is therefore satisfied. TODO-45 is
    complete and the optional Microsoft-backed PureBonjour package is approved
    to ship; the unrelated macOS workflow failure remains separate work.
  - Exact remote metadata and download commands (PowerShell, from the worktree
    root):

    ```powershell
    gh run view 32276057210 --repo jspitz-git/pure-lang `
      --json databaseId,headSha,headBranch,conclusion,status,url,jobs,createdAt,updatedAt
    gh run view 32276057210 --repo jspitz-git/pure-lang `
      --job 96143650236 --log | Select-String -Pattern `
      'tests passed|Test time|dependency audit passed|PE files|import edges|seven exact exports|Installed PureBonjour package verified|ZIP|SHA-256|sha256|bytes|Pure Windows SDK runtime closure'
    gh api repos/jspitz-git/pure-lang/actions/artifacts/9374344930
    $target = 'C:\pure-lang\.worktrees\todo-45-windows-pure-bonjour\build\Task 8 artifact download 1f05 Č'
    if (Test-Path -LiteralPath $target) { throw "target already exists: $target" }
    New-Item -ItemType Directory -Path $target | Out-Null
    gh run download 32276057210 --repo jspitz-git/pure-lang `
      --name windows-pure-bonjour --dir $target
    ```

  - Exact pre-extraction ZIP safety, inventory, and hash inspection used
    `System.IO.Compression.ZipArchiveMode.Read`; for every entry it rejected an
    empty name, directory, backslash, leading slash, UNC/drive root, `.`/`..`
    segment, exact duplicate, case-folded collision, or name outside the exact
    eight-path set. The executed inspection ended with:

    ```powershell
    Add-Type -AssemblyName System.IO.Compression
    $zipPath = 'C:\pure-lang\.worktrees\todo-45-windows-pure-bonjour\build\Task 8 artifact download 1f05 Č\windows-pure-bonjour.zip'
    $expected = @(
      'lib/pure/bonjour.dll',
      'lib/pure/bonjour.pure',
      'share/doc/pure-bonjour/COPYING',
      'share/doc/pure-bonjour/COPYING.LESSER',
      'share/doc/pure-bonjour/PureBonjourInventory.tsv',
      'share/doc/pure-bonjour/README',
      'share/doc/pure-bonjour/WINDOWS.md',
      'share/doc/pure-bonjour/examples/bonjour_examp.pure'
    )
    $item = Get-Item -LiteralPath $zipPath
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $stream = [IO.File]::OpenRead($zipPath)
    $zip = [IO.Compression.ZipArchive]::new(
      $stream, [IO.Compression.ZipArchiveMode]::Read, $false)
    try {
      $names = @($zip.Entries | ForEach-Object { $_.FullName })
      if ($names.Count -ne 8) { throw "entry count $($names.Count)" }
      $ordinal = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
      $folded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
      foreach ($entry in $zip.Entries) {
        $name = $entry.FullName
        if ([string]::IsNullOrEmpty($name) -or $name.EndsWith('/') -or
            $name.Contains('\') -or $name.StartsWith('/') -or
            $name.StartsWith('//') -or $name -match '^[A-Za-z]:' -or
            @($name.Split('/')) -contains '.' -or
            @($name.Split('/')) -contains '..') { throw "unsafe entry: $name" }
        if (-not $ordinal.Add($name)) { throw "duplicate entry: $name" }
        if (-not $folded.Add($name)) { throw "case collision: $name" }
        if ($expected -cnotcontains $name) { throw "unexpected entry: $name" }
      }
      foreach ($name in $expected) {
        if (-not $ordinal.Contains($name)) { throw "missing entry: $name" }
      }
    } finally { $zip.Dispose(); $stream.Dispose() }
    "ZIP_BYTES`t$($item.Length)"
    "ZIP_SHA256`t$hash"
    ```

  - Exact safe extraction created a previously absent
    `build/Task 8 artifact inspection Ž/Extracted package Č`, reopened the ZIP
    read-only, created each accepted parent incrementally, rejected every
    reparse parent and pre-existing file, and streamed each entry with
    `FileMode.CreateNew`:

    ```powershell
    $root = 'C:\pure-lang\.worktrees\todo-45-windows-pure-bonjour\build\Task 8 artifact inspection Ž'
    if (Test-Path -LiteralPath $root) { throw "inspection root already exists: $root" }
    New-Item -ItemType Directory -Path $root | Out-Null
    $extract = Join-Path $root 'Extracted package Č'
    New-Item -ItemType Directory -Path $extract | Out-Null
    $stream = [IO.File]::OpenRead($zipPath)
    $zip = [IO.Compression.ZipArchive]::new(
      $stream, [IO.Compression.ZipArchiveMode]::Read, $false)
    try {
      foreach ($entry in $zip.Entries) {
        $segments = $entry.FullName.Split('/')
        $destination = $extract
        for ($i = 0; $i -lt $segments.Length - 1; $i++) {
          $destination = Join-Path $destination $segments[$i]
          if (-not (Test-Path -LiteralPath $destination)) {
            New-Item -ItemType Directory -Path $destination | Out-Null
          }
          $directoryItem = Get-Item -LiteralPath $destination -Force
          if (($directoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "reparse directory: $destination"
          }
        }
        $destination = Join-Path $destination $segments[-1]
        if (Test-Path -LiteralPath $destination) {
          throw "pre-existing extraction target: $destination"
        }
        $input = $entry.Open()
        $output = [IO.File]::Open(
          $destination, [IO.FileMode]::CreateNew,
          [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $input.CopyTo($output) }
        finally { $output.Dispose(); $input.Dispose() }
      }
    } finally { $zip.Dispose(); $stream.Dispose() }
    ```

    External inventory verification then ran:

    ```powershell
    $extract = 'C:\pure-lang\.worktrees\todo-45-windows-pure-bonjour\build\Task 8 artifact inspection Ž\Extracted package Č'
    $inventoryPath = Join-Path $extract 'share/doc/pure-bonjour/PureBonjourInventory.tsv'
    $rows = @(Import-Csv -LiteralPath $inventoryPath -Delimiter "`t")
    if ($rows.Count -ne 7) { throw "inventory rows: $($rows.Count)" }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in $rows) {
      if (-not $seen.Add($row.relative_path)) {
        throw "duplicate inventory row: $($row.relative_path)"
      }
      $path = Join-Path $extract `
        $row.relative_path.Replace('/', [IO.Path]::DirectorySeparatorChar)
      $item = Get-Item -LiteralPath $path
      $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
      if ([string]$item.Length -cne $row.size -or $sha -cne $row.sha256) {
        throw "inventory mismatch: $($row.relative_path)"
      }
    }
    $inventorySha = (Get-FileHash -LiteralPath $inventoryPath `
      -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($inventorySha -cne `
        '7478c25b14d62976be7bf271cd10c91d01560e03d252c5aad653a5c89624170e') {
      throw "inventory oracle mismatch: $inventorySha"
    }
    ```

  - The first installed-verifier command used the local build oracle and
    correctly failed `PACKAGE_HASH` because the remote build is byte-distinct.
    The following exact command then created the clearly labeled temporary,
    artifact-derived `Remote oracle/PureBonjourExpected.sha256`. The explicit
    path array is ordinally sorted; hashing all eight extracted files includes
    the inventory's independently checked self-hash.

    ```powershell
    $inspectionRoot = [IO.Path]::GetFullPath(
      'C:\pure-lang\.worktrees\todo-45-windows-pure-bonjour\build\Task 8 artifact inspection Ž')
    $extract = [IO.Path]::GetFullPath((Join-Path $inspectionRoot 'Extracted package Č'))
    $oracleRoot = [IO.Path]::GetFullPath((Join-Path $inspectionRoot 'Remote oracle'))
    $oraclePath = Join-Path $oracleRoot 'PureBonjourExpected.sha256'
    $ownedPrefix = $inspectionRoot.TrimEnd('\') + '\'
    if (-not $oracleRoot.StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "oracle escaped inspection root: $oracleRoot"
    }
    if (Test-Path -LiteralPath $oracleRoot) {
      throw "oracle root already exists: $oracleRoot"
    }
    $oraclePaths = @(
      'lib/pure/bonjour.dll',
      'lib/pure/bonjour.pure',
      'share/doc/pure-bonjour/COPYING',
      'share/doc/pure-bonjour/COPYING.LESSER',
      'share/doc/pure-bonjour/PureBonjourInventory.tsv',
      'share/doc/pure-bonjour/README',
      'share/doc/pure-bonjour/WINDOWS.md',
      'share/doc/pure-bonjour/examples/bonjour_examp.pure'
    )
    $rows = foreach ($relative in $oraclePaths) {
      $file = Join-Path $extract `
        $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
      if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "artifact oracle input missing: $relative"
      }
      $sha = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
      "$sha  $relative"
    }
    if ($rows.Count -ne 8) { throw "oracle row count: $($rows.Count)" }
    New-Item -ItemType Directory -Path $oracleRoot | Out-Null
    [IO.File]::WriteAllLines(
      $oraclePath, $rows, [Text.UTF8Encoding]::new($false))
    Get-Content -LiteralPath $oraclePath
    ```

    The eight emitted rows, in order, were:

    ```text
    2a869ba14a170351322cf11a51d8efb84c50fa2f9d65538324a9d55b4d394756  lib/pure/bonjour.dll
    c8e5413133079718936c19fafbcb1c84d44af02f778f79f949657760b5bd2a75  lib/pure/bonjour.pure
    0b383d5a63da644f628d99c33976ea6487ed89aaa59f0b3257992deac1171e6b  share/doc/pure-bonjour/COPYING
    03c570a068086ee577dcd795519ea93462b2ed2fcb6dcc4dfce56a71a2fd6e5a  share/doc/pure-bonjour/COPYING.LESSER
    7478c25b14d62976be7bf271cd10c91d01560e03d252c5aad653a5c89624170e  share/doc/pure-bonjour/PureBonjourInventory.tsv
    562eb7733c773041151c40e3a10cae71b861ca11be98e4e26be6a7c02e01c831  share/doc/pure-bonjour/README
    c6efd4807ba9b62d622865e7dcbf96d2c1c65eb0c3fc5098d841687927a9fe78  share/doc/pure-bonjour/WINDOWS.md
    0953f2a348248c1f9fb50c357af3bcb989cc62d9658a143399bd56c7f26596cd  share/doc/pure-bonjour/examples/bonjour_examp.pure
    ```

    The exact remaining-check command was:

    ```powershell
    & 'C:/msys64/clang64/bin/cmake.exe' `
      '-DSTAGE_PREFIX=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/build/Task 8 artifact inspection Ž/Extracted package Č' `
      '-DSOURCE_PREFIX=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/pure-bonjour' `
      '-DBUILD_PREFIX=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/build/Task 8 artifact inspection Ž/Remote oracle' `
      '-DPURE_PREFIX=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/build/pure-sdk-regression-prefix' `
      -P pure-bonjour/cmake/VerifyInstalledPackage.cmake
    ```

    The temporary oracle was removed after use with a fresh containment and
    existence check:

    ```powershell
    $inspectionRoot = [IO.Path]::GetFullPath(
      'C:\pure-lang\.worktrees\todo-45-windows-pure-bonjour\build\Task 8 artifact inspection Ž')
    $oracleRoot = [IO.Path]::GetFullPath((Join-Path $inspectionRoot 'Remote oracle'))
    $ownedPrefix = $inspectionRoot.TrimEnd('\') + '\'
    if (-not $oracleRoot.StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "oracle escaped inspection root: $oracleRoot"
    }
    if (-not (Test-Path -LiteralPath $oracleRoot -PathType Container)) {
      throw "temporary oracle root missing: $oracleRoot"
    }
    $oracleItem = Get-Item -LiteralPath $oracleRoot -Force
    if (($oracleItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "temporary oracle root is a reparse point: $oracleRoot"
    }
    Remove-Item -LiteralPath $oracleRoot -Recurse
    if (Test-Path -LiteralPath $oracleRoot) {
      throw "temporary oracle root remains: $oracleRoot"
    }
    ```

    It was only a temporary structural-check input derived from the artifact
    under inspection and was never treated as the independent hash authority.

  - Exact independent PE/import/export audit command:

    ```powershell
    $audit = 'C:\pure-lang\.worktrees\todo-45-windows-pure-bonjour\build\Task 8 artifact inspection Ž\Independent dependency audit'
    if (Test-Path -LiteralPath $audit) { throw "audit path already exists: $audit" }
    & 'C:/msys64/clang64/bin/cmake.exe' `
      -DLLVM_READOBJ=C:/msys64/clang64/bin/llvm-readobj.exe `
      '-DMODULE=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/build/Task 8 artifact inspection Ž/Extracted package Č/lib/pure/bonjour.dll' `
      '-DPURE_PREFIX=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/build/pure-sdk-regression-prefix' `
      '-DVERIFY_WORK_DIR=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/build/Task 8 artifact inspection Ž/Independent dependency audit' `
      '-DDEPENDENCY_REPORT=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/build/Task 8 artifact inspection Ž/Independent dependency audit/PureBonjourDependencies.tsv' `
      -P pure-bonjour/cmake/VerifyWindowsDependencies.cmake
    ```

  - Exact sanitized smoke used `cmd.exe /d /c mklink /J` to create the fresh
    ASCII `build/task8-artifact-stage-alias` pointing to the canonical Unicode
    extraction, recorded the alias target (the installed verifier separately
    checked its canonical target), removed `PURELIB`, rejected any
    `msys64` segment, recorded Pure process counts before/after, and ran:

    ```powershell
    $target = 'C:\pure-lang\.worktrees\todo-45-windows-pure-bonjour\build\Task 8 artifact inspection Ž\Extracted package Č'
    $alias = 'C:\pure-lang\.worktrees\todo-45-windows-pure-bonjour\build\task8-artifact-stage-alias'
    $smokeRoot = 'C:\pure-lang\.worktrees\todo-45-windows-pure-bonjour\build\task8-artifact-sanitized-smoke'
    if (Test-Path -LiteralPath $alias) { throw "alias already exists: $alias" }
    if (Test-Path -LiteralPath $smokeRoot) { throw "smoke root already exists: $smokeRoot" }
    $targetNative = [IO.Path]::GetFullPath($target)
    $aliasNative = [IO.Path]::GetFullPath($alias)
    $smokeNative = [IO.Path]::GetFullPath($smokeRoot)
    $ownedRoot = [IO.Path]::GetFullPath(
      'C:\pure-lang\.worktrees\todo-45-windows-pure-bonjour\build')
    $ownedPrefix = $ownedRoot.TrimEnd('\') + '\'
    foreach ($ownedPath in @($aliasNative, $smokeNative)) {
      if (-not $ownedPath.StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "owned scratch escaped build root: $ownedPath"
      }
    }
    cmd.exe /d /c mklink /J "$aliasNative" "$targetNative"
    if ($LASTEXITCODE -ne 0) { throw 'alias creation failed' }
    try {
      $canonicalAlias = (Get-Item -LiteralPath $alias).Target
      "ALIAS_TARGET`t$canonicalAlias"
      if ([IO.Path]::GetFullPath($canonicalAlias) -cne $targetNative) {
        throw "alias target mismatch: $canonicalAlias"
      }
      $before = @(Get-Process -Name pure -ErrorAction SilentlyContinue).Count
      if ($before -ne 0) { throw "Pure processes before smoke: $before" }
      "PURE_PROCESSES_BEFORE`t$before"
      Remove-Item Env:PURELIB -ErrorAction SilentlyContinue
      $purePrefix = 'C:\pure-lang\.worktrees\todo-45-windows-pure-bonjour\build\pure-sdk-regression-prefix'
      $safePath = "$purePrefix\bin;$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\Wbem"
      if ($safePath -match '(?i)(^|;).*[/\\]msys64[/\\]') {
        throw "MSYS2 survived: $safePath"
      }
      $env:Path = $safePath
      & 'C:/msys64/clang64/bin/cmake.exe' -DSMOKE_OUTER_TIMEOUT_SECONDS=30 `
        '-DSMOKE_ROOT=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/build/task8-artifact-sanitized-smoke' `
        '-DPURE_EXECUTABLE=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/build/pure-sdk-regression-prefix/bin/pure.exe' `
        '-DMODULE_PATH=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/build/task8-artifact-stage-alias/lib/pure/bonjour.dll' `
        '-DWRAPPER_PATH=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/build/task8-artifact-stage-alias/lib/pure/bonjour.pure' `
        '-DSMOKE_SCRIPT=C:/pure-lang/.worktrees/todo-45-windows-pure-bonjour/pure-bonjour/tests/smoke.pure' `
        -P pure-bonjour/cmake/RunSmokeTest.cmake
      $after = @(Get-Process -Name pure -ErrorAction SilentlyContinue).Count
      if ($after -ne 0) { throw "Pure processes after smoke: $after" }
      "PURE_PROCESSES_AFTER`t$after"
    } finally {
      if (Test-Path -LiteralPath $smokeRoot) {
        $smokeItem = Get-Item -LiteralPath $smokeRoot -Force
        if (($smokeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          throw "smoke root is a reparse point: $smokeRoot"
        }
        if (@(Get-ChildItem -LiteralPath $smokeRoot -Force).Count -ne 0) {
          throw "smoke root is not empty: $smokeRoot"
        }
        Remove-Item -LiteralPath $smokeRoot
      }
      $aliasItem = Get-Item -LiteralPath $alias -Force
      if (($aliasItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or
          [IO.Path]::GetFullPath($aliasItem.Target) -cne $targetNative) {
        throw "alias changed before cleanup: $alias"
      }
      cmd.exe /d /c rmdir "$aliasNative"
      if ($LASTEXITCODE -ne 0) { throw 'alias cleanup failed' }
    }
    if (Test-Path -LiteralPath $alias) { throw 'alias remains' }
    if (Test-Path -LiteralPath $smokeRoot) { throw 'smoke root remains' }
    $finalProcesses = @(Get-Process -Name pure -ErrorAction SilentlyContinue).Count
    if ($finalProcesses -ne 0) {
      throw "Pure processes after cleanup: $finalProcesses"
    }
    "PURE_PROCESSES_AFTER_CLEANUP`t$finalProcesses"
    ```
