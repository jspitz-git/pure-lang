# TODO-12 - Debugging and Sanitizers

Status: Open
Branch: todo/12-debugging-and-sanitizers

## Purpose

Make LLVM 22 and ORC failures diagnosable with LLDB, useful JIT symbol information, and
sanitizer presets. Success means interpreter and JIT lifetime defects can be reproduced
with actionable stack traces rather than opaque crashes.

## Scope

- Standardize LLDB 22 as the primary debugger and keep GDB usable.
- Add debug, ASan/UBSan, and optional LeakSanitizer configurations.
- Integrate available ORC/JITLink debug-object registration for JITed symbols.
- Improve diagnostics around verification, materialization, lookup, and removal.

## Task List

1. [x] Add debug-friendly compiler flags without changing release behavior.
2. [x] Add sanitizer targets or presets with correct compile and link flags.
3. [ ] Configure LLDB launch support and document common breakpoints.
4. [ ] Register JIT debug objects and verify generated function names in LLDB.
5. [ ] Add concise IR/object dumps controlled by a runtime or build option.
6. [ ] Run resource-lifetime and redefinition stress tests under sanitizers.

## Debug-Friendly Builds

`PURE_DEBUG_FRIENDLY` is enabled by default and augments Clang C and C++
compilation in Debug configurations with:

- `-fno-omit-frame-pointer` for reliable stack unwinding;
- `-fno-optimize-sibling-calls` to preserve caller frames;
- `-fstandalone-debug` to retain complete type information; and
- `-gdwarf-4` for debugger-compatible linked debug information.

The option does not affect non-Debug configurations. DWARF 4 avoids invalid
DWARF 5 string offsets produced when GNU ld links the current Clang 22 objects.
`llvm-dwarfdump-22` still reports discarded-COMDAT range diagnostics for some
linked C++ template instances from LLVM headers. The corresponding project
objects verify without errors, and switching Debug links to LLD 22 does not
remove these range diagnostics.

## Sanitizer Builds

`PURE_SANITIZERS` accepts a comma-separated list of Clang sanitizers and applies
one matching `-fsanitize=` value to C and C++ compilation and to executable and
shared-library linking. Sanitized code always preserves frame pointers. Keeping
this in the toolchain avoids divergent compile and link flags and leaves the
standard `CMAKE_*_FLAGS` cache entries available to callers.

The `llvm22-asan` configure preset selects `address,undefined`. Its test preset
stops on ASan and UBSan findings, requests UBSan stack traces, and disables leak
scanning because the interpreter currently stalls during shutdown for several
bitcode tests even with no sanitizer diagnostic. The separate `llvm22-lsan`
test preset enables leak scanning against the same build for targeted tests.
No sanitizer finding is suppressed; Clang's documented `function` exception for
ORC-generated call targets remains scoped to `pure-jit-smoke`.

## Guardrails

- Debug instrumentation must be disabled or low-overhead in release builds.
- Never print host addresses or large IR dumps unconditionally.
- Do not suppress sanitizer findings without a documented root-cause analysis.

## Validation Plan

- `cmake --preset llvm22-asan`
- `cmake --build --preset llvm22-asan`
- `ctest --preset llvm22-asan -R pure-jit-smoke --output-on-failure`
- `ctest --preset llvm22-lsan -R pure-jit-smoke --output-on-failure`
- Launch the smoke test under `lldb-22` and resolve a named JITed frame.

## Open Questions

- Does LLVM 22's preferred debug plugin require selecting JITLink explicitly?
- Should sanitizer builds disable custom signal handling to improve reports?

## Progress Log

- 2026-07-22: Initial debugging and sanitizer plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
- 2026-07-24: Added opt-out debug-friendly Clang flags for complete types,
  reliable stack frames, and linker-compatible DWARF without changing Release.
  - Validation:
    - `cmake --preset llvm22-debug`
    - `cmake --preset llvm22-asan`
    - `cmake --preset llvm22-release`
    - `cmake --build --preset llvm22-debug --parallel 1`
    - `cmake --build --preset llvm22-release --parallel 1`
    - `ctest --preset llvm22-debug -R pure-jit-smoke --output-on-failure`
      passed.
    - `ctest --preset llvm22-release -R pure-jit-smoke --output-on-failure`
      passed.
    - Debug C++ commands contain all four debug-friendly flags; ASan inherits
      them, while Release remains `-O3 -DNDEBUG` without debug instrumentation.
    - `llvm-dwarfdump-22 --verify` reports no errors for `interpreter.cc.o`,
      `pure_jit.cc.o`, `pure-jit-smoke.cc.o`, or the `pure` executable.
    - The Release `libpure.so.8` contains no `.debug_*` sections.
- 2026-07-24: Centralized Clang sanitizer instrumentation behind
  `PURE_SANITIZERS` and added explicit ASan/UBSan and targeted LSan test modes.
  - Validation:
    - `cmake --list-presets=all` listed the `llvm22-lsan` test preset alongside
      the existing configure, build, and test presets.
    - `cmake --preset llvm22-asan --fresh`
    - `cmake --build --preset llvm22-asan --parallel 1`
    - Generated C and C++ compile commands contain one
      `-fsanitize=address,undefined` and one `-fno-omit-frame-pointer`; executable
      and shared-library links contain the same sanitizer selection.
    - The sanitizer build's general C, C++, executable-linker, and
      shared-linker `CMAKE_*_FLAGS` cache entries remain empty.
    - `ctest --preset llvm22-asan -R pure-jit-smoke --output-on-failure` passed
      without ASan or UBSan diagnostics.
    - `ctest --preset llvm22-lsan -R pure-jit-smoke --output-on-failure` passed
      without ASan, UBSan, or LeakSanitizer diagnostics.
    - A full sanitizer CTest run was attempted. All five bitcode interpreter
      tests timed out with leak detection enabled; focused reruns still timed
      out with leak detection disabled and produced no sanitizer diagnostics.
      Lifecycle stress and root-cause analysis remain in task 6. The Faust
      lifecycle test remained explicitly disabled in the sanitizer
      configuration.
