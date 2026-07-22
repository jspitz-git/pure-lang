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

1. [ ] Define which declarations are recreated in each working module.
2. [ ] Finalize, verify, optimize, and submit modules without later mutation.
3. [ ] Track resources for anonymous evaluation and definition environments.
4. [ ] Remove temporary evaluation resources after execution.
5. [ ] Replace legacy function-code deletion and stale-module operations.
6. [ ] Stress repeated evaluation and verify stable memory behavior.

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

- 2026-07-22: Initial compilation-unit and resource plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
