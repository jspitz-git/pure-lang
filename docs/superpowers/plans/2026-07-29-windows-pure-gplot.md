# Windows pure-gplot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package `pure-gplot` for portable Windows installations with gnuplot
6.0.4 as a reproducible optional component.

**Architecture:** Keep the public Pure module API and add a focused Windows
process bridge. The bridge uses `CreateProcessW` with an exact application path
and an inherited stdin pipe, resolving the optional gnuplot tree relative to
its own DLL location.
CMake installs the module with or without an explicitly supplied gnuplot root,
and CTest verifies rendering in a path containing spaces with a sanitized
environment.

**Tech Stack:** Pure, C11, Win32 process/pipe APIs, CMake 3.25+, CTest,
Windows PowerShell 5.1, official gnuplot 6.0.4 x86-64 Clang distribution.

## Global Constraints

- The controlled artifact is `gp604-win64-clang.exe` from the official
  gnuplot 6.0.4 SourceForge release directory and must match its upstream
  SHA-256 file.
- Installing `pure-gplot` without gnuplot remains supported.
- Bundling gnuplot is off by default and requires an explicit `GNUPLOT_ROOT`.
- The managed tree is installed below `tools/gnuplot`.
- Windows discovery checks an exact `GPLOT_EXE` first and otherwise derives
  `tools/gnuplot/bin/gnuplot.exe` from `gplot.dll`; it never searches `PATH`.
- All executable and output paths must support spaces.
- Noninteractive rendering is mandatory; the interactive desktop test is
  separately labelled and optional in headless environments.

---

### Task 1: Controlled dependency and launch contract

**Files:**
- Create: `pure-gplot/cmake/AcquireWindowsGnuplot.cmake`
- Create: `pure-gplot/gplot_win.c`
- Modify: `pure-gplot/gplot.pure`
- Create: `pure-gplot/tests/command.pure`
- Create: `pure-gplot/cmake/RunCommandTest.cmake`
- Create: `pure-gplot/CMakeLists.txt`
- Modify: `pure/todo/TODO-42-windows-pure-gplot.md`

**Interfaces:**
- Consumes: `GPLOT_EXE` as an optional exact executable path.
- Produces: `gplot::GPLOT_EXE`, `gplot::open executable`,
  `lib/pure/gplot.dll`, and an extracted root whose
  `bin/gnuplot.exe` reports version `6.0 patchlevel 4`.

- [x] **Step 1: Write the command-contract test**

  Add `tests/command.pure` which imports `gplot`, asserts the expected value of
  `gplot::GPLOT_EXE`, opens it, sends `print GPVAL_VERSION` and `exit`, and
  asserts that `gplot::close` returns zero. `RunCommandTest.cmake` must unset
  `PURELIB`, set `GPLOT_EXE` to a controlled executable below a path containing
  spaces, and restrict `PATH` to the staged Pure runtime plus Windows.

- [x] **Step 2: Verify the existing implementation fails**

  Configure with:

  ```powershell
  cmake -S pure-gplot -B "C:\tmp\Pure Gplot Build 20260729" `
    -G Ninja -DBUILD_TESTING=ON `
    -DPURE_PREFIX="C:\tmp\pure-liblo-stage-final-20260728"
  ctest --test-dir "C:\tmp\Pure Gplot Build 20260729" `
    -R pure-gplot-command --output-on-failure
  ```

  Expected: failure because the original CRT `popen` path splits the spaced
  executable name and, through the Pure system wrapper, closes the child stdin
  pipe before the first write.

- [x] **Step 3: Implement controlled acquisition and discovery**

  `AcquireWindowsGnuplot.cmake` must download only the pinned official URL,
  validate `EXPECTED_HASH SHA256=2c31e3fc91b21c450f4b015f1cd1f2f84f7a8cfc63afc037f9ba5efb47cc0c23`, silently extract/install to
  a caller-provided child directory, and verify `gnuplot.exe --version`.
  `gplot_win.c` must export `gplot_open(const char*)`,
  `gplot_write(void*, const char*)`, `gplot_close(void*)`, and
  `gplot_default_executable(void)`. It must use `CreateProcessW` with an exact
  application path and inherited stdin pipe, resolve the managed executable
  relative to its DLL, and never invoke or search through a command shell.
  Update `gplot.pure` to preserve the public `open/puts/close` API through these
  functions on Windows while retaining the Unix implementation.

- [x] **Step 4: Run the command test**

  Run the focused CTest command from Step 2. Expected: one passing test with
  `PATH` containing no unrelated gnuplot.

- [x] **Step 5: Record and commit the verified step**

  Check task 2 in TODO-42, record the pinned checksum and command-contract
  result, then commit:

  ```powershell
  git add pure-gplot pure/todo/TODO-42-windows-pure-gplot.md
  git commit -m "Make pure-gplot launch controlled Windows gnuplot"
  ```

### Task 2: Deterministic rendering and interactive smoke coverage

**Files:**
- Create: `pure-gplot/tests/render.pure`
- Create: `pure-gplot/tests/interactive.pure`
- Create: `pure-gplot/cmake/RunRenderTest.cmake`
- Create: `pure-gplot/cmake/RunInteractiveTest.cmake`
- Modify: `pure-gplot/CMakeLists.txt`
- Modify: `pure/todo/TODO-42-windows-pure-gplot.md`

**Interfaces:**
- Consumes: `gplot::open`, `gplot::output`, `gplot::plotxy`,
  `gplot.dll`, and an explicit test output root.
- Produces: CTest `pure-gplot-render` and optional
  `pure-gplot-interactive`.

- [x] **Step 1: Add the failing deterministic test**

  `render.pure` must select `pngcairo size 320,200`, write
  `known plot.png`, render fixed x/y vectors, call `unset output`, and close
  gnuplot. `RunRenderTest.cmake` must check the eight-byte PNG signature,
  decode the big-endian IHDR dimensions as 320 by 200, require a payload above
  1 KiB, and fail on a nonzero Pure or gnuplot exit status.

- [x] **Step 2: Run the deterministic test before fixes**

  Run:

  ```powershell
  ctest --test-dir "C:\tmp\Pure Gplot Build 20260729" `
    -R pure-gplot-render --output-on-failure
  ```

  Expected: failure until CMake provides the controlled launcher, module path,
  gnuplot root, and spaced output directory.

