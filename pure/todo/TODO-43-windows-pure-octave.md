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

1. [x] Select and document a compatible Windows Octave toolchain.
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
- 2026-07-29: Validated the signed Windows Octave 11.3.0 embedding toolchain.
  - Provenance: official `octave-11.3.0-w64.7z` (no ZIP fallback), detached
    signature primary fingerprint
    `DBD9C84E39FE1AAE99F04446B05F05B75D36644B`, extracted below the temporary
    work root at
    `C:\tmp\Pure Octave Build 20260729\pure-octave-work\octave-11.3.0\octave-11.3.0-w64`.
  - Toolchain: `octave-cli.exe` and `mkoctfile.exe` are in `mingw64/bin`;
    modules are in `mingw64/lib/octave/11.3.0`; share files are in
    `mingw64/share/octave/11.3.0`. `octave-cli --version` reported
    `GNU Octave (x86_64-w64-mingw32) version 11.3.0`.
  - Public API decision: the official manual example uses `parse.h`, but the
    installed public `interpreter.h` exposes `interpreter::feval`; the user
    approved that instance method while retaining only `oct.h`, `octave.h`,
    and `interpreter.h` in the probe.
  - Validation:
    - `cmake -S pure-octave -B "C:\tmp\Pure Octave Build 20260729" -G Ninja -DBUILD_TESTING=ON -DPURE_PREFIX="C:\tmp\Relocated Pure Gplot Final Bundle 20260729" -DOCTAVE_ROOT="C:\tmp\Pure Octave Fake Root"` failed as expected with all required missing path classes.
    - `ctest --test-dir "C:\tmp\Pure Octave Build 20260729" --output-on-failure` passed 2/2: rejected-root contract and sanitized public-API embedding probe.
