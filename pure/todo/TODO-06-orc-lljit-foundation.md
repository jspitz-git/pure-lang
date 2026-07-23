# TODO-06 - ORC LLJIT Foundation

Status: Complete
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
2. [x] Create `LLJIT`, its main `JITDylib`, and process symbol generator.
3. [x] Add `ThreadSafeModule` submission and typed address lookup helpers.
4. [x] Convert LLVM `Error` and `Expected` failures to actionable Pure messages.
5. [x] Compile and invoke a minimal constant-returning function.
6. [x] Route initial interpreter evaluation through `PureJit`.

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

- 2026-07-23: Routed the first anonymous interpreter evaluation through ORC.
  - `doeval` verifies and snapshots the mutable module, promotes only the copied
    internal entry function for lookup, resolves it with a typed
    `pure_expr* ()` signature, invokes it, and removes its resource tracker.
  - Submission and lookup failures roll back the tracker before producing a
    contextual Pure error, preventing duplicate symbols on retry.
  - The smoke test now verifies promotion and lookup of an internal entry symbol
    without modifying the source module.
  - Validation:
    - The complete Debug build and isolated ORC CTest pass with zero warnings
      and errors.
    - First-process evaluations return `1` for `1;` and `2` for `1+1;` through
      the ORC path.
    - `test007.pure` no longer reports missing or duplicate ORC symbols. It now
      reaches `pure_call(nullptr)`, exposing unmigrated runtime/global mappings
      owned by TODO-08.
  - This completes the narrow eager `LLJIT` foundation. Compilation-unit
    lifetime, global symbols, and closure redefinition remain in TODO-07–09.
- 2026-07-23: Added an ORC-safe snapshot path for the mutable interpreter module.
  - `PureJit::add_module_copy` serializes a module to bitcode, reparses it in a
    fresh owned `LLVMContext`, and submits the resulting `ThreadSafeModule`
    under an explicit resource tracker.
  - The original module and interpreter context remain untouched, avoiding
    ownership conflicts while the interpreter still mutates its legacy module.
  - Validation:
    - The smoke test now uses the snapshot path and still resolves/invokes the
      constant function and removes its tracker successfully.
    - The isolated CTest and complete Debug build both pass with zero warnings
      and errors.
- 2026-07-23: Corrected the type-function compilation boundary for whole-module
  MCJIT behavior.
  - All dirty type function bodies are now completed before any
    `getPointerToFunction` call, and the module is verified once at that boundary.
  - This eliminated the former LLVM stack corruption in branch-probability
    analysis, which was caused by MCJIT seeing later type prologs with
    unterminated entry blocks.
  - Validation:
    - The complete Debug build succeeds with zero warnings and errors.
    - The module verifier now passes before type compilation.
    - `test007.pure` advances to anonymous `$$init` evaluation, where MCJIT
      returns null because its already-finalized module cannot accept the newly
      added function. This identifies the first concrete function that must move
      to a separate ORC compilation unit.
- 2026-07-23: Restored a runnable transitional MCJIT baseline alongside ORC.
  - CMake links the `MCJIT` component, and `interpreter.cc` includes the official
    `MCJIT.h` force-link hook so static archive registration is retained.
  - `EngineBuilder` failures use `setErrorStr`; a function-level `main` catch
    now reports constructor-time Pure errors instead of aborting on an uncaught
    `err`.
  - Validation:
    - The complete Debug build succeeds with zero warnings and errors.
    - The linked runtime contains `LLVMLinkInMCJIT`, the MCJIT static initializer,
      and `ExecutionEngine::MCJITCtor`.
    - Minimal evaluations produced `1` for `1;` and `2` for `1+1;`, both with
      exit code zero.
    - `test007.pure` still segfaults while defining/applying a lambda; this is
      the next execution-path issue and confirms task 6 is not yet complete.
- 2026-07-23: Fixed CMake detection of the system `strptime` implementation.
  - The symbol check now uses `_XOPEN_SOURCE=700`, matching glibc's declaration
    requirements, and maps the result to the existing `HAVE_STRPTIME` feature.
  - The obsolete bundled K&R fallback is no longer compiled on Ubuntu.
  - Validation:
    - CMake found `HAVE_XOPEN_STRPTIME=1`, generated
      `#define HAVE_STRPTIME 1`, and removed `strptime.c` from Ninja's graph.
    - The complete LLVM 22 Debug build succeeded with zero warnings and errors
      for the first time.
    - The isolated `pure-jit-smoke` CTest still passed.
