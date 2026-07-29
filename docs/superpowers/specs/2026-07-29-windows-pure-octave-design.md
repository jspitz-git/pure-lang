# Windows pure-octave Design

Date: 2026-07-29
Status: Approved
TODO: `pure/todo/TODO-43-windows-pure-octave.md`
Branch: `todo/43-windows-pure-octave`

## Goal

Provide the full `pure-octave` API in portable Windows installations while
keeping Octave an optional component. Preserve in-process evaluation, data
conversion, function objects, and the `pure_call` callback from Octave into
Pure.

GNU Octave 11.3.0 is the initial candidate. It becomes the supported version
only after the compilation, ABI, callback, error-recovery, shutdown, staging,
and relocation gates in this design pass. The official Windows distribution
and current embedding guidance are published at:

- <https://octave.org/download>
- <https://docs.octave.org/latest/Standalone-Programs.html>

## Decisions

- Support exactly one pinned Windows x86-64 Octave distribution at a time.
- Prefer a compatible external installation when it exactly matches the
  supported version, architecture, distribution identity, and C++ ABI.
- Otherwise offer a private side-by-side installation below `tools/octave`.
- Never replace, modify, or uninstall an existing unsupported Octave.
- Never discover Octave implicitly through `PATH`.
- Keep `pure-octave` and the Octave runtime optional.
- Preserve the existing public Pure API and full bidirectional callback
  behavior.
- Do not implement final installer dialogs in TODO-43. Expose deterministic
  detection and installation contracts for TODO-49.

## Runtime Architecture

Split the native module into two layers.

### Stable loader

`octave_embed.dll` is a small Windows loader with no static dependency on
Octave libraries. It:

1. selects an exact Octave root;
2. validates that root against the supported distribution contract;
3. configures a restricted DLL search path with Windows APIs;
4. loads the ABI-specific implementation with `LoadLibraryExW`;
5. resolves and delegates the existing C entry points;
6. returns a clear initialization failure without falling back to `PATH`.

Runtime root selection uses this order:

1. the explicit `PURE_OCTAVE_ROOT` environment variable;
2. an installer-written configuration naming a validated external root;
3. the bundle-relative `tools/octave` root;
4. a deterministic error.

The installer-written path is allowed to be absolute because it identifies an
external installation. The managed root remains bundle-relative and relocates
with the portable prefix.

### ABI-specific implementation

`octave_bridge_impl.dll` contains the embedded Octave interpreter and all
Pure/Octave conversions. It is compiled with the toolchain and headers of the
one supported Octave distribution and links only to that distribution's
libraries plus the Pure C runtime interface.

No C++ object, allocator ownership, standard-library container, or exception
may cross the boundary between the Pure runtime and the Octave implementation.
The exported bridge interface remains C ABI. Octave exceptions are caught
inside the implementation and translated to stable result/error data before
control returns to Pure.

The implementation owns exactly one Octave interpreter per Pure process.
Restart after shutdown is not supported unless the selected Octave API proves
it safe during validation.

## Public Behavior

The following existing capabilities remain supported:

- `octave_eval`;
- `octave_get` and `octave_set`;
- `octave_call`;
- `octave_func`;
- `octave_valuep`;
- scalar, string, integer, real, and complex matrix conversion;
- higher-dimensional array, cell, and structure converters;
- `pure_call` callbacks from Octave to Pure;
- error recovery followed by further Octave calls;
- orderly process shutdown.

Internal initialization may gain a result code and diagnostic query so that
`octave.pure` can report loader, version, dependency, or interpreter failures
clearly. This does not change the public computational API.

## Distribution Selection and Acquisition

The first candidate is the official Windows x86-64 GNU Octave 11.3.0
distribution. Acquisition must:

- use an official Octave/GNU URL;
- pin and verify the selected artifact's cryptographic identity;
- extract or install only into a caller-controlled child directory;
- verify version and architecture without using host `PATH`;
- retain upstream license and provenance material;
- expose the compiler, `mkoctfile`, headers, import libraries, runtime tree,
  and module/data paths required by the embedded interpreter.

