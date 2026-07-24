# TODO-01 - Baseline and Test Inventory

Status: Closed on 2026-07-24
Branch: todo/01-baseline-and-test-inventory

## Purpose

Establish the existing tests and documented behavior as the migration baseline without
requiring an installation of unsupported LLVM 3.5. Success means that later LLVM 22
changes can be evaluated against a clear, runnable set of expectations.

## Scope

- Inventory `run-tests`, the `test/` corpus, examples, and expected outputs.
- Identify tests covering JIT compilation, closures, redefinition, bitcode, and Faust.
- Add narrowly scoped regression cases where critical behavior is not covered.
- Do not install or build LLVM 3.5 as a prerequisite.

## Task List

1. [x] Document how the current test runner discovers inputs and expected results.
2. [x] Map tests to the migration areas and record important coverage gaps.
3. [x] Add focused tests for function redefinition and closure code lifetime.
4. [x] Define the initial smoke subset that each later TODO must run.
5. [x] Validate the test inventory and record any tests that cannot run before the port.

## Retrospective Inventory

With no explicit arguments, `run-tests` executes `lib/prelude.pure` followed by
sorted `test/test*.pure` inputs. Each input is run by `run-test` through the
build-tree interpreter with the source `lib` and `test` directories configured
as search paths. Output is compared verbatim with the same-basename `.log` file;
a failure leaves a unified `.diff` in the build tree. This raw comparison also
explains why CRLF source and golden files remain a release-harness issue.

Later TODOs supplied the migration coverage this initial plan requested:

- `pure-jit-smoke` became the minimal typed lookup/materialization/removal gate;
- `test096.pure` covers nested closures, old recursive generations, mutual
  recursion, redefinition, and reentrant clear;
- `pure-jit-lifetime-stress` repeats retained-closure and generation cleanup
  without prelude startup and has passed Debug, Release, ASan/UBSan, and LSan;
- focused bitcode tests cover duplicate exports, malformed input, ABI mismatch,
  unresolved dependencies, and unload;
- `pure-faust-lifecycle` covers load, reload, rollback, sample ABI rejection,
  live-instance protection, and teardown when Faust is available; and
- the current focused suite is all CTest tests except `pure-regression`.

Before the port, no supported LLVM 22 interpreter existed and no retained LLVM
3.5 executable was used as an oracle. TODO-02 through TODO-06 preserve the exact
compile boundaries which prevented JIT execution. The checked-in golden logs
remained the behavioral oracle. TODO-13 later ran every complete preset and
classified the remaining regression-corpus CRLF and startup-duration gaps.

## Guardrails

- Treat existing expected results as the behavioral specification unless clearly broken.
- Do not rewrite broad groups of expected outputs merely to make the new runtime pass.
- Keep tests independent of a locally installed LLVM 3.5 executable.

## Validation Plan

- Inspect the test runner with `./run-tests --help` if supported.
- Run syntax-only or non-JIT checks that work before the LLVM migration.
- After a runnable LLVM 22 binary exists, run the defined smoke subset and `ctest`.

## Decisions

- No previously built Pure executable was used; checked-in golden outputs were
  the behavioral oracle.
- Faust integration tests require the external `faust` compiler and are
  registered only when CMake finds it. The source fixtures themselves remain in
  the corpus when the tool is unavailable.

## Progress Log

- 2026-07-22: Initial migration baseline plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
- 2026-07-24: Reconciled the baseline retrospectively after the LLVM 22 port.
  Later TODOs supplied all requested coverage and preserved the pre-runtime
  build blockers, while TODO-13 classified the complete current corpus.
  - Validation:
    - Inspected `run-tests.in` and `run-test.in` discovery, environment, golden
      output, and diff behavior.
    - Cross-checked focused JIT, closure/redefinition, bitcode, Faust, and
      lifetime tests against TODO-09 through TODO-13.
    - No test was rerun because this step reconciles already recorded results.
