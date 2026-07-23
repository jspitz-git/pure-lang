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
2. [x] Design stable binding and concrete implementation data structures.
3. [x] Redirect public bindings atomically when a definition changes.
4. [x] Keep old `ResourceTracker`s alive while referenced by closures.
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

## Generation and Binding Design

### `FunctionBinding`

One interpreter-owned entry per global Pure symbol tag:

```text
FunctionBinding
  tag                    Pure symbol id
  slot                   existing stable GlobalVar / pure_expr ** address
  next_generation        monotonic generation number
  current                current FunctionGeneration, or none after clear
```

- `slot` is already registered as an ORC absolute data symbol and remains stable.
  First-class symbol lookup and unsaturated/dynamic calls continue loading the
  current closure from this slot.
- Publishing a definition changes the slot contents and `current`, never the slot
  address. The interpreter is single-threaded today, so publication requires an
  ordered retain/swap/release sequence rather than a lock-free stub update.
- Clearing a name publishes its cbox/undefined value and sets `current` to none;
  old generations remain independently owned.

### `FunctionGeneration`

One immutable record for each successfully materialized global implementation:

```text
FunctionGeneration
  tag, generation        logical identity
  key, refp              runtime closure identity and implementation references
  tracker                all ORC code/data owned by this implementation
  fast_symbol/address    internal fastcc entry when distinct
  c_symbol/address       C-callable closure entry
  state                  building, current, superseded, removable
```

- Symbols use generation-qualified names such as `$$orc.fun.<tag>.<generation>`;
  redefining source IR cannot collide with an older live generation.
- A generation is immutable after submission. Its `Env::f`/`h` source IR may be
  cleared or rebuilt only after addresses, symbols, and ownership have been copied
  into the generation record.
- The public cached closure contributes to `refp`. Replacing that cache can make a
  superseded generation removable, but only after closure and dependent-unit
  references also reach zero.

### Ownership registry

Extend the interpreter compilation-resource registry with:

```text
bindings[tag]                 stable FunctionBinding
implementations[key]          FunctionGeneration owning that closure key
```

- `pure_clos` and closure copies already increment `*refp`. When `pure_free_clos`
  decrements it to zero, it must notify the interpreter by `key`; the registry can
  then remove a superseded generation tracker and erase the key mapping.
- Anonymous and local environments keep their existing `Env *` tracker ownership.
  A global generation uses the key callback because global closures currently have
  no `ep` and the mutable `globalfuns[tag]` environment is reused.
- If one ORC unit references a separately owned generation rather than cloning its
  implementation, that dependency must hold an explicit generation reference.
  Initially cloning concrete reachable generation bodies per unit avoids an
  implicit cross-tracker dependency.

### Call and publication policy

- Direct saturated calls emitted while compiling a unit bind to the concrete
  generation selected at that compilation boundary. Old caller units therefore
  keep coherent old dependency code; newly compiled callers select current
  generations.
- First-class/global calls continue through the stable closure slot and observe the
  newly published generation.
- A deferred closure stores tag/key but no address reference. On first invocation it
  resolves `bindings[tag].current`, stores that generation's callable address, and
  acquires its implementation reference. This preserves test 053 semantics.
- Build and verify a new generation completely before publication. On failure,
  remove its tracker and leave both `current` and the host slot unchanged.
- Publish by retaining the new closure, swapping the host slot/current pointer, then
  releasing the old cached closure. Mark the previous generation superseded and
  collect it immediately only if its implementation references are zero.

### Why no ORC indirect stub initially

- The existing stable `GlobalVar` slot already provides language-level indirection
  for first-class values and dynamic calls.
- Concrete generation calls preserve old-closure/caller semantics more naturally
  than retargeting every call through one mutable native stub.
- ORC indirect stubs remain an option only if native extension clients require a
  stable callable address for an interactively redefinable Pure name. Batch-export
  ABI stability is separate from interactive closure semantics.

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

- 2026-07-23: Added ORC ownership for immutable global function generations.
  - Added generation-qualified ORC units indexed by closure key, with independent
    trackers retained after a generation is superseded.
  - Materialized each global definition before publication while preserving deferred
    closure semantics: first invocation resolves the current generation and transfers
    the closure's key/refcounter ownership before storing its callable address.
  - Kept tracker removal out of closure release paths; obsolete generations remain
    registered until safe collection is implemented in item 5.
  - Moved runtime type-function entry points to ORC as well, preventing ORC-generated
    globals from calling stale transitional execution-engine code.
  - Validation:
    - LLVM 22 debug build passed.
    - `pure-jit-smoke` passed.
    - Tests 052, 053, and 068 produce the expected closure/redefinition results; the
      runner still reports failure because of pre-existing malformed pragma warnings
      while loading library scripts.
    - Test 063 no longer crashes, but `__func__` inside `when`/`case` still differs in
      two nested identity cases tracked by item 6; the remaining test behaves as
      expected.
- 2026-07-23: Made global function binding publication ordered and reentrant-safe.
  - Added one publication path which retains the replacement, swaps the stable
    `GlobalVar` host slot, and only then releases or retires the previous value.
  - Used deferred retirement while `compile()` is active so closure sentries cannot
    reenter compilation before the new definition is visible.
  - Routed `clearsym()` through the same publication path, including publication of
    a null binding for `--defined` externals.
  - Validation:
    - LLVM 22 debug configure and build passed.
    - `pure-jit-smoke` passed.
    - Tests 052, 053, 063, and 068 ran but failed because the current ORC deferred
      resolver leaves global calls unreduced; library loading also reports existing
      malformed pragma diagnostics. These failures precede generation ownership and
      collection work in the remaining tasks.
    - The full `pure-regression` CTest exceeded the 180-second validation limit.
- 2026-07-23: Designed stable bindings and immutable implementation generations.
  - Selected the existing ORC-bound `GlobalVar` closure slot as the stable public
    binding instead of adding an LLVM indirect stub to every Pure function.
  - Defined concrete `FunctionBinding` and `FunctionGeneration` fields, registry
    indexes, generation-qualified symbols, two-phase publication, rollback, and
    zero-reference collection through the existing closure key/refp mechanism.
  - Specified concrete-generation direct calls, slot-based first-class calls, and
    latest-generation resolution for deferred closures.
  - Validation:
    - Architecture/source review only; no runtime behavior changed and no build or
      test process was started.
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
