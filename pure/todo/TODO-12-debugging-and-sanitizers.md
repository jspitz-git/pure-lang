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

1. [ ] Add debug-friendly compiler flags without changing release behavior.
2. [ ] Add sanitizer targets or presets with correct compile and link flags.
3. [ ] Configure LLDB launch support and document common breakpoints.
4. [ ] Register JIT debug objects and verify generated function names in LLDB.
5. [ ] Add concise IR/object dumps controlled by a runtime or build option.
6. [ ] Run resource-lifetime and redefinition stress tests under sanitizers.

## Guardrails

- Debug instrumentation must be disabled or low-overhead in release builds.
- Never print host addresses or large IR dumps unconditionally.
- Do not suppress sanitizer findings without a documented root-cause analysis.

## Validation Plan

- `cmake --preset llvm22-asan`
- `cmake --build --preset llvm22-asan`
- `ctest --preset llvm22-asan --output-on-failure`
- Launch the smoke test under `lldb-22` and resolve a named JITed frame.

## Open Questions

- Does LLVM 22's preferred debug plugin require selecting JITLink explicitly?
- Should sanitizer builds disable custom signal handling to improve reports?

## Progress Log

- 2026-07-22: Initial debugging and sanitizer plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
