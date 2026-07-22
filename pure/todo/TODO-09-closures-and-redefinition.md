# TODO-09 - Closures and Redefinition

Status: Open
Branch: todo/09-closures-and-redefinition

## Purpose

Preserve Pure's function redefinition and closure semantics using stable entry points
and explicit ownership of old implementations. Success means redefining a function
updates new calls without invalidating closures that still reference earlier code.

## Scope

- Model compiled implementation lifetime independently from public function bindings.
- Add stable stubs or equivalent indirection for redefinable names.
- Tie implementation resources to closure/environment reference lifetime.
- Remove historical unmapping workarounds and intentional code leaks.

## Task List

1. [ ] Document exact current semantics for global, local, and anonymous functions.
2. [ ] Design stable binding and concrete implementation data structures.
3. [ ] Redirect public bindings atomically when a definition changes.
4. [ ] Keep old `ResourceTracker`s alive while referenced by closures.
5. [ ] Release obsolete implementations after the last reference disappears.
6. [ ] Cover nested, recursive, and mutually recursive redefinition cases.

## Guardrails

- Never leave a closure with a pointer to removed ORC resources.
- Preserve old-closure behavior unless tests and language documentation say otherwise.
- Avoid process-lifetime leaks as a substitute for correct ownership.

## Validation Plan

- Run dedicated closure/redefinition regression tests repeatedly under ASan.
- Test closures created before and after several redefinitions.
- Exercise local functions, global functions, recursion, and exception paths.

## Open Questions

- Which LLVM 22 indirection-stub API offers the best long-term compatibility?
- Must public symbol addresses remain stable for native extension clients as well?

## Progress Log

- 2026-07-22: Initial closure and redefinition plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
