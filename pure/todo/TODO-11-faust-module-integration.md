# TODO-11 - Faust Module Integration

Status: Open
Branch: todo/11-faust-module-integration

## Purpose

Port Faust DSP module loading and hot reload to LLVM 22 and the new ORC resource model.
Success means compatible Faust bitcode can be loaded, wrapped, called, reloaded, and
released without stale function or global pointers.

## Scope

- Port Faust module inspection and generated convenience wrappers.
- Replace typed-pointer precision detection with an opaque-pointer-safe ABI check.
- Compile each Faust generation under explicit ORC resources.
- Redirect stable bindings during hot reload while preserving live users.

## Task List

1. [ ] Document the expected Faust-generated symbols and supported ABI variants.
2. [ ] Port module validation, name mangling, and wrapper IR generation.
3. [ ] Implement reliable single/double precision detection.
4. [ ] Add Faust module resources and stable reload bindings.
5. [ ] Retire old generations only after live wrappers no longer reference them.
6. [ ] Test initial load, unchanged reload, changed reload, and rejected ABI changes.

## Guardrails

- Do not assume bitcode from an arbitrary Faust/LLVM version is compatible.
- Do not replace live code before the new module has fully compiled successfully.
- Preserve the old module if reload validation or materialization fails.

## Validation Plan

- Generate test DSP bitcode with the documented compatible Faust toolchain.
- Run load and reload tests under ASan and LLDB when failures involve code lifetime.
- Verify wrapper modules with LLVM's verifier before ORC submission.

## Open Questions

- Which Faust release will be the supported reference for LLVM 22 output?
- Should Faust support be optional when the compiler is unavailable at configure time?

## Progress Log

- 2026-07-22: Initial Faust integration plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
