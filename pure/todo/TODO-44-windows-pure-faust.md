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

1. [x] Select and reproduce the Windows Faust dependency set.
2. [x] Deliberately exclude the legacy native bridge and audit the
   generated-code tool requirements.
3. [x] Add deterministic compile and DSP smoke tests.
4. [x] Keep the compiler in the optional `FaustDeveloper` component.
5. [ ] Stage and validate the advertised configuration.

## Guardrails

- Do not require MSYS2 at package runtime.
- Keep generated-code compiler dependencies explicit.

## Validation Plan

- Compile a small Faust program, load it, and process a fixed signal buffer.
- Run from a clean VM with only the selected installer components present.

## Open Questions

- None. The default `Runtime` selection loads prebuilt bitcode; Faust 2.85.9
  and the Clang/LLVM 22 compile-only closure are optional `FaustDeveloper`
  content.

## Progress Log

- 2026-07-25: Created as an optional DSP Windows package candidate.
- 2026-08-16: Completed local implementation and prepared clean-runner
  automation.
  - `Runtime` contains `faust2.pure`, documentation, and the prebuilt fixture;
    it deliberately excludes `faust.cc`, `faust.pure`, `pure.cpp`,
    `faust.dll`, Faust, Clang, LLVM tools, and MSYS2.
  - `FaustDeveloper` pins Faust 2.85.9 and a dependency-derived Clang/LLVM 22
    compile-only closure. The installed helper supports paths containing
    spaces, verifies bitcode before atomic publication, and rebuilds the same
    deterministic two-input/one-output fixture consumed by the runtime smoke.
  - On the development Windows host, the sanitized `Runtime` label passed 3/3
    CTests in 13.82 seconds and the sanitized `faust` label passed 8/8 CTests
    in 26.82 seconds. The complete unfiltered suite also passed 8/8 in 26.59
    seconds.
  - Fresh stages in paths containing spaces passed the installed-package
    verifier: runtime-only contained 5 files with sorted inventory SHA-256
    `917f73e596348654eb98c918045b52c92bdfe9ab35dadd8ec292dd04563de386`;
    runtime plus developer contained 52 files with sorted inventory SHA-256
    `03c48fc651a0ff7979c52765e269500ea007ed6f7928e743ba769e321ef8d2d0`.
    The authoritative developer allowlist SHA-256 was
    `ff283ce1b7b1d97fc6a35bda10c1657f804490fc5a2a4fbe53304c51a971bbdc`.
  - Bounded caveat: the new clean-runner matrix has not been dispatched, so
    there is no workflow URL or uploaded archive SHA-256 yet. TODO-44 remains
    open until both `Runtime` and `Runtime+FaustDeveloper` jobs pass on a clean
    Windows runner. Record the run URL, tested commit, CTest counts and elapsed
    times, and both uploaded archive SHA-256 values here before closing.
