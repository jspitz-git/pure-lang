# TODO-35 - Windows pure-gl Package

Status: Closed on 2026-07-28
Branch: todo/35-windows-pure-gl

## Purpose

Build, validate, and package `pure-gl` with native Windows OpenGL and FreeGLUT.

## Scope

- Build all advertised native components and associated Pure modules.
- Bundle FreeGLUT and other non-system runtime DLLs.
- Cover context creation, rendering, event handling, and clean shutdown.

## Task List

1. [x] Build the package against the staged runtime and CLANG64 FreeGLUT.
2. [x] Inventory OpenGL/GLU/FreeGLUT imports and module coverage.
3. [x] Add a bounded off-screen or hidden-window rendering smoke test.
4. [x] Validate interactive examples on a Windows desktop.
5. [x] Stage and inspect the package outside MSYS2.

## Guardrails

- CI tests must terminate without user interaction.
- Do not bundle Windows system OpenGL DLLs.

## Validation Plan

- Create a context, render a known frame, process events, and exit automatically.
- Run an interactive example and inspect all non-system PE dependencies.

## Progress Log

- 2026-07-25: Created as an optional graphics Windows package candidate.
- 2026-07-28: Added a native CLANG64 CMake build for all seven wrapper families.
  - One `pure-gl.dll` contains GL, GLU, GLUT, ARB, EXT, NV, and ATI wrappers.
  - The build uses strict warnings, staged Pure SDK metadata, FreeGLUT 3.8.0,
    and native Windows OpenGL and GLU import libraries.
  - A clean Release build produced a COFF x86-64 module.
- 2026-07-28: Audited module coverage and the Windows dependency boundary.
  - A marker test loads all seven Pure interfaces and checks a representative
    constant from every wrapper family.
  - The PE audit requires x86-64 `pure-gl.dll` and `libfreeglut.dll`, rejects
    MSYS/GNU runtimes, and records the Windows system API imports.
  - A regression test exposed that CLANG64 installs `libfreeglut.dll` while the
    generated sources requested `freeglut.dll`; the generator template and all
    seven checked-in C files now use the installed name.
- 2026-07-28: Added a bounded hidden-window rendering test.
  - It creates a 32 by 32 RGBA context, clears it to a known color, reads the
    center pixel as `[64,128,191,255]`, and destroys the window.
  - The runner supplies explicit include/module paths, treats Pure diagnostics
    as failures even when the interpreter exits with zero, and has nested
    45/55-second timeouts.
- 2026-07-28: Validated visible rendering and event processing on Windows.
  - The opt-in `check-gl-interactive` target displays an RGB triangle for one
    second, processes a FreeGLUT display event, checks every OpenGL error
    boundary, closes the window, and exits automatically.
  - This test exposed lazy `wglGetProcAddress` calls inside `glBegin/glEnd`.
    Standard exports are now resolved from `opengl32.dll`, `glu32.dll`, and
    FreeGLUT before the WGL extension fallback, eliminating
    `GL_INVALID_OPERATION`.
- 2026-07-28: Staged and inspected the portable Windows package.
  - Installing into a fresh 40-file runtime added exactly 26 files and removed
    none: one module, seven Pure interfaces, `libfreeglut.dll`, its license,
    documentation, examples, and three test scripts.
  - The FreeGLUT DLL hash matches the CLANG64 source runtime. The complete
    staged package passed the load and hidden-render tests with `PURELIB`
    unset and `PATH` restricted to the staged `bin` and Windows system paths.
  - PE inspection passed for both staged binaries. `opengl32.dll`, `glu32.dll`,
    `gdi32.dll`, `user32.dll`, and `winmm.dll` are explicitly forbidden from
    the package.
  - A negative configure test rejected `PURE_LIBRARY_INSTALL_DIR=../escape`.
