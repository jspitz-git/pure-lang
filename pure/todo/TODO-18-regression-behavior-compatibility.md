# TODO-18 - Regression Behavior Compatibility

Status: Open
Branch: todo/18-regression-behavior-compatibility

## Purpose

Resolve the deterministic language/runtime differences exposed after TODO-17 made the
complete regression corpus finish. Success means all 97 Release inputs (prelude plus
`test001` through `test096`) match their normalized golden logs, with equivalent Debug
and sanitizer results or explicitly justified configuration-specific expectations.

## Scope

- Reduce and fix ORC duplicate-definition and incomplete-module failures.
- Restore or deliberately update formatted-input compatibility.
- Validate binary blob fixture discovery and architecture expectations.
- Classify the remaining stack, exception, reflection, recursion, and output differences.
- Change golden logs only after current behavior is proven intentional and supported.

## Release Failure Baseline

The first complete LLVM 22 Release run used `run-tests -j 4` and finished all 97
inputs in 1347.36 seconds. Seventy-seven inputs passed and 20 failed. A subsequent
serial `run-tests -f -j 1` reproduced the same 20 failures, establishing that they
are deterministic runtime/golden differences rather than scheduler races.

| Class | Inputs | Initial signature |
| --- | --- | --- |
| ORC definition/materialization | `prelude`, `test014`, `test015`, `test020`, `test021`, `test025`, `test028`, `test036`, `test061`, `test072`, `test079` | Duplicate `$$fastcc.*` definitions, often followed by unterminated type-JIT functions; prelude also aborts after the reported failure. |
| Formatted input | `test011`, `test018`, `test069` | `sscanf` returns `scanf_error` or `failed_cond` for previously accepted string, unsigned, and GMP formats. |
| Binary fixture loading | `test042` | All four architecture blob reads fail their condition despite resolving under `srcdir/test`. |
| Other language/runtime behavior | `test020`, `test054` | Math-test segmentation fault and a separate `stack_fault`; the other five initial members passed after transactional type-generation replacement. |

The ORC class overlaps TODO-14's hybrid-runtime migration, but TODO-18 owns the
minimal corpus reproducers and the release golden-pass criterion. Fixes may land in
TODO-14 when their root cause is shared with transitional MCJIT/ORC ownership.

## Current Disposition

The initial ORC publication class is resolved. Reduced ORC units now localize every
reachable helper definition except their uniquely exported entry, so a later unit may
clone the same mutable-module helper without publishing a duplicate `$$fastcc.*`
symbol. A smoke test keeps two such units alive and callable simultaneously.

All 11 initial ORC inputs no longer report duplicate definitions or unterminated
follow-on modules. Nine now match their golden logs completely: `prelude`, `test014`,
`test015`, `test021`, `test025`, `test028`, `test036`, `test061`, and `test079`.
`test020` proceeds to a later segmentation fault. The former `test072`
interface-dispatch difference was subsequently fixed by fresh type generations.

The formatted-I/O and blob classes are also resolved. `pure_pointer_tag` previously
round-tripped semantic pointer names through LLVM `type_name`; every opaque pointer
therefore became `<unknown C type>`. Standard streams were tagged with that placeholder
while generated wrappers correctly checked `FILE*`, causing `printf`, `sscanf`, and the
blob test's diagnostic output to fail. Pointer normalization now preserves `CAbiType`
names, and a focused test covers `FILE*`, formatted output, and formatted input.

That sanitizer test also exposed four runtime string constructors which allocated
`EXPR::STR` buffers with `new[]` although the common destructor uses
`my_strfree`/`free`. They now use matching `malloc` ownership. Under ASan the focused
test disables the historical address-difference `PURE_STACK` heuristic; ASan itself
remains responsible for detecting actual stack overflow.

Mutable type functions no longer reuse a cached ORC address keyed only by their stable
`llvm::Function*`. Type recompilation now materializes a new unit, publishes its address
through `pure_add_rtty`, and removes the previous tracker afterward. This fixed stale
type behavior in `test058` and also cleared `test051`, `test057`, `test063`, and
`test072`. Only `test020` and `test054` remain from the initial 20 failures.

## Task List

