# Reject Windows pure-readline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close TODO-48 as rejected with reproducible evidence that the Windows interpreter already uses GNU readline and that no separate `pure-readline` package belongs in the Windows distribution.

**Architecture:** This is a disposition-only change. Audit the existing core dependency and REPL paths, confirm that no active Windows packaging boundary selects the wrapper, and record those results in TODO-48; do not alter either the interpreter or the portable `pure-readline/` sources.

**Tech Stack:** CMake, GNU readline, Pure C++, PowerShell, Git

## Global Constraints

- The readline DLL used by the core is the single permitted readline runtime in the Windows distribution.
- Do not delete or modify the portable `pure-readline/` sources.
- Do not expose the package's script-facing API from the interpreter core.
- Do not build or package `pure-readline` for Windows.
- Keep validation bounded and automated; Windows Terminal and plain-console checks are optional supplements.
- Do not change unrelated Windows package decisions.

---

## File Structure

- Modify `pure/todo/TODO-48-windows-pure-readline.md`: record the rejected status, completed investigation checklist, evidence, validation commands, and Windows-only disposition.
- Do not modify `pure-readline/`: preserve the portable package byte-for-byte.
- Do not modify packaging code: TODO-49 has not yet created an installer or package-selection manifest, and the core install manifest has no package-extension boundary in which `pure-readline` can be selected.

### Task 1: Record and verify the Windows package rejection

**Files:**
- Modify: `pure/todo/TODO-48-windows-pure-readline.md`
- Reference only: `pure/cmake/PureDependencies.cmake`
- Reference only: `pure/cmake/PureConfigure.cmake`
- Reference only: `pure/cmake/PureTargets.cmake`
- Reference only: `pure/pure.cc`
- Reference only: `pure-readline/readline.c`
- Reference only: `pure-readline/readline.pure`
- Reference only: `.github/workflows/non-linux-release-validation.yml`

**Interfaces:**
- Consumes: the existing `PkgConfig::READLINE` imported target, `HAVE_LIBREADLINE`/`USE_READLINE` configuration, and the interpreter's `readline`, history, completion, EOF, and signal-handling paths.
- Produces: a closed TODO whose normative result is “do not build, stage, or install `pure-readline` in the Windows distribution.”

- [ ] **Step 1: Capture the portable package baseline**

Run:

```powershell
git status --short
git diff -- pure-readline
git ls-files -s pure-readline
```

Expected: the working tree has no unrelated changes that overlap this task; `git diff -- pure-readline` is empty. Save the `git ls-files -s pure-readline` output for comparison in Step 8, but do not add it to the repository.

- [ ] **Step 2: Verify the core dependency and interpreter integration statically**

Run:

```powershell
rg -n -S "pkg_check_modules\(READLINE REQUIRED|PkgConfig::READLINE|HAVE_LIBREADLINE|USE_READLINE" pure/cmake pure/config.h.cmake pure/pure.cc
rg -n -S "readline\(prompt\)|add_history|read_history|write_history|rl_attempted_completion_function|pure_completion|SIGINT|SetConsoleCtrlHandler" pure/pure.cc
```

Expected: CMake requires readline, the `pure` executable links `PkgConfig::READLINE`, configuration enables `HAVE_LIBREADLINE` and `USE_READLINE`, and `pure.cc` contains the REPL input, history, completion, EOF-return, and Windows interruption paths.

- [ ] **Step 3: Verify that the separate wrapper adds only a script-facing API and isolated history**

Run:

```powershell
rg -n -S "using \"lib:readline\"|wrap_readline|wrap_add_history|wrap_clear_history|wrap_read_history|wrap_write_history" pure-readline/readline.pure pure-readline/readline.c
rg -n -S "history_get_history_state|history_set_history_state|rl_attempted_completion_function = NULL|readline\(prompt\)" pure-readline/readline.c
```

Expected: the module exports five thin wrappers, temporarily disables completion, and swaps process-global readline history around each operation. No separate terminal implementation exists.

