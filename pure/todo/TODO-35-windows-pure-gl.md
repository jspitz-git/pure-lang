# TODO-35 - Windows pure-gl Package

Status: Closed on 2026-07-28
Branch: todo/35-windows-pure-gl

## Purpose

Build, validate, and package `pure-gl` with native Windows OpenGL and FreeGLUT.

## Scope

- Build all advertised native components and associated Pure modules.
- Bundle FreeGLUT and other non-system runtime DLLs.
- Cover context creation, rendering, event handling, and clean shutdown.

## Task List

1. [x] Build the package against the staged runtime and CLANG64 FreeGLUT.
2. [x] Inventory OpenGL/GLU/FreeGLUT imports and module coverage.
3. [x] Add a bounded off-screen or hidden-window rendering smoke test.
4. [x] Validate interactive examples on a Windows desktop.
5. [x] Stage and inspect the package outside MSYS2.

## Guardrails

- CI tests must terminate without user interaction.
- Do not bundle Windows system OpenGL DLLs.

## Validation Plan

- Create a context, render a known frame, process events, and exit automatically.
- Run an interactive example and inspect all non-system PE dependencies.

## Progress Log

- 2026-07-25: Created as an optional graphics Windows package candidate.
- 2026-07-28: Added a native CLANG64 CMake build for all seven wrapper families.
  - One `pure-gl.dll` contains GL, GLU, GLUT, ARB, EXT, NV, and ATI wrappers.
  - The build uses strict warnings, staged Pure SDK metadata, FreeGLUT 3.8.0,
    and native Windows OpenGL and GLU import libraries.
  - A clean Release build produced a COFF x86-64 module.
- 2026-07-28: Audited module coverage and the Windows dependency boundary.
  - A marker test loads all seven Pure interfaces and checks a representative
    constant from every wrapper family.
  - The PE audit requires x86-64 `pure-gl.dll` and `libfreeglut.dll`, rejects
    MSYS/GNU runtimes, and records the Windows system API imports.
  - A regression test exposed that CLANG64 installs `libfreeglut.dll` while the
    generated sources requested `freeglut.dll`; the generator template and all
    seven checked-in C files now use the installed name.
- 2026-07-28: Added a bounded hidden-window rendering test.
  - It creates a 32 by 32 RGBA context, clears it to a known color, reads the
    center pixel as `[64,128,191,255]`, and destroys the window.
  - The runner supplies explicit include/module paths, treats Pure diagnostics
    as failures even when the interpreter exits with zero, and has nested
    45/55-second timeouts.
- 2026-07-28: Validated visible rendering and event processing on Windows.
  - The opt-in `check-gl-interactive` target displays an RGB triangle for one
    second, processes a FreeGLUT display event, checks every OpenGL error
    boundary, closes the window, and exits automatically.
  - This test exposed lazy `wglGetProcAddress` calls inside `glBegin/glEnd`.
    Standard exports are now resolved from `opengl32.dll`, `glu32.dll`, and
    FreeGLUT before the WGL extension fallback, eliminating
    `GL_INVALID_OPERATION`.
- 2026-07-28: Staged and inspected the portable Windows package.
  - Installing into a fresh 40-file runtime added exactly 26 files and removed
    none: one module, seven Pure interfaces, `libfreeglut.dll`, its license,
    documentation, examples, and three test scripts.
  - The FreeGLUT DLL hash matches the CLANG64 source runtime. The complete
    staged package passed the load and hidden-render tests with `PURELIB`
    unset and `PATH` restricted to the staged `bin` and Windows system paths.
  - PE inspection passed for both staged binaries. `opengl32.dll`, `glu32.dll`,
    `gdi32.dll`, `user32.dll`, and `winmm.dll` are explicitly forbidden from
    the package.
  - A negative configure test rejected `PURE_LIBRARY_INSTALL_DIR=../escape`.
