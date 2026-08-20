# Focused follow-up: transactional compiled-wrapper rollback report

Date: 2026-08-20

Implementation commit: the commit containing this report

## Result

The residual compiled-wrapper rollback finding is closed. Generic interactive
bitcode declaration transactions now record every wrapper materialized by
`declare_extern`. If a later declaration fails, rollback retires each wrapper's
ORC tracker and removes its compiled-function registry entry while the owning
`Function*` is still valid, before restoring IR, symbols, bindings, externals,
pointer types, and namespace state. First-load provider cleanup follows that
wrapper/state rollback.

The implementation extends the existing preallocated `TrackerOwner` model. It
does not add another tracker owner: the transaction holds only a pre-reserved
vector of raw `Function*` rollback keys. Successful removal releases the existing
owner exactly once. Failed removal erases the soon-to-dangle function key but
leaves the existing owner, tracker reference, and pending-cleanup state in the
stable `tracker_owners` list for retry and bounded shutdown.

## Root cause

`declare_extern(..., materialize=true)` compiled an ORC wrapper and published a
`Function* -> CompiledFunction(address, TrackerOwnerSP)` entry before publishing
the external declaration. `batch_bitcode_transaction` restored parser and IR
state after a later declaration failed, but it did not retire that compiled entry
before erasing the wrapper `Function`. This left both a dangling registry key and
live wrapper code. The first-load error branch also attempted provider cleanup
before the transaction destructor restored wrapper state.

## Implementation

- `interpreter` exposes the currently active bitcode declaration transaction to
  `declare_extern`; transaction construction saves/restores a previous pointer so
  nested lifetime is explicit.
- The bitcode export count pre-reserves the transaction's wrapper-key vector
  before publication. Recording a successfully compiled wrapper is therefore
  nonallocating.
- `CompilationUnitResources::retire_function` copies the wrapper's existing
  `TrackerOwnerSP`, calls the single central `remove_tracker` path, and erases the
  registry entry regardless of cleanup success. Stable failed ownership remains
  in `tracker_owners`.
- Rollback processes recorded wrappers in reverse order before restoring the
  transaction snapshots. Commit clears only the raw rollback keys and leaves the
  normal compiled registry/owner relationship unchanged.
- Both the first-load and already-loaded namespace error branches perform
  explicit rollback so diagnostics can include cleanup failures. First-load
  provider cleanup runs afterward.

## TDD evidence

Tests and fixtures were changed before production code. On clean base
`32b77e53c7320c6b2a53274a39bb5ba3748f33eb`, the three focused declaration
checks failed deterministically, 0/3. The injected second declaration failure and
empty namespace rollback were visible, but the old implementation could not
satisfy the required evidence that export 1 had a compiled registry entry and
that rollback returned the registry to its baseline. Source tracing at that RED
state showed `compile_orc_function` inserting the entry while transaction
rollback had no corresponding removal. The old run's later `[40,2]` happened to
use a fresh allocation, which is why the final test also keeps explicit,
different module results rather than relying on allocator reuse to expose stale
code.

After the fix, all three focused checks passed. Their runtime evidence is:

- first-load branch: injected export-2 failure; `first bitcode wrapper
  materialized`; `compiled function registry returned to baseline`; empty
  namespace `[]`; retry result `[40,2]`; sum `42`;
- already-loaded branch: seed module result `7`, the same materialization and
  baseline evidence, empty failed namespace, then `[40,2]` and `42` from the
  replacement module;
- cleanup-removal failure: persistent wrapper removal failure, registry baseline
  restoration, successful distinct-result retry, and final shutdown diagnostic
  within a 15-second test timeout.

The first fixture returns 7 and 11; the retry fixture returns 40 and 2. Thus a
stale wrapper/address reuse is observable independently for both exports.

## Verification

All build and test commands ran sequentially (`--parallel 1` / `-j1`). The
Release build completed successfully with only pre-existing legacy warnings.

Focused declaration checks:

```powershell
ctest --test-dir pure/build/final-fix-verified-release -R '^pure-bitcode-declaration-(first-retry|loaded-retry|wrapper-cleanup)$' --output-on-failure -j1
```

Exit 0; **3/3 passed**, 7.71 s.

Declaration, generic bitcode transaction, and JIT ownership gates:

```powershell
ctest --test-dir pure/build/final-fix-verified-release -R '^(pure-bitcode-(declaration|transaction)|pure-jit-)' --output-on-failure -j1
```

Exit 0; **20/20 passed**, 17.57 s.

Authoritative full serial suite (with the MSYS POSIX utilities ahead of the
unrelated Windows coreutils installation used by the regression harness):

```powershell
cmake -E env 'PATH=C:\msys64\usr\bin;C:\msys64\clang64\bin;<inherited PATH>' ctest --test-dir pure/build/final-fix-verified-release --output-on-failure -j1
```

Exit 0; **49/49 passed**, 509.81 s. `pure-regression` passed in 369.20 s and the
harness contract passed in 0.66 s. The captured regression log contains exactly
97 `.pure: passed` entries.

An earlier full invocation with only `clang64/bin` prepended passed 47 tests but
the corpus selected `C:\Program Files\coreutils\bin\find.exe`; that external PATH
collision produced `name.test\\test001` and failed `pure-regression` before the
corpus ran. A standalone corrected corpus passed, followed by the authoritative
fresh 49/49 run above. This was not accepted as a product RED or test result.

## Hygiene and review

- No `pure`, `pure-jit-smoke`, or `faust` process remained after testing.
- No `.run-tests.*` directory or PID-qualified Pure/Faust temporary C file
  remained in the verification tree.
- Repository audit still finds exactly one product
  `ResourceTracker::remove()` call, in the central cleanup helper.
- No rollback bypass, new TODO, or duplicate cleanup path remains.
- Both transaction branches, success ownership, cleanup failure ownership,
  retry behavior, ordering, and exception/preallocation boundaries were reviewed.
- `git diff --check` passed; Git emitted only line-ending conversion notices.

## Remaining concerns

No new correctness concern was found in the focused scope. The authoritative
Windows test environment must keep `C:\msys64\usr\bin` before the separate
Windows coreutils installation so the POSIX `run-tests` harness receives the
expected `find` semantics. This follow-up used the already verified Release tree;
it did not add a new ASan gate beyond the clean ASan evidence recorded in
`final-fix-report.md`.
