# TODO-43 - Windows pure-octave Package

Status: Open
Branch: todo/43-windows-pure-octave

## Purpose

Determine whether `pure-octave` can be supported against a controlled 64-bit
Windows Octave distribution.

## Scope

- Select a compatible Octave version, compiler ABI, and module build method.
- Validate data conversion, calls in both directions, exceptions, and shutdown.
- Assess the large runtime footprint before including it as an installer component.

## Task List

1. [ ] Select and document a compatible Windows Octave toolchain.
2. [ ] Build the bridge and audit its full runtime dependency closure.
3. [ ] Add scalar, matrix, complex, callback, and error smoke tests.
4. [ ] Decide whether to bundle, externally detect, or defer the package.

## Guardrails

- Do not mix incompatible Octave and Pure C++ runtimes.
- Do not silently bundle an incomplete Octave runtime.

## Validation Plan

- Execute representative Octave functions and round-trip matrices and errors.
- Repeat on a clean VM with only the explicitly staged dependencies.

## Open Questions

- Whether the size and ABI stability justify an integrated installer component.

## Progress Log

- 2026-07-25: Created as an optional scientific Windows package investigation.