The artifact format is selected during the prototype. Prefer the smallest
official artifact that contains the complete build and runtime closure. The
choice must not require an unrelated system extractor at end-user install
time.

The candidate distribution may be installed permanently on the development
computer only after the compilation prototype and initial ABI tests pass.
That installation is side-by-side and does not replace any user Octave.

## Detection and Installer Contract

TODO-43 provides a deterministic probe returning one of:

- `compatible-external`, with its validated root;
- `unsupported-external`, with detected version and reason;
- `not-installed`;
- `invalid`, for an incomplete or corrupted candidate.

When the user selects the optional `pure-octave` component, TODO-49 uses the
probe as follows:

- `compatible-external`: offer to use it;
- `unsupported-external`: explain that it remains untouched and request
  consent to add the supported private copy;
- `not-installed`: request consent to install the supported private copy;
- `invalid`: reject it and offer the supported private copy.

Declining the private copy leaves `pure-octave` uninstalled without affecting
the rest of the Windows bundle.

## Validation Gates

### Compilation prototype

Build a minimal embedded interpreter with the candidate distribution's own
toolchain. Load it from the portable Pure runtime and execute one built-in
function. Failure here rejects the candidate before permanent installation.

### Functional contract

Automated tests cover:

- numeric and string scalars;
- integer, real, and complex matrices;
- multiple arguments and return values;
- Octave function objects;
- higher-dimensional arrays, cells, and structures;
- Octave-to-Pure `pure_call`;
- a Pure exception raised inside a callback;
- an Octave parse or execution error followed by a successful call;
- repeated calls through one interpreter;
- orderly shutdown without a crash or hang.

### ABI and dependency audit

Audit the complete PE import closure of the loader and implementation. Confirm:

- the loader has no Octave dependency;
- the implementation resolves only against the controlled Octave tree,
  Windows system libraries, and the expected Pure C runtime;
- no dependency is satisfied accidentally from MSYS2 or host `PATH`;
- C++ values, ownership, and exceptions remain inside the implementation;
- the official Octave C++ runtime can coexist safely with the portable
  Clang/libc++ Pure process under conversion, callback, error, and shutdown
  stress.

Successful module loading alone is not evidence of ABI compatibility.

### Package validation

Validate both supported layouts:

- an exactly compatible external Octave root;
- a private bundle-relative `tools/octave` root.

For each layout, run from paths containing spaces with `PURELIB` unset and a
sanitized `PATH`. Copy the complete staged prefix to a differently named
location and repeat. Simulate missing, unsupported, and incomplete Octave
roots and verify deterministic diagnostics with no fallback.

The final clean-machine validation must contain only the explicitly staged
Pure and Octave dependency closures.

## Failure Policy

If Octave 11.3.0 requires manageable source adaptations, update the binding
while preserving its public behavior and record the API changes.

If the official GCC-based Windows distribution cannot safely coexist with the
portable Pure runtime, do not suppress or bypass the incompatibility. Evaluate
a controlled Octave build using a compatible Clang/libc++ toolchain.

If neither approach produces a supportable, reproducible runtime closure,
close TODO-43 as deferred with the exact technical evidence. Do not ship a
partial binding or incomplete Octave tree.

## Documentation and Handoff

Install:

- the Pure modules and stable loader;
- the ABI-specific implementation;
- optional managed Octave files only when selected;
- examples and installed verification scripts;
- Octave and pure-octave license/provenance material;
- Windows instructions for external detection, managed installation,
  relocation, diagnostics, and removal.

Document the size of the selected managed component. Expose the supported
version, distribution fingerprint, detection result, and managed install root
in a machine-readable form for TODO-49.

## Completion Criteria

TODO-43 is complete when:

- one exact Octave distribution passes every validation gate;
- or the task is explicitly deferred with reproducible incompatibility
  evidence;
- all supported public behavior has automated coverage;
- optional external and managed installation paths are deterministic;
- the installed package passes relocation and clean-machine validation;
- TODO-49 has an unambiguous component detection and installation contract.
