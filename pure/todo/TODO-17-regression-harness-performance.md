# TODO-17 - Regression Harness Performance

Status: Open
Branch: todo/17-regression-harness-performance

## Purpose

Reduce the complete regression corpus runtime without weakening process isolation or
golden-output coverage. Success means the supported corpus fits a documented CI and
release-validation budget in Debug, Release, and sanitizer configurations.

## Scope

- Measure prelude compilation and per-script startup costs by preset.
- Determine which tests require isolated processes or filesystem state.
- Evaluate safe parallel execution, precompiled prelude reuse, or a persistent runner.
- Keep TODO-13's CRLF normalization at the harness boundary unless the corpus is
  deliberately normalized in a separate review.

## Task List

1. [ ] Record per-test and startup timings in all supported presets.
2. [ ] Classify isolation and shared-filesystem constraints across the corpus.
3. [ ] Choose a bounded execution design which preserves test semantics.
4. [ ] Implement deterministic scheduling and collision-free output handling.
5. [ ] Validate identical golden results before and after the harness change.
6. [ ] Set and document realistic CTest timeouts for complete release runs.

## Guardrails

- Do not hide failures by sharding away or disabling corpus inputs.
- Preserve verbatim logical output comparison after line-ending normalization.
- Do not share interpreter state between tests unless equivalence is demonstrated.

## Validation Plan

- Run the complete corpus before and after the change and compare all outcomes.
- Exercise interrupted runs and `run-tests -f` cleanup/retry behavior.
- Run the final design in Debug, Release, and sanitizer presets within its stated budget.

## Origin

Created from TODO-13 retrospective gate 6. TODO-13 fixes CRLF-sensitive input and
golden comparison; this follow-up owns the independent repeated-startup performance cost.
