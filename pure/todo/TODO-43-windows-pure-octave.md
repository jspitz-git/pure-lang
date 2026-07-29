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
- 2026-07-29: Ported the basic bridge to Octave 11.3 behind a stable C loader.
  - TDD RED: compiling the legacy `embed.cc` with the validated 11.3
    `mkoctfile.exe` failed first at
    `embed.cc:26:10: fatal error: octave/config.h: No such file or directory`.
  - Loader: validates the signed-root fingerprint, uses DLL-relative,
    config-file, or explicit-root selection in that order, restricts Windows
    DLL lookup to controlled directories, verifies the loaded
    `liboctinterp-15.dll` path, and publishes the implementation table only
    after all exports and the exact ABI are validated.
  - Interpreter: uses the public Octave 11.3 instance lifecycle and evaluation
    APIs. Because the embedded public lifecycle supplied only `.` as its load
    path in the Pure host, the implementation deterministically enumerates the
    validated root's full `mingw64/share/octave/11.3.0/m` tree, excluding
    package-private directories.
  - Pure initialization now passes `--quiet`, `--no-history`, and
    `--no-init-file`, checks the result, and reports loader-owned diagnostics.
  - Validation:
    - `ctest --test-dir "C:\tmp\Pure Octave Build 20260729" -R "pure-octave-(basic|loader|dependencies)" --output-on-failure` passed 3/3.
    - The first full-suite run exposed that the Task 1 nested rejected-root
      configure no longer inherited a C compiler after enabling the C loader;
      explicitly propagating the validated compiler made its focused
      regression and the eight-test suite pass.
- 2026-07-29: Restored the complete data-conversion and function-value contract.
  - TDD RED: the new conversion and function-value tests failed 0/2 before the
    exports existed. The first Octave 11.3 typed-array port then failed because
    its typed `fortran_vec()` accessor is non-const.
  - Native copy conversions now cover real, complex, logical, integer, and
    string scalars/matrices. Opaque `octave_value` wrappers are allocated and
    deleted only inside `octave_bridge_impl.dll`.
  - Converter hooks restore cells, structs, struct arrays, and N-D arrays. The
    Octave 11.3 public multi-output API required the cell extractor to request
    the exact element count rather than the legacy single output.
  - Function tests invoke named `eig` and an anonymous `x+y` handle. A chained
    test sentry invokes the original `octave_free`, increments an exact Pure
    reference counter, and proves all 60 wrappers finalize across top-level
    evaluation boundaries before a further successful Octave call.
  - Runtime conflict: repository and installed-DLL export audits confirmed that
    controlled Pure 0.68 has no language or public C-runtime `pure_gc`; the user
    approved evaluation boundaries plus the exact chained-sentry count as the
    leak proof. No production GC API or working-set heuristic was added.
  - The standalone absolute-preload helper cannot use the real Pure DLL closure:
    adding the controlled Pure runtime directory before the loader or before
    `octave_init` caused a Windows stack overflow. Its test-only fail-fast stub
    exports exactly the implementation's 33 imported but uncalled Pure symbols;
    any call exits with status 99. CMake confines it to the test tree and
    disposable fixture, audits its PE exports, and asserts fixture cleanup. The
    production loader continues to use only its existing trusted search roots.
  - Validation:
    - `ctest --test-dir "C:\tmp\Pure Octave Build 20260729" -R "pure-octave-(conversions|function-values)" --output-on-failure` passed 2/2 in 20.60 seconds.
    - `ctest --test-dir "C:\tmp\Pure Octave Build 20260729" --output-on-failure` passed 10/10 in 44.25 seconds.
