# LLVM 22 correctness hardening: final remediation report

Date: 2026-08-20

Implementation commit: `f308e278` (`Complete LLVM 22 correctness hardening`)

## Result

All eight final-review findings and the listed minor findings were addressed in one
defensive remediation wave.  The final clean Release tree passed all 48 registered
CTest tests serially, including the exact 97-file regression corpus.  The final
clean ASan tree passed deterministic first-attempt and fresh-process JIT gates with
address sanitizer instrumentation retained on the interpreter and PureJit paths.

## Finding disposition

### 1. Stable, nonthrowing ORC cleanup ownership

`CompilationUnitResources::TrackerOwner` is now the single stable owner for every
removable ORC tracker.  Owners are preallocated in a list before ORC registration,
and `remove_tracker` is the only product location that calls
`ResourceTracker::remove()`.  Failed removal leaves the last tracker reference in
stable quarantine ownership; cleanup does not allocate and does not throw.

The common path covers eager and deferred add/lookup/removal failures, generic
compile failure, retired type functions, temporary definitions and evaluations,
first and already-loaded bitcode, prepared Faust candidates and their destructor,
Faust generations, batch providers, host symbols, and shutdown.  The final stable
owners are handed to LLJIT immediately before LLJIT destruction because a tracker
cannot outlive its execution session.

### 2. Host-global transactional replacement

Replacement now keeps the old map entry and backing authoritative until the new
definition commits.  The new tracker owner, rollback storage, backing storage, and
map node are allocated before ORC registration.  On failure the new tracker is
removed and the old registration is restored.  If both new registration and old
restoration fail, the implementation crosses an explicit fatal boundary instead
of continuing with a false authoritative map.  Quarantine uses a stable
`GlobalVariable *` and a nonallocating host-symbol lookup.

Regression coverage includes removal failure, re-registration failure, successful
rollback, and the new-registration plus restoration double-failure fatal case.

### 3. Declaration publication transactions

Already-loaded Faust namespace declarations, already-loaded generic bitcode
declarations, and first interactive bitcode declarations now use the same
preflight/publication transaction.  Parser state is snapshotted, every export is
validated, rollback is complete on a later declaration failure, and tracker
ownership is retained only at commit.  Each branch has a two-export test in which
the second declaration fails and the same load then succeeds on retry.

### 4. Candidate-authoritative Faust generations

Faust generation renaming excludes the reserved `llvm.*` namespace.  Appending
globals (`llvm.global_ctors`, `llvm.global_dtors`, `llvm.used`, and
`llvm.compiler.used`) are rebuilt from the new candidate and only the required
live definitions; retired generation entries do not accumulate.  Interactive and
batch tests exercise constructors and `llvm.used`, and A/B/C reloads observe
candidate values 11, 22, and 33.

The exact Task 4 RED-only preflight bypass used to prove the rollback test was:

```diff
-  if (!candidate_error.empty() || !prepare_linked_bitcode_exports
-        (*ORC, *candidate, bitcode, orc_unit_counter, candidate_error)) {
+  if (false && (!candidate_error.empty() || !prepare_linked_bitcode_exports
+        (*ORC, *candidate, bitcode, orc_unit_counter, candidate_error))) {
```

It was immediately reverted after the expected RED result and is also recorded in
`task-4-report.md`.  No bypass remains in the product tree.

### 5. Shipped Faust pipelines

All shipped `pure-faust/examples`, `pd-faust`, and other repository build rules now
run configurable Faust to a uniquely owned temporary Pure C file, then compile
that exact file with the configured matching Clang.  No rule invokes a direct
Faust LLVM backend.  Each target/invocation uses a PID-qualified temporary C file
and a shell trap for safe cleanup.  Double-quoted shell assignment is intentional:
single quotes would prevent `$$` PID expansion.

The repository-wide runnable contract canonicalizes the scan root (so it cannot
scan itself through `pure/..`) and rejects direct LLVM Faust output, nonconfigurable
tools, shared temporary C files, and unsafe cleanup.

### 6. Committed serial nested corpus

`PureInstallAndTests.cmake` commits `TEST_JOBS=1` on Windows and propagates the
configured value into the generated harness.  A fresh configure, with no edits to
generated files, emitted both `TEST_JOBS=1` and
`PURE_CONFIGURED_TEST_JOBS=1` in `CTestTestfile.cmake`; the nested 97-file corpus
then ran serially.

### 7. POSIX-capable regression harness

The harness uses the native PATH separator, makes copied `run-tests` and fake
`pure` programs executable, invokes natively on POSIX, and asserts golden-output
emission before checking the child status.  The contract test exercises the
POSIX-sensitive separator, permission, invocation, and output-order behavior on
this Windows host.  A native POSIX host was not available in this remediation
environment, so native POSIX execution remains an explicit portability follow-up.

