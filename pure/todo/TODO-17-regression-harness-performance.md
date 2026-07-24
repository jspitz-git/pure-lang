# TODO-17 - Regression Harness Performance

Status: Open
Branch: todo/17-regression-harness-performance

## Purpose

Reduce the complete regression corpus runtime without weakening process isolation or
golden-output coverage. Success means the supported corpus fits a documented CI and
release-validation budget in Debug, Release, and sanitizer configurations.

## Scope

- Measure prelude compilation and per-script startup costs by preset.
- Determine which tests require isolated processes or filesystem state.
- Evaluate safe parallel execution, precompiled prelude reuse, or a persistent runner.
- Keep TODO-13's CRLF normalization at the harness boundary unless the corpus is
  deliberately normalized in a separate review.

## Task List

1. [ ] Record per-test and startup timings in all supported presets.
2. [x] Classify isolation and shared-filesystem constraints across the corpus.
3. [x] Choose a bounded execution design which preserves test semantics.
4. [x] Implement deterministic scheduling and collision-free output handling.
5. [ ] Validate identical golden results before and after the harness change.
6. [ ] Set and document realistic CTest timeouts for complete release runs.

## Isolation Audit

All 96 `test001.pure` through `test096.pure` inputs may run concurrently when
each retains its current independent `run-test` interpreter process. They must
not share an interpreter: tests define, trace, and clear global symbols, including
redefinition/lifetime cases whose isolation is part of their semantics.

No test launches an external process, changes directory, mutates the parent
environment, or writes a shared path during normal top-level execution. The only
explicit filesystem API is in `test042.pure`: its unused `write_test` helper can
write an arbitrary path, but the executed test only reads four fixed blob fixtures
under `srcdir/test`. `test035.pure` also loads a read-only example by relative path.
Workers must therefore retain the existing build working directory and inherited
`srcdir`, but distinct tests have no active filesystem conflict.

Parallel hazards are currently confined to `run-tests.in`:

- persistent `test/<basename>.diff` files are both failure results and the `-f`
  selection database, so concurrent harness invocations can overwrite state;
- transient names include the parent `$$` and rely on unique basenames;
- the loop replaces one shell-global cleanup trap for every test;
- direct worker status and verbose-diff output would interleave by completion order.

## Bounded Execution Design

The implementation will preserve one process per test and the existing logical
order: prelude first, then sorted corpus inputs, or explicit command-line order.
It will:

1. acquire a build-directory lock before `-f` selection and hold it through result
   publication, preventing concurrent harnesses from racing on persistent diffs;
2. reject duplicate basenames because the basename remains the persistent result key;
3. create one run-scoped staging directory with one ordinal child per test, holding
   normalized input/expected output, candidate diff, status, and captured output;
4. execute a bounded number of silent workers selected by `TEST_JOBS` or `-j`, with
   a compatibility default of one until preset budgets choose an explicit value;
5. replay status, publish/remove persistent diffs, and print `-v` output strictly in
   original test order, independent of worker completion order;
6. use one run-scoped cleanup trap and preserve aggregate nonzero exit status.

This changes scheduling and temporary ownership only. Golden comparison, CRLF
normalization, process isolation, deterministic output, and `run-tests -f`
semantics remain unchanged.

## JIT Startup Root Cause

The parallel runner exposed a runtime regression rather than an inherently expensive
corpus. Each of the 97 isolated processes loaded the 1848-line prelude, and one empty
Release process spent 22.91 seconds and 115 MiB doing so; the same ASan/UBSan process
spent 68.08 seconds and 750 MiB. Starting without the prelude took 0.01 and 0.04
seconds respectively, while `test001` added only 3.00 and 6.41 seconds. Test complexity
was therefore not the dominant cost.

Prelude loading produced 530 separately optimized and materialized ORC objects: 272
global function generations, 220 external wrappers, 25 type functions, and 13
anonymous evaluations. Every entry submission first serialized the entire growing
interpreter module, parsed it in a new LLVM context, reduced it to the entry, ran a
second O1 module pipeline after function O1, and forced object emission through
`lookup`. This made startup quadratic in accumulated IR and defeated the historical
`DEFER_GLOBALS` policy. Commit `ead40820` introduced the eager global-generation
lookup even though the published closure still received a null function pointer.

