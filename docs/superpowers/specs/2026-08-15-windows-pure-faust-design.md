# Windows pure-faust Design

Status: Approved
Date: 2026-08-15
Affected TODO: `pure/todo/TODO-44-windows-pure-faust.md`

## Goal

Ship `pure-faust` on Windows as a lightweight compatibility package based on
`faust2.pure` and Pure's built-in Faust bitcode loader. Keep DSP execution in
the default runtime while making the Faust compilation toolchain an optional
developer component.

## Architecture

- Install `faust2.pure` as the Windows compatibility API. Do not build or
  install the legacy `faust.cc` bridge, `faust.pure`, `pure.cpp`, or a native
  `faust.dll` on Windows.
- Reuse the Faust loader, ABI validation, DSP lifecycle, and cleanup behavior
  implemented in the Pure core. Do not add a second loader or DSP runtime.
- Preserve the portable legacy sources and their behavior for non-Windows
  platforms.
- Use Faust 2.85.9 to generate C with its bundled `pure.c` architecture, and
  use the distribution's Clang 22 to compile that C to LLVM bitcode. Before
  packaging, prove that this newer frontend still satisfies the module ABI and
  deterministic fixture behavior established by TODO-11.

## Components

### Runtime component

The default runtime component contains:

- `faust2.pure` in the distribution-relative Pure library directory;
- the required license and provenance records;
- a small compatible, prebuilt bitcode DSP fixture for end-to-end runtime
  validation.

The runtime does not contain the Faust compiler or require Clang, LLVM command
line tools, MSYS2, or a system-wide `PURELIB` setting. It can load compatible
bitcode produced elsewhere.

### Optional developer component

The optional component contains the supported Faust 2.85.9 compiler, `pure.c`,
and the distribution's Clang 22 and bitcode-verification tools needed by the
documented workflow. A Windows-native helper replaces the Unix-oriented
`faust2pure` script. It discovers every shipped input relative to its own
installation and does not depend on fixed build-machine paths or MSYS2.

The helper performs these steps:

1. Generate C from a DSP source with Faust and `pure.c`.
2. Compile the generated C to LLVM bitcode with the distribution's Clang 22.
3. Verify the bitcode with the matching LLVM toolchain.
4. Publish the requested output atomically only after all steps succeed.

The Faust 2.85.9 redistributable payload is selected from a reproducible
upstream Windows artifact during implementation. Its version, checksum, source
URL, license, and installed files become explicit package metadata rather than
an implicit host dependency. If an acceptable 2.85.9 artifact cannot be
redistributed, implementation stops for a packaging decision instead of
silently substituting another Faust version.

## Discovery and Data Flow

Runtime module discovery follows Pure's distribution-relative library lookup.
The developer helper resolves Faust, `pure.c`, Clang, and the verifier from the
selected installer components. User input and output paths may be absolute or
relative and may contain spaces; tool paths are never inferred from the host
`PATH` when a distribution-owned tool is required.

The runtime smoke path imports `faust2`, loads the staged fixture through the
built-in loader, creates and initializes a DSP instance, processes a fixed
buffer, checks the deterministic result, and releases the instance. The
developer smoke path first regenerates that fixture in a temporary directory
and then runs the same runtime assertions against the generated bitcode.

## Diagnostics and Failure Safety

- A missing optional tool reports the missing component and instructs the user
  to install the Faust developer component.
- The helper rejects an incompatible Clang, a missing `pure.c`, failed Faust or
  Clang execution, invalid bitcode, and an output path that cannot be safely
  published.
- Intermediate files remain confined to a temporary work directory. A failed
  build does not replace an existing destination file.
- Tool diagnostics preserve the failing stage and command name without leaking
  build-machine paths into staged artifacts.
- Runtime ABI, target, or materialization failures use the focused diagnostics
  of the Pure core and must leave the interpreter usable.

## Packaging Boundaries

The Windows package manifest declares runtime and developer payloads
separately. The default selection installs only the runtime component. Staging
validation rejects:

- the legacy native bridge or `faust.dll`;
- `faust.pure` or `pure.cpp` as advertised Windows runtime inputs;
- `msys-2.0.dll` or another undeclared MSYS2 payload;
- undeclared compilers or LLVM tools; and
- absolute build, source, or host-tool paths embedded in the staged package.

The component definition is owned by TODO-44. The final installer UI and
cross-package component integration remain owned by TODO-49.

## Verification

Focused validation covers:

1. Importing `faust2` from a staged runtime-only layout.
2. Loading the prebuilt fixture, checking its channel counts, initializing it,
   processing a fixed signal buffer, comparing exact expected output, and
   cleaning it up.
3. Regenerating and verifying the fixture with only the optional developer
   component installed, then repeating the runtime test.
4. Comparing Faust 2.85.9 generated symbols, sample-format metadata, target
   metadata, channel counts, and deterministic output with the TODO-11 ABI
   contract; a mismatch blocks packaging rather than weakening the contract.
5. Running both configurations from an installation path containing spaces and
   with a sanitized `PATH`.
6. Confirming that the runtime-only configuration neither invokes nor requires
   Faust, Clang, LLVM utilities, or MSYS2.
7. Auditing the staged manifest for the forbidden files and paths listed above.

The runtime-only and runtime-plus-developer checks run on a clean Windows VM.
Repository-level focused tests run after each implementation milestone, and
the final validation records exact commands and results in TODO-44.

## Acceptance

TODO-44 is ready to close when the default Windows installation can run the
deterministic prebuilt DSP through `faust2`, the optional developer component
can reproducibly rebuild and run it, both paths work without MSYS2 or host
toolchain leakage, and the staged manifest contains no legacy Windows bridge.