- 2026-09-12: Hardened strict configuration and native test completion in a
  follow-up audit. The historical 2026-07 closure and desktop evidence above
  remain intact.
  - `pure-gl-configure-contract` rejects omitted, noncanonical, wrong-type,
    and wrong-prefix inputs, including pkg-config include/library paths that
    disagree with the explicit CLANG64 prefix. CI supplies all tool/root
    paths and both reviewed LLVM tool hashes explicitly.
  - `pure-gl-runner-contract` proves that inherited PATH/PURELIB cannot supply
    runtime dependencies. The native supervisor retains input identities,
    creates a bounded Job Object, drains both output streams, and requires
    exit zero, empty stderr, and exactly one terminal random-token completion
    record. Functional limits are 90 seconds inside the supervisor, a
    five-second adapter margin, and 100 seconds in CTest.
  - Mandatory load and hidden-render checks cover all seven interfaces,
    nonempty OpenGL context strings, RGBA `[64,128,191,255]` within two per
    channel, OpenGL error boundaries, and verified window destruction.
    The separate opt-in `pure-gl-render-contract` supplies semantic mutation
    coverage; Task 2's retained result was three pristine scripts and 18
    rejected mutations. That optional target is not counted as an additional
    CTest or as a rerun in the final verification below.
- 2026-09-12: Replaced the partial PE checks with an exact recursive import
  and origin contract.
  - `pure-gl-runtime-verifier-contract` now passes 31 negative mutations and
    seven pristine cases, including missing/unexpected imports, malformed
    records, pinned-tool changes, architecture, runtime shadows, reparses,
    and decorated or obsolete FreeGLUT loader strings.
  - Both fresh build and installed audits inspect 12 non-system AMD64 DLLs
    plus ten terminal AMD64 Windows system DLLs: 22 PE files and 141 normal
    import edges, with empty missing/unexpected sets. Windows OpenGL, GLU,
    GDI, User32, and WinMM binaries remain forbidden package payloads.
  - The pinned reader's physical Unicode `File:` path is accepted only as
    byte-exact canonical UTF-8; every other record remains strict ASCII.
    Invalid UTF-8 and non-ASCII structural-record regressions are mandatory.
- 2026-09-12: Replaced path-existence installation checks with sealed package
  ownership and same-prefix FreeGLUT provenance.
  - `pure-gl-install-contract` passes 33 negatives/eight positives, including
    altered bytes, extra files/directories outside historical globs,
    collisions, manifest changes, wrong runtime/notice origins, and attempts
    to change or install into the canonical baseline.
  - `pure-gl-install-guard-contract` passes 18 negatives/20 positives with
    zero protected writes. It covers retained identities, stage exclusion,
    authenticated context/source consumption, reservations across components,
    final equality, child completion, and controlled-failure rollback with
    existing-manifest restoration. This is not a crash/power-loss atomicity
    claim.
  - The frozen baseline is 49 entries (40 files, nine directories). Runtime
    adds nine files and documentation adds 17, with six new directories:
    **49 + 26 + 6 = 81 entries**, or 66 files and 15 directories. Full
    verification requires both disjoint components and an unchanged final
    snapshot after the two installed functional tests.
  - The sole added third-party DLL is FreeGLUT 3.8.0 from CLANG64 package
    `mingw-w64-clang-x86_64-freeglut` 3.8.0-1. Its 359,936-byte runtime and
    1,439-byte notice use the canonical `bin/libfreeglut.dll` and
    `share/licenses/freeglut/COPYING` origins; the unchanged notice installs
    as `share/doc/pure-gl/licenses/FreeGLUT.txt`. The inventory binds project,
    version, upstream archive URL, MIT metadata, notice mapping, and both
    source hashes. Pins remain
    `a297e3b3fa824de6eb21285e23a409fbbf0bc573c60dd04c227bbc89d8398519`
    and `b6593d5ec4c113a274abb85b10e8615895cb0ddb89f7912af5fe5aa8df38a275`.
- 2026-09-12: Made the public source release independently verifiable and
  guarded the legacy deletion/generation paths.
  - `pure-gl-source-dist-contract` executes public `make dist`, verifies the
    exact 78-file/nine-directory archive including all CMake/native helpers,
    Windows/provenance docs and tests, removes its copied source, then
    configures/builds/inspects/tests the extracted archive. Four archive
    negatives cover missing, extra, stale generated, and symlink inputs.
    A standalone archive registers nine tests and runs eight non-source-dist
    tests inside this gate; it carries the workflow contract script but not
    repository `.github`.
  - Public `make distcheck` binds `DIST_AUDIT_BUILD` to the retained canonical
    `CMAKE_HOME_DIRECTORY` of the same strict source tree. Source and build
    roots must be disjoint before either copying driver creates an audit leaf.
  - `pure-gl-cleanup-contract` passes 35 public legacy negatives, 15 inherited
    driver negatives, one source/cache binding case, four layout cases and
    eight POSIX name-policy cases, with zero protected writes. It proves
    byte-exact clean inventory, realclean, and real four-worker generation
    using a Make executable path with spaces and an ampersand. Fixed owned
    leaves, sentinels, no-follow identity and protected-descendant checks
    replace the old broad cleanup paths.
