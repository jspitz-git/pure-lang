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

1. [ ] Specify and document the metadata schema and versioning policy.
2. [ ] Parse metadata without relying on removed typed-pointer information.
3. [ ] Validate semantic ABI entries against each exported LLVM function.
4. [ ] Publish pointer-bearing exports only after complete validation.
5. [ ] Preserve metadata across cached imports and batch output.
6. [ ] Test valid pointers, missing metadata, malformed metadata, signature mismatch,
   duplicate exports, unload, and rollback.

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
