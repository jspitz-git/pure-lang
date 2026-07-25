# TODO-40 - Windows pure-lilv Package

Status: Open
Branch: todo/40-windows-pure-lilv

## Purpose

Build, validate, and package `pure-lilv` with the Windows LV2 discovery stack.

## Scope

- Use controlled CLANG64 builds of Lilv and its transitive dependencies.
- Define relocatable plugin discovery without machine-wide environment changes.
- Cover world creation, metadata discovery, loading, and cleanup.

## Task List

1. [ ] Build the package and inventory the complete Lilv dependency graph.
2. [ ] Define distribution-relative LV2 search behavior.
3. [ ] Add metadata discovery and lifecycle smoke tests.
4. [ ] Stage and validate the package on a clean Windows VM.

## Guardrails

- Do not discover test plugins accidentally from the build host.
- Bundle license material for every copied LV2-stack library.

## Validation Plan

- Discover a controlled bundled test plugin with a sanitized environment.
- Inspect all PE dependencies and verify deterministic search paths.

## Progress Log

- 2026-07-25: Created as an optional audio-plugin Windows package candidate.
