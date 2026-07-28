# TODO-39 - Windows pure-gtk Package

Status: Complete
Branch: todo/39-windows-pure-gtk

## Purpose

Determine a maintainable Windows build of `pure-gtk` and package it if the
existing GTK 2 based bindings remain viable.

## Scope

- Build all native bridge components against one controlled GTK stack.
- Bundle the required GTK, GLib, Cairo, Pango, ATK, loader, and data files.
- Validate relocatable loader and theme discovery.

## Task List

1. [x] Confirm the supported GTK version and CLANG64 dependency set.
2. [x] Build every advertised module and audit generated bindings.
3. [x] Define a relocatable minimal GTK runtime layout.
4. [x] Add bounded widget, callback, rendering, and shutdown tests.
5. [x] Decide whether to ship, defer, or replace the package.

## Guardrails

- Do not ship a partially functioning GTK runtime.
- Keep the loader-cache template and GTK data paths inside the distribution;
  materialize only the absolute cache in a per-user temporary directory.

## Validation Plan

- [x] Open and close a representative window with callbacks and text rendering.
- [x] Run the combined staging prefix with MSYS2 removed from `PATH`, all GTK
  discovery variables unset, and every non-system PE dependency constrained to
  the staging prefix. This provides the clean-runtime check without requiring a
  separately provisioned Windows VM.

## Open Questions

- GTK 2 remains a legacy compatibility stack. New Pure GUI development should
  not add GTK 2-only dependencies, but the existing binding is supportable in
  the Windows bundle while MSYS2 CLANG64 continues to provide GTK 2.

## Decision

- Ship `pure-gtk` as an optional legacy-compatible Windows package.
- Keep the five existing modules (`gtk`, `glib`, `atk`, `cairo`, and `pango`)
  together with one controlled GTK 2 runtime.
- Generate the absolute GdkPixbuf loader cache at run time from a relocatable
  installed template. Do not require an MSYS2 installation at run time.
- Revisit replacement by a newer GUI binding separately; it is not required
  for the first Windows bundle.

## Progress Log

- 2026-07-25: Created as an optional GUI Windows package investigation.
- 2026-07-28: Selected the MSYS2 CLANG64 stack: GTK 2.24.33, GLib 2.88.2,
  ATK 2.60.5, Cairo 1.18.4, and Pango 1.58.0.
- 2026-07-28: Built and audited all five x86-64 PE modules, including 31 GTK
  UTF-8 compatibility exports and rejection of MSYS/GNU ABI dependencies.
- 2026-07-28: Added bounded native and Pure GUI lifecycle tests covering
  widget creation, callbacks, rendering setup, and shutdown.
- 2026-07-28: Added a relocatable installation containing 42 hash-matched
  runtime DLLs, 13 GdkPixbuf loaders, 2 GTK engines, the GAIL accessibility
  module, themes, icons, Fontconfig data, and 35 license directories.
- 2026-07-28: Verified the combined portable Pure, pure-ffi, and pure-gtk
  staging tree from a path containing spaces with MSYS2 absent from `PATH`.
  The three installed runtime tests passed and every non-system PE dependency
  resolved inside the staging prefix.