- [ ] **Step 4: Verify there is no active Windows package selection to patch**

Run:

```powershell
rg -n --hidden -S "pure-readline|readline\.dll|libreadline" .github pure/cmake pure/test pure/todo/TODO-19-portable-windows-runtime.md pure/todo/TODO-49-windows-distribution-installer.md
```

Expected: `pure-readline` appears only in TODO-48 or historical/documentation context; no active CMake install rule, workflow, staging manifest, or installer component selects it. `libreadline8.dll` may appear as the core runtime dependency, but not as a second package-owned copy.

- [ ] **Step 5: Update TODO-48 with the disposition and evidence**

Change the document header and task list to:

```markdown
Status: Rejected on 2026-08-09
Branch: todo/48-windows-pure-readline

## Decision

Do not build, stage, or install the separate `pure-readline` package in the
Windows distribution. The Windows interpreter already requires and links GNU
readline for its interactive input, editing, history, completion, EOF, and
interruption behavior. The package adds only a script-facing wrapper with a
separate history and would share mutable process-global readline state with the
interpreter.

This is a Windows packaging decision only. The portable `pure-readline/`
sources remain unchanged for other platforms and batch-compiled applications.

## Task List

1. [x] Audit the module and duplicate runtime dependency risk.
2. [x] Compare its exported behavior with the core runtime.
3. [x] Audit bounded coverage for input, history, completion, EOF, and interruption.
4. [x] Reject it from the Windows distribution.
```

Append this entry to `## Progress Log`:

```markdown
- 2026-08-09: Rejected the separate package for Windows.
  - `pure/cmake/PureDependencies.cmake` requires GNU readline and
    `pure/cmake/PureTargets.cmake` links `PkgConfig::READLINE` into `pure.exe`.
  - `pure/pure.cc` already supplies readline input/editing, interpreter and
    debugger history, symbol/keyword/command completion, EOF propagation, and
    Windows console interruption handling.
  - `pure-readline` exports only script-callable wrappers for line input and
    history. It disables custom completion and swaps the same library's
    process-global history state, so it does not provide a second Windows
    terminal implementation.
  - No active Windows staging or installer manifest selects the package;
    TODO-49 remains responsible for admitting only independently approved
    packages. The core-owned readline DLL remains the sole permitted copy.
  - Static audits and the existing bounded non-Linux release workflow establish
    the rejection without an unbounded interactive test. The portable
    `pure-readline/` tree was left unchanged.
```

- [ ] **Step 6: Validate the authored disposition before committing**

Run:

```powershell
rg -n -S "^Status: Rejected on 2026-08-09$|^## Decision$|Do not build, stage, or install|Windows packaging decision only|\[x\]" pure/todo/TODO-48-windows-pure-readline.md
git diff --check -- pure/todo/TODO-48-windows-pure-readline.md
git diff -- pure/todo/TODO-48-windows-pure-readline.md
```

Expected: all decision markers are present, all four task items are checked, `git diff --check` is silent, and the diff changes only TODO-48.

- [ ] **Step 7: Commit the disposition**

Run:

```powershell
git add pure/todo/TODO-48-windows-pure-readline.md
git diff --cached --check
git diff --cached --name-only
git commit -m "Reject Windows pure-readline package"
```

Expected: the staged path list contains only `pure/todo/TODO-48-windows-pure-readline.md`, and the commit succeeds.

- [ ] **Step 8: Run final acceptance checks**

Run:

```powershell
git status --short
git diff HEAD^ -- pure-readline
git ls-files -s pure-readline
rg -n --hidden -S "pure-readline" .github pure/cmake pure/test pure/todo/TODO-19-portable-windows-runtime.md pure/todo/TODO-49-windows-distribution-installer.md
git show --stat --oneline HEAD
```

Expected: the working tree is clean; `git diff HEAD^ -- pure-readline` is empty; the `git ls-files` inventory matches Step 1; no active Windows build, test, staging, or installer path selects `pure-readline`; and the final commit changes only TODO-48.