- [x] **Step 3: Wire render and interactive tests**

  Add `PURE_GPLOT_INTERACTIVE_TESTS` defaulting to `OFF`. The interactive
  script must select the `windows` terminal, draw fixed data, send
  `pause 1`, `set term windows close`, and `exit`; its runner must enforce a
  20-second timeout. Label the tests `render;windows` and
  `interactive;desktop;windows` respectively.

- [x] **Step 4: Verify both tests**

  Run the complete CTest suite with interactive tests enabled from an
  interactive desktop. Expected: command, render, and interactive tests all
  pass; rerun with `GPLOT_EXE` and the gnuplot directory removed from `PATH`
  except through the managed launcher.

- [x] **Step 5: Record and commit the verified step**

  Check task 3 in TODO-42, record the PNG and desktop results, then commit:

  ```powershell
  git add pure-gplot pure/todo/TODO-42-windows-pure-gplot.md
  git commit -m "Test pure-gplot rendering on Windows"
  ```

### Task 3: Optional installation and relocated-package verification

**Files:**
- Create: `pure-gplot/cmake/Install.cmake`
- Create: `pure-gplot/cmake/VerifyInstalledPackage.cmake`
- Create: `pure-gplot/WINDOWS.md`
- Modify: `pure-gplot/CMakeLists.txt`
- Modify: `pure/todo/TODO-42-windows-pure-gplot.md`

**Interfaces:**
- Consumes: `PURE_GPLOT_INSTALL_GNUPLOT=ON|OFF`, explicit
  `GNUPLOT_ROOT`, an existing portable Pure prefix, and installed test scripts.
- Produces: `lib/pure/gplot.pure`, `lib/pure/gplot.dll`, documentation and,
  only when enabled, `tools/gnuplot`.

- [x] **Step 1: Add install rules and the installed verifier**

  Install the Pure module and native bridge unconditionally. When
  `PURE_GPLOT_INSTALL_GNUPLOT=ON`, reject an absent or wrong-version
  `GNUPLOT_ROOT`, copy the complete controlled tree below `tools/gnuplot`, and
  install gnuplot provenance/license material below
  `share/doc/pure-gplot/licenses/gnuplot`. Install the existing LGPL/GPL files,
  examples, Windows instructions, and render test.

- [x] **Step 2: Stage into a copied portable prefix**

  Copy the current verified Windows bundle to a new path, install
  `pure-gplot` with the optional component enabled, then run:

  ```powershell
  cmake -DSTAGE_PREFIX="C:\tmp\Pure Gplot Stage 20260729" `
    -DSOURCE_RUNTIME_DIR="C:\path\to\source-bundle\bin" `
    -P pure-gplot/cmake/VerifyInstalledPackage.cmake
  ```

  The verifier must unset `PURELIB` and `GPLOT_EXE`, restrict `PATH`, render
  below a path containing spaces, validate the PNG, confirm gnuplot 6.0.4, and
  confirm `open` fails without searching `PATH` after the optional component is hidden.

- [x] **Step 3: Relocate and repeat**

  Copy the complete stage to a differently named path containing spaces and
  rerun the installed verifier. Expected: the same checks pass without any
  source, build, MSYS2, or original-prefix path in the environment.

- [x] **Step 4: Close and commit TODO-42**

  Set the TODO status to complete, check task 4, record the installed inventory
  and relocation evidence, then commit:

  ```powershell
  git add pure-gplot pure/todo/TODO-42-windows-pure-gplot.md
  git commit -m "Package pure-gplot as an optional Windows component"
  ```

### Task 4: Integrate into windows-bundle

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: verified `todo/42-windows-pure-gplot`.
- Produces: pushed `windows-bundle` containing the merge commit.

- [ ] **Step 1: Run fresh feature-branch verification**

  Run the complete CTest suite, the installed verifier against the relocated
  prefix, `git diff --check`, and `git status --short`. Expected: all tests
  pass and the worktree is clean.

- [ ] **Step 2: Merge and verify the result**

  Switch to `windows-bundle`, merge with `--no-ff`, and rerun the same CTest
  and installed verification commands. Stop without pushing on any failure.

- [ ] **Step 3: Push and confirm**

  Push `windows-bundle`, verify `HEAD` equals `origin/windows-bundle`, and
  delete the merged local TODO branch.
