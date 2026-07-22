# TODO-01 - Baseline and Test Inventory

Status: Open
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

1. [ ] Document how the current test runner discovers inputs and expected results.
2. [ ] Map tests to the migration areas and record important coverage gaps.
3. [ ] Add focused tests for function redefinition and closure code lifetime.
4. [ ] Define the initial smoke subset that each later TODO must run.
5. [ ] Validate the test inventory and record any tests that cannot run before the port.

## Guardrails

- Treat existing expected results as the behavioral specification unless clearly broken.
- Do not rewrite broad groups of expected outputs merely to make the new runtime pass.
- Keep tests independent of a locally installed LLVM 3.5 executable.

## Validation Plan

- Inspect the test runner with `./run-tests --help` if supported.
- Run syntax-only or non-JIT checks that work before the LLVM migration.
- After a runnable LLVM 22 binary exists, run the defined smoke subset and `ctest`.

## Open Questions

- Is a previously built Pure executable available as an optional behavioral oracle?
- Which Faust tests require external tools not currently installed?

## Progress Log

- 2026-07-22: Initial migration baseline plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
