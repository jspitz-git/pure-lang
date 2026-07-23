# TODO-08 - Runtime Symbols and Globals

Status: Open
Branch: todo/08-runtime-symbols-and-globals

## Purpose

Replace `addGlobalMapping`, `updateGlobalMapping`, and the lazy external resolver with
explicit ORC symbols and host-address bindings. Success means generated code reliably
resolves the Pure runtime, external functions, and mutable host-backed globals.

## Scope

- Register host addresses as ORC absolute symbols.
- Add current-process dynamic symbol lookup where appropriate.
- Represent mapped globals as external declarations in generated IR.
- Define deterministic behavior and diagnostics for unresolved externals.

## Task List

1. [x] Inventory runtime functions and globals currently mapped through `ExecutionEngine`.
2. [x] Add mangled absolute-symbol registration to `PureJit`.
3. [x] Convert activation stack, shadow stack, function pointer, and Pure globals.
4. [ ] Convert external C wrapper lookup and indirect calls.
5. [ ] Replace `resolve_external` with an ORC-compatible failure strategy.
6. [ ] Test symbol visibility for executable, shared-library, and plugin builds.

## Legacy Symbol Inventory

| Category | Current mechanism | Storage and lifetime | ORC migration |
| --- | --- | --- | --- |
| Runtime functions | `declare_extern(fp, ...)` adds each address with `DynamicLibrary::AddSymbol`; MCJIT also uses `resolve_external` | Functions and process symbols live for the process | Prefer LLJIT's current-process generator; define explicit absolute symbols for runtime addresses that are not exported reliably |
| User C externals | `SearchForAddressOfSymbol`, external declarations, and direct calls from generated wrappers | Owned by permanently loaded libraries or the process | Resolve through the ORC process/library search order and report lookup failure as a Pure error |
| `$$sstk$$` | `addGlobalMapping(sstkvar, &sstk)` | Address of the interpreter's mutable shadow-stack pointer; interpreter lifetime | External declaration plus absolute data symbol bound to `&sstk` |
| `$$fptr$$` | `addGlobalMapping(fptrvar, &fptr)` | Address of the current environment pointer; interpreter lifetime | External declaration plus absolute data symbol bound to `&fptr` |
| Pure symbol/global slots | `GlobalVar::v` is mapped to `&GlobalVar::x` under `$name`, `$(name)`, `$$private.name`, or generated symbol labels | Usually a node in `globalvars`; storage must outlive all generated readers and old closures | External declarations plus absolute data symbols; unregister or retain bindings according to storage lifetime |
| Cached constants | `$$const.<name>` maps to `&GlobalVar::x`; superseded values may move to separately allocated `pure_expr **` storage | Cached value or preserved old binding lifetime | Register each stable host slot once and keep superseded slots alive while old code can reference them |
| Temporary wrapped expressions | `$$tmpvar...` maps to heap `GlobalVar::x`; `EXPR::~EXPR` unmaps and erases it | Owning `EXPR::WRAP` lifetime | Give each slot a unique absolute symbol and remove its binding only after dependent ORC resources are gone |
| Faust dispatch slots | `$<external-name>` maps to a heap `void **`; reload patches it through `getPointerToGlobal` | Must survive every wrapper using the Faust external; currently allocated without explicit reclamation | Keep host-owned dispatch storage in a registry, bind it absolutely, and update the stored function address on reload |
| Faust provider globals | `$$__faust__$<module>$...` are JIT-owned globals queried with `getPointerToGlobal` | Faust module/provider lifetime | Keep them in their provider ORC unit; do not also register them as absolute symbols |
| Compiled function addresses | `getPointerToFunction` fills Pure closures, runtime type entries, external wrappers, Faust dispatch slots, and anonymous definition calls | Tied to generated implementation and any escaped closure | Replace with typed ORC lookup and retain the provider `ResourceTracker` for every consumer lifetime |

### Update and removal sites

- `Env::clear` unmaps local/global function addresses while preserving code used by
  closures; TODO-09 replaces this with stable bindings and tracked implementations.
- `clearsym`, failed `dodefn`, and `EXPR::~EXPR` remove or recreate host-backed
  slots. ORC symbol removal must be ordered after code-resource removal.
- `LoadFaustDSP` clears old module mappings and patches dispatch pointers during
  reload. Provider resources and host dispatch storage need separate ownership.
- `pure_symbol`, `defn`, `dodefn`, `cbox`, external wrapper creation, and startup
  placeholder restoration all lazily create `GlobalVar` mappings and must call one
  shared registration path.

### Migration order

1. Add mangled absolute data/function registration and explicit lookup helpers to
   `PureJit`.
2. Register process-lifetime runtime functions plus `$$sstk$$` and `$$fptr$$`.
3. Centralize creation and lifetime of Pure, constant, temporary, and Faust host
   slots, then convert their IR definitions to external declarations.
