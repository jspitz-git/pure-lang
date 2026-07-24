# TODO-13 - Release Validation and Cleanup

Status: Open
Branch: todo/13-release-validation-and-cleanup

## Purpose

Complete the LLVM 22 migration by running broad validation, documenting the supported
toolchain, and removing superseded LLVM 2.x/3.x and Autoconf infrastructure. Success
means a clean CMake/Ninja build is the sole documented path and the full supported test
suite passes.

## Scope

- Run the complete corpus in Debug, sanitizer, and release configurations.
- Remove obsolete `ExecutionEngine`, LLVM compatibility macros, and build checks.
- Retire Autoconf/Makefile files only after feature and installation parity is confirmed.
- Update installation, development, bitcode, Faust, and debugging documentation.

## Task List

1. [x] Audit the tree for old JIT calls, LLVM version macros, and obsolete headers.
2. [x] Run the full tests and classify any remaining behavior differences.
3. [x] Verify build, test, install, uninstall, and installed-program execution.
4. [x] Update documentation for Clang/LLVM 22, CMake, Ninja, LLDB, and bitcode policy.
   - The active batch compiler and manual now use an LLVM 22 O1-to-`llc
     -filetype=obj` pipeline, covered by a focused object-output test.
5. [x] Remove superseded Autoconf and Makefile infrastructure after parity review.
6. [x] Perform a clean-tree release build and close or create follow-up TODOs.

Final status remains open pending TODO-17's preset worker and timeout policy. The
Release build and all 12 current focused tests pass. The bounded Release corpus
initially found 20 deterministic differences; TODO-18 fixed all of them, and complete
confirmation runs now pass 97/97 in Release, Debug, and ASan/UBSan. This establishes
the supported-suite behavior pass; only codifying its budgets remains.

## Legacy LLVM Audit

The runtime still has a hybrid ORC/MCJIT architecture. `PureJit` owns current
interactive compilation units, but `interpreter::JIT` remains a live
`ExecutionEngine` created by `EngineBuilder`. It cannot be removed as dead code.

### Runtime-reachable MCJIT dependencies

| Area | Active dependency |
| --- | --- |
| Initialization and shutdown | `interpreter::init`, `init_jit_mode`, and the destructor create, configure, and delete `JIT` |
| Host globals | Stack, frame, and generated globals use `addGlobalMapping` and `updateGlobalMapping` beside ORC absolute symbols |
| Eager compilation | `jit_now` and `pure_interp_compile` materialize functions with `getPointerToFunction` |
| Batch definitions | The `dodefn(keep)` path still invokes generated initializers through MCJIT |
| Faust batch mode | Dispatch slots and functions use `getPointerToGlobal` and `getPointerToFunction`; interactive Faust already uses ORC |
| Environment cleanup | Legacy mappings are cleared while ORC generation trackers reclaim their own resources |
| Build linkage | `PureTargets.cmake` still requests the `ExecutionEngine` and `MCJIT` LLVM components |

There is no remaining `freeMachineCodeForFunction` call. Only an obsolete
comment and the Autoconf `LLVMFreeMachineCodeForFunction` probe remain.

### Compatibility inventory

`interpreter.hh` unconditionally defines `LLVM26`, `LLVM27`, `LLVM30`,
`LLVM31`, `LLVM32`, `LLVM33`, and `LLVM35`. The C++ tree contains 25 references
to these macros. For LLVM 22 they divide into:

- active modern branches whose behavior should become unconditional, including
  `CreatePHI`, object output, `deleteBody`, native-target initialization, and
  the current `EngineBuilder` path;
- compile-time-dead pre-LLVM-3.5 alternatives, including
  `ExistingModuleProvider`, old `ExecutionEngine::create` overloads,
  `GuaranteedTailCallOpt`, and the pre-LLVM-3.0 `CreatePHI` call;
- a MinGW LLVM 3.5 workaround and historical `opt -std-compile-opts` batch
  command which require platform and batch-output validation before removal.

