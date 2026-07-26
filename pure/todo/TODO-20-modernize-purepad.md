# TODO-20 - Modernize PurePad

Status: Open
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
3. [ ] Launch the sibling `pure.exe` without depending on global `PATH`.
4. [ ] Move per-user state to an appropriate Windows application-data directory.
5. [ ] Validate editing, execution, interruption, diagnostics, help, and shutdown.

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
