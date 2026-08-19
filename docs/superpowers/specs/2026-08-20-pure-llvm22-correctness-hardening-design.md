# Pure LLVM 22 Correctness Hardening Design

## Purpose

The LLVM 22 port passes its normal JIT, regression, Faust C-backend, and
lifetime tests, but its error paths do not consistently preserve ownership or
interpreter state. A failed reload, import, materialization, or temporary
evaluation can mutate live state before the replacement has proved usable.
The regression runner can also accept a crashed interpreter, and inline Faust
still selects a direct bitcode route which is incompatible with the configured
LLVM 22 toolchain.

This change makes failed operations observationally atomic, makes cleanup
exception-safe, and establishes one supported Faust compilation pipeline.

## Scope

In scope:

- Batch Faust reload state and generation ownership.
- Generic batch bitcode import.
- Deferred global materialization and retry.
- Temporary `doeval` and `dodefn` interpreter state.
- Inline Faust compilation.
- The regression runner and batch smoke assertions.
- Deterministic failure-path, retry, ASan, and integration coverage.
- User documentation for the supported Faust path.

Out of scope:

- A general split of `interpreter.cc` into new subsystems.
- Changes to Pure language semantics or public language syntax.
- Supporting Faust-generated LLVM bitcode from a different LLVM major.
- Unrelated warning cleanup in legacy glob, fnmatch, strptime, or CRT wrappers.

## Governing Invariant

An operation which replaces or augments executable state has two phases:

1. **Prepare:** build, link, verify, materialize, look up, and bind a candidate
   using private IR and private ORC resources.
2. **Commit:** publish the fully usable candidate in one ownership transition,
   then retire the superseded state.

Before commit, failure must leave all live IR, symbol tables, environments,
cached values, Faust generations, and callable addresses unchanged. Resources
created by the failed attempt must be removed or destroyed. After commit, the
new state is authoritative; cleanup of superseded state must retain explicit
ownership until cleanup succeeds rather than creating dangling pointers.

## Transactional Module Changes

### Batch bitcode import

The destination module is not passed directly to `Linker::linkModules`.
Instead, the implementation clones the destination, links the imported module
into the clone, verifies it, discovers exports, and prepares all required
wrappers against that candidate. Only after every step succeeds is the live
module replaced with the candidate and the corresponding metadata published.

A link error, verifier error, missing symbol, wrapper error, ORC add error, or
lookup error destroys the candidate and leaves the original module usable.

### Batch Faust reload

Reload uses the same candidate-module discipline. Existing entries in
`loaded_dsps`, and the functions and globals they reference, remain untouched
through compilation, linking, verification, materialization, symbol lookup,
wrapper creation, slot lookup, and generation retention.

Commit installs the new DSP state first and transfers all candidate ownership.
Only then may the old generation, functions, globals, wrappers, and tracker be
retired. If retirement itself reports an error, the implementation preserves
enough ownership to retry or safely release it; it never restores dangling
pointers to the old IR.

## Deferred Global Materialization

Each deferred generation retains a canonical, reusable snapshot until lookup
has succeeded. A materialization attempt creates a fresh snapshot copy and an
ephemeral ORC resource tracker. On add or lookup failure, the ephemeral tracker
is removed and the canonical snapshot remains available for retry.

Only successful lookup commits the tracker and address to the generation and
releases the canonical snapshot. A failed attempt followed by satisfying the
missing dependency must therefore succeed without rebuilding the generation.

## Exception-Safe Temporary Evaluation

`doeval` and `dodefn` use focused RAII guards for every temporarily replaced or
newly owned item: `fptr`, interpreter/environment pointers, global or source IR
state, cached values, and ORC resource trackers. A guard restores the prior
state and releases temporary ownership on every exceptional exit. The success
path explicitly transfers the objects that become part of permanent state and
disarms only the corresponding rollback action.

Guards remain local implementation details. They do not change public Pure
interfaces or introduce test-only methods into production classes.

## Supported Faust Pipeline

All inline and file-based DSP compilation uses one route:

1. Faust emits C using the `pure.c` architecture file.
2. The configured Clang 22 compiler compiles that C to LLVM input compatible
   with the running Pure toolchain.
3. The normal transactional import path verifies, materializes, and commits it.

The direct `faust -lang llvm` path is removed rather than version-gated. Faust
may itself have been built against another LLVM major, so its bitcode is not a
safe interchange format. Documentation and automatic selection logic must not
recommend or silently choose that route.

Temporary source, bitcode, object, and diagnostic files are uniquely owned and
removed on both success and failure. Commands use configured executable paths
and remain safe when paths contain spaces.

## Test Harness Correctness

The regression runner captures interpreter output in its own file and records
the interpreter exit status independently. Output normalization and comparison
run afterward. A case passes only when the interpreter exits zero and the
normalized output matches the golden file. Pipeline exit semantics must not be
used as the authority for interpreter success.

The runner has a contract test in which a controlled program emits the exact
golden output and then exits nonzero; the case must fail for the interpreter
status. The contract exercises the runnable harness rather than searching its
source text.

The batch smoke program emits a fixed literal result. Its test requires the
exact stdout, a zero exit status, an existing nonempty object, and an object
format/machine report matching the configured x86-64 Windows target.

## Test-First Validation

Every production correction begins with a focused test which is observed to
fail for the audited reason:

- Valid Faust A, invalid or unresolved B, then valid C; A remains callable
  after B and C installs successfully. The scenario also runs under ASan.
- Deferred global lookup failure followed by supplying its dependency and a
  successful retry from the same generation.
- Failed batch bitcode import followed by valid batch code in the unchanged
  interpreter.
- Injected ORC failure in each of `doeval` and `dodefn`, followed by a
  successful evaluation or definition.
- A real inline DSP compiled through `pure.c` and configured Clang 22.
- Golden output followed by nonzero interpreter exit is rejected by the
  regression harness.
- Batch smoke exact output and object architecture checks.

Failure injection is deterministic, scoped to tests, and placed at existing
dependency boundaries. Tests assert externally visible state and successful
retry, not private helper calls or source text.

## Validation and Resource Limits

All local compilation and tests run sequentially to avoid overloading the
Windows host. Completion requires fresh evidence from:

- Focused RED/GREEN tests for each ownership or harness contract.
- A clean warning-reviewed Release build against LLVM/Clang 22.
- The full CTest suite.
- The complete `prelude.pure` plus `test001.pure` through `test096.pure`
  regression corpus with a validated diff executable.
- Repeated JIT lifetime and deferred-generation tests.
- An ASan build containing the Faust A/B/C failure-retry scenario.
- A documentation scan showing no supported direct Faust LLVM-bitcode route.

Owned temporary test files and processes must be checked and cleaned after
each gate. Existing untracked `_deps/` and `build/` directories are preserved.

## Success Criteria

- All six audited correctness findings have a regression test that was observed
  failing before its fix and passing afterward.
- No failed operation can expose partial IR, lose retry data, retain a temporary
  environment, or leave callable state pointing at destroyed storage.
- Inline Faust works through the single C/Clang 22 route.
- The regression runner cannot mask interpreter failure.
- Full sequential Release, regression, repeated lifetime, and ASan gates pass.
- The tracked worktree contains only intentional source, test, build-system,
  documentation, specification, and plan changes.