1. [ ] Reduce each failure class to the smallest deterministic reproducer.
2. [x] Fix duplicate ORC publication and invalid type-JIT continuation after failure.
3. [x] Reconcile `printf`/`sscanf` string, integer, unsigned, and GMP behavior.
4. [x] Validate blob fixture discovery and decoding after the shared I/O fix.
5. [ ] Classify and fix the two remaining language/runtime differences.
6. [ ] Run all 97 inputs in Release with no golden differences.
7. [ ] Run the complete corpus in Debug and sanitizer configurations.

## Guardrails

- Do not regenerate golden logs to hide an unexplained runtime difference.
- Preserve transactional ORC publication: a failed generation must not corrupt later IR.
- Keep one process per corpus input so failures remain independently reproducible.
- Distinguish unsupported host-specific expectations from LLVM migration regressions.

## Validation Plan

- Add focused reproducers or CTest cases before changing each runtime subsystem.
- Run the affected corpus input serially before and after every fix.
- Use `run-tests -f` to verify that each repaired class clears its persistent diffs.
- Finish with complete Release, Debug, and sanitizer corpus runs.

## Origin

Created from the first complete TODO-17 Release run on 2026-07-24. Earlier bounded
TODO-13 runs did not progress far enough to expose these deterministic differences.

## Progress Log

- 2026-07-24: Fixed duplicate helper publication across reduced ORC generations.
  - Changed entry reduction to internalize reachable function, constant-global,
    alias, and ifunc definitions while retaining only the renamed entry as external.
  - Added a JIT smoke case which submits two live reduced modules containing the
    same originally external helper and calls both unique entries successfully.
  - Cleared the duplicate/invalid-module signature from all 11 initial reproducers;
    nine pass fully, while later `test020` and `test072` differences remain classified.
  - Validation:
    - Release and ASan/UBSan `pure-jit-smoke` passed in 0.04 and 0.10 seconds.
    - All 11 focused Release CTests passed in 121.74 seconds.
    - `prelude.pure` and `test014.pure` passed together after the initial fix.
    - The complete 11-input ORC subset ran in 399.92 seconds with nine full passes
      and no duplicate-definition or unterminated-module diagnostic.
- 2026-07-24: Restored custom pointer tags and formatted I/O compatibility.
  - Preserved canonical `CAbiType` names when `pure_pointer_tag` normalizes opaque
    pointer types, keeping `FILE*` globals and wrappers on the same runtime tag.
  - Reclassified `test042`: fixture paths, reads, and decoding were valid; its
    failure came from the same broken `printf` wrapper as the formatted-I/O tests.
  - Added focused `FILE*`, `printf`, and `sscanf` integration coverage.
  - Replaced four `new[]` allocations stored in `EXPR::STR` with `malloc`, matching
    the existing `my_strfree`/`free` destruction path found by the new ASan test.
  - Validation:
    - Minimal `printf "%s" "ok"` returned 2 and `pointer_type stdout` returned
      `FILE*`; the equivalent temporary `void*` alias confirmed the former tag mismatch.
    - `test011`, `test018`, `test042`, and `test069` all passed in one 44.49-second
      Release run.
    - `pure-formatted-io` passed in Release in 26.19 seconds.
    - With `PURE_STACK=0` replacing the ASan-incompatible address heuristic,
      `pure-formatted-io` passed under ASan/UBSan in 62.64 seconds without a finding.
    - All 12 focused Release CTests passed in 118.11 seconds after the runtime
      allocator fix and new integration test were included.
- 2026-07-24: Replaced stale cached type-function addresses transactionally.
  - Confirmed `compile_orc_function` returned a cache hit for `$$type.nat` after
    `test058` extended the type with a `bigint` rule.
  - Preserved cache reuse for immutable external wrappers, but made type
    recompilation add and resolve a new ORC unit before replacing the registry entry.
  - Publish the new type address through `pure_add_rtty` before removing the old
    tracker, preserving the previous generation if materialization fails.
  - Extended the no-prelude lifetime stress with an `int` type dispatch followed by
    a `bigint` extension of the same tag.
  - Validation:
    - `test058.pure` passed after the replacement fix.
    - `pure-jit-lifetime-stress` passed in Release and ASan/UBSan in 0.24 and
      0.47 seconds respectively.
    - Of the six remaining runtime inputs, `test051`, `test057`, `test063`, and
      `test072` now pass; only `test020` and `test054` still fail.
    - All 12 focused Release CTests passed in 109.58 seconds.