4. Convert generated function consumers to typed ORC lookup and replace the lazy
   unresolved fallback with actionable lookup errors.

## Guardrails

- Do not define an ORC-allocated global and an absolute symbol under the same name.
- Keep host storage alive for at least as long as generated code can access it.
- Missing symbols must produce Pure diagnostics rather than an LLVM process abort.

## Validation Plan

- Run focused tests for globals, externals, wrappers, and unresolved symbols.
- Validate both shared and non-shared runtime build variants if retained.
- Use `llvm-nm-22` or debugger inspection when symbol visibility is ambiguous.

## Open Questions

- Why does LeakSanitizer's process-exit scan stall after an evaluated closure even
  though the same ASan/UBSan run exits immediately with leak detection disabled?
- Should mutable Pure globals remain absolute symbols or move to a runtime table API?
- Which symbols must be exported from the main executable with linker options?

## Progress Log

- 2026-07-23: Moved Faust wrapper dispatch slots to the ORC host registry.
  - Faust external wrappers now register their heap `void **` dispatch storage as
    absolute data symbols and roll back both storage and IR if registration fails.
  - Interactive reload patches the host address recorded by the registry instead
    of asking MCJIT for a global address. A compatibility fallback remains for a
    dispatch global owned by an already batch-compiled module.
  - Provider-owned `$$__faust__$...` globals remain separate and are not registered
    as host absolute symbols.
  - Validation:
    - Full Debug and ASan builds plus focused Debug and sanitizer ORC smoke tests
      passed with zero warnings, errors, leaks, or sanitizer diagnostics.
    - End-to-end DSP loading is blocked by the TODO-11 Faust ABI migration. Faust
      2.70.3 emits `allocatemydsp`, `destroymydsp`, and `getJSONmydsp`, while the
      current loader requires legacy `new`/`delete` and `buildUserInterface_llvm`;
      the generated bitcode is therefore rejected before wrapper creation.
  - Task 4 remains open for ORC lookup of external/provider functions and removal
    of the batch/MCJIT compatibility fallback.
- 2026-07-23: Completed temporary host-global lifecycle tracking.
  - `wrap_expr` now registers each uniquely named `$$tmpvar` through the shared
    ORC/MCJIT host-global path and rolls back its LLVM global, expression value,
    and heap `GlobalVar` if registration fails.
  - `EXPR::WRAP` removes the symbol tracker before erasing IR and releasing host
    storage. Its destructor reports removal failure and deliberately preserves
    the slot rather than leaving an ORC symbol with a dangling address.
  - Validation:
    - Debug and ASan builds and the focused ORC smoke test passed with zero build
      warnings, errors, or sanitizer diagnostics.
    - Regression test 044 exercised cached pointer and local-closure runtime data
      in Debug and under ASan/UBSan without unresolved, duplicate, host-global
      removal, or shutdown diagnostics.
  - Task 3 is complete. Remaining direct data mapping is Faust dispatch storage,
    which belongs to task 4; transitional MCJIT mappings remain until their code
    paths migrate fully.
- 2026-07-23: Added recoverable ORC host-symbol rebinding.
  - Host registry entries now retain both address and individual tracker. Binding
    the same name to a new stable slot removes the old lookup definition, registers
    the replacement, and restores the old address if replacement registration
    fails.
  - Already materialized ORC code keeps its relocated old address; existing
    constant cleanup preserves that old heap-backed storage while new modules
    resolve the replacement address.
  - Converted cached `$$const.*` creation, constant-to-cbox `clearsym` replacement,
    and embedded-interpreter slot restoration to the shared rebind path.
  - Validation:
    - Debug and ASan builds and the focused ORC smoke test passed with zero
      warnings, errors, or sanitizer diagnostics.
    - Regression test 084 preserved `bar` across `clear foo`, rebound a new `foo`,
      and created `baz` without unresolved, duplicate, removal, or shutdown
      diagnostics in Debug and under ASan/UBSan.
  - Task 3 remains open for temporary wrappers and Faust dispatch/storage.
- 2026-07-23: Registered stable Pure symbol and cbox host slots with ORC.
  - Routed embedded-interpreter restoration, compiled global-function caches,
    ordinary `defn`, external fallback/failed-match cboxes, `cbox`, and runtime
    `pure_symbol` creation through the shared host-global registration path.
  - These slots retain one stable `pure_expr **` address and update only its
    contents, so generated ORC units can resolve them without rebinding.
  - Deliberately deferred `clearsym`, cached constants, `$$tmpvar` wrappers, and
    Faust dispatch slots because they replace or remove storage and require an
    explicit rebind/lifetime policy.
  - Validation:
    - Full Debug and ASan builds plus Debug and sanitizer ORC smoke tests passed
      with zero warnings, errors, leaks, or sanitizer diagnostics.
    - The focused global-definition rollback/closure test still returned `42`
      without unresolved, duplicate, removal, or shutdown diagnostics.
    - Regression harness test 007 completed in Debug and under ASan/UBSan with no
      ORC diagnostics. Its existing malformed `--endif` warnings are unrelated.
  - Task 3 remains open for rebinding globals, constants, temporary wrappers, and
    Faust dispatch storage.
