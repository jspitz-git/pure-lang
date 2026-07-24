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
2. [ ] Run the full tests and classify any remaining behavior differences.
3. [ ] Verify build, test, install, uninstall, and installed-program execution.
4. [ ] Update documentation for Clang/LLVM 22, CMake, Ninja, LLDB, and bitcode policy.
5. [ ] Remove superseded Autoconf and Makefile infrastructure after parity review.
6. [ ] Perform a clean-tree release build and close or create follow-up TODOs.

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
- The legacy build consists of `configure.ac`, `acinclude.m4`, `Makefile.in`, and
  `examples/Makefile.in`. Its LLVM 2.5-3.5 tool search, removed-header probes,
  `jit` component selection, and version feature checks are obsolete, but the
  files stay until installation parity is verified in task 3.

The safe cleanup order is: collapse dead version gates, preserve their LLVM 22
behavior, migrate live materialization and host mappings to ORC, remove the
transitional engine and linked components, then retire Autoconf after parity
review.

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