`NEW_USER_ITERATOR` is another always-enabled LLVM 3.5 compatibility gate. Its
modern `Value::user_iterator` behavior can become unconditional. `LLVM_VERSION`
is current build metadata used in version and generated-file output, not a
compatibility gate, and must remain.

### Header and build-file classification

- `ExecutionEngine.h`, `MCJIT.h`, and the `TargetOptions.h` include in
  `interpreter.hh` support the live transitional engine and must remain until
  its consumers are migrated.
- `TargetOptions.h` includes in `pure.cc`, `pure_norl.cc`, and `runtime.cc` only
  support dead `GuaranteedTailCallOpt` branches and can be removed with those
  branches.
- ORC headers and `ExecutionEngine/JITSymbol.h` are current LLVM 22 dependencies;
  the latter supplies live `JITSymbolFlags` and is not legacy MCJIT residue.
- The legacy build consisted of `configure.ac`, `acinclude.m4`, `Makefile.in`,
  and `examples/Makefile.in`. Its LLVM 2.5-3.5 tool search, removed-header
  probes, `jit` component selection, and version feature checks were obsolete.
  The files remained through installation parity validation in task 3 and were
  removed in task 5.

The remaining runtime cleanup order is: collapse dead version gates, preserve
their LLVM 22 behavior, migrate live materialization and host mappings to ORC,
and then remove the transitional engine and linked components. Retiring the
independent legacy build files required installation parity, not completion of
that runtime migration.

## Full-test Classification

All ten focused integration tests pass in Debug and Release. The ASan/UBSan
preset initially had the Faust lifecycle test disabled; running its exact driver
under the sanitizer environment completed without a finding, so it is now
active. With sanitizer-specific bitcode and Faust timeouts raised to 300 seconds,
all ten ASan/UBSan integration tests pass in one 434-second CTest run.

The `pure-regression` test remains a harness and performance blocker rather than
a classified language or ORC behavior failure:

- the complete preset was started in all three configurations; bounded runs
  completed the prelude plus 1 Debug, 17 Release, and 6 ASan regression scripts
  before their 5- or 10-minute outer validation limits expired;
- every completed script produced a golden diff at minimum because 208 of 223
  checked `.pure` and `.log` files use CRLF while `core.autocrlf=input` leaves
  those endings in the Linux worktree and the current output uses LF;
- the lexer also treats the CR before a pragma newline as part of its token, so
  CRLF `--if` values and `--endif` lines produce unrecognized or unmatched
  pragma diagnostics that prefix every result;
- no completed diff or CTest output contained an assertion, crash, ASan, UBSan,
  or LeakSanitizer diagnostic;
- each isolated interpreter startup recompiles the prelude in roughly 28-85
  seconds, so the serial 97-input runner needs tens of minutes in Release and
  substantially longer under ASan.

TODO-13 fixed EOL handling at both relevant boundaries: pragma lexer rules now
accept CRLF in directly loaded library scripts, and `run-tests` normalizes line
endings in test inputs and golden logs before execution/comparison. The former
`test070.pure` reproducer now passes while loading the prelude and libraries.
TODO-17's bounded runner completed the full Release corpus in 1347.36 seconds with
four workers. It found 77 passing and 20 failing inputs; serial `-f` reproduced all
20 failures, proving they are not scheduler races. TODO-18 owns their behavior
compatibility classification and fixes, with the ORC subset shared with TODO-14.
TODO-18 has now cleared the configuration-independent differences: initial confirmation
runs passed 97/97 in Release in 897.16 seconds with four workers and in Debug in
1043.32 seconds with eight workers. The initial four-worker Debug run exceeded its
30-minute outer limit but correctly cleaned up workers, staging, and the build-directory
lock. After removing quadratic ORC snapshots and restoring deferred global compilation,
the four-worker corpora still pass 97/97 but now finish in 292.28 seconds in Release
and 457.56 seconds in Debug. The first complete pre-fix sanitizer run finished all 97
inputs with eight workers in 5273.61
seconds and exposed five genuine ASan/UBSan failures. Their bigint conversion,
blob alignment, pragma parsing, and hash-rotation root causes are fixed. The post-fix
sanitizer confirmation passes 97/97 in 1280.27 seconds with four workers, `PURE_STACK=0`,
and a nonzero 64 MiB ASan quarantine. The supported corpus now passes in all three
configurations; TODO-17 only needs to codify the measured preset budgets.

