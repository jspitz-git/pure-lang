# TODO-15 - Pointer Bitcode ABI Metadata

Status: Completed
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
2. [x] Parse metadata without relying on removed typed-pointer information.
3. [x] Validate semantic ABI entries against each exported LLVM function.
4. [x] Publish pointer-bearing exports only after complete validation.
5. [x] Preserve metadata across cached imports and batch output.
6. [x] Test valid pointers, missing metadata, malformed metadata, signature mismatch,
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
- 2026-07-25: Implemented transactional parsing of version-1 `pure.abi` metadata.
  - Added internal records for semantic result/argument descriptors, exact pointer depth,
    base constness, and constness on every pointer level.
  - Parsed the named metadata immediately after bitcode decoding and before target metadata
    canonicalization, symbol renaming, linking, ORC submission, or declaration publication.
  - Rejects empty/malformed version records, unsupported versions, malformed function
    records, non-string operands, duplicate function records, and non-canonical type strings
    with actionable `pure.abi` diagnostics.
  - Kept metadata absence behavior unchanged; semantic-to-LLVM signature validation and
    pointer export publication remain tasks 3 and 4.
  - Validation:
    - LLVM 22 Release serial build passed.
    - All five existing `pure-bitcode-*` integration tests passed in Release.
    - A verifier-accepted temporary bitcode module with version 2 was rejected before load
      while the interpreter continued safely with the following expression.
- 2026-07-25: Validated semantic ABI records against their LLVM definitions.
  - Required every record to name an external definition with the C calling convention and
    exactly one descriptor per fixed LLVM parameter.
  - Matched builtin scalar descriptors by concrete LLVM kind and host ABI width, rejected
    scalar `void` arguments and non-pointer semantic roles, and required every pointer role
    to correspond to an address-space-zero opaque LLVM pointer.
  - Kept pointer depth, pointee role, and const qualifiers metadata-authoritative while
    validating every distinction which remains observable in LLVM 22.
  - Performed validation after target triple/layout compatibility checks but before target
    canonicalization, symbol renaming, linking, ORC submission, or declaration publication.
  - Validation:
    - LLVM 22 Release serial build passed.
    - A temporary valid scalar metadata export executed and returned `42`.
    - A temporary `char*` result record over an LLVM `i32` definition was rejected with the
      function name, semantic type, and concrete LLVM type; execution then continued safely.
    - All five existing `pure-bitcode-*` integration tests passed in Release.
- 2026-07-25: Published pointer-bearing exports from fully validated metadata.
  - Selected validated semantic result and argument names before source symbols are renamed,
    replacing opaque-pointer rejection only for functions with a matching `pure.abi` record.
  - Extended `CAbiType` to recover the unqualified base role and exact pointer depth from
    canonical metadata while retaining the complete const-qualified name in `ExternInfo`.
  - Preserved legacy permissive external declaration parsing outside `pure.abi` and kept
    pointer definitions without metadata unpublished with their existing warning.
  - Validation:
    - LLVM 22 Release serial build passed.
    - A metadata-backed `const char* -> const char*` identity export accepted a Pure string
      and returned `"pointer metadata"`.
    - The equivalent opaque pointer definition without metadata remained unpublished and
      emitted the unsupported-prototype warning.
    - All five existing `pure-bitcode-*` integration tests passed in Release.
- 2026-07-25: Preserved qualified ABI types across cached imports and batch output.
  - Confirmed `bc_export_t` owns the canonical ABI strings used to recreate declarations in
    later namespaces without reparsing the immutable provider module.
  - Added reversible percent encoding for whitespace-bearing batch extern type tokens while
    leaving legacy single-token scalar and pointer names byte-for-byte unchanged.
  - Decoded qualified names before reconstructing `CAbiType` and LLVM types in the batch
    runtime, with malformed encoded tokens terminating extern table restoration safely.
  - Removed source-name `pure.abi` from a batch provider after transferring its validated
    semantics into `ExternInfo`; otherwise private symbol renaming would leave dangling
    metadata records in emitted `.ll`/`.bc` modules.
  - Validation:
    - LLVM 22 Release serial build passed.
    - Two namespace imports of one cached metadata provider both returned their input strings.
    - Batch `.bc` contained `%const%20char*` result/argument tokens and no stale `pure.abi`
      named metadata.
    - A complete metadata-backed batch object linked and executed with clean shutdown.
    - All five `pure-bitcode-*` tests and `pure-batch-executable` passed in Release.
- 2026-07-25: Completed permanent pointer ABI metadata regression coverage.
  - Added LLVM IR source fixtures for a valid const-qualified pointer export, a pointer
    export without metadata, unsupported metadata version, pointer/scalar mismatch,
    duplicate function records, and two independent pointer-bearing providers exporting the
    same source name.
  - Added `llvm-as` fixture generation beside disassembly and verifier steps, so every
    metadata test input is reproducible and verifier-accepted LLVM 22 bitcode.
  - Covered cached declarations in two namespaces, successful pointer calls, missing
    metadata compatibility, malformed and mismatched transactional rejection, duplicate
    metadata rejection, duplicate namespaced exports, provider unload, and clean shutdown.
  - Every negative metadata test loads and executes the known scalar provider afterward,
    proving that rejection occurs before link, ORC, declaration, or cache publication.
  - Applied sanitizer failure expressions to the complete bitcode test family.
  - Validation:
    - Release passed all 11 `pure-bitcode-*` tests in 70.93 seconds.
    - Debug passed all 11 tests in 113.29 seconds.
    - ASan/UBSan passed all 11 tests in 270.99 seconds without sanitizer findings.
    - Serial builds generated, disassembled, and verified every new fixture in all three
      presets.
