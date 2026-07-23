# TODO-07 - Compilation Units and Resources

Status: Open
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

## Task List

1. [x] Define which declarations are recreated in each working module.
2. [ ] Finalize, verify, optimize, and submit modules without later mutation.
3. [ ] Track resources for anonymous evaluation and definition environments.
4. [ ] Remove temporary evaluation resources after execution.
5. [ ] Replace legacy function-code deletion and stale-module operations.
6. [ ] Stress repeated evaluation and verify stable memory behavior.

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

## Guardrails

- Never modify a `Module` after ownership has moved into `ThreadSafeModule`/ORC.
- Remove resources only when no live code pointer can reference them.
- Keep resource lifetime explicit rather than relying on intentional leaks.

## Validation Plan

- Run repeated anonymous evaluations under ASan and LeakSanitizer.
- Test successful and exceptional evaluation cleanup paths.
- Inspect resource-removal errors and ensure they are reported rather than ignored.

## Open Questions

- What is the smallest practical compilation unit for mutually recursive definitions?
- Which declarations should be cloned versus recreated from a module template?

## Progress Log

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
