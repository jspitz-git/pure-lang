# TODO-07 - Compilation Units and Resources

Status: Completed
Branch: todo/07-compilation-units-and-resources

## Purpose

Replace the single mutable module and per-function machine-code deletion with explicit
ORC compilation units and `ResourceTracker` ownership. Success means temporary code can
be removed safely without mutating modules already owned by ORC.

## Scope

- Define working-module creation and finalization boundaries.
- Group generated IR into logical units for evaluations and definitions.
- Associate each unit with an ORC `ResourceTracker`.
- Replace `freeMachineCodeForFunction` and post-compilation IR erasure.

## Dependencies

TODO-08 registered host-backed `GlobalVar`, `$$sstk$$`, and `$$fptr$$` storage as
ORC absolute symbols. TODO-09 then supplied stable bindings, implementation
generations, and old-closure ownership. Both original blockers are resolved:
definition environments now use ORC trackers, and lifetime stress has passed
under sanitizers. The transitional MCJIT cleanup formerly listed as task 5 has
been transferred to TODO-14, which owns the complete hybrid-runtime migration.

## Task List

1. [x] Define which declarations are recreated in each working module.
2. [x] Finalize, verify, optimize, and submit modules without later mutation.
3. [x] Track resources for anonymous evaluation and definition environments.
4. [x] Remove temporary evaluation resources after execution.
5. [x] Transfer legacy function-code deletion and stale-module operations to TODO-14.
6. [x] Stress repeated evaluation and verify stable memory behavior.

## Working Module Policy

Each entry produces a `CompilationUnitPlan` with separate sets for owned
definitions, function declarations, global declarations, absolute-symbol
requirements, provider dependencies, and omitted values.

- Clone the entry definition and the transitive definitions owned by its
  environment: local fastcc bodies, C-callable stubs, lambdas, `case`/`when`
  helpers, and not-yet-published wrappers reached through calls or function
  pointer constants.
- Clone reachable unit-owned immutable data such as string, numeric, bigint,
  and matrix constant arrays, including initializer dependencies.
- Recreate runtime functions, C externals, and definitions owned by an existing
  ORC provider as declarations with exact function type, varargs, and calling
  convention. Declarations need no provider-local definition.
- Recreate host-backed mutable globals as external declarations without an
  initializer. This includes `$$sstk$$`, `$$fptr$$`, `GlobalVar` slots,
  `$$const.*`, `$$tmpvar*`, and Faust dispatch slots. The plan records an
  absolute-symbol requirement, but TODO-08 owns registration and updates.
- Treat Faust and loaded-bitcode definitions as definitions of their own
  provider units; evaluation and definition units reference them by declaration.
- Omit older `$$init*`, unreachable internal helpers/constants, and previously
  published Pure/type/wrapper definitions. Only the current entry is promoted
  to external linkage for lookup; its owned helpers remain internal.
- Select definitions by ownership plus transitive operand/initializer
  reachability, not linkage alone. Existing `check_used` traversal covers the
  relevant direct-call, function-constant, and global-reference edge classes,
  but a unit has one explicit entry root rather than every `$$init*` root.

### Lifetime Rules

- A plain anonymous evaluation tracker can be removed after invocation only if
  no local closure escaped.
- An evaluation or definition with escaped closures ties its tracker to the
  corresponding `Env` reference lifetime.
- Global provider trackers survive redefinition until the last old closure is
  released; TODO-09 owns generation indirection and redefinition semantics.
- A module is immutable after submission. Provider replacement creates and
  submits a new module instead of mutating an ORC-owned module.

## Retrospective Status

Anonymous evaluations and interactive definitions both register their ORC
tracker by `Env` identity. Non-escaping environments remove resources after
invocation; escaped closures retain the environment and tracker until cleanup.
Global implementation generations remain available while old closures refer to
them, and the prelude-independent lifetime stress exercises this behavior under
Debug, Release, ASan/UBSan, and LeakSanitizer.

The legacy cleanup remains real, but it is not unfinished ORC compilation-unit
ownership. `Env::clear` retains mapping and body-deletion operations because eager
JIT, batch definitions, and batch Faust still consume the transitional
`ExecutionEngine`. TODO-14 now owns those consumers and the complete MCJIT removal.

## Remaining Transitional Runtime Work

TODO-14 explicitly owns completion of the hybrid-runtime migration:

