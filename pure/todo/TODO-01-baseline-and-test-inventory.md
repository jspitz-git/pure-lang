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
2. [x] Map tests to the migration areas and record important coverage gaps.
3. [ ] Add focused tests for function redefinition and closure code lifetime.
   - `test052` now covers three simultaneous generations and out-of-order closure
     release; execution remains pending until the LLVM 22 interpreter is runnable.
4. [x] Define the initial smoke subset that each later TODO must run.
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

### Migration coverage map

| Migration area | Existing coverage | Assessment |
| --- | --- | --- |
| Basic JIT and IR generation | `test001`, `test002` | Definitions, guards, recursion, lambdas, local functions, integers, and big integers provide a useful initial execution baseline. |
| Local environments and closures | `test004`, `test016`, `test036` | Covers nested environments, captured values, local operators, and unevaluated local closures. |
| Function lifetime and redefinition | `test029`, `test052`, `test056` | Covers replacement of a live global value, stale global/local function pointers, `clear`, and dynamic defined/undefined behavior. |
| Tail calls | `test002`, `test004` | Shallow local/global cases run by default; stack-independent deep cases exist but are commented out. |
| External symbols and C ABI | `test013`, `test018`, `test037`, `test042`, `test045`, `test054`, `test068` | Covers math/process symbols, private externals, constant folding, integer marshalling, lazy function-pointer lookup, temporary lifetimes, C strings, and `getenv`. |
| Exceptions and unwind paths | `test017`, `test030`, `test063`, `test072`, `test075`, `test085`, `test092` | Covers `throw`/`catch` in language and library paths, but not failures during ORC materialization or resource removal. |
| Thunks and delayed code | `test023`, `test030` | Exercises delayed infinite lists and thunked/caught generated code. |
| Data layout and host ABI | `test018`, `test025`, `test041`, `test042` | Exercises numeric C marshalling, matrices, serialization, and four cross-architecture blob fixtures. |
| Generic bitcode loading | none in default corpus | Examples exist under `examples/bitcode/`, but no golden regression invokes `LoadBitcode`. |
| Faust DSP loading and reload | none in default corpus | `test089` is only a Faust-like language DSL; it does not compile or load a DSP module. |

### Important coverage gaps

- No minimal test repeatedly compiles and removes anonymous evaluation functions,
  so ORC `ResourceTracker` cleanup and memory growth are not covered.
- `test052` now includes a focused case with three generations and closures
  released in a different order, but it cannot be behaviorally validated until
  the LLVM 22 interpreter is runnable.
- Proper tail-call behavior is not asserted at a depth that would overflow the C
  stack without tail-call elimination; the deep cases in `test004` are commented.
- Unresolved external symbols and ORC lookup/materialization errors have no golden
  diagnostic test.
- Generic bitcode load, duplicate symbols, incompatible target/data layout, unload,
  and malformed bitcode are absent from the default suite.
- Faust initial load, ABI rejection, successful hot reload, failed hot reload, and
  old-wrapper lifetime are absent.
- No sanitizer-oriented stress test checks code/global lifetime after exceptions or
  failed compilation.

Actual bitcode and Faust examples live under `examples/bitcode/`; they require
modern fixture generation and dedicated automated coverage rather than inclusion
as opaque historical `.bc` files.

### Required smoke subsets

Every implementation TODO that produces a runnable interpreter must first run the
core subset:

```sh
./run-tests \
  test/test001.pure \
  test/test004.pure \
  test/test013.pure \
  test/test016.pure \
  test/test029.pure \
  test/test036.pure \
  test/test052.pure
```

This set covers basic generated code, recursion, captured environments, external
symbol lookup, global value replacement, local closures, and function generations
surviving `clear` and redefinition.

Changes affecting calls, data layout, exceptions, thunks, globals, or resource
lifetime must additionally run the extended JIT subset:

```sh
./run-tests \
  test/test018.pure \
  test/test023.pure \
  test/test030.pure \
  test/test041.pure \
  test/test042.pure \
  test/test054.pure \
  test/test056.pure
```

The full numbered corpus remains the final check for a completed implementation
TODO. Bitcode and Faust TODOs must add and run their own integration tests because
neither feature is exercised by these subsets.

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

- 2026-07-22: Defined a seven-test core smoke subset and a seven-test extended
  JIT subset, with full-corpus and feature-specific escalation rules.
  - Validation:
    - Confirmed that every listed source has a matching golden `.log` file.
    - Execution remains deferred until a compatible `pure` binary and generated
      runner are available.
- 2026-07-22: Extended `test052` with three live function generations and
  out-of-order release of newer closures before invoking the oldest closure.
  - Validation:
    - `git diff --check` passed for the test source, golden log, and TODO update.
    - Static review confirmed matching commands and expected scalar results in
      `test052.pure` and `test052.log`.
    - Execution is blocked because neither generated `run-tests` nor a compatible
      `pure` executable exists; checklist item 3 remains open until it runs.
- 2026-07-22: Mapped migration areas to focused regression tests and recorded
  gaps in resource cleanup, deep tail calls, symbol failures, bitcode, Faust,
  and sanitizer stress coverage.
  - Validation:
    - Inspected focused tests `001`, `002`, `004`, `013`, `016`, `018`, `023`,
      `029`, `030`, `036`, `037`, `042`, `045`, `052`, `054`, `056`, and `068`.
    - Confirmed that the default numbered corpus contains no direct
      `LoadBitcode` or `LoadFaustDSP` integration test.
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