## Installation Validation

A fresh out-of-tree Release configuration used an isolated configure-time
prefix and built successfully with Ninja and one compile job. Its ten focused
integration tests passed before installation. CMake installs 28 manifest entries
covering the executable, versioned runtime library and symlinks, public header,
`pure_main.c` and `pure_main.o`, 19 Pure library scripts, pkg-config metadata,
and the manual page. This matches the legacy build's core installation set.

The installed `pure --version` reports Pure 0.68 and LLVM 22.1.8. With the
nonstandard temporary library directory supplied through `LD_LIBRARY_PATH`, the
installed interpreter locates its configured library scripts and executes
`examples/hello.pure`, printing `Hello, world!`. Its additional pragma output is
the CRLF issue already classified in task 2. `pkg-config` reports version 0.68
and the isolated include and library directories.

CMake now provides an `uninstall` target backed by `install_manifest.txt`. It
removes all installed files and symlinks, tolerates already absent files, and a
second invocation remains successful. It intentionally leaves empty parent
directories owned by the prefix.

The legacy build could optionally install Emacs and TeXmacs integrations. CMake
now provides opt-in source installation for both, with configurable destination
directories. Emacs bytecode generation is intentionally left to package
maintainers because `.elc` output depends on the target Emacs version. Neither
Emacs nor TeXmacs is required to preserve or install the portable source assets.

## Supported Documentation

`INSTALL` now defines Clang/LLVM 22 with CMake and Ninja as the supported source
build. It documents presets and custom builds, serial compilation, focused and
full tests, sanitizer and leak modes, configure-time installation prefixes,
pkg-config, manifest uninstall, LLDB/Zed launch support, symbolic ORC
breakpoints, and opt-in JIT dumps. The README installation summary points to the
same workflow and no longer recommends Autoconf or LLVM 2.5-3.5.

The language manual now describes eager materialization without obsolete LLVM
version gates. Its active foreign-code sections require LLVM 22-compatible
bitcode, use `clang-22` and Flang 22 examples, explain target/data-layout
validation and cross-version incompatibility, and document transactional Faust
reload with explicit sample-format markers or recognized legacy metadata.
Historical release notes and glossary entries remain as history rather than
supported build instructions.

## Legacy Build Removal

The CMake build now preserves the final optional installation features from the
legacy Makefiles. `PURE_INSTALL_EMACS_MODE` configures and installs
`pure-mode.el` with `flycheck-pure.el`, while `PURE_INSTALL_TEXMACS_PLUGIN`
installs the complete package, documentation, Scheme helpers, and Pure helper
script. Both options default to off so the verified core installation manifest
is unchanged, and both destination roots are configurable.

With this parity in place, `configure.ac`, `acinclude.m4`, `Makefile.in`, and
`examples/Makefile.in` have been removed. Historical references in `ChangeLog`
remain intact. Live MCJIT/`ExecutionEngine` dependencies and LLVM compatibility
gates are outside this build-system cleanup and remain tracked for a dedicated
runtime migration.

## Retrospective TODO Audit

A second pass over TODO-01 through TODO-12 found prerequisites which later work
satisfied but never reconciled in the originating documents, plus deliberate
scope deferrals which still need explicit ownership. Historical progress-log
entries remain unchanged; only their current status and follow-up implications
need correction.

