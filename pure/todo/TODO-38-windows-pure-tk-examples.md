# TODO-38 - Windows pure-tk-examples Package

Status: Open
Branch: todo/38-windows-pure-tk-examples

## Purpose

Validate and package `pure-tk-examples` after `pure-tk` is available on Windows.

## Scope

- Install examples, data files, and documentation without hard-coded source paths.
- Classify examples as automated, interactive, or unsupported.
- Repair Windows path and newline assumptions found during execution.

## Task List

1. [ ] Inventory every example and its runtime/data dependencies.
2. [ ] Add bounded smoke modes where practical.
3. [ ] Validate every supported example on a Windows desktop.
4. [ ] Stage examples and document how to launch them.

## Guardrails

- Do not mark an example supported based only on successful parsing.
- Interactive examples must not be part of an unbounded CI test.

## Validation Plan

- Run automated examples to completion.
- Launch, interact with, and close each remaining supported example manually.

## Progress Log

- 2026-07-25: Created as a follow-up to the Windows `pure-tk` package.
