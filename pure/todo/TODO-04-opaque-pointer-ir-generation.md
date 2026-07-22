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

1. [x] Inventory obsolete `IRBuilder` signatures and typed-pointer assumptions.
2. [ ] Port loads, stores, GEPs, calls, and indirect calls with explicit types.
3. [ ] Replace pointer nesting comparisons in external and Faust ABI detection.
4. [ ] Modernize function, basic block, attribute, and calling-convention APIs.
5. [ ] Run `verifyFunction` and `verifyModule` over representative generated IR.
6. [ ] Compile all IR generation code without deprecated compatibility wrappers.

## Inventory Findings

- The main IR generator contains 63 `CreateGEP` call-site lines: 60 in
  `interpreter.cc` and three shared `Env` wrappers in `interpreter.hh`.
- It contains 46 `CreateLoad` call-site lines: 43 in `interpreter.cc` and three
  `Env::CreateLoadGEP` wrappers. The six inline wrapper calls are the first LLVM
  22 compile blockers because both GEP and load now require explicit source types.
- There are 137 ordinary `CreateCall` call-site lines and five removed numbered
  helpers (`CreateCall3`). Calls receiving an `llvm::Function*` retain function
  type information; indirect or generic-value callees must carry an explicit
  `FunctionType` during the port.
- There are three stores, 53 bitcasts, and three constant pointer casts. No
  `getElementType`, `getPointerElementType`, or `CreateStructGEP` use was found,
  so pointee recovery is implicit in helper arguments and pointer comparisons
  rather than concentrated in deprecated element-type queries.
- `interpreter.cc` has 70 `PointerType::get` call-site lines. Under opaque
  pointers, aliases such as `VoidPtrTy`, `CharPtrTy`, `ExprPtrTy`, and nested
  pointer variants compare as the same address-space pointer type. Existing
  equality tests therefore cannot distinguish external ABI types or Faust
  precision.
- Explicit GEP source types can be taken from existing semantic owners:
  expression layout helpers use `ExprTy` and its variant structs, global arrays
  expose their `GlobalVariable::getValueType()`, and compiler table globals retain
  their declared array types. No pointee type needs to be guessed.
- The highest-risk typed-pointer hotspots are `named_type`, `type_name`,
  `dsptype_name`, `declare_extern`, and Faust sample-type detection. These need
  separate semantic ABI metadata rather than reconstructed pointer nesting.

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

- 2026-07-23: Inventoried obsolete builder signatures and typed-pointer
  assumptions on `todo/04-opaque-pointer-ir-generation`.
  - Validation:
    - Focused source counts found 63 GEP, 46 load, 137 ordinary call, five
      numbered-call, three store, 53 bitcast, three constant-pointer-cast, and
      70 pointer-construction call-site lines.
    - No pointer element-type query was found.
    - The latest `cmake --build --preset llvm22-debug -- -j1` baseline stops at
      the three `Env::CreateGEP` and three `Env::CreateLoadGEP` wrappers, matching
      the first planned implementation slice.
- 2026-07-22: Initial opaque-pointer migration plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