| TODO | Current audit result | Required disposition before task 6 |
| --- | --- | --- |
| TODO-01 | Retrospectively closed: the runner inventory, later coverage, smoke policy, golden oracle, and pre-port blockers are now explicit. | Complete; the historical branch lacked implementation commits, but downstream evidence satisfies the original baseline purpose. |
| TODO-02 | Build/install blockers are resolved on Linux. Windows and macOS were deliberately not validated. | Keep the historical closure and assign non-Linux validation only after defining the supported release matrix. |
| TODO-03 | Context/type migration is complete. The deferred LLVM version gates still protect both dead branches and live MCJIT code. | Move gate removal with the transitional engine rather than treating it as context cleanup. |
| TODO-04 | Closed after reconciling its verifier boundary with downstream integration results. Pointer-bearing external bitcode is still rejected without explicit Pure ABI metadata. | Verifier work is complete; assign pointer ABI metadata under gate 5. |
| TODO-05 | Closed with standard O1 as the supported function and reduced-module correctness baseline. Verified unoptimized/O1 IR supplies the ABI comparison; no runtime O0 mode is supported. | Complete; runtime selectors, custom pipelines, and tuning require future profiling rather than release validation. |
| TODO-06 | The LLJIT foundation and typed lookup are complete. `ExecutionEngine` remains live for mappings, eager JIT, batch definitions, and batch Faust. | Assign full MCJIT removal to a runtime follow-up. |
| TODO-07 | Reopened with task 3 complete. Legacy unmapping/body deletion in task 5 remains tied to MCJIT. | Move task 5 to the runtime follow-up under gate 4, then close the ORC resource TODO. |
| TODO-08 | ORC host symbols, rebinding, and missing-symbol diagnostics are complete. Legacy mappings and the fallback resolver remain active beside them. | Preserve the ORC closure and assign removal of the synchronized legacy path to the runtime follow-up. |
| TODO-09 | Closure generations, redefinition, and collection are complete. ORC stubs are unnecessary for language calls, which use stable closure slots. | No native callable-address guarantee is currently promised; TODO-14 owns an explicit future decision and any implementation. |
| TODO-10 | Target/data-layout policy and per-provider trackers are complete. It did not solve TODO-04's pointer ABI metadata requirement. | Close its resolved design questions without claiming pointer-bearing ABI support. |
| TODO-11 | Interactive Faust load/reload/rollback/lifetime behavior is complete. The LLVM 22 batch object pipeline now passes, while batch Faust still uses legacy MCJIT. | TODO-14 owns complete batch-Faust execution and MCJIT removal; active batch documentation is corrected. |
| TODO-12 | Closed after all five targeted LeakSanitizer bitcode tests passed. JIT symbol publication is automatic; actual LLDB inferior launch fails identically for the smoke binary and `/bin/true` on this host. | Complete with a reproducible host limitation; a real named-frame stop remains an interactive check on a host which permits LLDB launch. |

The remaining work therefore falls into six explicit gates before final release
closure:

1. [x] Reconcile the stale TODO-01, TODO-04, and TODO-07 checklists/statuses.
2. [x] Resolve TODO-05's O0/O1 validation disposition and stale design questions.
3. [x] Exercise the named JIT frame under LLDB 22 and the bitcode tests under the
   targeted LeakSanitizer preset, recording the host launch limitation.
4. [x] Correct the active batch documentation and assign LLVM 22 batch/MCJIT
   modernization, compatibility-gate removal, and native callable ABI policy to
   TODO-14.
5. [x] Assign explicit Pure metadata for pointer-bearing bitcode to TODO-15 and
   non-Linux release validation to TODO-16.
6. [x] Fix CRLF-sensitive lexer/input/golden handling and assign the independent
   repeatedly-started regression-harness performance problem to TODO-17. Do not
   claim a complete supported test-suite pass until TODO-17 completes it.

## Release-build Result

A fresh out-of-tree Release configuration in `build/todo13-release-final` used
Clang/LLVM 22.1.8 and Ninja. Its serial 31-step build completed successfully, and
all 11 focused CTest tests passed in 193 seconds, including bitcode, Faust, JIT
lifetime/debug-dump, and LLVM 22 batch object output. This satisfies the clean
build portion of task 6. The complete `pure-regression` corpus is deliberately not
reported as passing; TODO-17 owns the remaining startup-duration gate.

The release cleanup produced four numbered follow-ups:

- TODO-14: complete ORC runtime/batch migration and decide native callable ABI;
- TODO-15: define pointer-bearing external bitcode ABI metadata;
- TODO-16: define and validate the non-Linux release matrix;
- TODO-17: bound the repeatedly-started complete regression harness;
- TODO-18: resolve deterministic corpus behavior and golden differences.

