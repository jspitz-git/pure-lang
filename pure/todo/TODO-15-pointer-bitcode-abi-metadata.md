# TODO-15 - Pointer Bitcode ABI Metadata

Status: Open
Branch: todo/15-pointer-bitcode-abi-metadata

## Purpose

Define explicit Pure ABI metadata for pointer-bearing external bitcode functions.
Success means LLVM 22 opaque pointers can be mapped to Pure's semantic C ABI without
guessing pointee types, while malformed or incomplete metadata is rejected safely.

## Scope

- Specify a versioned metadata representation for exported function ABI names.
- Preserve pointer depth, constness where relevant, and named/custom pointer roles.
- Validate metadata against LLVM function arity, scalar types, and calling convention.
- Integrate metadata with bitcode symbol inspection, caching, diagnostics, and batch
  extern serialization.
- Add positive and negative source-generated LLVM 22 fixtures.

## Task List

1. [x] Specify and document the metadata schema and versioning policy.
2. [ ] Parse metadata without relying on removed typed-pointer information.
3. [ ] Validate semantic ABI entries against each exported LLVM function.
4. [ ] Publish pointer-bearing exports only after complete validation.
5. [ ] Preserve metadata across cached imports and batch output.
6. [ ] Test valid pointers, missing metadata, malformed metadata, signature mismatch,
   duplicate exports, unload, and rollback.

## Metadata Schema and Versioning

Generic bitcode modules describe semantic Pure C ABI types in the `pure.abi` named
metadata node. The first and only version record is followed by zero or more function
records:

```llvm
!pure.abi = !{!0, !1}
!0 = !{!"version", i32 1}
!1 = !{!"function", !"lookup", !"char*", !"const char*"}
```

A version-1 function record contains the pre-linkage LLVM function name, its result type,
and one type for each fixed LLVM parameter. LLVM itself remains authoritative for arity,
varargs, calling convention, and scalar widths; metadata supplies semantic ABI roles which
opaque pointers cannot represent. Records use source names because the loader validates
metadata before assigning private linked names.

Version-1 type strings have this canonical grammar:

```text
type         := ["const "] base ("*" [" const"])*
base         := builtin | role
builtin      := "void" | "bool" | "char" | "short" | "int" | "int64" |
                "long" | "size_t" | "float" | "double"
role         := "expr" | "matrix" | "dmatrix" | "cmatrix" | "imatrix" |
                identifier
identifier   := [A-Za-z_][A-Za-z0-9_:.]*
```

Pointer stars encode exact depth. `const` before the base qualifies the base object reached
through the pointer chain; `const` after a star qualifies the pointer produced by that
star. The loader preserves qualifiers in cached and emitted metadata even where the current
wrapper needs only the unqualified role. Custom roles require at least one pointer level. Scalar `void`
is permitted only as a result, and all other scalar entries must use a builtin.

A module may omit `pure.abi`; scalar-only exports then retain the existing inferred ABI,
while pointer-bearing definitions without a valid record remain unpublished with the
existing unsupported-prototype warning. If `pure.abi` is present, an unknown version,
missing or duplicate version record, malformed record/type, duplicate function record, or
record naming no external definition rejects the entire load before linking, ORC
submission, declaration, or cache publication. Every recorded function must use the C
calling convention and its result/parameter descriptors must match LLVM scalar kinds,
pointer positions, fixed arity, and varargs shape. Scalar functions may also be recorded,
but metadata cannot override an incompatible LLVM scalar signature.

Version 1 is immutable once released. Backward-compatible spelling additions require a
new version because canonical strings are persisted in `bcdata_t` and batch bitcode.
Readers reject unsupported versions rather than guessing; future versions may use a new
record shape under the same `pure.abi` node.

## Guardrails

- Never infer pointer semantics from LLVM opaque `ptr` types.
- Keep scalar-only external bitcode compatible.
- Keep Faust's separately defined operation/sample ABI policy unchanged.
- Reject unsupported metadata with an actionable diagnostic before publication.

## Validation Plan

- Generate fixtures from C or LLVM IR source with Clang/LLVM 22.
- Verify every fixture with LLVM's verifier.
- Run loader success, rejection, rollback, and lifetime tests in Debug and sanitizer builds.

## Origin

Created from TODO-04's explicit opaque-pointer deferral and TODO-13 retrospective gate 5.

## Progress Log

- 2026-07-25: Specified version 1 of the generic bitcode Pure ABI metadata.
  - Chose a `pure.abi` named metadata node with one module version record and source-named
    function records containing the result followed by fixed argument type descriptors.
  - Defined canonical semantic type strings for scalar types, exact pointer depth,
    per-level constness, and named/custom pointer roles without consulting LLVM pointees.
  - Kept missing metadata compatible for scalar-only exports while requiring transactional
    rejection of malformed, unknown, duplicate, mismatched, or dangling metadata before
    any link, ORC, declaration, or cache publication boundary.
  - Confirmed the existing `bc_export_t` cache already owns result/argument ABI strings and
    the batch linker can preserve module named metadata; implementation and executable
    validation begin with task 2.
  - Validation:
    - Read-only audit of `LoadBitcode`, `bc_export_t`, `CAbiType`, `bctype_name`, and
      `declare_extern`; no source build or runtime test was required for this design step.
