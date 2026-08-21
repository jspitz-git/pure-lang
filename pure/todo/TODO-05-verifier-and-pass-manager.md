# TODO-05 - Verifier and New Pass Manager

Status: Closed on 2026-07-24; audited and corrected on 2026-08-21
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
3. [x] Run function or module optimization at a clearly defined ownership boundary.
4. [x] Verify before optimization in every build and after optimization in debug
   builds.
5. [x] Surface verifier and pass errors through Pure diagnostics.
6. [x] Compare representative optimized IR with unoptimized output for ABI changes.

## Optimization Policy

The supported LLVM 22 runtime uses the standard O1 function-simplification
pipeline for completed interactive functions and the standard per-module O1
pipeline for reduced ORC snapshots. Keeping both boundaries at O1 provides one
correctness baseline and avoids unmeasured behavioral differences between
interactive definitions, imported providers, and their submitted snapshots.

Task 6 compared representative unoptimized and O1 IR directly and verified both
forms. The temporary comparison files were removed, so the original experiment
is recorded in the progress log but cannot be reproduced from this repository.
That is an evidence-retention limitation, not a runtime O0 requirement: the
interpreter has no supported runtime O0 mode. Adding one solely for a one-time
smoke comparison would create a new configuration surface without a release
requirement. A future ABI comparison should retain its input IR and command as a
test fixture. A runtime optimization selector, custom pipeline, or lazy-JIT
performance work requires profiling and belongs outside this correctness
migration.

## Guardrails

- Correctness takes priority over matching the exact historical optimization sequence.
- Do not enable aggressive or parallel optimization before basic JIT tests pass.
- Preserve tail calls and exception/unwind paths during optimization.

## Validation Plan

- Configure and build a Release tree with LLVM 22 and `BUILD_TESTING=ON`.
- Run `pure-jit-invalid-function-verifier`; its test-only hook injects malformed
  function IR immediately before optimization and requires the actionable
  `LLVM verifier failed before optimization` diagnostic.
- Run `pure-jit-smoke` to cover the normal O1 JIT path without injection.
- For a future O0/O1 ABI comparison, retain the representative IR as a fixture
  and verify both forms rather than relying only on a historical log entry.

## Decisions

- Interactive function optimization and reduced ORC module optimization both use
  O1. Batch modernization must preserve that baseline unless later profiling
  justifies a deliberate difference.
- LLVM's standard O1 pipelines remain preferred over an unmeasured custom pass
  sequence. Performance tuning is not part of the LLVM 22 correctness release.

## Progress Log

- 2026-08-21: Audited the completed implementation and corrected a Release-only
  verifier gap.
  - The pre-optimization `verifyFunction` call was guarded by `NDEBUG`. Release
    therefore admitted malformed function IR into the O1 pass pipeline; only the
    later reduced-module verifier reported it before ORC submission.
  - Made function verification unconditional before O1. The post-optimization
    verifier remains debug-only, and the existing module verifier still protects
    the ORC submission boundary.
  - Added `pure-jit-invalid-function-verifier`, using the existing
    `PURE_ENABLE_TEST_HOOKS` mechanism to inject malformed IR at the precise
    function/pipeline boundary.
  - Red result before the production fix: the focused Release test failed because
    it saw only `failed to snapshot deferred ORC global function: invalid reduced
    ORC module`, not the required pre-optimization diagnostic.
  - Green result after the fix: Release `pure-jit-smoke` and
    `pure-jit-invalid-function-verifier` both passed (2/2, 1.23 seconds) with
    Clang/LLVM 22.1.8 in the MSYS2 CLANG64 environment.
  - The original task 6 comparison cannot be independently reproduced because
    its temporary IR files were deleted. The historical ABI conclusions remain
    documented, but a future repeat must retain a fixture and command.

- 2026-07-23: Compared representative Pure-style opaque-pointer IR before and
  after LLVM 22 `default<O1>` optimization.
  - Both the input and optimized modules passed
    `opt-22 -passes=verify -disable-output`.
  - O1 preserved symbol names, pointer parameter/result types, address space
    zero, `fastcc`, parameter counts, and the existing tail-call marker.
  - Mem2reg removed the test alloca, an ordinary call was safely promoted to a
    tail call, and the `%expr` field GEP was canonically lowered to the
    equivalent byte offset. Added `readonly`, `captures(none)`, and
    `local_unnamed_addr` properties do not change the function ABI.
  - Temporary comparison files were removed after validation.
  - This completes TODO-05. Executing Pure smoke tests at O0/O1 remains blocked
    until TODO-06 replaces the legacy JIT and produces a runnable interpreter.
- 2026-07-23: Confirmed actionable diagnostics across all verifier boundaries.
  - Function failures throw Pure `err` values with the phase, symbol name, and
    complete LLVM diagnostic.
  - Linked Faust and generic bitcode modules return diagnostics through their
    existing `msg` results; batch compilation raises a Pure compiler error.
  - LLVM's new transformation pass managers return `PreservedAnalyses`, not
    `Error`; malformed pass output is therefore surfaced by the debug
    post-optimization verifier rather than a separate pass error channel.
  - This completes task 5 without introducing a process-aborting LLVM handler.
- 2026-07-23: Added debug-only function verification before and after O1
  optimization.
  - Verification failures now throw a Pure `err` containing the phase, function
    name, and complete LLVM verifier diagnostic.
  - Removed five unchecked `verifyFunction` calls; batch `main` remains covered
    by the actionable whole-module verifier immediately before output.
  - Validation:
    - Both `llvm22-debug` and `llvm22-release` configured successfully.
    - Both builds compiled the new verifier path with zero warnings and no new
      errors, retaining only the nine known legacy JIT errors.
    - Release uses `-DNDEBUG`, confirming that pre/post verification is omitted
      there as intended.
- 2026-07-23: Replaced the legacy function pass manager with the LLVM 22 O1
  function-simplification pipeline.
  - Optimization runs only after a generated or imported function body is
    complete, at the five existing function-finalization boundaries.
  - Cached function analyses are explicitly invalidated before each fresh
    pipeline run, protecting the long-lived mutable interpreter module from
    stale analysis results.
  - Removed the legacy pass manager member, headers, manual pass sequence, and
    initialization/finalization lifecycle.
  - The full module O1 pipeline remains reserved for a future one-shot module
    ownership boundary before ORC submission or batch output.
  - Validation:
    - `cmake --preset llvm22-debug` configured successfully.
    - `cmake --build --preset llvm22-debug -- -j1` compiled all five new
      optimization call sites with zero warnings and no new errors; only the
      nine known legacy JIT errors remain.
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
- 2026-07-24: Closed the deferred optimization-policy questions after TODO-06
  made the O1 runtime path executable.
  - Validation:
    - Confirmed both active function and ORC module pipelines select LLVM O1 and
      expose no runtime O0 selector.
    - Retained the recorded verifier-backed unoptimized/O1 IR comparison as the
      ABI-equivalence check.
    - `ctest --preset llvm22-debug -R '^pure-jit-smoke$'
      --output-on-failure` passed 1/1 in 5.90 seconds.
    - Classified runtime O0, custom pipelines, and performance tuning as future
      measured design work rather than release correctness requirements.
