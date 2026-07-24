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
| Other language/runtime behavior | `test051`, `test054`, `test057`, `test058`, `test063` | Reflection output failure, `stack_fault`, unhandled recursive-compiler condition, changed recursive result rendering, and failed constant/function evaluation. |

The ORC class overlaps TODO-14's hybrid-runtime migration, but TODO-18 owns the
minimal corpus reproducers and the release golden-pass criterion. Fixes may land in
TODO-14 when their root cause is shared with transitional MCJIT/ORC ownership.

## Task List

1. [ ] Reduce each failure class to the smallest deterministic reproducer.
2. [ ] Fix duplicate ORC publication and invalid type-JIT continuation after failure.
3. [ ] Reconcile `sscanf` string, unsigned, and GMP conversion behavior.
4. [ ] Restore portable blob fixture discovery and validation.
5. [ ] Classify and fix the five remaining language/runtime differences.
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
