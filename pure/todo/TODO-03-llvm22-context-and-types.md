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

1. [ ] Add explicit context ownership to the interpreter-facing LLVM state.
2. [ ] Replace `getGlobalContext()` and context-free builders and modules.
3. [ ] Modernize primitive, structure, function, and constant type helpers.
4. [ ] Replace obsolete includes and remove corresponding configure feature macros.
5. [ ] Compile the affected translation units and categorize remaining API failures.

## Guardrails

- Maintain one LLVM context per set of modules that may be linked together.
- Do not preserve LLVM 3.5 compatibility in the new implementation.
- Keep host ABI structure definitions consistent with `runtime.h` and GSL layouts.

## Validation Plan

- `cmake --build --preset llvm22-debug`
- Compile focused translation units with verbose Ninja output when diagnostics are unclear.
- Verify representative structure layouts with assertions or targeted tests.

## Open Questions

- Should `ThreadSafeContext` be introduced now or only with the ORC layer?
- Which generated headers expose LLVM types and need migration at the same time?

## Progress Log

- 2026-07-22: Initial LLVM context and type migration plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
