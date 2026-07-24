# TODO-14 - Complete ORC Runtime and Batch Migration

Status: Open
Branch: todo/14-complete-orc-runtime-and-batch-migration

## Purpose

Finish the hybrid-runtime migration left after the LLVM 22 release baseline. Success
means all runtime-reachable materialization, mappings, retained definitions, and Faust
batch operations use ORC ownership, after which MCJIT and the LLVM 2.x/3.x
compatibility gates can be removed.

## Scope

- Route eager compilation and retained batch initialization through ORC.
- Move batch Faust dispatch and materialization away from `ExecutionEngine`.
- Replace legacy host mappings, external resolution, unmapping, and body deletion.
- Remove MCJIT linkage, obsolete headers, and LLVM version compatibility gates.
- Decide whether native extensions need stable callable addresses for interactively
  redefinable Pure functions; language-level stable closure slots remain supported.
- Preserve the LLVM 22 O1-to-`llc -filetype=obj` batch pipeline established by TODO-13.

## Task List

1. [x] Inventory every remaining `ExecutionEngine`, MCJIT, mapping, and materialization consumer.
2. [x] Route `jit_now` and `pure_interp_compile` through explicit ORC units.
3. [ ] Route retained `dodefn(keep)` initialization and batch Faust through ORC.
4. [ ] Replace legacy mappings and fallback resolution with ORC symbols.
5. [ ] Replace stale-module cleanup with tracker and generation ownership.
6. [ ] Decide and document the native callable-address ABI policy.
7. [ ] Remove `ExecutionEngine`, MCJIT linkage, obsolete headers, and `LLVM26` through
   `LLVM35` plus `NEW_USER_ITERATOR` compatibility gates.
8. [ ] Validate eager mode, complete batch executables, batch Faust, redefinition
   lifetime, and shutdown in Debug, Release, and sanitizer builds.

## Transitional Engine Inventory

The remaining `ExecutionEngine` is created from the interpreter's mutable module by
`EngineBuilder` during `interpreter::init`, configured for eager/lazy mode by
`init_jit_mode`, given the `resolve_legacy_external` fallback, and deleted after global
environments during interpreter shutdown. CMake links both `ExecutionEngine` and
`MCJIT` solely for this path.

Runtime consumers fall into five migration groups:

| Group | Active consumers | Required ORC replacement |
| --- | --- | --- |
| Core host state | `$$sstk$$`, `$$fptr$$`, `register_host_global`, and `remove_host_global` mirror ORC absolute symbols into `addGlobalMapping`/`updateGlobalMapping`. | Remove the synchronized legacy half after every submitted ORC unit resolves these host addresses. |
| Eager/native materialization | `jit_now` walks either the entire mutable module or the `check_used` closure and calls `getPointerToFunction`; `pure_interp_compile` is its public C API entry. | Materialize explicit immutable ORC generations for requested Pure functions and define whether the API promises only compilation or a stable native address. |
| Retained batch initialization | `dodefn(keep)` invokes generated `$$init` code through MCJIT while retaining that code in the batch output module. | Execute a temporary reduced ORC initializer without consuming or removing the definition needed by later object emission. |
| Batch Faust | The compiling path links Faust definitions into the output module, creates stable dispatch slots, obtains operation addresses with `getPointerToFunction`, patches reload slots, and unmaps removed globals. `declare_extern(..., materialize)` also uses MCJIT for Faust dispatch initialization. | Keep definitions in batch IR while materializing separate ORC snapshots for initialization/dispatch; track their slots and temporary providers explicitly. |
| Legacy cleanup | `Env::clear` unmaps live local/global function addresses before deleting bodies; batch Faust reload unmaps old globals. | Let generation/resource trackers own machine code and remove only mutable-module IR after all ORC snapshots and closure references are accounted for. |

Two `getPointerToGlobal` sites are not independent ownership requirements: the Faust
fallback is paired with legacy batch materialization, while the global-function use is
`DEBUG>1` diagnostics. The commented `const_defn` mapping call is dead documentation,
not a consumer.

The active compatibility/linkage residue is correspondingly bounded:

- `LLVM27` controls eager-mode configuration, obsolete engine construction branches,
  and stale body cleanup; `LLVM26`/`LLVM31` select dead engine/target alternatives;
- `LLVM30` wraps the modern `CreatePHI` signature, `LLVM32` aliases `DataLayout`, and
  `NEW_USER_ITERATOR` selects the modern user iterator;
