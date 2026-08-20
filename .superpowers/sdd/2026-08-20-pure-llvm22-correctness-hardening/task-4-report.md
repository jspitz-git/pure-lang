# Task 4 report — transactional generic batch bitcode import

## Scope and commit

Implemented Task 4 in
`C:\pure-lang\.worktrees\pure-llvm22-hardening` and committed it as:

- `09509ab881da44e34e66a4b0f7165fa579c0dc5b Make batch bitcode imports transactional`

All configure, build, fixture compilation, and tests ran sequentially (`-j 1`
or `--parallel 1`). Tasks 1–3 and their tests were preserved. No existing
untracked build or dependency directory was removed or staged.

## Root-cause and data-flow trace

`LoadBitcode` parsed the source module in the interpreter-owned `LLVMContext`,
validated ABI metadata and target properties, assigned a unique prefix, renamed
all externally visible definitions, and cached owned export/type strings.

The old batch path then mutated state in this order:

1. `Linker::linkModules(*module, std::move(M))` consumed the source and changed
   the live batch module.
2. The live module was verified.
3. Imported functions, globals, aliases, and ifuncs were internalized; exported
   functions were optimized.
4. `declare_extern` ran once per export. It could create a symbol-table entry,
   host-backed default global, wrapper IR, ORC wrapper tracker/address, and
   `externals` entry before the next export was attempted.
5. Only after every wrapper succeeded did `bitcode.declare` and
   `loaded_bcs.emplace` publish the import record.

The regression's invalid module deliberately makes export 1,
`pure_transaction_value`, usable with value `7`, while export 2,
`pure_transaction_invalid`, references absent `pure_transaction_missing`.
The old path therefore published the first wrapper and `externals` metadata,
then failed while materializing the second wrapper. The later valid module
exporting value `42` found the stale external declaration and reused the failed
module's first wrapper, producing `7`.

The live `module` object cannot safely be replaced wholesale. `globalvars`,
`globalfuns`, `globaltypes`, `externals`, `always_used`, Faust `bcdata_t`,
`sstkvar`, `fptrvar`, nested `Env` objects, and heap-backed `EXPR::WRAP` values
retain raw IR pointers. The `LLVMContext` and semantic LLVM types are stable,
but replacing the module would require a complete remap of all those owners and
of ORC registry keys. Tasks 1–3 also rely on those identities.

## RED evidence

The corrected multi-export behavior test was run against a one-line mutation
which bypassed candidate rejection, reproducing the original live-link path:

```diff
@@ interpreter::LoadBitcode batch candidate rejection
-  if (!candidate_error.empty() || !prepare_linked_bitcode_exports
-        (*ORC, *candidate, bitcode, orc_unit_counter, candidate_error)) {
+  if (false && (!candidate_error.empty() || !prepare_linked_bitcode_exports
+        (*ORC, *candidate, bitcode, orc_unit_counter, candidate_error))) {
```

This was a temporary working-tree mutation only and was removed immediately
after the RED run.

```text
Symbols not found: [ pure_transaction_missing ]

7

Pure bitcode batch executable did not print the expected literal
0% tests passed, 1 tests failed out of 1
```

The focused command was:

```powershell
C:\msys64\clang64\bin\ctest.exe `
  --test-dir pure/build/audit-llvm22-release `
  -R '^pure-bitcode-transaction-recovery$' --output-on-failure -j 1
```

This is a behavioral mutation proof: the test observes a real Clang 22 bitcode
module, real LLVM link/wrapper/materialization paths, a failed import followed
by a valid import in the same batch compiler process, and the stale result `7`
rather than inspecting private helpers.

## Implementation and commit ordering

- `prepare_linked_module` clones the live module, links the consumed import into
  the clone, verifies it, and destroys the clone on error.
- `finalize_linked_bitcode` performs imported-symbol discovery checks,
  internalization, export optimization, and final verification on the private
  candidate first.