- 2026-09-12: Added mandatory Windows CI coverage and independent semantic
  workflow regressions.
  - Both push and pull-request path filters in
    `.github/workflows/non-linux-release-validation.yml` include `pure-gl/**`,
    this TODO, the approved design, and the implementation plan. The existing
    Windows 2025 job includes CLANG64 FreeGLUT, native GNU Make and PyYAML.
  - Six unconditional PowerShell steps capture Pure immediately after its
    portable install, configure strict Release/Ninja in `${{ runner.temp }}/gl8`,
    build/inspect PE with four workers, run every `gl` CTest, independently
    execute public distcheck, and install/verify both components in physical
    `${{ runner.temp }}/gl package café`. Source retains spaces and sibling
    `.github`; the SDK copy is ASCII/unspaced `${{ runner.temp }}/glp`.
  - Parent runtime PATH is exactly `C:/Windows/System32;C:/Windows`, PURELIB
    is removed, and pkg-config roots are explicit. Each native failure stops
    the step. An `always()` artifact upload retains GL logs/build for 14 days.
  - The registered `pure-gl-workflow-contract` runs the actual validator and
    independent Python suite. Fresh working-tree verification passed all 23
    methods in 199.256 seconds, including 402 GL mutation cases, four
    independently authored pristine/formatting variants and focused guard/SDK
    regressions. Actual validator CLI, real YAML parse, both documentation
    PowerShell blocks, six CI PowerShell blocks, and `git diff --check` pass.
    Hosted CI was not dispatched, so its graphics support, 8.3 availability
    and combined job duration are not established by these local results.
- 2026-09-12: Recorded the three investigated Windows path boundaries.
  - Pure 0.68 converts its executable-relative library prefix to UTF-8, while
    prelude loading reaches narrow Windows CRT `stat`/`fopen`. Retained direct
    executable/script 2x2 and wide/ACP/UTF-8 path probes isolated the lost
    prelude to a physical Unicode executable prefix on the local ACP 1250
    host, including misleading Pure exit zero with diagnostics.
  - The installed supervisor launches the same physical stage's `pure.exe`
    through its identity-checked ASCII Windows 8.3 spelling. Physical paths
    still own every source/hash/manifest/DLL/PE check; no ASCII runtime copy
    or alternate Pure executable is used. Four unsafe alias cases fail and
    the same-stage identical-byte positive passes. The selected volume must
    already provide a valid ASCII alias; otherwise verification fails closed.
    Arbitrary Unicode Pure argument paths are not claimed supported.
  - Native Make/pkgconf splits POSIX-escaped include/library flags from a
    spaced SDK prefix, so the immutable SDK is ASCII/unspaced. Source and
    tool paths with spaces remain covered, as does the Unicode/spaced final
    stage. The exact physical UTF-8 PE `File:` exception above is separate
    from Pure's executable-launch compatibility path.
