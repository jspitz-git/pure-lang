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

1. [ ] Create and validate a 64-bit MFC build.
2. [ ] Fix compiler, Unicode, path-length, and ownership issues found by the build.
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