- `LLVM33` and `LLVM35` are defined but have no remaining C++ consumers;
- four `!LLVM31` blocks in `pure.cc`, `pure_norl.cc`, and `runtime.cc` guard the dead
  global `GuaranteedTailCallOpt` path;
- `LLVM_VERSION` is unrelated current version metadata and remains protected by the
  task guardrail.

Migration order is therefore: add explicit eager ORC materialization and settle its
native ABI, move retained initializers and batch Faust to ORC snapshots, remove mirrored
legacy mappings/cleanup, then delete engine construction, resolver, linkage, headers,
and compatibility branches. Interactive evaluation, definition units, lazy global
snapshots, type generations, external wrappers, bitcode providers, and interactive
Faust generations already use ORC and form the correctness baseline.

## Guardrails

- Do not remove MCJIT while any runtime-reachable consumer remains.
- Do not weaken old-closure, first-class extern-wrapper, or transactional Faust
  reload lifetime behavior.
- Do not promise a stable native callable address unless tests define and enforce it.
- Keep `LLVM_VERSION`; it is current build metadata, not a compatibility gate.

## Validation Plan

- Build and run focused eager, definition, closure, batch, and Faust tests in all presets.
- Link and execute a complete batch-produced program, not only an object-file smoke test.
- Search for `ExecutionEngine`, `EngineBuilder`, MCJIT mapping/materialization methods,
  `LLVM2`/`LLVM3` compatibility macros, and `NEW_USER_ITERATOR`.
- Run the complete supported regression corpus after the runtime transition.
- Preserve TODO-18's reduced-helper localization and transactional type-generation
  replacement; stale type addresses and all initial duplicate-publication boundaries
  now pass their focused and corpus reproducers.

## Origin

Created from TODO-07 task 5 and TODO-13 retrospective gate 4. It also owns the
batch-mode deferral recorded by TODO-11 and the native callable ABI question from
TODO-09. TODO-18 supplies 11 complete-corpus reproducers for duplicate ORC
publication and invalid continuation after a failed materialization.

## Progress Log

- 2026-07-25: Completed the transitional engine and compatibility-gate inventory.
  - Classified engine ownership, host mappings, eager/C-API materialization, retained
    batch initialization, batch Faust dispatch/reload, and stale IR cleanup.
  - Distinguished active runtime consumers from one commented mapping and a debug-only
    address print.
  - Confirmed `pure_interp_compile` delegates directly to `jit_now` and that CMake's
    `ExecutionEngine`/`MCJIT` components support the single interpreter-owned engine.
  - Counted the active `LLVM26`/`27`/`30`/`31`/`32` and `NEW_USER_ITERATOR` gates;
    `LLVM33` and `LLVM35` have no consumers beyond their definitions.
  - Validation:
    - Read-only source, header, and CMake audit; no build or runtime test was required.
- 2026-07-25: Routed eager compilation and `pure_interp_compile` through current ORC
  function generations.
  - Extracted shared current-generation materialization from deferred closure resolution,
    preserving tracker ownership, immutable snapshots, and latest-generation rebinding.
  - Kept `jit_now`'s dependency analysis while replacing MCJIT function-pointer requests
    with explicit ORC snapshot submission and lookup.
  - Added the no-prelude `pure-jit-eager` regression test for eager root and dependency
    materialization; the public C API continues to delegate directly to `jit_now`.
  - Validation:
    - `cmake --build --preset llvm22-release --parallel 1` passed.
    - `pure-jit-eager`, `pure-jit-lifetime-stress`, and `pure-jit-smoke` passed in the
      LLVM 22 Release preset.
    - `cmake --build --preset llvm22-asan --parallel 1` and the same focused tests passed
      under ASan/UBSan without sanitizer findings.
    - Confirmed `jit_now` no longer calls `getPointerToFunction`; remaining calls belong
      to retained definition and batch Faust migration in task 3.
- 2026-07-25: Routed retained `dodefn(keep)` initialization through an immutable ORC
  snapshot.
  - Unified interactive and batch definition execution on reduced, uniquely renamed ORC
    copies while leaving retained `$$init` IR in the mutable module for object emission.
  - Attached the batch snapshot tracker to the retained definition environment so escaped
    local closures and their machine code share the existing lifetime boundary.
  - Removed the definition initializer's `ExecutionEngine::getPointerToFunction` use;
    batch Faust remains before task 3 can be marked complete.
  - Validation:
    - LLVM 22 Release and ASan/UBSan serial builds passed.
    - `pure-batch-object` and `pure-jit-lifetime-stress` passed in both presets without
      sanitizer findings.