## Guardrails

- Do not remove the old build before the CMake path covers required installation assets.
- Do not close the migration with unexplained disabled tests or sanitizer findings.
- Keep unrelated historical project files and changelog entries intact.

## Validation Plan

- Configure and build from a fresh directory with each supported preset.
- Run `ctest --preset llvm22-debug --output-on-failure` and release/ASan equivalents.
- Run installation into a temporary prefix and execute the installed binary and examples.
- Search for `ExecutionEngine`, `freeMachineCodeForFunction`, and `LLVM2`/`LLVM3` macros.

## Open Questions

- Which operating systems and architectures are required for the first LLVM 22 release?
- Should any optional legacy feature be deferred to a separately numbered TODO?

## Progress Log

- 2026-07-22: Initial final-validation and cleanup plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
- 2026-07-24: Audited legacy LLVM APIs, compatibility gates, headers, and build
  infrastructure. The audit distinguishes compile-time-dead LLVM 2.x/3.x
  branches from the runtime-reachable transitional MCJIT used by host mappings,
  eager compilation, batch definitions, and Faust batch mode.
  - Validation:
    - Searched C and C++ sources for `ExecutionEngine`, `EngineBuilder`, MCJIT
      mapping and materialization calls, and `freeMachineCodeForFunction`.
    - Counted 25 `LLVM26` through `LLVM35` references in C++ sources and
      classified their active and dead branches under LLVM 22.
    - Audited LLVM includes and confirmed that ORC's `JITSymbol.h` remains live.
    - Inventoried the four legacy build files and the obsolete LLVM probes in
      `configure.ac`.
    - No build or runtime validation was needed because this step changes audit
      documentation only.
- 2026-07-24: Ran the complete Debug, Release, and ASan CTest presets and
  classified the remaining regression-runner differences. All focused
  integration tests pass; ASan now runs Faust lifecycle instead of disabling it.
  - Validation:
    - `ctest --preset llvm22-debug --output-on-failure` passed its first ten
      tests; the outer 300-second limit expired during `pure-regression`.
    - `ctest --preset llvm22-release --output-on-failure` passed its first ten
      tests; the outer 600-second limit expired during `pure-regression`.
    - The initial complete ASan run passed all nine enabled tests without a
      finding and reached `pure-regression` before its 600-second outer limit.
    - The disabled Faust driver passed manually under the preset's ASan/UBSan
      environment, then passed as an enabled CTest test in 104 seconds.
    - `ctest --preset llvm22-asan -E pure-regression --output-on-failure`
      passed all ten integration tests in 434 seconds after increasing
      sanitizer integration-test timeouts to 300 seconds.
    - Bounded regression runs completed 1 Debug, 17 Release, and 6 ASan scripts
      after the prelude. Their diffs contain the classified CRLF EOL and pragma
      noise, with no crash or sanitizer signatures.
- 2026-07-24: Verified the CMake build, focused tests, installation metadata,
  installed interpreter, representative example, and manifest-based uninstall
  in an isolated prefix. Core host installation parity is complete.
  - Validation:
    - Fresh Release configure in `build/install-validation/build` with Clang 22,
      LLVM 22, Ninja, and a prefix under `build/install-validation/prefix`.
    - `cmake --build build/install-validation/build --parallel 1`
    - `ctest --test-dir build/install-validation/build -E pure-regression
      --output-on-failure` passed all ten tests in 164 seconds.
    - `cmake --install build/install-validation/build` installed 28 manifest
      entries with no path outside the temporary prefix.
    - Installed `pure --version` reported Pure 0.68 and LLVM 22.1.8.
    - Installed Pure ran `examples/hello.pure` and printed `Hello, world!`.
    - `pkg-config --modversion pure` reported 0.68; cflags and libraries used
      the temporary prefix.
    - The first `uninstall` removed every manifest file and symlink. A second
      invocation succeeded with all entries already absent.
    - Emacs and TeXmacs were unavailable; their optional legacy install rules
      remain a task 5 parity decision.
