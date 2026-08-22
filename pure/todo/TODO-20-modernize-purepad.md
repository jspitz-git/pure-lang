# TODO-20 - Modernize PurePad

Status: Closed on 2026-07-26
Branch: todo/20-modernize-purepad

## Purpose

Build the existing PurePad Windows UI with a supported toolchain and make it work
with the portable Pure runtime.

## Scope

- Add a Visual Studio 2022 MFC build using CMake or a maintained project file.
- Replace fixed paths and environment assumptions with executable-relative lookup.
- Update settings, help, and `.pure` file-association behavior.
- Preserve the existing pipe and Windows event protocol with `pure.exe`.

## Task List

1. [x] Create and validate a 64-bit MFC build.
2. [x] Fix compiler, Unicode, path-length, and ownership issues found by the build.
3. [x] Launch the sibling `pure.exe` without depending on global `PATH`.
4. [x] Move per-user state to an appropriate Windows application-data directory.
5. [x] Validate editing, execution, interruption, diagnostics, help, and shutdown.

## Guardrails

- Do not rewrite the UI unless the existing MFC implementation proves unmaintainable.
- Keep PurePad independent of the compiler ABI used to build `libpure.dll`.
- Do not write application settings to the installation directory.

## Validation Plan

- Build on a clean Visual Studio runner with the MFC component installed.
- Run PurePad from a path containing spaces with a sanitized environment.
- Exercise normal execution, error output, interruption, and repeated runs.

## Progress Log

- 2026-07-25: Created from the PurePad source and dependency inventory.
- 2026-07-26: Added and validated a Visual Studio 2022 x64 MFC build.
  - Added CMake configure and Release/Debug build presets using shared MFC.
  - Removed the fixed HTML Help Workshop include and library paths inherited
    from the Visual C++ 6 project.
  - Fixed two blocking modern-MSVC compatibility errors: const-correct path
    scanning and selection of the global Win32 `HtmlHelp` function.
  - Release and Debug builds completed with MSVC 19.44 and Windows SDK 10.0.26100.
  - `dumpbin` confirmed a PE32+ x64 Windows GUI executable depending on
    `mfc140.dll`.
  - Remaining secure-CRT, narrowing, and path-size warnings are retained for
    task 2 rather than hidden with a global warning suppression.
- 2026-07-26: Removed the first set of ownership hazards.
  - `CBuffer` and `CPipe` now return `CString` values, removing caller-owned
    arrays and their manual `delete[]` contract.
  - `CPipe` closes all three persistent synchronization handles and closes the
    thread handles returned by successful `CreateProcess` calls.
  - Pipe writes now handle partial `WriteFile` results; the home-directory
    fallback uses mutable storage instead of modifying a string literal.
  - Release and Debug x64 builds passed after the changes; the remaining
    warnings are confined to the text and path modernization work.
- 2026-07-26: Completed the Unicode and path-length modernization.
  - Switched the MFC target from MBCS to Unicode and converted the editor,
    history, process-pipe, prompt, diagnostics, and settings paths to `TCHAR`
    and `CString`.
  - Replaced fixed-size path splitting and the legacy ANSI `QPATH` search with
    dynamically sized executable-relative and Unicode path handling.
  - Added an embedded `longPathAware` manifest; the extracted Release manifest
    confirms the setting alongside per-monitor DPI awareness.
  - Release and Debug x64 builds pass without compiler or linker warnings;
    `dumpbin` still identifies the Release artifact as an x64 Windows GUI
    executable.
- 2026-07-26: Made interpreter launch executable-relative.
  - PurePad now derives an absolute sibling `pure.exe` path from its own module
    path and no longer loads or persists the legacy PATH-dependent run command.
  - `CreateProcess` receives the absolute executable as `applicationName`; its
    command line separately quotes the executable and script arguments and
    retains the existing Run and Debug switches.
  - Missing sibling and pipe-setup failures are reported synchronously without
    leaving partially initialized worker state.
  - A staged Release PurePad in `C:\tmp\PurePad sibling probe` invoked a sibling
    probe executable for both Run (`-i -q`) and Debug (`-i -q -g`) with `PATH`
    restricted to `C:\Windows\System32;C:\Windows`.
  - Release and Debug x64 builds pass without warnings.
- 2026-07-26: Moved per-user state to roaming AppData.
  - PurePad now stores its MFC profile in the UTF-16
    `%APPDATA%\Pure\PurePad\PurePad.ini` file and command history in
    `%APPDATA%\Pure\PurePad\history.txt`.
  - A fresh profile imports all supported string and DWORD values from the
    legacy HKCU profile; the old registry data and history file are retained.
  - `PUREPAD_USER_DATA` provides an explicit isolated test/development override.
  - An isolated fresh-profile run migrated Settings, Font, and toolbar sections,
    redirected history, exited cleanly, and left the legacy registry unchanged.
  - Release and Debug x64 builds pass without warnings.
