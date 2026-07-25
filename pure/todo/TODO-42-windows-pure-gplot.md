# TODO-42 - Windows pure-gplot Package

Status: Open
Branch: todo/42-windows-pure-gplot

## Purpose

Validate and package `pure-gplot` with a clearly defined Windows gnuplot dependency.

## Scope

- Decide whether gnuplot is bundled, detected, or offered as a separate component.
- Make process launching and temporary-file handling Windows-safe.
- Cover noninteractive rendering as well as an interactive smoke test.

## Task List

1. [ ] Define the supported gnuplot version and packaging policy.
2. [ ] Repair executable discovery, quoting, and path handling where needed.
3. [ ] Add deterministic file-rendering smoke tests.
4. [ ] Stage and validate the package on a clean Windows VM.

## Guardrails

- Do not depend on an unrelated gnuplot found on the build host.
- Quote every executable and data path safely.

## Validation Plan

- Render a known plot to a file in a path containing spaces and verify the output.
- Launch one interactive plot and close it cleanly.

## Open Questions

- Whether gnuplot should be bundled or selected as an optional external prerequisite.

## Progress Log

- 2026-07-25: Created as an optional visualization Windows package candidate.
