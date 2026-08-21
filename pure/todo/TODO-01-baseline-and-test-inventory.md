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

## Historical Integration Note

The original TODO-01 work was developed in commits `46a0ecaf0`, `f86ef8fb7`,
`64d0cc0c5`, and `29d24ddde`. Those commits are not ancestors of the TODO closure
commit `a3b0336f1`; they became reachable from the current `HEAD` through other
later history. The three-generation closure case added to `test052.pure` by
`64d0cc0c5` is present in the current tree, but it was not part of the ancestry
used when `a3b0336f1` marked the TODO closed. The branch named above is therefore
a historical work-branch identifier; closure evidence and eventual integration
must be evaluated separately.

The checklist was closed retrospectively because later integrated TODOs supplied
equivalent or stronger coverage. The inventory and smoke subsets below recover
the useful documentation from the unintegrated work, while the replacement
coverage section identifies what is actually durable in the current tree.

## Baseline Inventory

### Test runner

- `configure` generates `run-tests` and `run-test` from their corresponding `.in`
  files. `make check` builds `pure` and invokes `./run-tests`; `make recheck`
  invokes `./run-tests -f` to rerun tests with an existing `.diff` artifact.
- With no explicit arguments, the runner selects `lib/prelude.pure` followed by
  every `test/test*.pure` file in lexical order. An explicit list runs only the
  named inputs. At the original inventory point the numbered corpus contained 95
  sources and matching logs; the integrated corpus later grew through
  `test096.pure`.
- `run-test` sets the build-tree runtime library path, `srcdir`, `PURELIB`,
  `PURE_INCLUDE`, and `LC_ALL=C`, then executes `./pure --norc -v7`. The prelude
  input additionally receives `-n`; `PURE_FLAGS` supplies variants such as
  `--notc`.
- At closure time, combined stdout and stderr were compared directly with the
  same-basename source-tree `.log`, and failures left a unified `.diff` in the
  build tree. The current runner first strips trailing CR characters from the
  input, golden log, and interpreter output, checks the interpreter exit status,
  and then compares the normalized output. This normalization was added later
  and resolves the historical CRLF harness gap described by TODO-13 and TODO-17.
- `run-tests -v` prints failure diffs, `run-tests -f` reruns prior failures, and
  `run-tests file...` runs a targeted subset. The current runner also supports
  parallel jobs and timings through `-j` and `-t`.

### Migration coverage map at the baseline

| Migration area | Existing coverage | Baseline assessment |
| --- | --- | --- |
| Basic JIT and IR generation | `test001`, `test002` | Definitions, guards, recursion, lambdas, local functions, integers, and big integers. |
| Local environments and closures | `test004`, `test016`, `test036` | Nested environments, captured values, local operators, and unevaluated local closures. |
| Function lifetime and redefinition | `test029`, `test052`, `test056` | Replacement of a live global value, stale global/local function pointers, `clear`, and dynamic defined/undefined behavior. |
| Tail calls | `test002`, `test004` | Shallow local/global cases ran by default; stack-independent deep cases were commented out. |
| External symbols and C ABI | `test013`, `test018`, `test037`, `test042`, `test045`, `test054`, `test068` | Math/process symbols, private externals, constant folding, integer marshalling, lazy lookup, temporary lifetimes, C strings, and `getenv`. |
| Exceptions and unwind paths | `test017`, `test030`, `test063`, `test072`, `test075`, `test085`, `test092` | Language and library `throw`/`catch`, but not ORC materialization or resource-removal failures. |
| Thunks and delayed code | `test023`, `test030` | Delayed infinite lists and thunked/caught generated code. |
| Data layout and host ABI | `test018`, `test025`, `test041`, `test042` | Numeric C marshalling, matrices, serialization, and architecture-specific blob fixtures. |
| Generic bitcode loading | none in the default corpus | Examples existed under `examples/bitcode/`, but no golden regression invoked `LoadBitcode`. |
| Faust DSP loading and reload | none in the default corpus | `test089` was a Faust-like language DSL, not a DSP compile/load integration test. |