- 2026-09-12: Completed the first entirely fresh follow-up release
  verification before adding these TODO entries.
  - Fresh source `C:/pure-lang/.worktrees/todo35-audit/t7 source2/pure-gl`
    preserved sibling `.github`; SDK `.../t7pure2` copied the unchanged
    98,751,285-byte canonical Pure baseline. Build `C:/pure-lang/g7b` is
    separate and 16 characters long. Final physical stage is
    `C:/pure-lang/.worktrees/todo35-audit/t7 final2 café`.
  - Tools measured by their actual executables: Pure 0.68 compiled for LLVM
    22.1.8; Clang/llvm-readobj/llvm-strings 22.1.8; CMake/CTest 4.4.0; GNU Make
    4.4.1; pkgconf 3.0.4; CLANG64 Python 3.14.6; native Python 3.14.5;
    PyYAML 6.0.3. Installed Ninja reports 1.13.2 but was not used for this
    local build. Windows reports build 26200.9445, display version 25H2.
  - The local Ninja lock/compiler-probe limitation uses the documented
    `MinGW Makefiles` fallback with explicit native Make and the recorded
    `CMAKE_C_COMPILER_WORKS=1` / `CMAKE_C_ABI_COMPILED=1` overrides. Top-level
    CI retains Ninja with normal probing. Native guard operations require
    the approved local named-pipe execution scope; authentication remains
    enabled. The sandbox-denied initial attempt is retained as diagnostic
    evidence and is not counted as the successful clean build.
  - Exact commands and cache pins are in [the operator reference](../../pure-gl/WINDOWS.md).
    This local run used those strict inputs with the documented generator
    fallback, followed by:

    ```powershell
    & C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/g7b --parallel 4
    & C:/msys64/clang64/bin/cmake.exe --build C:/pure-lang/g7b --target verify-windows-dependencies --parallel 4
    & C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/g7b -L gl --output-on-failure --no-tests=error -V
    & C:/msys64/clang64/bin/mingw32-make.exe --no-print-directory -C 'C:/pure-lang/.worktrees/todo35-audit/t7 source2/pure-gl' distcheck CMAKE=C:/msys64/clang64/bin/cmake.exe PKG_CONFIG=C:/msys64/clang64/bin/pkgconf.exe DIST_AUDIT_BUILD=C:/pure-lang/g7b
    & C:/msys64/clang64/bin/cmake.exe --install C:/pure-lang/g7b --prefix 'C:/pure-lang/.worktrees/todo35-audit/t7 final2 café' --component runtime
    & C:/msys64/clang64/bin/cmake.exe --install C:/pure-lang/g7b --prefix 'C:/pure-lang/.worktrees/todo35-audit/t7 final2 café' --component documentation
    & C:/msys64/clang64/bin/cmake.exe -DGL_INSTALL_CONTEXT=C:/pure-lang/g7b/pure-gl-install-context.cmake '-DSTAGE_PREFIX=C:/pure-lang/.worktrees/todo35-audit/t7 final2 café' -P 'C:/pure-lang/.worktrees/todo35-audit/t7 source2/pure-gl/cmake/VerifyInstalledPackage.cmake'
    ```

  - Strict configure passed in 2.926 seconds, four-worker build in 6.110
    seconds, and exact PE target in 2.811 seconds. All ten repository CTests
    passed in 1,377.74 seconds. The source-dist test within that suite passed
    in 611.06 seconds, including eight extracted tests in 595.80 seconds.
  - The independent public distcheck then passed 1/1 in 618.79 seconds
    (619.670 seconds including public dispatch), with eight extracted tests
    passing in 603.38 seconds. Both archives contain 78 files/nine directories.
    The separately retained public archive is 241,982 bytes, SHA-256
    `4e51cc95a7e32811370aaeeb794980fb235e7c9d08a13a273f5a1601f9741f81`.
  - Runtime/documentation installations passed in 4.057/3.426 seconds.
    Complete installed verification passed in 57.172 seconds, including two
    authenticated same-stage alias launches, context/pixel/error/destruction
    checks, the 22-file/141-import PE audit, and unchanged final inventory.
    The physical stage contains 81 entries, 66 files/15 directories and
    100,067,661 file bytes. Its renderer was AMD Radeon(TM) Graphics,
    OpenGL 4.6.0 Compatibility Profile Context 22.20.27.09.230330.
  - Baseline TSV SHA-256 is
    `7afa989e6f687351c221c3e43ca99cfde5d1a5d5e84bba77553ea21ab5182683`;
    inventory TSV is
    `038579d5e9f3b22cfc266a973a63bda2c7afdd20097126a8483ede9ed2010057`;
    the 616,448-byte module is
    `8098fe2268ccaa5f6934b5b0084b9b4459cd2acb12a7b70ae0401e31828f8a15`.
    The full measured logs, exact commands, archive copies, and context/runner/guard
    hashes are retained in the Task 7 SDD report. No visible desktop validation
    was rerun for this final gate;
    `check-gl-interactive` remains optional.
