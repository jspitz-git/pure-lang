# TODO-47 - Windows pure-reduce Package

Status: Open
Branch: todo/47-windows-pure-reduce

## Purpose

Determine a reproducible Windows build and packaging model for the large
`pure-reduce` integration.

## Scope

- Inventory the bundled Reduce/CSL sources, generated artifacts, tools, and licenses.
- Separate bridge requirements from the full computer-algebra runtime.
- Assess size, build time, relocatability, and maintenance cost.

## Task List

1. [ ] Reproduce the complete dependency and generation pipeline on Windows.
2. [ ] Build the bridge and required Reduce runtime components.
3. [ ] Make runtime data and executable lookup relocatable.
4. [ ] Add symbolic-algebra and lifecycle smoke tests.
5. [ ] Decide whether to ship as a separate installer component or artifact.

## Guardrails

- Do not include an incomplete generated runtime.
- Preserve all upstream license and source-offer obligations.

## Validation Plan

- Run representative algebra, simplification, and error cases outside MSYS2.
- Measure installed size and test installation, upgrade, and removal separately.

## Open Questions

- Whether its size and build complexity warrant a separate downloadable component.

## Progress Log

- 2026-07-25: Created as a large optional Windows package investigation.
