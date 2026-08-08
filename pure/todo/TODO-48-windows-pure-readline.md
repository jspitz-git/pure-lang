# TODO-48 - Windows pure-readline Package

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
3. [x] Audit static core code paths for input, history, completion, EOF, and interruption.
4. [x] Reject it from the Windows distribution.

## Guardrails

- Do not bundle duplicate or conflicting readline/terminal DLLs.
- Runtime and interactive checks are optional supplements, not acceptance
  requirements for this static packaging decision.

## Validation Plan

- Completed static acceptance: audit the core CMake linkage and interpreter
  code paths; audit wrapper exports and process-global state; search active
  Windows package selectors; confirm a clean diff and unchanged portable tree.
- Windows Terminal, plain-console, and other runtime readline behavior checks
  may supplement this evidence but are not required for the rejection.

## Validation

- Core dependency/linkage audit (exit 0):

  ```powershell
  rg -n -S "pkg_check_modules\(READLINE REQUIRED|PkgConfig::READLINE|HAVE_LIBREADLINE|USE_READLINE" pure/cmake pure/config.h.cmake pure/pure.cc
  rg -n -S "readline\(prompt\)|add_history|read_history|write_history|rl_attempted_completion_function|pure_completion|SIGINT|SetConsoleCtrlHandler" pure/pure.cc
  ```

  Found required `READLINE`, `PkgConfig::READLINE` linkage,
  `HAVE_LIBREADLINE`/`USE_READLINE`, and interpreter input, history,
  completion, and interruption paths.

- Wrapper/global-state audit (exit 0):

  ```powershell
  rg -n -S 'using "lib:readline"|wrap_readline|wrap_add_history|wrap_clear_history|wrap_read_history|wrap_write_history' pure-readline/readline.pure pure-readline/readline.c
  rg -n -S 'history_get_history_state|history_set_history_state|rl_attempted_completion_function = NULL|readline\(prompt\)' pure-readline/readline.c
  ```

  Found five script-facing wrappers, saved/restored process-global history,
  disabled custom completion, and no separate terminal implementation.

- Active Windows selector search (exit 0):

  ```powershell
  rg -n --hidden -S "pure-readline|readline\.dll|libreadline" .github pure/cmake pure/test pure/todo/TODO-19-portable-windows-runtime.md pure/todo/TODO-49-windows-distribution-installer.md
  ```

  Found only core configuration and a Linux release dependency; no active
  Windows build, staging, test, or installer selector for `pure-readline`.

- Repository checks (exit 0):

  ```powershell
  git diff --check HEAD^ HEAD
  git status --short
  git diff HEAD^ -- pure-readline
  git ls-files -s pure-readline
  ```

  Diff checks were silent, status was clean, and the portable-tree diff was
  empty with its tracked-file inventory matching the captured baseline. These
  static checks do not exercise runtime readline behavior; such tests are
  optional supplements.

## Progress Log

- 2026-07-25: Created as a compatibility Windows package investigation.
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
  - Static CMake/core, wrapper/global-state, selector, and portable-tree audits
    establish the rejection. Runtime and manual readline behavior tests are
    optional supplements; the portable `pure-readline/` tree was left
    unchanged.