Entry snapshots now clone only reachable definitions before bitcode serialization.
Deferred global generations retain that reduced bitcode buffer without an LLVM
context or resource tracker; first closure invocation parses, optimizes, submits, and
resolves it. This preserves immutable generations and process isolation while
restoring lazy compilation. Empty-prelude object emission dropped from 530 to 260.
Release prelude startup fell to 3.72 seconds and `test001` to 5.59 seconds. The complete
four-worker Release corpus passed 97/97 in 292.28 seconds, restoring the expected
several-minute scale.

ASan allocator quarantine explains the remaining memory multiplier. With compact lazy
snapshots, an empty sanitizer prelude process used 272 MiB with no quarantine, 413 MiB
with a 64 MiB quarantine, and 718 MiB with the default quarantine. Eight default
workers can therefore consume about 5.7 GiB even though retained JIT code is not that
The complete post-fix sanitizer run selected four workers and a nonzero 64 MiB
quarantine: all 97 inputs passed in 1280.27 seconds without a sanitizer finding or
golden difference. This establishes an observed 22-minute sanitizer baseline while
keeping expected interpreter RSS near 1.65 GiB for four concurrent workers. The policy
still needs to be encoded in presets and CTest timeouts.

## Guardrails

- Do not hide failures by sharding away or disabling corpus inputs.
- Preserve verbatim logical output comparison after line-ending normalization.
- Do not share interpreter state between tests unless equivalence is demonstrated.

## Validation Plan

- Run the complete corpus before and after the change and compare all outcomes.
- Exercise interrupted runs and `run-tests -f` cleanup/retry behavior.
- Run the final design in Debug, Release, and sanitizer presets within its stated budget.

## Origin

Created from TODO-13 retrospective gate 6. TODO-13 fixes CRLF-sensitive input and
golden comparison; this follow-up owns the independent repeated-startup performance cost.
Deterministic runtime/golden failures exposed by the completed runner belong to TODO-18.

## Progress Log

- 2026-07-24: Classified corpus isolation and selected the bounded execution design.
  - Audited all 96 regression inputs for process, environment, working-directory,
    random/timing, and filesystem side effects.
  - Confirmed per-test processes are required but distinct tests have no active
    write conflict; `test042.pure` only reads fixtures in its executed path.
  - Located concurrency hazards in persistent failure diffs, PID-only temporary
    names, loop-local traps, and completion-order terminal output.
  - Selected a locked, run-scoped, ordinal staging design with bounded silent
    workers and deterministic ordered result publication.
  - Validation:
    - Read-only source and harness audit; no build or runtime test was required.
- 2026-07-24: Implemented bounded parallel execution with deterministic publication.
  - Added `-j jobs` with `TEST_JOBS` as its environment default while preserving
    serial execution when neither selects a larger worker count.
  - Added an exclusive build-directory lock, one run-scoped staging tree, ordinal
    worker directories, duplicate-basename rejection, and signal/exit cleanup.
  - Workers retain separate interpreter processes and write no terminal or persistent
    result state; the parent publishes pass/fail lines and `.diff` files in input order.
  - Validation:
    - Generated Release runner passed `sh -n`.
    - `test001.pure` and CRLF-sensitive `test070.pure` passed under both `-j 1`
      and `-j 2` with byte-identical ordered terminal output.
    - A precreated lock blocked a second invocation, and a duplicate `test001`
      argument was rejected before execution.
    - An intentionally invalid `PURE_FLAGS` run created a failure result; `-f -j 2`
      selected, passed, and cleared exactly that test on retry.
    - Four Release inputs passed in 98.68 seconds with `-j 1` and 34.79 seconds
      with `-j 4`, a 2.84x wall-clock speedup with identical outcomes.
