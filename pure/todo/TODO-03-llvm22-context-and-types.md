# TODO-03 - LLVM 22 Context and Types

Status: Open
Branch: todo/03-llvm22-context-and-types

## Purpose

Replace the LLVM 2.x/3.x context, header, and type compatibility layer with a single
LLVM 22 implementation. Success means that the core interpreter declarations use
modern LLVM ownership and type APIs without historical preprocessor branches.

## Scope

- Introduce an explicitly owned `LLVMContext` or `ThreadSafeContext`.
- Update LLVM includes and basic type/constant helper functions.
- Replace removed named, opaque, and recursive structure APIs.
- Remove compatibility macros that only distinguish LLVM 2.5 through 3.5.
- Do not yet complete instruction-level opaque-pointer migration or ORC execution.

## Task List

1. [x] Add explicit context ownership to the interpreter-facing LLVM state.
2. [x] Replace `getGlobalContext()` and context-free builders and modules.
3. [x] Modernize primitive, structure, function, and constant type helpers.
4. [ ] Replace obsolete includes and remove corresponding configure feature macros.
5. [ ] Compile the affected translation units and categorize remaining API failures.

## Migration Findings

- `interpreter` now directly owns one `llvm::LLVMContext` before its module and
  environment containers are initialized.
- `Env` builders obtain that same context through `pure_llvm_context()`; no
  process-global LLVM context or independent builder context remains in their
  constructors.
- The module is constructed with the owned context, and legacy function-pass
  manager declarations use the current `llvm::legacy` namespace.
- A direct `LLVMContext` is sufficient for the mutable pre-ORC stage. TODO-06 can
  transfer or wrap this ownership in `ThreadSafeContext` when modules begin moving
  across ORC boundaries.
- All module, bitcode-reader, basic-block, and local-builder construction now uses
  the interpreter-owned context; `getGlobalContext()` is no longer referenced.
- Primitive, recursive structure, function, string-constant, and global-variable
  helpers now use the LLVM 22 APIs without LLVM 2.x/3.x alternatives.
- Compilation now stops first at the mandatory opaque-pointer `CreateGEP` and
  `CreateLoad` signatures in `Env`; that instruction-level migration belongs to
  TODO-04.

## Guardrails

- Maintain one LLVM context per set of modules that may be linked together.
- Do not preserve LLVM 3.5 compatibility in the new implementation.
- Keep host ABI structure definitions consistent with `runtime.h` and GSL layouts.

## Validation Plan

- `cmake --build --preset llvm22-debug`
- Compile focused translation units with verbose Ninja output when diagnostics are unclear.
- Verify representative structure layouts with assertions or targeted tests.

## Open Questions

- Which generated headers expose LLVM types and need migration at the same time?

## Progress Log

- 2026-07-22: Removed global-context use and modernized the shared LLVM type and
  constant helper layer.
  - Bitcode parsing now consumes a `MemoryBufferRef` and unwraps LLVM 22's
    `Expected<std::unique_ptr<Module>>` while preserving the existing caller
    ownership contract.
  - Validation:
    - `cmake --preset llvm22-debug` configured successfully.
    - `cmake --build --preset llvm22-debug -- -j1` no longer reported removed
      static types, structure helpers, `GlobalVariable` constructors, or
      context-free `BasicBlock` construction.
    - Compilation stopped at six expected opaque-pointer `CreateGEP`/`CreateLoad`
      errors in `Env`; deferred to TODO-04 by scope.
- 2026-07-22: Added explicit interpreter-owned LLVM context state and routed
  module and `Env` builder construction through it.
  - Validation:
    - `cmake --preset llvm22-debug` configured successfully.
    - `cmake --build --preset llvm22-debug -- -j1` passed generated-source and
      include setup, then reached LLVM 22 type-helper and opaque-pointer errors.
    - The previous missing `llvm/ExecutionEngine/JIT.h` and
      `llvm/PassManager.h` blockers were removed using current headers.
    - No context-construction diagnostic was emitted before Clang reached the
      expected `CreateGEP`, `CreateLoad`, static type, and global-variable APIs.
    - Removed the temporary Debug preset build directory after validation.
- 2026-07-22: Initial LLVM context and type migration plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