- 2026-09-12: Implemented fixes for the final review's five authority gaps; these
  results supersede the earlier follow-up's registration/archive counts while
  preserving that run as historical evidence.
  - Canonical runner inputs and every validated executable-alias component now
    retain read handles without write/delete sharing through supervised
    execution. Synchronized independent-child RED/GREEN coverage proves eight
    denied writes over two owned launches and two post-release controls.
  - Post-link module and runner hashes plus the completed-seal hash are embedded
    in the native installation guard. Ordinary verification authenticates and
    retains them before consuming mutable sidecars; the module policy no longer
    exempts BUILD hashes. Eight new negatives reject missing/modified modules,
    runners and completed seals, including coordinated artifact/sidecar changes.
    Corrected focused install/guard verification passed 2/2 in 569.03 seconds;
    existing 33 install negatives/eight positives and 18 guard negatives/20
    positives remain, with zero protected writes. Fixture restoration uses
    byte-exact copies; investigated initial line-ending failures are retained.
  - Public distcheck retains source-directory/cache authority through dispatch,
    and distribution creation retains each new leaf/package directory before
    child access. Synchronized checks cover dispatch, ten new directories and
    compatible child reads; destructive modes retain their required access.
  - The mandatory `pure-gl-render-contract` CTest now runs two pristine scripts
    and twelve load/hidden mutations. Only one visible pristine script and six
    visible mutations remain in the optional `pure-gl-interactive-contract`
    target. CI/extracted gates inspect the real CTest inventory before running
    it: eleven repository tests, ten standalone tests, no interactive CTest.
    Workflow regressions now cover 408 GL mutations and four independent
    positives within the unchanged 23-method Python suite.
  - The archive contains 87 regular files and nine directories. Its own
    bootstrap/helper code performs extracted verification while original
    checkout/build helpers deny new reads and image opens. A regression proves
    accidental original-source reads and original-helper execution fail during
    that interval. Toolchain/SDK roots remain explicit external dependencies;
    the already-consumed dispatch cache retains identity and locked bytes.
    No hosted CI or visible interactive rerun is claimed by this fix wave.