- 2026-07-24: Replaced the LLVM 3.4/Autoconf installation guide with the
  supported LLVM 22 CMake/Ninja workflow and synchronized the README and active
  bitcode, inline-code, eager-JIT, Faust, debugging, and uninstall guidance.
  - Validation:
    - Searched `INSTALL`, `README`, and active `pure.txt` sections for obsolete
      LLVM 2.x/3.x, llvm-gcc, DragonEgg, Autoconf, and GNU make instructions.
    - Confirmed current commands use the checked presets, Clang 22, LLVM 22,
      Ninja, LLDB 22, and the tested CMake install/uninstall targets.
    - Confirmed bitcode documentation covers target/data-layout rejection,
      resource ownership, and LLVM-major compatibility.
    - Confirmed Faust documentation covers sample-format validation,
      transactional replacement, live-instance protection, and rollback.
    - Confirmed `PURE_ATSCC`, `PURE_ATSCCOMP`, and `PURE_JIT_DUMP` names and
      values against their implementations.
    - Standalone `rst2html` validation is not applicable because `INSTALL` uses
      the Sphinx `highlight` directive; CMake has no documentation target.
    - No build was run because this step changes documentation only.
- 2026-07-24: Replaced the last optional legacy install rules with explicit
  CMake options and removed the superseded Autoconf and Makefile infrastructure.
  - Validation:
    - Configured a fresh Release build with both optional install features
      enabled, without requiring Emacs or TeXmacs executables.
    - Built serially; the focused integration suite passed all ten tests in 97
      seconds.
    - Installed into an isolated prefix and verified both configured paths in
      the generated Emacs mode, the Flycheck mode, and all eight TeXmacs assets
      among the 37 install-manifest entries.
    - Ran manifest uninstall and confirmed that every installed file was
      removed.
    - Searched the active tree for references to the four removed build files;
      only historical `ChangeLog` and this migration record remain.
- 2026-07-24: Re-audited TODO-01 through TODO-12 for deferred work whose later
  prerequisites have landed. Reopened the documentation milestone and recorded
  six pre-closure gates rather than hiding unresolved work in historical logs.
  - Validation:
    - Enumerated every current status and unchecked main checklist item across
      all thirteen TODO documents.
    - Cross-checked deferred ownership against later TODO results, current CMake
      tests, and the active interpreter implementation.
    - Confirmed that TODO-04 verification and TODO-07 definition tracking are
      now unblocked, while TODO-07 legacy cleanup remains coupled to MCJIT.
    - Confirmed active `ExecutionEngine` mappings/materialization, the legacy
      external resolver, LLVM compatibility gates, and batch Faust consumers.
    - Confirmed that pointer-bearing bitcode exports remain rejected pending
      explicit Pure ABI metadata.
    - Found the obsolete batch `opt -std-compile-opts` command in both
      `interpreter.cc` and active `pure.txt`, reopening task 4.
    - Counted 189 CRLF files among 199 top-level `test/*.pure` and `test/*.log`
      corpus files on this worktree.
    - No build or test was run because this step is a read-only ownership audit.
- 2026-07-24: Reconciled TODO-01, TODO-04, and TODO-07 after their downstream
  prerequisites and validation landed.
  - Validation:
    - Documented `run-tests` discovery, `run-test` environment setup, golden-log
      comparison, focused migration coverage, and the historical pre-port
      execution boundary in TODO-01.
    - Closed TODO-04's verifier task using the recorded LLVM verifier, fixture,
      and focused integration results while preserving pointer ABI metadata as
      follow-up work.
    - Marked TODO-07 definition tracking complete and changed its stale blocked
      status to open; legacy MCJIT cleanup remains its only unchecked task.
    - No test was rerun because this step reconciles existing implementation and
      recorded validation without changing code.
