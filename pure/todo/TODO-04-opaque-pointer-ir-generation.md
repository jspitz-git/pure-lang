# TODO-04 - Opaque-Pointer IR Generation

Status: Open
Branch: todo/04-opaque-pointer-ir-generation

## Purpose

Port instruction generation to LLVM 22's mandatory opaque-pointer model. Success means
that generated functions pass LLVM verification and no code relies on pointer element
types that LLVM no longer stores.

## Scope

- Update `IRBuilder` calls such as loads, GEPs, calls, and pointer casts.
- Make pointee and function types explicit where modern APIs require them.
- Replace pointer-type inspection used to infer ABI details.
- Cover all IR generation paths, but not JIT ownership or symbol resolution.

## Task List

1. [ ] Inventory obsolete `IRBuilder` signatures and typed-pointer assumptions.
2. [ ] Port loads, stores, GEPs, calls, and indirect calls with explicit types.
3. [ ] Replace pointer nesting comparisons in external and Faust ABI detection.
4. [ ] Modernize function, basic block, attribute, and calling-convention APIs.
5. [ ] Run `verifyFunction` and `verifyModule` over representative generated IR.
6. [ ] Compile all IR generation code without deprecated compatibility wrappers.

## Guardrails

- Never guess a pointee type solely to silence a compiler error.
- Preserve runtime calling conventions and integer widths exactly.
- Keep tail-call semantics unchanged until they can be tested explicitly.

## Validation Plan

- `cmake --build --preset llvm22-debug`
- Emit representative `.ll` files and run `opt-22 -passes=verify -disable-output`.
- Run focused tests for arithmetic, calls, aggregates, matching, and recursion once runnable.

## Open Questions

- Should Faust precision be detected from function metadata or from non-pointer parameters?
- Which indirect call sites need explicit stored `FunctionType` metadata?

## Progress Log

- 2026-07-22: Initial opaque-pointer migration plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