- A read-only metadata preflight checks every deterministic `declare_extern`
  rejection (visibility, Pure-definition conflicts, and existing external ABI)
  without creating symbols, globals, wrappers, or `ExternInfo` records.
- `prepare_linked_bitcode_exports` submits reduced candidate copies under one
  temporary ORC tracker, looks up every provider, and removes the tracker on
  success or failure. This catches the unresolved provider before any live IR
  or export metadata changes.
- `commit_module_candidate` performs the already-proven deterministic link from
  a retained import clone into the identity-stable live module. The same
  internalization/optimization/verification checks are then applied to live IR.
- Batch `declare_extern` calls use `materialize=false`: wrapper IR is emitted for
  the native batch object, while provider ORC add/lookup has already succeeded
  off-module and is not repeated after commit.
- Namespace declaration and `loaded_bcs` publication remain last.

On candidate failure, the candidate and retained commit source are destroyed,
the temporary tracker is removed, and live IR, symbol tables, globals,
environments, external metadata, and `loaded_bcs` remain unchanged.

## GREEN and verification evidence

The final verbose focused test printed the intended diagnostic and recovered
literal:

```text
transaction-invalid.bc: Failed to materialize bitcode export
'pure_transaction_invalid' ... Symbols not found: [ pure_transaction_missing ]

42
```

It passed 1/1 in 0.60 seconds. The required sequential focused gate passed
13/13 in 26.50 seconds:

- all 12 `pure-bitcode-*` tests, including transaction recovery;
- `pure-batch-object`.

The final LLVM/Clang 22 Release build completed through `pure-jit-smoke` with no
compiler diagnostics. `git diff --check` and `git diff --cached --check`
reported no whitespace errors. The worktree was clean after the commit.

## Changed files

- `pure/interpreter.cc`
- `pure/cmake/RunPureBitcodeTest.cmake`
- `pure/cmake/PureInstallAndTests.cmake`
- `pure/test/bitcode/transaction-invalid.c` (new)
- `pure/test/bitcode/transaction-valid.c` (new)
- `pure/test/bitcode/transaction-recovery.pure` (new)

`RunPureBitcodeTest.cmake` now accepts explicit first/second C source and
bitcode-output inputs, compiles both with the configured Clang, batch-compiles
the Pure script, links it with the configured C++ compiler and `pure_main`
object, runs it with the runtime loader path, and requires exact stdout `42`.
Sanitizer and non-PIE link flags are propagated for later plan-level gates.

## Ownership and mutation self-review

- Removing candidate rejection is caught by the observed `7` mutation.
- Skipping any provider lookup loses the required unresolved diagnostic or
  permits the stale first export, failing the same test.
- Publishing `loaded_bcs` or an `externals` entry before every provider succeeds
  makes the valid continuation reuse the failed wrapper and is caught.
- Candidate optimization and verification happen before the live commit and
  are repeated after it; no candidate `Function*` or `GlobalVariable*` escapes.
- The temporary ORC tracker is removed on add failure, lookup failure, and
  success. No candidate tracker is retained in `CompilationUnitResources`.
- The live `Module` address, `LLVMContext`, existing IR values, environments,
  host-global storage, and ORC function keys remain stable across commit.
- Generic interactive imports keep eager wrapper materialization. Only the
  prepared batch path suppresses the redundant post-commit wrapper JIT.
- The test compiles fresh fixtures on every invocation and deletes/replaces only
  its named object/executable outputs.

## Rulings and concerns

**Ruling — preserve live module identity.** The plan described replacing the
live module pointer with the verified clone. The ownership trace showed that
doing so would invalidate pervasive raw pointers, including heap-backed wrapped
expressions which cannot be enumerated safely. The implementation therefore
uses the clone as the complete prepare proof and commits a retained identical
import clone into the unchanged live module. Cost if wrong: two deterministic
LLVM links and extra temporary IR memory during each batch import. This is the
smallest change that preserves established ownership while preventing every
observed pre-commit failure from mutating live state.