- 2026-07-24: Closed TODO-05's deferred optimization-policy questions.
  - Validation:
    - Confirmed that both active LLVM pass-manager boundaries intentionally use
      standard O1 and that the interpreter exposes no runtime O0 mode.
    - Retained the verified unoptimized/O1 IR comparison as the ABI-equivalence
      half of the original validation plan.
    - `ctest --preset llvm22-debug -R '^pure-jit-smoke$'
      --output-on-failure` passed 1/1 in 5.90 seconds.
    - Kept runtime optimization selection, custom pipelines, and performance
      tuning outside the LLVM 22 correctness release until justified by profiling.
- 2026-07-24: Completed the deferred TODO-12 LeakSanitizer validation and
  reproduced the LLDB host limitation.
  - Validation:
    - `ctest --preset llvm22-lsan -R '^pure-bitcode-'
      --output-on-failure` passed 5/5 in 299.85 seconds without sanitizer or leak
      findings.
    - LLDB created the Debug smoke target and pending generated-function
      breakpoint, but `run` reported `no target` and timed out after 300 seconds.
    - The same launch failure occurred for `/bin/true` under a hard 30-second
      limit, isolating it from Pure's JIT and debugger-object registration.
    - TODO-12 now distinguishes automated generated-symbol publication from the
      interactive named-frame stop unavailable on this host.
- 2026-07-24: Modernized the active LLVM 22 batch object pipeline, fixed CRLF
  pragma and golden-test handling, assigned all retrospective deferrals, and ran
  the fresh Release validation.
  - Replaced `opt -std-compile-opts` and LLVM 3.x object-output branches with
    `opt -O1 -o - | llc -filetype=obj` in the compiler and active manual.
  - Added `pure-batch-object`, which compiles a no-prelude Pure source and checks
    that batch compilation creates a nonempty object file.
  - Made all active and skipped-source pragma rules consume CRLF correctly, and
    normalized test inputs and golden logs at the regression harness boundary.
  - Closed TODO-07 after moving its final hybrid-runtime cleanup to TODO-14;
    TODO-15, TODO-16, and TODO-17 own pointer ABI metadata, non-Linux validation,
    and regression startup performance respectively.
  - Validation:
    - Debug `pure-batch-object` passed in 0.08 seconds.
    - Debug and fresh Release `run-tests -v test/test070.pure` runs passed after
      rebuilding the lexer; this test also loads the CRLF prelude and libraries.
    - ASan/UBSan `pure-batch-object` passed in 0.15 seconds without a finding.
    - A fresh serial Release build in `build/todo13-release-final` completed all
      31 steps with Clang/LLVM 22.1.8 and Ninja.
    - `ctest --test-dir build/todo13-release-final -E '^pure-regression$'
      --output-on-failure` passed all 11 focused tests in 193.05 seconds.
    - At this point the complete regression corpus had not yet finished; later
      TODO-17 work below completed it and exposed the TODO-18 behavior failures.
- 2026-07-24: Finished the first bounded complete Release corpus and classified
  the remaining release blockers.
  - The parallel harness completed all 97 inputs with 77 passes and 20 golden
    failures; a serial failed-only rerun reproduced the exact same failure set.
  - Assigned 11 ORC publication/materialization cases jointly to TODO-14/TODO-18,
    and assigned formatted input, blob fixtures, and other language differences
    to TODO-18.
  - Validation:
    - `run-tests -j 4` finished in 1347.36 seconds.
    - `run-tests -f -j 1` reproduced all 20 failures in 789.98 seconds.
    - No complete-suite pass was claimed at this stage; later TODO-18 work fixed
      the deterministic differences while Debug/sanitizer budgets remain in TODO-17.
- 2026-07-24: Completed the corrected full Release corpus.
  - Validation:
    - `run-tests -j 4` passed all 97 inputs in 897.16 seconds with no golden diff.
    - Release behavior is complete; full Debug and sanitizer corpus validation
      remains before TODO-13 can close.
- 2026-07-24: Completed the corrected full Debug corpus.
  - Validation:
    - The initial `run-tests -j 4` exceeded the 30-minute outer validation limit;
      termination correctly removed its workers, staging tree, and build lock.
    - `run-tests -j 8` passed all 97 inputs in 1043.32 seconds with no golden diff.
    - Debug behavior is complete; only full sanitizer corpus validation remains
      before TODO-13 can claim the complete supported-suite pass.