### Important baseline gaps

- No minimal test repeatedly compiled and removed anonymous evaluation functions,
  so ORC `ResourceTracker` cleanup and memory growth were not covered.
- Before `64d0cc0c5`, `test052` detected stale pointers after redefinition but did
  not stress several simultaneous generations released out of order. That commit
  supplied the missing case and is present in the current history and tree.
- Proper tail-call behavior was not asserted at a depth that would overflow the C
  stack without tail-call elimination.
- Unresolved externals and ORC lookup/materialization errors had no golden
  diagnostic test.
- Generic bitcode load, duplicate symbols, incompatible target/data layout,
  unload, and malformed bitcode were absent from the default suite.
- Faust initial load, ABI rejection, successful and failed hot reload, and old
  wrapper lifetime were absent.
- No sanitizer-oriented stress test covered code/global lifetime after exceptions
  or failed compilation.

### Initial smoke subsets

Every implementation TODO producing a runnable interpreter was expected to run
this core subset first:

```sh
./run-tests \
  test/test001.pure test/test004.pure test/test013.pure \
  test/test016.pure test/test029.pure test/test036.pure \
  test/test052.pure
```

Changes affecting calls, data layout, exceptions, thunks, globals, or resource
lifetime were expected to add the extended JIT subset:

```sh
./run-tests \
  test/test018.pure test/test023.pure test/test030.pure \
  test/test041.pure test/test042.pure test/test054.pure \
  test/test056.pure
```

The full numbered corpus remained the final implementation check. Bitcode and
Faust work required dedicated integration tests because neither feature was
covered by these subsets.

## Integrated Replacement Coverage

Later TODOs supplied the migration coverage requested by TODO-01:

- the focused three-generation and out-of-order-release case is present in
  `test052.pure` through `64d0cc0c5`;
- `pure-jit-smoke` became the minimal typed lookup/materialization/removal gate;
- `test096.pure` covers nested closures, old recursive generations, mutual
  recursion, redefinition, and reentrant clear;
- `pure-jit-lifetime-stress` repeats retained-closure and generation cleanup
  without prelude startup and has passed Debug, Release, ASan/UBSan, and LSan;
- focused bitcode tests cover duplicate exports, malformed input, ABI mismatch,
  unresolved dependencies, and unload;
- `pure-faust-lifecycle` covers load, reload, rollback, sample ABI rejection,
  live-instance protection, and teardown when Faust is available; and
- the focused CTest gate is all registered tests except `pure-regression`.

Before the port, no supported LLVM 22 interpreter existed and no retained LLVM
3.5 executable was used as an oracle. TODO-02 through TODO-06 preserve the exact
compile boundaries which prevented JIT execution. The checked-in golden logs
remained the behavioral oracle. TODO-13 later ran every complete preset and
classified the regression-corpus CRLF and startup-duration gaps; TODO-17 then
addressed those harness issues.

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
- 2026-08-20: Audited the closure and restored the durable baseline inventory.
  - Recorded that the original TODO-01 documentation and `test052` commits were
    outside the closure ancestry; although the commits became reachable through
    later history, the original `test052` change is present in the current tree.
  - Restored the coverage map, known gaps, and initial smoke subsets from the
    historical commits and separated closure-time evidence from eventual
    integration.
  - Distinguished closure-time raw comparison from the current CRLF-normalizing,
    exit-status-aware test harness and identified the later integrated tests
    which replace the missing TODO-01 coverage.
  - Validation:
    - Inspected the ancestry and contents of `46a0ecaf0`, `f86ef8fb7`,
      `64d0cc0c5`, `29d24ddde`, and closure commit `a3b0336f1`.
    - Cross-checked the current `run-tests.in`, `run-test.in`, `test096.pure`,
      and CTest registrations; no executable test was run for this
      documentation-only correction.
