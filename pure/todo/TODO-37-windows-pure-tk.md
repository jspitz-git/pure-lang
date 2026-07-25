# TODO-37 - Windows pure-tk Package

Status: Open
Branch: todo/37-windows-pure-tk

## Purpose

Build, validate, and package `pure-tk` with a controlled Tcl/Tk runtime on Windows.

## Scope

- Build the native bridge and bundle the required Tcl/Tk files.
- Define reliable script, encoding, and extension lookup within the install prefix.
- Cover interpreter creation, widgets, callbacks, event processing, and shutdown.

## Task List

1. [ ] Build the module against the staged runtime and CLANG64 Tcl/Tk.
2. [ ] Define relocatable Tcl/Tk library discovery.
3. [ ] Add bounded headless or desktop GUI smoke tests.
4. [ ] Stage and audit the complete Tcl/Tk runtime subset.

## Guardrails

- Do not depend on another Tcl/Tk installation or global environment variables.
- Automated windows must close without user interaction.

## Validation Plan

- Create a Tcl interpreter and a minimal widget with a Pure callback.
- Run from a path containing spaces with a sanitized environment.

## Progress Log

- 2026-07-25: Created as an optional GUI Windows package candidate.
