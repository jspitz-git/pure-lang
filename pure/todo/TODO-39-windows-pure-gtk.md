# TODO-39 - Windows pure-gtk Package

Status: Open
Branch: todo/39-windows-pure-gtk

## Purpose

Determine a maintainable Windows build of `pure-gtk` and package it if the
existing GTK 2 based bindings remain viable.

## Scope

- Build all native bridge components against one controlled GTK stack.
- Bundle the required GTK, GLib, Cairo, Pango, ATK, loader, and data files.
- Validate relocatable loader and theme discovery.

## Task List

1. [ ] Confirm the supported GTK version and CLANG64 dependency set.
2. [ ] Build every advertised module and audit generated bindings.
3. [ ] Define a relocatable minimal GTK runtime layout.
4. [ ] Add bounded widget, callback, rendering, and shutdown tests.
5. [ ] Decide whether to ship, defer, or replace the package.

## Guardrails

- Do not ship a partially functioning GTK runtime.
- Keep GTK loader caches and data paths inside the distribution.

## Validation Plan

- Open and close a representative window with callbacks and text rendering.
- Test on a clean Windows VM with no separately installed GTK.

## Open Questions

- Whether continued GTK 2 packaging is supportable or a newer binding is required.

## Progress Log

- 2026-07-25: Created as an optional GUI Windows package investigation.
