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

1. [x] Document the expected Faust-generated symbols and supported ABI variants.
2. [ ] Port module validation, name mangling, and wrapper IR generation.
3. [ ] Implement reliable single/double precision detection.
4. [ ] Add Faust module resources and stable reload bindings.
5. [ ] Retire old generations only after live wrappers no longer reference them.
6. [ ] Test initial load, unchanged reload, changed reload, and rejected ABI changes.

## Supported Faust Module ABI

### Reference toolchain

- The canonical input is C emitted by Faust 2.70.3 with the bundled `pure.c`
  architecture, compiled to bitcode by the selected Clang 22 toolchain. The reference
  double fixture uses `faust -a pure.c -lang c` followed by
  `clang-22 -emit-llvm -c`.
- The Faust frontend and architecture source define the DSP API, while Clang 22 defines
  the accepted LLVM bitcode, target triple, data layout, and opaque-pointer IR. Bitcode
  from an arbitrary Faust LLVM backend is not a supported compatibility promise.
- In particular, the direct LLVM backend in the available Faust 2.70.3 build uses LLVM
  17 and emits only its internal `allocate`, `compute`, `destroy`, and JSON-oriented API;
  it does not emit `new`, `init`, or `buildUserInterface` and is not a valid Pure DSP
  module.
- A module must pass the same target-triple and exact data-layout checks as generic
  bitcode before any symbols are published. Rewriting incompatible target metadata is
  not part of the supported ABI.

### Class suffix and required symbols

`<class>` is the suffix selected by Faust's `-cn` option (`mydsp` by default). The
loader discovers it from `buildUserInterface<class>`; it must be nonempty and consistent
across the complete interface. The following non-variadic C ABI definitions are required:

| Symbol | C-level signature | Purpose |
| --- | --- | --- |
| `new<class>` | `dsp *()` | Allocate a DSP instance. |
| `delete<class>` | `void (dsp *)` | Destroy an instance and back Pure sentries. |
| `init<class>` | `void (dsp *, int32_t)` | Initialize an instance for a sample rate. |
| `buildUserInterface<class>` | `void (dsp *, UIGlue *)` | Enumerate controls through Pure's UI callbacks. |
| `getNumInputs<class>` | `int32_t (dsp *)` | Report input channel count. |
| `getNumOutputs<class>` | `int32_t (dsp *)` | Report output channel count. |
| `compute<class>` | `void (dsp *, int32_t, sample **, sample **)` | Process one sample block. |

Historical parameterless `getNumInputs<class>` and `getNumOutputs<class>` definitions may
be accepted for old source-compatible modules. All `dsp *`, `UIGlue *`, and buffer
parameters are LLVM opaque pointers, so their meanings must be established from the
validated operation name and precision metadata rather than inferred from pointee types.
Symbol order in the LLVM module is not ABI-significant.

### Optional symbols and Pure additions

- `metadata<class>(MetaGlue *)` enables the generated Pure `meta() -> expr *` wrapper.
- `getSampleRate<class>(dsp *) -> int32_t` is exposed when present. New fixtures require
  it; emulation through a historical sampling-frequency global is legacy-only.
- `classInit`, `instanceInit`, `instanceConstants`, `instanceClear`, and
  `instanceResetUserInterface`, with the class suffix, are valid `pure.c` lifecycle
  operations and may be exposed using their generated scalar signatures.
- Other class-suffixed operations are accepted only when every scalar type is representable
  by Pure's C ABI mapping and every pointer role has an explicit operation mapping. Unknown
  opaque-pointer signatures must be rejected rather than treated as `void *` by default.
- Pure adds `newinit(int32_t) -> dsp *` and `info(dsp *) -> expr *`; these are not expected
  in the input module. Pure adds `meta() -> expr *` only when `metadata<class>` exists.

### Supported precision variants

- Exactly two public sample ABIs are supported: `sample` may be `float` or `double`. The
  choice governs compute buffers, UI control zones and values, and the runtime UI callback
  table as one indivisible ABI property.
- Faust's internal `-single` or `-double` mode does not by itself determine this public ABI.
  The bundled `pure.c` architecture defines `FAUSTFLOAT` as `double`, so both compiler
  modes expose double buffers and controls; it is the canonical double ABI. A single ABI
  requires a compatible architecture which exposes `FAUSTFLOAT` as `float` throughout.
- Public precision must be explicit and unambiguous in loader-readable module metadata.
  LLVM 22 opaque pointer types cannot distinguish `float **` from `double **`; a source
  filename, Faust compilation flag, or guessed pointer type is not an ABI contract.
- `-quad`, fixed-point, mixed control/sample precision, vectorized buffer layouts that
  change the public C signature, and non-C calling conventions are unsupported.
- Reload may replace implementation code only when class suffix, precision, required
  operation signatures, target ABI, and externally visible globals remain compatible.
  An ABI change is rejected while the previous generation remains active.

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

- 2026-07-23: Defined the supported Faust module symbol and ABI contract.
  - Selected Faust 2.70.3 with `pure.c` plus Clang 22 as the canonical fixture pipeline,
    keeping LLVM bitcode production under the project's selected toolchain.
  - Classified required DSP allocation, lifecycle, UI, channel-count, and compute symbols;
    documented optional metadata and lifecycle operations plus Pure-generated wrappers.
  - Limited public sample formats to explicit float and double ABIs, distinguished these
    from Faust's internal precision mode, and recorded the reload compatibility invariants.
  - Declared the current direct Faust LLVM backend unsupported because its reduced API does
    not provide the architecture symbols required by Pure.
  - Validation:
    - Faust 2.70.3 generated `-single` and `-double` `pure.c` sources from
      `examples/bitcode/freeverb.dsp`; Clang 22 compiled both to opaque-pointer bitcode.
    - Source and `llvm-dis-22` inspection confirmed the documented symbol families and that
      bundled `pure.c` keeps the public sample ABI double in both internal precision modes.
    - `opt-22 -passes=verify` accepted both generated modules.
    - Direct `-lang llvm` output was inspected and confirmed to omit `new`, `init`, and
      `buildUserInterface`, so it cannot satisfy the documented contract.
- 2026-07-22: Initial Faust integration plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
