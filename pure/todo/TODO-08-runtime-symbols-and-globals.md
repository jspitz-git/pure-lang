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
3. [ ] Convert activation stack, shadow stack, function pointer, and Pure globals.
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

- Should mutable Pure globals remain absolute symbols or move to a runtime table API?
- Which symbols must be exported from the main executable with linker options?

## Progress Log

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