- 2026-07-23: Modernized generated lexer source for C++17 and LLVM 22 streams.
  - Removed the two obsolete `register` storage specifiers from `lexer.ll`.
  - LLVM function dumps now unconditionally adapt `std::ostream` through
    `llvm::raw_os_ostream`; removed feature branches selected by unset legacy
    header macros.
  - Validation:
    - Flex regenerated `lexer.cc`, and `lexer.cc.o` compiled with zero warnings
      and errors.
    - The full build advanced to legacy C compatibility errors in `strptime.c`.
- 2026-07-23: Fixed encoding portability exposed by the full C++17 build.
  - Encoding-name helpers and parameters now use `const char*`, eliminating 31
    writable-string warnings without casts.
  - The local `nl_langinfo` fallback uses its own `MYCODESET` token, and
    `ICONV_CONST` defaults to the POSIX/glibc signature when configure does not
    provide an override.
  - Validation:
    - `util.cc` compiled with zero warnings and errors.
    - The full build advanced to six independent C++17/LLVM stream errors in
      generated lexer code mapped to `lexer.ll`.
- 2026-07-23: Fixed platform declarations exposed after `interpreter.cc` began
  compiling completely.
  - `runtime.cc` now includes `<dirent.h>` under the generated `HAVE_READDIR`
    feature used by `pure_readdir`, rather than an unset `HAVE_DIRENT_H` macro.
  - Nanosleep fallback limits use the largest safely representable `double` not
    exceeding `LONG_MAX`, avoiding a 64-bit rounding overflow warning.
  - Validation:
    - The full build compiled `runtime.cc` with zero warnings and errors and
      advanced to pre-existing `util.cc` portability diagnostics (`CODESET`,
      `ICONV_CONST`, and writable string literals).
- 2026-07-23: Removed all seven calls to the deleted
  `ExecutionEngine::freeMachineCodeForFunction` API.
  - No one-for-one compatibility shim was added. The transitional engine keeps
    generated code until shutdown while IR cleanup remains unchanged.
  - Comments identify the future ORC `ResourceTracker` boundaries for Faust
    reloads, local/global definitions, and anonymous evaluation units; actual
    fine-grained reclamation belongs to TODO-07 and TODO-09.
  - Validation:
    - `interpreter.cc` now compiles with zero warnings and errors.
    - The full build advanced for the first time to `runtime.cc`, where it found
      three unrelated missing directory-API declarations and one numeric
      conversion warning.
    - No `freeMachineCodeForFunction` call remains in the source tree.
- 2026-07-23: Added the interpreter-side ORC creation and diagnostic boundary.
  - Each interpreter now owns a `PureJit`; creation failures are converted from
    LLVM `Expected` into a contextual Pure `err` only at this higher layer.
  - The interpreter module takes its data layout from ORC.
  - The temporary legacy `EngineBuilder` now receives explicit
    `unique_ptr<Module>` ownership and no longer uses the removed
    `setAllocateGVsWithCode` option. It remains only for operations not yet
    routed through ORC.
  - Validation:
    - The isolated `pure-jit-smoke` CTest still passes.
    - The full Debug build has zero warnings and dropped from nine to seven
      errors, all of which are removed `freeMachineCodeForFunction` calls.
- 2026-07-23: Added and executed an independent ORC module lifecycle smoke test.
  - `lookup_function<FunctionType>` converts `Expected<ExecutorAddr>` to a
    compile-time checked function pointer while preserving lookup errors.
  - The test builds a `ThreadSafeModule` containing an `i32 ()` function,
    submits it under a dedicated `ResourceTracker`, resolves and invokes it,
    checks the result `42`, and removes all tracked resources.
  - The CTest target links `pure_jit.cc` directly and is independent of the
    still-blocked legacy interpreter runtime.
  - Validation:
    - `cmake --build --preset llvm22-debug --target pure-jit-smoke -- -j1`
      completed with zero warnings and errors.
    - `ctest --preset llvm22-debug -R '^pure-jit-smoke$' --output-on-failure`
      passed 1/1 tests.
    - The full build retains zero warnings and only the nine known legacy JIT
      errors.
- 2026-07-23: Completed native `LLJIT` and process-symbol initialization.
  - `PureJit::create` initializes the native target, assembly printer, and
    assembly parser before constructing ORC.
  - `LLJITBuilder` explicitly enables LLVM 22's required process-symbol
    `JITDylib`, which is placed in the main dylib's default search order.
  - An attempted post-construction generator installation was rejected by LLVM
    22 because native platforms require the process-symbol dylib during
    `LLJITBuilder::create`; the final implementation follows that constraint and
    avoids duplicate generators.
  - Validation:
    - `pure_jit.cc.o` compiled separately with zero warnings and errors.
    - A temporary C++17 executable created and destroyed `PureJit`, observed a
      nonempty native data layout, and exited successfully.
    - Temporary smoke-test files were removed.
    - The full build retains zero warnings and only the nine known legacy JIT
      errors in `interpreter.cc`.
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