### 8. Windows ASan/JITLink first-attempt stability

Three distinct Windows COFF causes were isolated and corrected rather than hidden
by retries:

1. MinGW large+PIC objects emit weak `.refptr.*` COMDAT helpers.  ORC could bind a
   later graph to a helper in an earlier independently removable tracker, then
   dereference unmapped memory.  Windows JIT compilation now uses large code model
   plus static relocation so references use direct 64-bit fixups.
2. COFF unwind `.pdata` contains `IMAGE_REL_AMD64_ADDR32NB` image-relative RVAs.
   The explicit JITLink object layer supplies a graph-local synthetic
   `__ImageBase`, preventing the first object from depending on an unavailable PE
   image base.
3. `MapperJITLinkMemoryManager` may coalesce adjacent free intervals, while two
   adjacent intervals can belong to distinct Windows `VirtualAlloc` reservations.
   A later `VirtualProtect` across that artificial union fails with
   `ERROR_INVALID_ADDRESS`; this was the deterministic `test058` teardown crash.
   `GuardedInProcessMemoryMapper` reserves the requested range plus a hidden page,
   preventing independent allocations from becoming adjacent and preserving
   reservation boundaries during deinitialization.

The COFF JITLink implementation shim alone is compiled with
`-fno-sanitize=address` on Windows ASan builds.  LLVM 22's prebuilt MinGW static
libraries are uninstrumented, while client-side ASan changes the header-defined
`BumpPtrAllocator` layout and crosses that ABI boundary.  Interpreter and PureJit
translation units remain ASan-instrumented, and the generated command lines were
checked to prove this narrow scope.

Useful implementation references:

- <https://www.llvm.org/docs/doxygen/COFF__x86__64_8cpp_source.html>
- <https://github.com/llvm/llvm-project/issues/213568>
- <https://github.com/llvm/llvm-project/blob/llvmorg-22.1.0/llvm/lib/ExecutionEngine/Orc/LLJIT.cpp>
- <https://www.llvm.org/doxygen/MapperJITLinkMemoryManager_8cpp_source.html>
- <https://llvm.org/doxygen/MemoryMapper_8cpp_source.html>
- <https://llvm.org/doxygen/LinkGraphLinkingLayer_8cpp_source.html>

## Minor finding disposition

- The batch object inspector validates stdout only.
- `existing_extern_matches` is shared and compares varargs; a real varargs
  bitcode mismatch regression proves the diagnostic path.
- The exact Task 4 RED bypass hunk is documented above and in the task report.
- Inline-source unlink has one owner.
- Leak acceptance is formally narrowed in the tracked spec and plan.  LLVM 22's
  MinGW leak-sanitizer exit sweep stalls after a surviving compiled closure, so no
  leak-freedom claim is made from this unsupported combination.  Deterministic
  address-safety runs use `detect_leaks=0`; supported leak evidence must be
  collected on a host/runtime where LLVM and the client share a supported
  sanitizer ABI.

## TDD evidence

All product changes were introduced against a failing focused check before the
implementation was accepted.  The final remediation wave additionally captured
these decisive RED/GREEN pairs:

- Before the guarded mapper, isolated Release `test058` failed deterministically
  at teardown (exit 1, 5.22 s) with
  `failed to remove ORC evaluation module: Attempt to access invalid address`.
  After the mapper, it passed in 5.14 s; ten fresh sequential Release processes
  passed 10/10, and the clean ASan first attempt also passed.
- Removing the shared varargs comparison made the focused mismatch test fail as
  expected (exit 1, 2.85 s): it produced only `42` and omitted the required type
  diagnostic.  Restoring it passed the final focused and full suites.
- Tightening the Faust repository contract before fixing recipes failed as
  expected (exit 1) on four shipped paths because single-quoted PID temporaries
  could collide.  Fixing all six recipes and canonicalizing the scanner passed
  the two focused contracts (2/2, 5.34 s).
- Changing the prepared-Faust quarantine calls to the intended one-argument API
  first produced five compile errors (`too few arguments`, exit 1, 7.94 s).
  Converting the helper to a const tracker-reference, nonallocating API rebuilt
  successfully (exit 0, 24.67 s).
- Changing host quarantine first to pass the stable `GlobalVariable *` produced
  the expected compile error (`no viable conversion ... to string`, exit 1,
  7.75 s).  Adding the nonallocating lookup/API rebuilt successfully (exit 0,
  25.18 s).

## Final verification evidence

Every command below ran sequentially.  Build directories named
`final-fix-verified-*` did not exist before their respective configure commands.

### Clean Release configure and build

```powershell
cmake -S pure -B pure/build/final-fix-verified-release -G 'MinGW Makefiles' -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DCMAKE_CXX_COMPILER=C:/msys64/clang64/bin/clang++.exe -DLLVM_DIR=C:/msys64/clang64/lib/cmake/llvm '-DPURE_FAUST_EXECUTABLE=C:/Program Files/Faust/bin/faust.exe' -DPURE_STRICT_TOOLCHAIN=ON -DBUILD_TESTING=ON
```

