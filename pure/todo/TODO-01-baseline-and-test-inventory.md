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

1. [x] Document how the current test runner discovers inputs and expected results.
2. [ ] Map tests to the migration areas and record important coverage gaps.
3. [ ] Add focused tests for function redefinition and closure code lifetime.
4. [ ] Define the initial smoke subset that each later TODO must run.
5. [ ] Validate the test inventory and record any tests that cannot run before the port.

## Baseline Findings

### Test runner

- `configure` generates `run-tests` and `run-test` from their corresponding `.in`
  files and marks both scripts executable.
- `make check` builds `pure` and invokes `./run-tests`; `make recheck` invokes
  `./run-tests -f` to rerun tests with an existing `.diff` failure artifact.
- With no explicit arguments, `run-tests` selects `lib/prelude.pure` followed by
  every `test/test*.pure` file in lexical order. An explicit list runs only the
  named inputs.
- The corpus contains 95 numbered `.pure` inputs, 95 matching golden `.log`
  files, and four architecture-specific `.blob` fixtures. `prelude.log` is the
  golden output for the additional prelude input. `special.pure` and
  `special.log` exist but are not selected by the default runner.
- Each input is piped through `run-test`; combined stdout and stderr are compared
  with its source-tree golden log using unified `diff`. Failures are retained as
  `test/<name>.diff` in the build tree.
- `run-test` sets the build-tree runtime library path, `srcdir`, `PURELIB`,
  `PURE_INCLUDE`, and `LC_ALL=C`, then executes `./pure --norc -v7`. The prelude
  test additionally receives `-n`. `PURE_FLAGS` can inject variants such as
  `--notc` into all runs.
- `run-tests -v` prints failure diffs, `run-tests -f` reruns prior failures, and
  `run-tests file...` runs a targeted subset.

### Preliminary migration coverage

- `test001.pure`: core definitions, globals, recursion, lambdas, local `with`
  environments, integers, and big integers.
- `test004.pure`: local environment capture and local/global tail recursion;
  deep proper-tail-call cases are present but commented out.
- `test013.pure`: external C symbol resolution and a constant initialized from
  an external call.
- `test016.pure`: nested local environments.
- `test018.pure`: signed and unsigned integer marshalling through the C interface.
- `test023.pure`: thunks and delayed infinite-list evaluation.
- `test029.pure`: lifetime regression when replacing a global value.
- `test030.pure`: thunks, `catch`, lambdas, and generated-code equivalence.
- `test036.pure`: local function/operator definitions and local closures.
- `test052.pure`: stale function-pointer regression; old global and local
  closures are invoked after their functions are extended, cleared, and redefined.

The default numbered corpus has no direct test of `LoadBitcode` or
`LoadFaustDSP`. `test089.pure` contains an abridged Faust language DSL, not a
compiled DSP module. Actual bitcode and Faust examples live under
`examples/bitcode/` and require separate fixture generation and test coverage.

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

- 2026-07-22: Documented the test runner, corpus layout, first migration-critical
  tests, and the missing bitcode/Faust integration coverage.
  - Validation:
    - `find test -maxdepth 1 -name 'test*.pure' -type f | wc -l` reported 95.
    - `find test -maxdepth 1 -name 'test*.log' -type f | wc -l` reported 95.
    - `find test -maxdepth 1 -name '*.blob' -type f | wc -l` reported 4.
    - Inspected `run-tests.in`, `run-test.in`, the listed focused tests, and
      `examples/bitcode/Makefile`; no executable test run was possible because
      the configured runner and LLVM-compatible `pure` binary do not exist yet.
- 2026-07-22: Initial migration baseline plan created.
  - Validation:
    - Not run; this update created planning documentation only.