- 2026-07-24: Completed the first full sanitizer corpus and fixed its five findings.
  - A four-worker attempt exceeded a 60-minute outer limit and cleaned up correctly;
    eight workers completed all 97 inputs in 5273.61 seconds with five failures.
  - Fixed signed overflow in 32- and 64-bit bigint extraction, the one-byte pragma
    version scanset destination, an unaligned blob marker read, and signed hash shifts.
  - Validation:
    - ASan/UBSan `run-tests -f -j 5` passed `test018`, `test041`, `test042`,
      `test070`, and `test074` in 260.41 seconds without a finding.
    - The same five Release inputs passed in 80.40 seconds with unchanged golden output.
    - A clean complete sanitizer confirmation run remains required.
- 2026-07-24: Diagnosed and removed the ORC startup and memory regression.
  - Each isolated test process recreated 530 prelude objects. Entry snapshots copied
    the entire growing module before reduction, and global generations forced lookup
    despite active `DEFER_GLOBALS`; ASan quarantine amplified the allocation churn.
  - Entry snapshots now reduce before serialization, while deferred global generations
    retain compact bitcode and materialize only on first closure invocation.
  - Validation:
    - Release prelude startup improved from 22.91 to 3.72 seconds and ASan/UBSan
      startup from 68.08 to 12.56 seconds; object emission fell from 530 to 260.
    - Default-quarantine sanitizer RSS was 718 MiB per empty-prelude process versus
      413 MiB with a 64 MiB quarantine and 272 MiB with quarantine disabled.
    - All 12 focused Release and sanitizer tests passed in 36.18 and 112.44 seconds.
    - `run-tests -j 4` passed all 97 Release inputs in 292.28 seconds.
    - A complete post-fix sanitizer run remains required to select its final worker,
      quarantine, and timeout budget.
- 2026-07-24: Completed the clean post-fix ASan/UBSan corpus confirmation.
  - Validation:
    - `run-tests -j 4` passed the prelude and all 96 numbered inputs (97/97) in
      1280.27 seconds without a sanitizer finding or golden difference.
    - The run used `PURE_STACK=0`, the preset halt/strict sanitizer options, and a
      nonzero 64 MiB quarantine to cap four-worker memory while retaining UAF coverage.
    - Release, Debug, and sanitizer behavior validation is complete; only TODO-17's
      checked-in worker, quarantine, and CTest timeout policy remains before closure.
- 2026-07-24: Confirmed the complete Debug corpus after the JIT startup fix.
  - Validation:
    - `run-tests -j 4` passed all 97 inputs in 457.56 seconds with no golden diff.
    - Together with the post-fix Release and sanitizer runs, this confirms unchanged
      golden behavior across all supported configurations after lazy-JIT restoration.
- 2026-07-24: Removed fixed-size barriers from the parallel regression scheduler.
  - A completed worker now releases its slot immediately instead of waiting for all
    other workers in the same group; deterministic result replay remains unchanged.
  - Validation:
    - Generated runner passed `sh -n`.
    - A controlled uneven five-input `-j 4` schedule completed in 3.13 seconds, and
      five real Release inputs passed in deterministic argument order.
- 2026-07-24: Set preset-specific complete-corpus worker and timeout policy.
  - CTest now runs four regression workers with 10-minute Release, 15-minute Debug,
    and 30-minute sanitizer limits. Sanitizer regression also sets `PURE_STACK=0`,
    while ASan/LSan presets use a nonzero bounded 64 MiB quarantine.
  - Validation:
    - Generated CTest JSON contained the exact timeout/environment policy in all
      three presets.
    - The checked-in Release `pure-regression` test passed 97/97 in 243.72 seconds.
- 2026-07-24: Added opt-in ordered per-input timing to the regression runner.
  - `-t` and `TEST_TIMINGS=1` expose worker wall time without changing default output.
  - Validation:
    - Generated runner passed `sh -n`; timed and default two-input Release runs passed.
    - Invalid timing configuration was rejected before test execution.
