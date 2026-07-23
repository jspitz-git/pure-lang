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

1. [x] Document exact current semantics for global, local, and anonymous functions.
2. [ ] Design stable binding and concrete implementation data structures.
3. [ ] Redirect public bindings atomically when a definition changes.
4. [ ] Keep old `ResourceTracker`s alive while referenced by closures.
5. [ ] Release obsolete implementations after the last reference disappears.
6. [ ] Cover nested, recursive, and mutually recursive redefinition cases.

## Current Closure and Redefinition Semantics

### Runtime closure ownership

- Every runtime closure stores its implementation pointer in `pure_closure::fp`,
  its arity and captured values, an optional owning `Env *ep`, and a shared
  implementation reference counter `refp` selected by the environment key.
- Creating or copying a closure increments `ep->refc`, `*refp`, and references to
  captured `pure_expr` values. Freeing it performs the inverse operations; the last
  `ep` reference deletes the `Env`, which is the existing hook for removing an ORC
  compilation-unit tracker.
- `Env::refc` owns the environment object and its unit resources. Shared `refp`
  counts closures that still carry a function implementation pointer, including
  copies whose captured-value arrays differ.

### Anonymous evaluations and definitions

- Anonymous `doeval` and interactive `dodefn` environments have tag zero, a unique
  ORC entry symbol, and one tracker keyed by their heap `Env` identity.
- A result without an escaped closure removes the tracker immediately. An escaped
  closure retains `ep`, so `Env::clear` removes the tracker only after the last
  closure releases the environment.
- Anonymous units have no public redefinable binding; their implementation address
  is immutable for the closure lifetime.

### Local functions and lambdas

- Local environments set `local=true`, point to their lexical parent, and carry
  captured values in the closure environment array. Nested `with`, `case`, `when`,
  and lambda helpers belong to the compilation unit that materialized them.
- Copies preserve the same implementation key and pointer while independently
  retaining the parent environment and captured values. Identity-sensitive cases
  such as `__func__` rely on this stable key/pointer relationship.
- Clearing a local environment currently drops IR references. Legacy MCJIT unmaps
  function names but intentionally keeps machine code when `*refp != 0`; ORC must
  instead retain the owning implementation tracker until that count reaches zero.

### Global named functions

- `globalfuns[tag]` is the mutable compiler environment for the current definition.
  A `GlobalVar` host slot caches the current global closure and is the public value
  observed by new symbol lookups and indirect calls.
- Adding rules or clearing/redefining a name rebuilds that current environment and
  replaces the cached closure. New closures and calls must observe the new
  implementation without changing the address stored in older closure objects.
- An already materialized old closure keeps its old `fp` callable across clear or
  redefinition. Legacy cleanup therefore deletes function bodies but leaks or
  unmaps old machine code when closures remain; tests 052 and 068 guard against
  stale pointers and changed public bindings.
- A deferred global closure whose `fp` is still null is different: its first call
  resolves through the current `globalfuns` entry. Test 053 specifies that such a
  closure executes the latest definition, not the definition visible when the
  closure value was captured.
- The closure cached in the global host slot normally contributes one reference.
  During clear/redefinition, code is dead only when no external closure remains
  after discounting that cache reference.

### Required ORC behavior

- Separate stable public bindings from immutable implementation generations.
- Redirect only the public binding when publishing a new generation.
- Keep each materialized generation tracker alive while any closure has its `fp`;
  deferred closures may resolve to the current generation on first call.
- Remove a generation only after its closure references, nested environments, and
  dependent compilation units are gone.

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

- 2026-07-23: Documented current closure ownership and redefinition semantics.
  - Traced `Env::refc`, shared implementation `refp`, closure copies, captured
    values, public `GlobalVar` bindings, and the existing `Env::clear` cleanup path.
  - Distinguished anonymous unit lifetime, lexical local closures, materialized
    global generations, and deferred global closures that resolve the latest
    definition on first call.
  - Mapped regression expectations from tests 052, 053, 063, and 068 to the ORC
    requirements for stable bindings and immutable implementation generations.
  - Validation:
    - Source and regression-test review only; no runtime behavior changed and no
      build or test process was started.
- 2026-07-22: Initial closure and redefinition plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