**Ruling — exact unresolved fixture retained.** The unresolved module is valid
LLVM and links successfully, but batch `declare_extern` eagerly materialized
its provider and rejected it after live mutation. No artificial verifier hook
or alternate fixture was needed. Two exports were necessary to make the prior
partial metadata publication observable; a single failing export left only
dead IR which final global DCE could discard.

The full project CTest and ASan suites are later plan-level gates and were not
run in this task. Direct MSYS child processes require execution outside the
restricted sandbox; all reported final runs used that approved path.

## Review correction round 1/5

Commit:

- `4762da0905d5dfc93fd6cc7a5d8c6a41cf98b997 Complete transactional batch bitcode import`

This correction supersedes the original report's statements that provider
materialization alone completed preparation and that the second live
link/finalizer was an ordinary recoverable operation.

### Verified review findings and root causes

1. Batch `declare_extern(..., materialize=false)` still created symbol-table
   entries, wrapper functions, default-value globals, host absolute symbols,
   `defined`/`nodefined` state, pointer tags, and `ExternInfo` records after the
   imported IR had already been linked. In particular, a recoverable
   `register_host_global` error could leave earlier exports published.
2. `PureJit::snapshot_module` and `reduce_to_entry` retained reachable global
   definitions only when they were constant. A valid exported function reading
   an imported mutable global therefore materialized with an unresolved
   qualified data symbol.
3. The replay `Linker::linkModules` and live `finalize_linked_bitcode` could
   report failure after modifying the identity-stable live module.
4. A failed removal of the temporary provider tracker was joined into the
   diagnostic, but the last owning `ResourceTrackerSP` then died with the
   attempt. There was no stable retry owner.

### RED evidence

The mutable fixture changed the valid continuation to increment imported
`pure_transaction_state`, initialized to 41. Before the correction the real
batch compiler reported:

```text
Failed to materialize bitcode export 'pure_transaction_value' ...
Symbols not found: [ $$bc.3.pure_transaction_state ]
```

The new two-export prepare fixture returns 7 from its first export. Three
separate compiler processes requested failures at the second wrapper host
registration, the final verified precommit boundary, and provider-tracker
removal. Before the hooks and transactional correction, all three requests
were ignored, no injected diagnostic was emitted, and the test rejected the
run instead of accepting the stale first import.

### Correction

- Import-owned data-definition names are now explicit optional inputs to
  `PureJit` reduction. Reachable mutable definitions are retained only for
  those qualified imported names; ordinary evaluation snapshots continue to
  externalize interpreter-owned mutable host globals. Reachable functions,
  aliases, and ifunc resolver graphs keep their existing definition handling.
- `batch_bitcode_transaction` checkpoints existing live LLVM values, symbol
  allocation, prior symbol flags, `externals`, global bindings and expression
  references, `defined`/`nodefined`, pointer tags, and the pointer-tag counter.
  Wrapper construction happens before imported IR commit under this guard.
  Failure removes newly created wrappers/declarations/globals, restores prior
  expressions and metadata, unregisters host globals, and clears symbol caches
  before discarding newly allocated symbol entries.
- If host-symbol removal itself fails, the host tracker remains in
  `host_symbols`; an extracted map node keeps the absolute symbol's backing
  address alive in the same stable quarantine used for bounded retries.
- The exact post-wrapper live module plus the already prepared import is cloned,
  linked, internalized, optimized, and verified before commit. A test hook sits
  after this latest recoverable boundary. The final live link is deterministic
  replay and any divergence is an LLVM fatal invariant; post-link work only
  applies already-proven linkage changes and publishes namespace/load metadata.
- Provider tracker removal failures move the tracker into
  `CompilationUnitResources::quarantined_trackers`. The next import makes one
  bounded removal pass. The deterministic test additionally rejects a retry if
  the pending tracker has lost its owner. Repeated cleanup failures retain
  ownership and suppress duplicate diagnostics.

### GREEN and final verification

The verbose failure test observed each requested diagnostic followed by the
valid continuation's exact output `42`:

