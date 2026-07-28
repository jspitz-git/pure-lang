# TODO-37 - Windows pure-tk Package

Status: Closed on 2026-07-28
Branch: todo/37-windows-pure-tk

## Purpose

Build, validate, and package `pure-tk` with a controlled Tcl/Tk runtime on Windows.

## Scope

- Build the native bridge and bundle the required Tcl/Tk files.
- Define reliable script, encoding, and extension lookup within the install prefix.
- Cover interpreter creation, widgets, callbacks, event processing, and shutdown.

## Task List

1. [x] Build the module against the staged runtime and CLANG64 Tcl/Tk.
2. [x] Define relocatable Tcl/Tk library discovery.
3. [x] Add bounded headless or desktop GUI smoke tests.
4. [x] Stage and audit the complete Tcl/Tk runtime subset.

## Guardrails

- Do not depend on another Tcl/Tk installation or global environment variables.
- Automated windows must close without user interaction.

## Validation Plan

- Create a Tcl interpreter and a minimal widget with a Pure callback.
- Run from a path containing spaces with a sanitized environment.

## Progress Log

- 2026-07-25: Created as an optional GUI Windows package candidate.
- 2026-07-28: Added a native CLANG64 CMake build for pure-tk.
  - The module links against the installed Tcl/Tk 8.6 import libraries and
    builds with strict warnings as COFF x86-64 `tk.dll`.
  - Direct imports are `tcl86.dll`, `tk86.dll`, `libpure.dll`, and UCRT.
  - Commit: `278895c0` (`Build pure-tk on Windows`).
- 2026-07-28: Validated relocatable Tcl/Tk discovery and dependency closure.
  - A staged runtime in a path containing spaces finds `lib/tcl8.6` and
    `lib/tk8.6` with all Tcl/Tk/Pure discovery environment variables cleared.
  - A mutation run without the script trees fails on missing `init.tcl`; the
    complete runtime passes encoding-data and Unicode roundtrip checks.
  - PE inspection covers the module plus Tcl, Tk, and zlib and rejects
    MSYS/GCC/C++ runtimes.
  - Commit: `a5130d9a` (`Validate relocatable Tcl Tk runtime`).
- 2026-07-28: Added a bounded native GUI lifecycle test.
  - It creates a hidden button, invokes a real Pure callback with data,
    processes a scheduled Tk event, destroys the root window, and verifies
    interpreter shutdown without user interaction.
  - Both tests use nested 25/35-second timeouts.
  - Commit: `0cdaa9fc` (`Test pure-tk Windows GUI lifecycle`).
- 2026-07-28: Staged and audited the portable pure-tk package.
  - Installing into a fresh 40-file runtime added exactly 907 files and
    removed none: two DLLs, the module/interface, 821 Tcl files, 75 Tk core
    files, documentation/licenses, and two test scripts.
  - `zlib1.dll` and `libpure.dll` are reused byte-for-byte from the base
    runtime. Demo and logo trees are excluded from the runtime subset.
  - Both installed GUI tests and the staged PE audit passed with a sanitized
    environment. A negative configure test rejected an escaping install path.
  - `gnocl.pure` remains deferred to TODO-38 after the GTK investigation.