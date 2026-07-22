# TODO-08 - Runtime Symbols and Globals

Status: Open
Branch: todo/08-runtime-symbols-and-globals

## Purpose

Replace `addGlobalMapping`, `updateGlobalMapping`, and the lazy external resolver with
explicit ORC symbols and host-address bindings. Success means generated code reliably
resolves the Pure runtime, external functions, and mutable host-backed globals.

## Scope

- Register host addresses as ORC absolute symbols.
- Add current-process dynamic symbol lookup where appropriate.
- Represent mapped globals as external declarations in generated IR.
- Define deterministic behavior and diagnostics for unresolved externals.

## Task List

1. [ ] Inventory runtime functions and globals currently mapped through `ExecutionEngine`.
2. [ ] Add mangled absolute-symbol registration to `PureJit`.
3. [ ] Convert activation stack, shadow stack, function pointer, and Pure globals.
4. [ ] Convert external C wrapper lookup and indirect calls.
5. [ ] Replace `resolve_external` with an ORC-compatible failure strategy.
6. [ ] Test symbol visibility for executable, shared-library, and plugin builds.

## Guardrails

- Do not define an ORC-allocated global and an absolute symbol under the same name.
- Keep host storage alive for at least as long as generated code can access it.
- Missing symbols must produce Pure diagnostics rather than an LLVM process abort.

## Validation Plan

- Run focused tests for globals, externals, wrappers, and unresolved symbols.
- Validate both shared and non-shared runtime build variants if retained.
- Use `llvm-nm-22` or debugger inspection when symbol visibility is ambiguous.

## Open Questions

- Should mutable Pure globals remain absolute symbols or move to a runtime table API?
- Which symbols must be exported from the main executable with linker options?

## Progress Log

- 2026-07-22: Initial runtime symbol and global mapping plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