```text
injected batch-bitcode-host-global ORC host global registration failure
42
injected batch-bitcode-precommit failure
42
injected batch-bitcode-provider-remove ORC tracker removal failure
42
```

All commands were sequential:

- LLVM/Clang 22 Release build completed through `pure-jit-smoke`.
- `pure-bitcode-transaction-recovery` and
  `pure-bitcode-transaction-prepare-failures`: 2/2 passed.
- `^(pure-bitcode-.*|pure-batch-object)$`: 14/14 passed in 27.97 seconds.
- `pure-jit-smoke` and `pure-jit-eval-failure-recovery`: 2/2 passed.
- `git diff --check` and `git diff --cached --check` reported no whitespace
  errors; only the repository's expected LF-to-CRLF notices were printed.

### Changed files and self-review

The correction changes `interpreter.cc/.hh`, `pure_jit.cc/.hh`, and
`symtable.cc/.hh`; extends the bitcode CMake driver and registration; adds the
failure driver and two-export fixture/script; and makes
`transaction-valid.c` exercise mutable imported state.

Mutation review:

- Removing the import-owned mutable-name argument restores the unresolved
  qualified global and fails transaction recovery.
- Failing to roll back any first-export wrapper, external entry, symbol, or
  host binding makes the retry reuse value 7 instead of 42.
- Moving the precommit hook before exact replay stops testing the latest
  recoverable boundary; its present location is after replay finalization.
- Dropping a provider tracker instead of quarantining it triggers the
  `PURE_TEST_TRACKER_RETRY` ownership check on the second import.
- The live `Module` and `LLVMContext` identities remain unchanged. Candidate
  pointers never enter published maps; live wrapper/global pointers remain
  valid on commit, and all attempt-created pointers are erased on rollback.
- Generic interactive bitcode loading and Task 1–3 environment/function/Faust
  ownership paths retain their existing behavior; their two focused ORC tests
  passed after the shared cleanup extension.

Concern: the commit invariant intentionally terminates on an impossible replay
link divergence instead of trying to continue from partially mutated live IR.
The full project CTest and ASan suites remain later plan-level gates.

## Review correction round 2: exact imported storage and host registration ownership

Commit: `d01267f8175a7a9e5cb6dd635976dcb6b8510623`

### Root-cause trace

Provider reduction received only `data_symbols`, which intentionally contains
defined globals with external linkage because that same list drives public
import finalization. A valid export reaching a `static` mutable global therefore
reached the provider clone, but the mutable definition was not authorized for
retention and became an unresolved declaration. Alias and ifunc dependency
walking was already generic; the ownership list supplied to it was incomplete.

Host cleanup quarantine stored a reusable symbol name and optional backing, but
not the absolute-symbol registration that had failed removal. If a later
transaction removed the old tracker and rebound the same Pure name, the next
quarantine retry called `remove_host_symbol(name)` and could remove the new
tracker. Shutdown also cleared quarantined backing after one bounded removal
pass, before ORC destruction, even when exact removal still failed.

### RED evidence

`transaction-valid.c` changed its state to a real internal mutable definition:

```text
Failed to materialize bitcode export 'pure_transaction_value' ...
Symbols not found: [ pure_transaction_state ]
```

`pure-bitcode-transaction-recovery` failed because the valid continuation could
not produce `42`.

The same-name replacement and shutdown fixtures initially failed because the
new host-removal injection was absent. Tightening the shutdown assertion then
showed that batch mode took the compiler's normal quick `exit()` and omitted
the required `failed to remove ORC compilation unit` diagnostic. Enabling the
full interpreter destructor exposed the already documented dangling compiler
module (signal 11), so the final test hook invokes the factored ORC shutdown
subset and retains the normal batch exit ruling.

### Correction

- Every defined imported global is privately qualified and recorded in
  `owned_data_symbols`. Provider snapshots receive that list, so only reachable
  candidate-owned mutable definitions survive reduction through ordinary
  function/global/alias/ifunc dependency traversal. `data_symbols` remains the
  external-linkage-only list, so static names are not published as public data
  exports.