- 2026-07-26: Completed end-to-end functional validation.
  - Replaced Unicode MFC raw serialization with UTF-8 output and decoding for
    UTF-8, legacy ANSI, and BOM-marked UTF-16 source files.
  - Initialized OLE before modern MFC recent-file handling, fixing a fast-fail
    when PurePad opened a document from its command line.
  - Made missing or unusable `puredoc.chm` help report its executable-relative
    path instead of failing silently.
  - Replaced lossy `PulseEvent` signalling and removed the child-start race by
    creating named auto-reset events while `pure.exe` is still suspended.
  - An automated x64 Release workflow in a path containing spaces verified
    editing and UTF-8 saving, real interpreter output, a line-2 syntax error,
    source navigation, interactive Break, missing-help diagnostics, and clean
    shutdown with no remaining child process.
  - Break reduced the allocating interpreter loop from about 1,000 ms CPU per
    second to 0 ms; Release and Debug x64 builds pass without warnings.
- 2026-08-22: The lifecycle-hardening audit remediation passed; the historical
  `Status: Closed on 2026-07-26` above remains the original completion record.
  - The Visual Studio 2022 x64 build tree was configured/reconfigured from
    MSYS2 CLANG64 with `PATH=/usr/bin:/clang64/bin`, followed by fresh
    four-worker `--clean-first` builds.  Release completed in 31.27 seconds and
    `ctest --test-dir build/vs2022-x64 -C Release --output-on-failure` passed
    4/4 tests in 37.39 seconds: the process-session lifecycle test, the live
    source-policy gate, its forbidden-source fixture contract, and the
    intentionally Release-only install-contract test.
  - The fresh four-worker Debug `--clean-first` build completed in 30.00
    seconds and
    `ctest --test-dir build/vs2022-x64 -C Debug --output-on-failure` passed its
    lifecycle and source-policy tests, 3/3, in 6.33 seconds.  Debug omits the
    install-contract test by design; lifecycle and source-policy validation
    remain required in both configurations.
  - The Release process-session lifecycle test then passed 100 consecutive
    repetitions with `--repeat until-fail:100` in 603.87 seconds.  The immediate
    `Get-Process purepad-process-child` residue gate found zero surviving child
    processes.
  - CTest now enforces the source-policy gate and its behavioral negative
    fixtures; the independent static scan found no forbidden thread-termination
    or startup-association API use in PurePad C++ sources or headers, and
    `git diff --check` passed.  The installed-executable verifier also parses
    the PE header and rejects non-AMD64 machines and non-GUI subsystems through
    mutated negative fixtures.  Process ownership is represented by the tested
    `ProcessSession` lifecycle; PurePad does not terminate worker threads
    asynchronously.
  - `.pure` file-association creation and removal is owned by TODO-49's
    installer, not by PurePad startup.  The same installer owns the deployment
    handoff for the matching Microsoft Visual C++ Redistributable and shared
    MFC runtime; runtime DLLs are not copied from Visual Studio.
  - The final authoritative GitHub Actions GREEN, workflow run `32571242498`,
    validated head `7749fabe` in PurePad job `97026890714` on `windows-2022`
    with Visual Studio 2022.  Validation, configure, build, and test all
    succeeded, as did the CTest artifact upload; the job completed successfully
    at `2026-08-22T11:49:19Z`.
  - The `windows-2022` runner selection is intentional and binding for the
    supported Visual Studio 2022 x64 build: GitHub migrated `windows-2025` to
    Visual Studio 2026 in June 2026, so it no longer supplies the required
    toolchain identity.
- 2026-08-22: Bounded the inherited-stdout reader shutdown identified by the
  lifecycle-hardening final review.
  - The regression now pauses the output callback until cleanup reaches reader
    shutdown, then uses named-event handshakes to keep an inherited descendant
    producing another stdout chunk after every callback.  Against the old
    implementation it failed deterministically after the generous ten-second
    hang-detection bound, released the descendant safely, and left zero child
    residue.
  - The reader now peeks before every read and requests only bytes already
    available.  A generation-local manual-reset event, signaled only after the
    main process exits or is terminated, wakes idle polling and starts a final
    drain bounded independently to 250 ms and 1 MiB.  Reader cleanup no longer
    relies on a one-shot `CancelSynchronousIo`.
  - From the PurePad directory under MSYS2 CLANG64 with
    `PATH=/usr/bin:/clang64/bin`, the four-worker clean Release build completed
    in 34 seconds and the full Release suite passed 4/4 tests in 38.55 seconds.
    The four-worker clean Debug build completed in 30 seconds and the full
    Debug suite passed 3/3 tests in 6.82 seconds.
  - The Release process-session lifecycle test passed 100/100 consecutive
    invocations in 607.88 seconds.  The immediate process-residue gate found
    zero surviving `purepad-process-child` processes; the independent forbidden
    source scan found zero matches, and no root build directory was created.
  - A review follow-up split the two shutdown guarantees into separate tests.
    The continuous-writer case covers the deadline/byte-bounded drain and final
    parent output.  The new empty-pipe case pauses immediately after an
    unsignaled reader-stop check, lets `Stop()` latch the dedicated event, and
    then releases the reader; a deliberate future-byte `ReadFile` mutant failed
    the generous outer hang detector while the peek-based reader passed.
  - With the narrow no-op test seam in production, the focused Debug lifecycle
    case passed 10/10 consecutive invocations in 49.99 seconds.  Four-worker
    clean Release and Debug builds completed in 26 and 25 seconds; their full
    suites passed 4/4 in 32.13 seconds and 3/3 in 5.89 seconds, respectively.
    The earlier 100/100 Release run remains the production-behavior stress
    evidence; this review round added the targeted 10/10 seam-positioned repeat.