- 2026-09-12: Completed fresh final-fix verification using source snapshot
  `.../todo35-audit/ff source4/pure-gl`, immutable SDK `.../ffpure4`, short build
  `C:/pure-lang/gf4`, and separate physical stage `.../ff final4 café`.
  - Strict configure/four-worker build/exact PE checks passed in
    3.325/6.824/2.770 seconds with the previously documented local MinGW
    Makefiles/compiler-probe fallback. Tool versions and pinned dependency
    hashes remain unchanged from the earlier measured follow-up. These are
    local results, not evidence of hosted Ninja execution.
  - The fresh public distcheck ran before the complete repository suite:

    ```powershell
    & C:/msys64/clang64/bin/mingw32-make.exe --no-print-directory -C 'C:/pure-lang/.worktrees/todo35-audit/ff source4/pure-gl' distcheck CMAKE=C:/msys64/clang64/bin/cmake.exe PKG_CONFIG=C:/msys64/clang64/bin/pkgconf.exe DIST_AUDIT_BUILD=C:/pure-lang/gf4
    & C:/msys64/clang64/bin/cmake.exe -DBINARY_DIR=C:/pure-lang/gf4 -P 'C:/pure-lang/.worktrees/todo35-audit/ff source4/pure-gl/tests/VerifyCTestInventory.cmake'
    & C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/gf4 -L gl --output-on-failure --no-tests=error -V
    & C:/msys64/clang64/bin/cmake.exe --install C:/pure-lang/gf4 --prefix 'C:/pure-lang/.worktrees/todo35-audit/ff final4 café' --component runtime
    & C:/msys64/clang64/bin/cmake.exe --install C:/pure-lang/gf4 --prefix 'C:/pure-lang/.worktrees/todo35-audit/ff final4 café' --component documentation
    & C:/msys64/clang64/bin/cmake.exe -DGL_INSTALL_CONTEXT=C:/pure-lang/gf4/pure-gl-install-context.cmake '-DSTAGE_PREFIX=C:/pure-lang/.worktrees/todo35-audit/ff final4 café' -P 'C:/pure-lang/.worktrees/todo35-audit/ff source4/pure-gl/cmake/VerifyInstalledPackage.cmake'
    ```

  - Public distcheck passed 1/1 in 1,198.07 seconds (1,198.924 seconds including
    dispatch), with nine extracted tests passing in 1,179.23 seconds. Its
    249,777-byte archive SHA-256 is
    `5169735bd27deb41a538c1ff3a83ecae314fa1274af417daf864b756673358c2`.
    All eleven repository CTests then passed in 2,315.81 seconds. Its independent
    source-dist gate passed in 1,085.20 seconds, including nine extracted tests
    in 1,064.57 seconds; that 249,749-byte archive SHA-256 is
    `7401c1fabf8c806320a6f654cc39dc75383f4f96e2cc45bdfbc76c2882d67df2`.
    Both archives contain 87 files/nine directories and seal all 26 payloads.
    Isolation denied 392/469 original input files respectively and rejected
    both accidental original-source and original-helper dependencies.
  - The final repository render contract passed in 346.35 seconds; extracted
    render passed in 356.61 seconds. Final workflow verification passed the
    23-method/408-mutation suite in 177.346 seconds. Repository install/guard
    contracts passed in 319.72/196.27 seconds, with zero protected writes.
  - Separate stage runtime/documentation installation passed in 4.284/3.883
    seconds. Complete installed verification passed in 70.278 seconds, including
    two authenticated same-stage alias launches, context/pixel/error/destruction
    checks, exact 22-file/141-import PE audit, and unchanged final inventory.
    The stage has 81 entries, 66 files/15 directories and 100,069,130 file bytes;
    the baseline remains 49 entries and 98,751,285 bytes.
  - Final metrics prove byte-for-byte equality of all 87 package source files
    and all four `.github` files with the reviewed worktree. The inventory TSV
    SHA-256 is `f72b3037d90770e9f55d8d01b9ca2469812532bc87bb4eff7ab38abda1410cc3`;
    the 616,448-byte module is
    `7991cd0d8d8a7b4c1261a50a50f88359e091ec6dd99163fe72aadb3f32bd2668`;
    the 190-byte completed seal is
    `f1d261f48655805644571c696f754361a78f1b12c0a64d319c0b8e94dc01c765`.
    Full RED/GREEN evidence, exact commands, retained archives, metrics and
    self-review are in the final-fix SDD report. Documentation/new-helper/CI
    PowerShell parsing, real YAML parsing and final whitespace checks pass.
- 2026-09-12: The scoped re-review confirmed all five prior fixes but found R1:
  archive-contained bootstrap code ran before independent extracted-byte
  validation. The user explicitly authorized a second fix wave.
  - A new independent regression exercises the real outer handoff with changed
    `IsolateSource.ps1`, `VerifyExtractedSource.cmake`, and `AuditHelpers.cmake`.
    Before the production fix all three execution markers appeared; two stale
    bootstraps exited successfully and the third rejected itself only after
    execution. The fresh RED source-dist test failed as expected in 4.42 seconds.
  - The trusted outer driver now checks the complete extracted file/directory
    inventory, regular no-reparse/non-hardlinked tree, every frozen source hash,
    and permitted README substitution before any archive helper runs. All three
    focused negatives now reject without executing the changed helper; the
    restored pristine outer preflight passes. Genuine original-input isolation
    and the prior in-isolation mutations remain unchanged. The shipped new
    regression increases the archive to 88 files/nine directories; registration
    remains eleven repository/ten standalone CTests.
  - The reported reused-`gf4` Windows error 5 was reproduced by the ordinary
    seal verifier in the default sandbox. The identical command immediately
    passed in the approved native authentication-channel scope, without cleanup,
    rebuilding, ACL changes or source repair. Both original gf4 install/guard
    contracts then passed in 447.13 seconds (276.29/170.83), including final
    pristine checks and zero protected writes. No reentrance regression was
    found, so no speculative authentication/reentrance change was made.
