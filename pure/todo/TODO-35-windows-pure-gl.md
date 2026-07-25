# TODO-35 - Windows pure-gl Package

Status: Open
Branch: todo/35-windows-pure-gl

## Purpose

Build, validate, and package `pure-gl` with native Windows OpenGL and FreeGLUT.

## Scope

- Build all advertised native components and associated Pure modules.
- Bundle FreeGLUT and other non-system runtime DLLs.
- Cover context creation, rendering, event handling, and clean shutdown.

## Task List

1. [ ] Build the package against the staged runtime and CLANG64 FreeGLUT.
2. [ ] Inventory OpenGL/GLU/FreeGLUT imports and module coverage.
3. [ ] Add a bounded off-screen or hidden-window rendering smoke test.
4. [ ] Validate interactive examples on a Windows desktop.
5. [ ] Stage and inspect the package outside MSYS2.

## Guardrails

- CI tests must terminate without user interaction.
- Do not bundle Windows system OpenGL DLLs.

## Validation Plan

- Create a context, render a known frame, process events, and exit automatically.
- Run an interactive example and inspect all non-system PE dependencies.

## Progress Log

- 2026-07-25: Created as an optional graphics Windows package candidate.