- Each quarantined host entry now owns the exact `ResourceTrackerSP`, address,
  flags, name, and backing. Retry removes the tracker only when all registration
  identity fields still match the live map entry. A rebound name retires only
  the stale quarantine; the deterministic test also performs a real ORC lookup
  and compares the replacement address before continuing.
- Removal injection follows the exact first-failed tracker. The replacement
  sequence fails initial cleanup and one retry, successfully replaces the old
  registration under the same Pure name, performs the stale retry, and the
  linked program still calls the replacement and prints exactly `42`.
- ORC teardown is factored into `shutdown_orc_resources`. It snapshots shared
  quarantined backing ownership, performs one bounded removal pass, destroys
  the resource registry and ORC, and only then releases the backing. The batch
  test-only hook calls this same routine before the compiler's required quick
  exit, avoiding its documented stale Module pointer while exercising bounded
  shutdown ownership.

### GREEN and verification evidence

All commands were sequential (`--parallel 1` / `-j 1`):

- LLVM/Clang 22 Release build completed through `pure-jit-smoke`.
- Transaction-focused gate: 4/4 passed (`recovery`, `prepare-failures`,
  `host-replacement`, `host-shutdown`).
- Prior JIT/ORC gate: 8/8 `pure-jit-*` tests passed.
- Complete generic bitcode gate: 15/15 `pure-bitcode-*` tests passed in
  28.98 seconds.
- Verbose replacement evidence included the injected host removal and final
  executable output `42`.
- Verbose shutdown evidence included exactly the persistent host removal and
  `failed to remove ORC compilation unit`, then exited normally within 0.45 s.
