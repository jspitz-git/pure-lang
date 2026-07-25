# TODO-44 - Windows pure-faust Package

Status: Open
Branch: todo/44-windows-pure-faust

## Purpose

Build, validate, and package `pure-faust` with a reproducible Windows Faust
toolchain.

## Scope

- Define the supported Faust version and whether its compiler is bundled.
- Remove fixed external-tool paths and use distribution-relative discovery.
- Cover compilation, module loading, DSP processing, diagnostics, and cleanup.

## Task List

1. [ ] Select and reproduce the Windows Faust dependency set.
2. [ ] Build the Pure bridge and audit generated-code tool requirements.
3. [ ] Add deterministic compile and DSP smoke tests.
4. [ ] Decide the runtime versus developer-component split.
5. [ ] Stage and validate the advertised configuration.

## Guardrails

- Do not require MSYS2 at package runtime.
- Keep generated-code compiler dependencies explicit.

## Validation Plan

- Compile a small Faust program, load it, and process a fixed signal buffer.
- Run from a clean VM with only the selected installer components present.

## Open Questions

- Whether the Faust compiler belongs in the default or developer installation.

## Progress Log

- 2026-07-25: Created as an optional DSP Windows package candidate.