1. Route eager `jit_now`/`pure_interp_compile` materialization through ORC.
2. Route retained batch `dodefn(keep)` initializers and batch Faust dispatch
   materialization through explicit ORC units.
3. Remove synchronized `addGlobalMapping`/`updateGlobalMapping`,
   `getPointerToFunction`/`getPointerToGlobal`, and the legacy external resolver
   after their final consumers migrate.
4. Replace legacy `Env::clear` unmapping and body deletion with tracker/generation
   ownership, then remove `ExecutionEngine`, MCJIT linkage, and obsolete headers.
5. Collapse `LLVM26` through `LLVM35` and `NEW_USER_ITERATOR` gates to their LLVM
   22 behavior, retaining only `LLVM_VERSION` build metadata.
6. Validate eager mode, retained definitions, complete batch executables, batch
   Faust, redefinition lifetime, and clean shutdown in Debug, Release, and
   sanitizer builds.

The LLVM tool subprocess used after batch IR emission is no longer part of this
legacy list: TODO-13 replaced `opt -std-compile-opts` and LLVM 3.x object-output
branches with the LLVM 22 O1-to-`llc -filetype=obj` pipeline and added a focused
no-prelude object test. Full batch execution and Faust batch validation remain in
TODO-14; regression-harness startup performance is tracked by TODO-17.

## Guardrails

- Never modify a `Module` after ownership has moved into `ThreadSafeModule`/ORC.
- Remove resources only when no live code pointer can reference them.
- Keep resource lifetime explicit rather than relying on intentional leaks.

## Validation Plan

- Run repeated anonymous evaluations under ASan and LeakSanitizer.
- Test successful and exceptional evaluation cleanup paths.
- Inspect resource-removal errors and ensure they are reported rather than ignored.

## Decisions

- One implementation generation owns one tracker and one qualified concrete
  symbol. Self-recursion stays generation-local; calls to peer global names use
  their stable dynamic bindings, including mutual recursion across redefinition.
- Entry-reachable owned definitions and immutable data are cloned into a fresh
  context. Runtime/provider functions and host-backed mutable globals are
  recreated as exact declarations; unreachable definitions are omitted.

## Progress Log

- 2026-07-23: Identified the prerequisite boundary for definition resources.
  - `dodefn` writes matched values through host-backed `GlobalVar` storage mapped
    by the transitional `ExecutionEngine`; submitting it to ORC now would fail on
    unresolved globals or create duplicate storage.
  - Remaining `Env::clear` unmapping, body deletion, and deferred IR erasure keep
    old closure pointers valid for local/global definitions. Removing them before
    TODO-09 supplies stable bindings would introduce dangling code pointers.
  - Tasks 3 and 5 therefore remain open. TODO-08 must land host absolute symbols
    first, followed by TODO-09 implementation lifetime and redefinition semantics.
  - Validation:
    - Source-path and ownership review only; no runtime behavior changed.
- 2026-07-23: Completed sanitizer stress validation for anonymous ORC units.
  - Disabled only Clang's UBSan `function` check for `pure-jit-smoke`. That check
    reads compiler-emitted type metadata before an indirect-call target, but ORC
    functions do not carry the marker; ASan and all other UBSan checks remain
    enabled for the target.
  - Validation:
    - The ASan/UBSan `pure-jit-smoke` target built and passed with LeakSanitizer
      enabled and no sanitizer diagnostics.
    - One interpreter process evaluated 1000 expressions with the exact expected
      results and no ASan, LeakSanitizer, UBSan, duplicate-symbol, tracker-removal,
      or shutdown diagnostics.
    - After an intentional syntax error, the same sanitized process evaluated the
      following expression to `42` and shut down cleanly.
  - Task 6 is complete for anonymous evaluation resources. Definition and
    redefinition lifetime stress remains covered by TODO-12 after those paths
    migrate to ORC.
- 2026-07-23: Routed every anonymous evaluation through an independent ORC unit.
  - Removed the one-time ORC evaluation switch. Each `doeval` now snapshots,
    finalizes, submits, looks up, and invokes its own entry with a dedicated
    `ResourceTracker`.
  - Non-escaping evaluation resources are removed immediately, while escaped
    closures retain their tracker through the existing `Env` registry lifetime.
  - Validation:
    - A clean full Debug build and isolated ORC smoke test passed with zero
      warnings and errors.
    - Three sequential expressions and a 100-expression stress run completed in
      one interpreter process with all expected results.
    - No duplicate-symbol, resource-removal, or shutdown diagnostics occurred.
  - Task 3 remains open for definition environments.