- 2026-07-24: Captured worker-shell diagnostics for deterministic publication.
  - Redirected each background worker's own output into its ordinal staging area;
    unexpected shell diagnostics are appended to a failed diff in input order.
  - Validation:
    - A parallel Release run with the known-failing prelude followed by passing
      `test001.pure` emitted only their ordered status/diff output; no `Aborted`
      diagnostic escaped ahead of parent publication.
- 2026-07-24: Completed and classified the first bounded full Release corpus run.
  - `run-tests -j 4` executed the prelude and all 96 numbered tests in 1347.36
    seconds: 77 passed and 20 produced persistent golden diffs.
  - A serial `run-tests -f -j 1` reran the 20 failures in 789.98 seconds and
    reproduced every one, excluding parallel scheduling as their cause.
  - Classified 11 ORC definition/materialization failures, three formatted-input
    failures, one blob-fixture failure, and five other language/runtime differences.
  - Created TODO-18 to own behavior compatibility and the all-golden release gate;
    TODO-17 remains scoped to timing, scheduling equivalence, and preset budgets.
  - Validation:
    - Complete Release corpus finished without a harness timeout or lost result.
    - Persistent diffs selected exactly the same 20 inputs for the serial `-f` run.
- 2026-07-24: Completed the corrected Release corpus within a bounded budget.
  - After TODO-18 fixed all deterministic runtime differences, `run-tests -j 4`
    passed all 97 inputs in 897.16 seconds with deterministic ordered output.
  - This establishes a 15-minute observed Release baseline; timeout policy remains
    open until Debug and sanitizer measurements determine preset-specific budgets.
- 2026-07-24: Completed the corrected Debug corpus and measured its worker budget.
  - `run-tests -j 4` exceeded a 30-minute outer limit, so four workers are not a
    sufficient Debug release-validation configuration on this host.
  - Timeout termination correctly removed all workers, the run-scoped staging tree,
    and the build-directory lock, confirming interrupted-run cleanup at corpus scale.
  - `run-tests -j 8` passed all 97 inputs in 1043.32 seconds with deterministic
    ordered output and no golden difference.
  - This establishes an observed 18-minute Debug baseline with eight workers;
    sanitizer measurement is still required before setting preset timeout policy.
- 2026-07-24: Measured the first complete ASan/UBSan corpus execution.
  - Four workers exceeded a 60-minute outer limit and cleaned up all run state.
  - Eight workers completed all 97 inputs in 5273.61 seconds, establishing an
    88-minute pre-fix baseline while exposing five genuine sanitizer findings.
  - The five-input failed-only confirmation passed in 260.41 seconds after their
    runtime fixes; a clean complete run remains required for the final budget.
- 2026-07-24: Removed quadratic ORC startup work and restored deferred globals.
  - Isolated prelude timing proved test bodies were not the dominant cost: no-prelude
    startup was effectively instantaneous, while every process rebuilt 530 ORC units.
  - Reduced entry modules before serialization and retained unmaterialized global
    generations as compact bitcode snapshots until their first closure invocation.
  - Release prelude startup improved from 22.91 to 3.72 seconds; ASan/UBSan improved
    from 68.08 to 12.56 seconds. Prelude object emission fell from 530 to 260 objects.
  - Measured sanitizer RSS at 272 MiB without quarantine, 413 MiB with a 64 MiB
    quarantine, and 718 MiB with the default quarantine.
  - Validation:
    - Release and ASan/UBSan JIT smoke and lifetime stress tests passed.
    - All 12 focused Release tests passed in 36.18 seconds.
    - All 12 focused ASan/UBSan tests passed in 112.44 seconds.
    - The complete four-worker Release corpus passed 97/97 in 292.28 seconds.
- 2026-07-24: Completed the post-fix sanitizer corpus within a bounded budget.
  - Four workers with `PURE_STACK=0` and a 64 MiB ASan quarantine passed all 97
    inputs in 1280.27 seconds with deterministic output and no sanitizer finding.
  - This establishes a 22-minute observed sanitizer baseline and completes the
    final behavioral measurement needed for preset-specific policy.