- `git diff --check` and `git diff --cached --check` reported no whitespace
  errors (only the repository's expected LF-to-CRLF notices).

An exploratory `ctest -L bitcode` also selected the independently labeled
`pure-faust-lifecycle`; its file-reload timing expectation failed on this
Windows run (reload remained at 11 after fixture swaps). No Faust path changed,
and the requested exact `pure-bitcode-*` and prior ORC ownership gates passed.

### Changed files and self-review

Changed `interpreter.cc/.hh`, `pure.cc`, the bitcode CMake registration/driver,
and `transaction-valid.c`; added the old-registration C fixture and replacement
and bounded-shutdown Pure scripts.

Self-review rulings:

- The live `Module` and `LLVMContext` identities remain unchanged. Private
  qualification happens on the imported source before candidate/replay linking.
- Internal globals enter only the provider-retention list, never public
  `bitcode.exports`, namespace declarations, or external data finalization.
- Exact host identity is tracker plus address and flags; cleanup never resolves
  an owning registration by name alone. Backing ownership is released only
  after exact retirement, stale replacement detection, or ORC destruction.
- Retry and shutdown loops remain bounded and diagnostics remain single-pass.
- The test-only batch shutdown hook deliberately does not run the full
  interpreter destructor because `compiler()`'s dangling Module is an existing,
  documented invariant; it calls the exact production ORC teardown routine.

## Review correction round 3: rollback backing transfer and LLVM reserved globals

Commit: `a8bf8a87b168c78f88183828ac679b08aae59e59`

### Root-cause trace

When replacement registration failed, `retain_host_symbol` successfully removed
the old tracker and restored the old address under a new rollback tracker. The
quarantine still identified the retired tracker and remained the only owner of
the detached `GlobalVar` map node. The next retry treated every tracker mismatch
as a true replacement, erased the quarantine, and freed storage still addressed
by the restored live registration. Transaction rollback also tested only whether
the reusable name existed, so it could attempt to remove the restored old
registration while processing the new binding at a different address.

The round-2 qualification loop also renamed every defined global, including
LLVM-reserved appending globals. Renaming `llvm.global_ctors`, `llvm.global_dtors`,
`llvm.used`, or `llvm.compiler.used` removes their reserved semantics. Once the
names were preserved, the batch compiler's older manual stripping pass exposed
a related dependency gap: it did not treat functions referenced through reserved
initializers as roots, erased the internal constructor, and left a dangling
constant. LLDB located the deterministic access violation in
`llvm::ValueEnumerator::EnumerateType` while `WriteBitcodeToFile` serialized that
module.

### RED evidence

The valid transaction fixture now initializes its internal mutable state to 41
from a real C constructor and emits a `used` anchor. Before correction,
`pure-bitcode-transaction-recovery` failed before producing the batch object;
the compiler exited on signal 11. The captured backtrace ended in
`ValueEnumerator` -> `BitcodeWriter::writeModule` -> `WriteBitcodeToFile` ->
`interpreter::compiler`.

The new rollback sequence requested an initial precommit failure, two exact old
tracker removal failures, a replacement-registration failure, and a persistent
shutdown removal failure for the rollback tracker. Before the hook and transfer
logic existed, the test rejected the compiler output because the expected
re-registration failure was absent.

### Correction

- `HostSymbol` can now own detached backing directly. Replacement failure
  carries any existing live backing into the rollback registration. When the
  old backing is still quarantined, stale retry distinguishes rollback from
  replacement by matching name, address, and flags despite the new tracker; it
  moves the backing to the restored live `HostSymbol` instead of freeing it.
- Transaction rollback removes a host binding only when the registered address
  is exactly `&binding.x`; a same-name registration for restored old storage is
  left intact.
- Shutdown snapshots backing from both quarantined and live restored host
  symbols before its bounded removal pass and releases it only after ORC
  destruction.
- The deterministic test verifies the rollback registration with an actual ORC
  lookup, compares its address, reads the restored slot, then triggers exact
  rollback-tracker removal failure during shutdown. The compiler exits normally
  and the valid third import's executable prints exactly `42`.
- All globals whose names begin `llvm.` bypass private namespace qualification
  and public imported-data tracking. Ordinary defined globals remain qualified,
  so the internal mutable-state retention fix is unchanged.
- Batch stripping recursively collects functions referenced by LLVM-reserved
  global initializers as dependency roots. This preserves constructors,
  destructors, aliases, and function pointers retained via `llvm.used` or
  `llvm.compiler.used` without exposing any reserved name as a Pure export.

### GREEN and final verification

All commands were sequential (`--parallel 1` / `-j 1`):

- LLVM/Clang 22 Release build completed through `pure-jit-smoke`.
- Transaction gate: 5/5 passed, including constructor recovery and exact
  rollback re-registration/shutdown.
- Generic bitcode gate: 16/16 `pure-bitcode-*` tests passed in 29.35 seconds.
- Prior ownership gate: 8/8 `pure-jit-*` tests passed.
- Verbose re-registration evidence showed initial removal failure, precommit
  failure, replacement registration failure, persistent exact rollback-tracker
  shutdown failure, and final output `42`.
- `git diff --check` and `git diff --cached --check` reported no whitespace
  errors; only the repository's expected LF-to-CRLF notices appeared.

### Changed files and self-review

Changed `interpreter.cc`, the bitcode CMake registration/driver, and the valid
constructor fixture. Added separate new-registration and post-retry C fixtures
and the rollback re-registration Pure script.

Self-review rulings:

- Tracker mismatch alone no longer decides backing ownership. Same address and
  flags means rollback restoration; a different address or flags means a true
  replacement. Removing that branch makes the new ownership invariant fail.
- Exact-address rollback checks prevent reusable names from authorizing removal
  of unrelated or restored storage.
- A failed shutdown removal cannot outlive its backing: the local shared-owner
  snapshot spans `remove_all`, registry deletion, and ORC deletion.
- Reserved `llvm.*` names never enter `owned_data_symbols`, `data_symbols`,
  `bitcode.exports`, or namespace publication. Their ordinary referenced
  internal mutable globals still link into the candidate and live module.
- Removing reserved-function root traversal reproduces the dangling constructor
  reference and serializer crash; removing the reserved-name exclusion prevents
  constructor execution and the expected value 42.

## Review correction round 4: custom-main reserved linkage

Commit: `b5e3b204ee3bf3e7a28a977da0a25510650a7d75`

### Root-cause trace and RED evidence

Round 3 excluded every defined `llvm.*` global from import qualification and
kept functions referenced by reserved initializers rooted during batch
stripping. The later custom-entry branch in `interpreter::compiler` still
iterated the complete live module whenever an explicit `--main` was present and
changed every defined global to `InternalLinkage`. That overwrote the required
`AppendingLinkage` of Clang's `llvm.global_ctors` and `llvm.used` lists after
the transactional import had already preserved them correctly.

The new `pure-bitcode-transaction-custom-main` fixture uses the real Clang 22
constructor/retention payload from `transaction-valid.c`, batch-compiles the
same failed-import-then-valid recovery script with the distinct option
`--main=pure_transaction_custom_main`, links a dedicated C launcher which calls
that generated entry, and requires the constructor-initialized literal `42`.
Before the production correction the focused command failed at the intended
module verifier boundary:

```text
pure: invalid LLVM module: invalid linkage for intrinsic global variable
ptr @llvm.global_ctors
invalid linkage for intrinsic global variable
ptr @llvm.used
```

The fixture and launcher had already reached the unresolved-import diagnostic,
so this was not an argument, source, or link setup error. It was the exact
blanket custom-main linkage rewrite under review.

### Correction and equivalent-loop audit

The custom-main global loop now retains the original linkage for every named
`llvm.*` global. Its existing internalization remains unchanged for every
ordinary defined global, and function internalization is unchanged.

Every equivalent global-linkage rewrite was inspected:

- `LoadBitcode` excludes `llvm.*` definitions before qualification and before
  populating `owned_data_symbols` or public `data_symbols`.
- Candidate finalization and deterministic live commit only internalize names
  from `data_symbols`; reserved globals therefore cannot enter either loop.
- `PureJit::reduce_to_entry` operates on an entry dependency clone. LLVM
  constructor/retention list globals are not part of that forward dependency
  closure, while imported mutable definitions retain their round-2 handling.
- The custom-main loop was the only later whole-module linkage rewrite and is
  consequently the only production location changed in this round.

### GREEN and sequential verification evidence

All builds and tests used one job. The LLVM/Clang 22 Release build completed
for `pure` and the custom launcher target. The verbose custom-main run showed
the expected unresolved-symbol diagnostic followed by exact stdout `42`.

- Custom-main RED/GREEN test: 1/1 passed after the correction.
- Complete transaction gate: 6/6 passed.
- Generic bitcode plus ordinary batch-object gate: 18/18 passed in 30.44 s.
- Prior JIT/ORC ownership gate: 8/8 passed in 2.85 s.
- `git diff --check` reported no whitespace errors; only the repository's
  expected LF-to-CRLF notices appeared.

### Self-review and mutation strength

- Removing the new `llvm.*` condition reproduces both verifier diagnostics in
  the real custom-main compilation before an object can be emitted.
- Special-casing only `llvm.global_ctors` still leaves `llvm.used` with invalid
  linkage and fails the same test; the prefix rule also covers
  `llvm.global_dtors` and `llvm.compiler.used` without enumerating a fragile
  partial list.
- The expected value is hand-authored and depends on the imported constructor
  setting private state to 41 before the exported function increments it.
- The custom launcher calls only `pure_transaction_custom_main`; reverting the
  driver option or generated-entry name causes a real undefined-symbol/link
  failure rather than accidentally exercising the default entry.
- Existing transaction recovery still uses the default entry and passed, while
  the custom branch continues to internalize nonreserved globals exactly as
  before. `llvm-nm --defined-only` reported the imported state and functions as
  local lowercase `d`/`t` symbols and only `pure_transaction_custom_main` as
  the intended external `T` entry.

Concern: the complete project CTest and ASan suites remain plan-level Task 7
gates. This round changes no ORC ownership or transaction commit boundary.
