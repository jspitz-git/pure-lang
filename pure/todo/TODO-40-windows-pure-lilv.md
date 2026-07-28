# TODO-40 - Windows pure-lilv Package

Status: Complete
Branch: todo/40-windows-pure-lilv

## Purpose

Build, validate, and package `pure-lilv` with the Windows LV2 discovery stack.

## Scope

- Use a controlled CLANG64 Lilv build with Dynamic Manifest support enabled
  and stage its transitive runtime dependencies.
- Define relocatable plugin discovery without machine-wide environment changes.
- Cover world creation, metadata discovery, loading, and cleanup.
- Use a small statically described C LV2 plugin for the package's independent
  tests; defer the `pure-lv2` interoperability test to TODO-41.

## Task List

1. [x] Add the CLANG64 CMake build and inventory the complete Lilv dependency
   graph.
2. [x] Enable Dynamic Manifest support in the controlled Lilv build and in
   `pure-lilv` world creation.
3. [x] Define distribution-relative LV2 search behavior and add deterministic
   metadata, processing, state, and lifecycle tests.
4. [x] Stage the module, LV2 specifications, runtime DLL closure, and licenses;
   validate the relocated package with a sanitized environment.

## Guardrails

- Do not discover test plugins accidentally from the build host.
- Bundle license material for every copied LV2-stack library.
- Do not depend on the stock MSYS2 Lilv build for Dynamic Manifest support;
  its upstream Meson option defaults to disabled.
- Do not require a machine-wide `LV2_PATH`; tests must provide an isolated
  search root containing only controlled bundles.

## Validation Plan

- First prove that the controlled static test plugin is invisible with an
  empty `LV2_PATH`, then discover it from the staged bundle root.
- Instantiate the plugin, process a fixed buffer, round-trip state, and release
  the plugin and world in a bounded Pure test.
- Verify Dynamic Manifest discovery separately with a controlled manifest
  generator so TODO-41 can rely on the capability.
- Inspect all staged PE dependencies and reject DLLs outside the staged
  runtime or Windows system allowlist.
- Relocate the installed tree and repeat all smoke tests with `PURELIB`
  unset and `PATH` restricted to the relocated `bin` directory and Windows.

## Design Decision

`pure-lilv` is the Windows LV2 host foundation and therefore precedes
`pure-lv2`. The package will use Lilv 0.26.4 built with
`-Ddynmanifest=enabled`, then set `LILV_OPTION_DYN_MANIFEST` before loading a
world. TODO-40 remains independently testable through a minimal static C LV2
plugin. TODO-41 will later provide the stronger cross-package test by
generating a batch-compiled Pure LV2 plugin and loading it through this host.

## Progress Log

- 2026-07-25: Created as an optional audio-plugin Windows package candidate.
- 2026-07-29: Confirmed that the CLANG64 Lilv/LV2 stack is available and that
  `pure-lilv` compiles and links as a PE32+ DLL after replacing the Unix-only
  `alloca.h` include and linking Serd explicitly.
- 2026-07-29: Loaded the module from a relocated Pure staging tree and
  discovered, instantiated, ran, and released a controlled Windows LV2 gain
  plugin with a sanitized environment.
- 2026-07-29: Confirmed that the stock MSYS2 Lilv 0.26.4 build leaves the
  upstream `dynmanifest` Meson feature disabled. Chose a controlled
  Dynamic-Manifest-enabled Lilv build so TODO-41 plugins can be validated.
- 2026-07-29: Built the controlled Lilv 0.26.4 runtime after applying the
  upstream Dynamic Manifest include fix. The isolated CTest discovered both
  static and generated-manifest plugins, processed a fixed audio buffer,
  round-tripped state, saved a relative preset, and passed the PE dependency
  audit.
- 2026-07-29: Installed the module with 5 LV2-stack DLLs, 25 LV2
  specification bundles (82 files), and 6 license directories into the
  combined portable Pure/Tk/GTK tree. The installed verifier passed both
  before and after copying the tree to a new path with spaces, with `PURELIB`
  and `LV2_PATH` unset and `PATH` restricted to the bundle and Windows.