- 2026-07-23: Connected escaped evaluation resources to `Env` destruction.
  - `Env::clear` idempotently removes any tracker retained for that environment
    and reports LLVM removal failures, completing the delayed cleanup path for
    escaped evaluation closures.
  - Validation:
    - Full Debug build and isolated ORC smoke test passed with zero warnings and
      errors.
    - Single and repeated scalar evaluations completed without environment or
      shutdown removal diagnostics.
    - A lambda evaluation now stops cleanly at unresolved `$$fptr$$`, confirming
      that escaped-closure execution is blocked by TODO-08 host bindings rather
      than resource registry lifetime.
- 2026-07-23: Added interpreter-owned compilation-unit resource tracking for
  anonymous ORC evaluation.
  - Trackers are registered by `Env` identity before invocation. A non-escaping
    evaluation removes its tracker before deleting the environment; an escaped
    closure retains both for later lifetime integration.
  - Interpreter shutdown removes all remaining trackers before destroying
    `LLJIT` and reports aggregated LLVM removal errors instead of ignoring them.
  - Validation:
    - A clean Debug build and isolated ORC smoke test passed with zero warnings
      and errors.
    - Single evaluations and a repeated `1; 2;` process returned expected
      results with no resource-removal or shutdown diagnostics.
  - Task 4 is complete for temporary evaluations. Task 3 remains open until
    definition environments and escaped closure cleanup use the same registry.
- 2026-07-23: Completed the immutable ORC module finalization pipeline.
  - Each reduced snapshot is verified, optimized with a fresh standard module
    O1 pipeline and local analysis managers, verified again, then moved into a
    `ThreadSafeModule` and submitted without further mutation.
  - The long-lived interpreter module remains const throughout snapshot creation.
  - Validation:
    - A clean full Debug build completed with zero warnings and errors.
    - The ORC smoke test preserved its typed entry ABI, returned `42`, and
      removed its tracker after O1 optimization.
    - Isolated ORC evaluations still returned `1` and `2` for `1;` and `1+1;`.
- 2026-07-23: Implemented entry-reachable reduced ORC snapshots.
  - After the fresh-context bitcode roundtrip, `PureJit` traverses instruction
    operands, constant initializers, aliases, and ifunc resolvers from one entry.
  - Unreachable function bodies become declarations; only reachable immutable
    constant globals retain definitions. Mutable globals become external
    declarations, and unreachable aliases/ifuncs are omitted.
  - The reduced module is verified before submission, and only its entry is
    promoted for lookup. The source module remains unchanged.
  - Validation:
    - A clean full Debug build completed with zero warnings and errors.
    - The isolated smoke test passed reduced-module verification, lookup,
      execution, result `42`, and tracker removal.
    - `test007.pure` no longer reports duplicate definitions. It now fails with
      unresolved `$pointer`/`$pointer_tag` host-backed globals, the expected
      TODO-08 absolute-symbol boundary.
- 2026-07-23: Defined the working-module declaration and ownership policy.
  - Inventoried host-backed `$$sstk$$`, `$$fptr$$`, `GlobalVar`, cached constant,
    temporary expression, and Faust dispatch slots. They must become external
    declarations plus TODO-08 absolute-binding requirements, never cloned
    storage.
  - Classified runtime/C declarations, provider-owned Pure/Faust/bitcode
    definitions, entry-owned helpers/closures, and immutable constant data.
  - Defined transitive reachability roots and tracker lifetime rules for plain
    evaluations, escaped closures, definitions, and superseded providers.
  - Validation:
    - Documentation-only architecture milestone; no build behavior changed.
- 2026-07-22: Initial compilation-unit and resource plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
- 2026-07-24: Revisited the TODO after TODO-08, TODO-09, and TODO-12 removed its
  blockers. Marked definition-environment tracking complete and reopened only
  the legacy operation cleanup.
  - Validation:
    - Cross-checked evaluation and definition tracker ownership against current
      `doeval`, `dodefn`, and `Env::clear` behavior.
    - Reused the recorded Debug, Release, ASan/UBSan, and LSan lifetime-stress
      results from TODO-12.
    - Confirmed that remaining mapping/body deletion is still consumed by live
      MCJIT paths and therefore cannot be removed independently.