- 2026-09-13: Completed the second fix wave's entirely fresh release gate using
  `.../todo35-audit/sf source2/pure-gl`, sibling `.github`, `.../sfpure2`, short
  build `C:/pure-lang/gs2`, and separate physical `.../sf final2 café` stage.
  - Configure/four-worker build/exact PE checks passed in 3.009/7.060/2.925
    seconds with the documented local Make/compiler-probe fallback and approved
    native authentication-channel scope. The full executed sequence included:

    ```powershell
    & C:/msys64/clang64/bin/mingw32-make.exe --no-print-directory -C 'C:/pure-lang/.worktrees/todo35-audit/sf source2/pure-gl' distcheck CMAKE=C:/msys64/clang64/bin/cmake.exe PKG_CONFIG=C:/msys64/clang64/bin/pkgconf.exe DIST_AUDIT_BUILD=C:/pure-lang/gs2
    & C:/msys64/clang64/bin/cmake.exe -DBINARY_DIR=C:/pure-lang/gs2 -P 'C:/pure-lang/.worktrees/todo35-audit/sf source2/pure-gl/tests/VerifyCTestInventory.cmake'
    & C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/gs2 -L gl --output-on-failure --no-tests=error -V
    & C:/msys64/clang64/bin/cmake.exe --install C:/pure-lang/gs2 --prefix 'C:/pure-lang/.worktrees/todo35-audit/sf final2 café' --component runtime
    & C:/msys64/clang64/bin/cmake.exe --install C:/pure-lang/gs2 --prefix 'C:/pure-lang/.worktrees/todo35-audit/sf final2 café' --component documentation
    & C:/msys64/clang64/bin/cmake.exe -DGL_INSTALL_CONTEXT=C:/pure-lang/gs2/pure-gl-install-context.cmake '-DSTAGE_PREFIX=C:/pure-lang/.worktrees/todo35-audit/sf final2 café' -P 'C:/pure-lang/.worktrees/todo35-audit/sf source2/pure-gl/cmake/VerifyInstalledPackage.cmake'
    ```

  - Public distcheck passed 1/1 in 1,015.30 seconds (1,016.190 including public
    dispatch), with nine isolated extracted tests in 995.75 seconds. All eleven
    repository CTests then passed in 2,330.56 seconds. Their separate source-dist
    gate passed in 1,125.41 seconds, including nine extracted tests in 1,105.74
    seconds. Both gates reject all three changed bootstrap/helpers before
    execution, pass the pristine outer preflight and original-dependency
    regressions, deny 393/470 original inputs respectively, and seal 26 payloads.
  - Both retained archives contain 88 files/nine directories. The public
    250,926-byte archive has SHA-256
    `d30719c157d4e078915eafe4892a6f624c5f4273191827176a354363a6fd39d8`;
    the repository suite's 250,928-byte archive has SHA-256
    `3c0c476187f1d9507e5bb73c0d7d1776ab611a5d9b935012ebecf624499114a1`.
  - Separate runtime/documentation installs passed in 4.331/3.886 seconds;
    full installed verification passed in 75.382 seconds with two authenticated
    same-stage launches, exact 22-PE/141-import closure and final equality.
    The physical stage contains 81 entries, 66 files/15 directories and
    100,069,412 file bytes. Baseline counts/bytes remain unchanged.
  - Independent checks passed 23 Python methods/408 GL mutations in 246.562
    seconds; the final registered workflow suite repeated them in 170.161
    seconds. Actual validator CLI, YAML parsing, six CI/two documentation
    PowerShell ASTs and whitespace checks pass. Final metrics confirm identical
    bytes for all 88 package files and all four workflow files in the tested
    snapshot. Tool versions and reviewed runtime/tool pins remain unchanged.
  - Final inventory TSV SHA-256 is
    `18d0146009dc41baefdcf07740007468eaa8c9fc3d7775b23fcc968e4f6d889a`;
    module SHA-256 is `913a50aaa22c09f178d0b3525e8d641b6f56e5ec8df02012db62b0bc96758c05`;
    completed seal SHA-256 is
    `900c7054376857fc09a7c95132dcefcaf8367fcb211c7bd90f43ed16d2d53109`.
    Detailed RED/GREEN, error-5 diagnosis, commands, archives, metrics and scoped
    self-review are preserved in the second-fix SDD report. No hosted CI/Ninja
    execution or visible interactive rerun is claimed.
