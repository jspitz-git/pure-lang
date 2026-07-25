# TODO-41 - Windows pure-lv2 Package

Status: Open
Branch: todo/41-windows-pure-lv2

## Purpose

Build, validate, and package `pure-lv2` after the required Windows Lilv/LV2
infrastructure is available.

## Scope

- Build the native host/bridge components with the distribution toolchain.
- Cover plugin instantiation, ports, processing, state, errors, and cleanup.
- Package a controlled test plugin for deterministic validation where licensing permits.

## Task List

1. [ ] Build the package against the staged Pure and Lilv runtimes.
2. [ ] Audit host ABI, plugin discovery, and native DLL loading.
3. [ ] Add deterministic plugin instantiation and processing tests.
4. [ ] Stage and validate the package outside MSYS2.

## Guardrails

- Do not claim compatibility with arbitrary plugins from a single test plugin.
- Keep real-time callbacks free of avoidable blocking or allocation regressions.

## Validation Plan

- Load a known plugin, process a fixed buffer, verify output, save state, and unload.
- Run on a clean VM without external LV2 environment variables.

## Progress Log

- 2026-07-25: Created as a follow-up to the Windows `pure-lilv` package.
