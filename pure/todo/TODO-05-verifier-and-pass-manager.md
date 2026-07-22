# TODO-05 - Verifier and New Pass Manager

Status: Open
Branch: todo/05-verifier-and-pass-manager

## Purpose

Replace the legacy function pass manager with LLVM 22's new pass manager and make IR
verification a standard boundary before JIT compilation. Success means malformed IR
fails with an actionable diagnostic before entering ORC.

## Scope

- Set up `PassBuilder` and the required analysis managers.
- Replace the old mem2reg, instcombine, reassociation, GVN, and CFG pipeline.
- Add verifier checks and useful IR dumps around compilation boundaries.
- Start with correctness-oriented optimization; performance tuning is later work.

## Task List

1. [x] Introduce reusable new-pass-manager analysis state.
2. [x] Select an initial interactive pipeline, preferably standard `O1`.
3. [ ] Run function or module optimization at a clearly defined ownership boundary.
4. [ ] Add verification before and after optimization in debug builds.
5. [ ] Surface verifier and pass errors through Pure diagnostics.
6. [ ] Compare representative optimized IR with unoptimized output for ABI changes.

## Guardrails

- Correctness takes priority over matching the exact historical optimization sequence.
- Do not enable aggressive or parallel optimization before basic JIT tests pass.
- Preserve tail calls and exception/unwind paths during optimization.

## Validation Plan

- `cmake --build --preset llvm22-debug`
- `opt-22 -passes=verify -disable-output` on emitted pre- and post-pass IR.
- Run smoke tests at `O0` and `O1` and compare observable results.

## Open Questions

- Should interactive and batch compilation use different optimization levels?
- Is a custom small pipeline measurably preferable to LLVM's standard `O1` pipeline?

## Progress Log

- 2026-07-23: Selected LLVM's standard correctness-oriented O1 pipelines.
  - Interactive optimization will use the repeatable O1 function-simplification
    pipeline for newly completed functions.
  - Finalized batch or ORC modules will use a fresh per-module default O1
    pipeline once at a defined ownership boundary; it will not be repeatedly
    applied to the long-lived mutable interpreter module.
  - Pipeline factories are now part of `NewPassManagerState`; execution and
    analysis invalidation remain task 3.
  - Validation:
    - `cmake --preset llvm22-debug` configured successfully.
    - `cmake --build --preset llvm22-debug -- -j1` compiled both LLVM 22 O1
      pipeline factories with zero warnings and no new errors; only the nine
      known legacy JIT errors remain.
- 2026-07-23: Added interpreter-owned LLVM 22 new-pass-manager analysis state.
  - `NewPassManagerState` owns `PassBuilder` plus loop, function, CGSCC, and
    module analysis managers and cross-registers their proxies once.
  - The implementation is hidden behind a forward-declared interpreter member;
    the active legacy optimization pipeline is unchanged for this milestone.
  - Validation:
    - `cmake --preset llvm22-debug` configured successfully.
    - `cmake --build --preset llvm22-debug -- -j1` compiled the new state with
      zero warnings and no new errors; only the nine known legacy JIT errors
      remain.
- 2026-07-22: Initial verifier and pass-manager plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
