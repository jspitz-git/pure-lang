# TODO-38 - Windows pure-tk-examples Package

Status: Closed on 2026-07-28
Branch: todo/38-windows-pure-tk-examples

## Purpose

Validate and package `pure-tk-examples` after `pure-tk` is available on Windows.

## Scope

- Install examples, data files, and documentation without hard-coded source paths.
- Classify examples as automated, interactive, or unsupported.
- Repair Windows path and newline assumptions found during execution.

## Task List

1. [x] Inventory every example and its runtime/data dependencies.
2. [x] Add a bounded staged-runtime dependency probe.
3. [x] Classify all three applications from runtime evidence.
4. [x] Exclude unsupported payloads and document future enablement.

## Guardrails

- Do not mark an example supported based only on successful parsing.
- Interactive examples must not be part of an unbounded CI test.

## Validation Plan

- [x] Run the bounded Tcl package probe to completion against the staged
  `pure-tk` runtime with no external Tcl library paths.
- [x] Confirm that no example remains classified as supported, so no parsing
  result is mistaken for a successful interactive validation.

## Decision

- Defer the entire package and install none of its application payloads in the
  first Windows bundle.
- `pure-gtk` supplies GTK 2 but not the required Gnocl and GnoclCanvas Tcl
  extensions.
- Reconsider `graphedit` and `pong` after a compatible GnoclCanvas stack is
  packaged. Reconsider `scale` only after that stack, VTK Tcl bindings, and
  TODO-43 (`pure-octave`) are all complete.
- Keep the complete dependency and data-file inventory in
  `pure-tk-examples/WINDOWS.md`.

## Progress Log

- 2026-07-25: Created as a follow-up to the Windows `pure-tk` package.
- 2026-07-28: Inventoried 56 application files: 10 for `graphedit`, 5 for
  `pong`, and 41 for `scale`; all three applications are interactive.
- 2026-07-28: Confirmed that `graphedit` and `pong` require both Gnocl and
  GnoclCanvas. The MSYS2 CLANG64 package set supplies neither extension.
- 2026-07-28: Confirmed that `scale` additionally requires the historical
  `vtk` and `vtkinteraction` Tcl packages, Pure Octave, and Octave.
- 2026-07-28: Ran the bounded dependency probe against the verified portable
  `pure-tk` staging prefix. All four Tcl `package require` operations reported
  unavailable, and Pure Octave was absent from the staged module set.
- 2026-07-28: Classified zero applications as shippable and excluded the
  package from the first Windows bundle rather than distributing untested or
  nonfunctional examples.
