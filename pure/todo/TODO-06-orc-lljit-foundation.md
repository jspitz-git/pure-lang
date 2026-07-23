# TODO-06 - ORC LLJIT Foundation

Status: Open
Branch: todo/06-orc-lljit-foundation

## Purpose

Introduce a small `PureJit` abstraction backed by LLVM 22 ORC `LLJIT`. Success means a
minimal generated module can be added, looked up by name, executed, and diagnosed
without exposing ORC details throughout the interpreter.

## Scope

- Add dedicated JIT source and header files.
- Initialize the native target and create `LLJIT` with the required data layout.
- Add module submission, symbol lookup, and LLVM `Error` handling.
- Implement eager compilation first; lazy compilation is out of scope.

## Task List

1. [x] Define the narrow `PureJit` API and ownership model.
2. [ ] Create `LLJIT`, its main `JITDylib`, and process symbol generator.
3. [ ] Add `ThreadSafeModule` submission and typed address lookup helpers.
4. [ ] Convert LLVM `Error` and `Expected` failures to actionable Pure messages.
5. [ ] Compile and invoke a minimal constant-returning function.
6. [ ] Route initial interpreter evaluation through `PureJit`.

## Guardrails

- Keep ORC classes out of unrelated runtime and parser interfaces.
- Do not emulate removed `ExecutionEngine` methods one for one when semantics differ.
- Do not add `LLLazyJIT` until eager execution is stable and measured.

## Validation Plan

- Add and run a focused `PureJit` smoke test through CTest.
- Run the simplest constant and arithmetic interpreter tests.
- Confirm missing-symbol and malformed-module errors do not abort the process.

## Open Questions

- Should the initial ORC object layer use RuntimeDyld or JITLink on Linux?
- What typed entry-point signature should replace untyped `void*` lookups?

## Progress Log

- 2026-07-23: Added the initial `PureJit` ownership and error-preserving API.
  - `PureJit` exclusively owns `LLJIT` through `unique_ptr`; the incomplete ORC
    type remains hidden from callers and is destroyed out of line.
  - `ThreadSafeModule` is accepted by value and moved into ORC. Optional
    `ResourceTrackerSP` ownership is explicit, and lookup returns
    `Expected<ExecutorAddr>`.
  - Creation, module submission, lookup, and resource operations preserve LLVM
    `Error`/`Expected` values for conversion at the Pure diagnostic boundary.
  - `pure_jit.cc` is part of `pure-runtime`; the interpreter does not use the
    wrapper yet.
  - Validation:
    - `cmake --preset llvm22-debug` configured successfully.
    - Ninja compiled `CMakeFiles/pure-runtime.dir/pure_jit.cc.o` separately with
      zero warnings and errors.
    - The full build retains only the nine known legacy JIT errors in
      `interpreter.cc`; no `PureJit` diagnostics were added.
- 2026-07-22: Initial ORC foundation plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
