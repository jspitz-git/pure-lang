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

1. [ ] Inventory every remaining `ExecutionEngine`, MCJIT, mapping, and materialization consumer.
2. [ ] Route `jit_now` and `pure_interp_compile` through explicit ORC units.
3. [ ] Route retained `dodefn(keep)` initialization and batch Faust through ORC.
4. [ ] Replace legacy mappings and fallback resolution with ORC symbols.
5. [ ] Replace stale-module cleanup with tracker and generation ownership.
6. [ ] Decide and document the native callable-address ABI policy.
7. [ ] Remove `ExecutionEngine`, MCJIT linkage, obsolete headers, and `LLVM26` through
   `LLVM35` plus `NEW_USER_ITERATOR` compatibility gates.
8. [ ] Validate eager mode, complete batch executables, batch Faust, redefinition
   lifetime, and shutdown in Debug, Release, and sanitizer builds.

## Guardrails

- Do not remove MCJIT while any runtime-reachable consumer remains.
- Do not weaken old-closure lifetime or transactional Faust reload behavior.
- Do not promise a stable native callable address unless tests define and enforce it.
- Keep `LLVM_VERSION`; it is current build metadata, not a compatibility gate.

## Validation Plan

- Build and run focused eager, definition, closure, batch, and Faust tests in all presets.
- Link and execute a complete batch-produced program, not only an object-file smoke test.
- Search for `ExecutionEngine`, `EngineBuilder`, MCJIT mapping/materialization methods,
  `LLVM2`/`LLVM3` compatibility macros, and `NEW_USER_ITERATOR`.
- Run the complete supported regression corpus after the runtime transition.

## Origin

Created from TODO-07 task 5 and TODO-13 retrospective gate 4. It also owns the
batch-mode deferral recorded by TODO-11 and the native callable ABI question from
TODO-09.