Exit 0; configure 32.7 s, generate 0.6 s.  The generated CTest file contained
`TEST_JOBS=1` and `PURE_CONFIGURED_TEST_JOBS=1` without generated-file edits.

```powershell
cmake --build pure/build/final-fix-verified-release --parallel 1
```

Exit 0; approximately 90 s; 100% built.  Output contained only pre-existing legacy
warnings in `runtime.cc`, `libglob`, and `strptime`; no new-file warning appeared.

### Full serial CTest and exact corpus

```powershell
ctest --test-dir pure/build/final-fix-verified-release --output-on-failure -j1
```

Exit 0; **48/48 tests passed**, total 560.18 s.  `pure-regression` took
419.36 s and its harness contract took 0.72 s.  The captured corpus log had exactly
97 `passed` entries, from `prelude.pure: passed` through
`test096.pure: passed`; an exact expected/actual sequence comparison reported
`exact_sequence_entries=97` and `exact_sequence_match=true`.
`test058.pure: passed` was explicitly present.

### Focused changed-path gates

The cleanup/declaration/Faust group passed **15/15**, exit 0, total 35.35 s:
deferred retry, type-retirement retry, evaluation failure, first and loaded
bitcode declaration retries, varargs mismatch, candidate prepare failures, four
host-global cases, Faust makefile and repository pipeline contracts, prepared
Faust cleanup, and loaded Faust declaration retry.

```powershell
ctest --test-dir pure/build/final-fix-verified-release -R '^pure-jit-(lifetime-stress|deferred-generation|deferred-retry)$' --repeat until-fail:20 --output-on-failure -j1
```

Exit 0; all three tests passed 20/20 (**60 sequential invocations**), CTest total
10.89 s (command wall 11.317 s).

The standalone repository-wide Faust scan passed, exit 0, 3.85 s, with
`Repository-wide Faust pipeline contract passed`.

### Clean ASan configure and build

```powershell
cmake -S pure -B pure/build/final-fix-verified-asan -G 'MinGW Makefiles' -DCMAKE_BUILD_TYPE=Debug -DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe -DCMAKE_CXX_COMPILER=C:/msys64/clang64/bin/clang++.exe -DLLVM_DIR=C:/msys64/clang64/lib/cmake/llvm '-DPURE_FAUST_EXECUTABLE=C:/Program Files/Faust/bin/faust.exe' -DPURE_STRICT_TOOLCHAIN=ON -DBUILD_TESTING=ON -DPURE_SANITIZERS=address
```

Exit 0; configure 33.7 s, generate 0.6 s.

```powershell
cmake --build pure/build/final-fix-verified-asan --parallel 1
```

Exit 0; approximately 90 s.  Generated compile commands showed
`-fsanitize=address` on runtime/interpreter and `pure-jit-smoke`; only
`coff_jitlink.cc` appended the documented `-fno-sanitize=address` boundary.

With `ASAN_OPTIONS=detect_leaks=0:halt_on_error=1`, all deterministic clean and
quiescent first attempts passed:

- `pure-jit-smoke`: 1/1, exit 0, 1.45 s.
- `pure-jit-lifetime-stress`: 1/1, exit 0, 1.65 s.
- `pure-jit-fresh-process-repeat`: 20/20, exit 0, 4.44 s, with exact output
  `Pure fresh-process JIT attempts passed: 20`.
- `pure-inline-source-lifetime`: 1/1, exit 0, 59.36 s.
- `sh ./run-tests -v ../../test/test058.pure` from the ASan build: exit 0,
  `test058.pure: passed` on the isolated first attempt.

### Hygiene and diff review

- Post-gate process check found no `pure`, `pure-jit-smoke`, or `faust` process.
- No PID-qualified Faust temporary C file or `.run-tests.*` directory remained in
  either final verification tree.
- Repository audit found one product `ResourceTracker::remove()` call, inside the
  central cleanup helper, and one product tracker creation, inside
  `prepare_tracker`.
- No `false &&` bypass or new TODO marker remains.
- `git diff --cached --check` passed before the implementation commit; only Git's
  existing line-ending conversion notices were emitted while staging.

## Remaining limitations

1. Leak freedom is not claimed on LLVM 22 MinGW/Windows; the deterministic ASan
   acceptance is address-safety only with leak detection disabled for the stated
   unsupported ABI/runtime behavior.
2. The POSIX harness contract is present and exercised, but this Windows-only
   environment could not execute the entire regression corpus on a native POSIX
   host.
3. The Windows ASan-specific `coff_jitlink.cc` no-instrumentation boundary should
   be removed when LLVM and the client are built together with a compatible ASan
   ABI.