- 2026-07-23: Routed interactive variable definitions through ORC host globals.
  - Split the interpreter host-symbol registry into one tracker per symbol, so a
    failed or temporary binding can be removed without invalidating unrelated
    core globals.
  - Added shared `register_host_global`/`remove_host_global` helpers that keep
    transitional MCJIT mappings synchronized while definition call sites migrate.
  - `dodefn` now registers newly created Pure variable slots, submits its anonymous
    matcher/binder with a unique ORC entry name, retains escaped closure resources,
    and removes both failed definition resources and unused host symbols in order.
    Batch `keep` execution remains on the transitional engine.
  - Validation:
    - Full Debug and ASan builds and focused ORC smoke tests passed with zero
      warnings, errors, leaks, or sanitizer diagnostics.
    - `let y = \\x -> x; y 42;` returned `42` in Debug and under ASan/UBSan,
      replacing the previous wild jump into non-executable MCJIT memory.
    - A failed nonlinear pattern binding removed its `$y` symbol, after which the
      same name was registered again and a closure application returned `7` with
      no duplicate, unresolved, removal, or shutdown diagnostics.
  - Task 3 remains open for the other Pure/global creation sites, cached constants,
    temporary wrappers, and Faust dispatch slots.
- 2026-07-23: Bound the core interpreter stack and environment globals in ORC.
  - Registered `$$sstk$$` and `$$fptr$$` as absolute data symbols backed by the
    interpreter member slots while retaining their transitional MCJIT mappings.
    One interpreter-lifetime tracker is removed after all evaluation units and
    before LLJIT destruction; partial registration failures roll it back.
  - Configured LLJIT for the large PIC code model. This avoids x86-64 `Delta32`
    relocation failures when JIT code and host slots, including stack-resident
    interpreter objects, are more than 2 GiB apart.
  - Gave each anonymous ORC snapshot a unique exported entry name. Escaped
    closures can now retain old evaluation trackers without colliding with the
    next source-level `$$init` function.
  - Validation:
    - Full Debug and sanitizer builds plus focused ORC smoke tests passed with
      zero warnings, errors, or sanitizer diagnostics.
    - A retained lambda followed by a lambda application produced a closure and
      `42` without unresolved, relocation, duplicate-symbol, removal, or shutdown
      diagnostics.
    - Twenty scalar evaluations exited cleanly under ASan/LeakSanitizer/UBSan.
      Five closure/application pairs passed under ASan/UBSan with leak detection
      disabled.
    - LeakSanitizer's exit scan stalls after even one successful closure pair;
      this is recorded as an open sanitizer issue rather than suppressed.
  - Task 3 remains open for Pure, constant, temporary, and Faust host slots.
- 2026-07-23: Added tracker-owned mangled absolute-symbol registration.
  - `PureJit::register_absolute_symbol` mangles and interns names against LLJIT's
    target `DataLayout`, defines strong symbols in the main `JITDylib`, and assigns
    them to an explicit `ResourceTracker`.
  - Its typed pointer overload uses `ExecutorSymbolDef::fromPtr`, which preserves
    data addresses and automatically marks function pointers as callable without
    converting them through `void *`.
  - The ORC smoke test now resolves an external host integer and host function,
    executes JIT code that loads and calls them to produce `42`, removes module
    resources before symbol resources, and verifies that the removed data symbol
    can no longer be looked up.
  - Validation:
    - Focused Debug and ASan/LeakSanitizer/UBSan builds and smoke tests passed with
      zero warnings, errors, leaks, or sanitizer diagnostics.
- 2026-07-23: Completed the legacy runtime symbol and host-global inventory.
  - Classified process/runtime functions, dynamic C externals, interpreter stack
    pointers, Pure and constant slots, temporary wrappers, Faust dispatch storage,
    provider-owned Faust globals, and compiled function-address consumers.
  - Recorded storage lifetimes, update/removal sites, and the required distinction
    between host-owned absolute symbols and ORC-provider-owned definitions.
  - Defined an implementation order beginning with reusable mangled absolute-symbol
    registration in `PureJit`.
  - Validation:
    - Source ownership and call-site review only; no runtime behavior changed.
- 2026-07-22: Initial runtime symbol and global mapping plan created.
  - Validation:
    - Not run; this update creates planning documentation only.
