# Windows pure-gl Audit Hardening Design

## Purpose

Reopen the evidence behind `TODO-35-windows-pure-gl.md` and make the Windows
`pure-gl` package claim reproducible. A clean Windows CI job must prove the
build, noninteractive OpenGL behavior, package ownership, third-party origin,
source release completeness, and native dependency closure without relying on
an ambient MSYS2 runtime environment.

## Current gaps

The 2026-07 implementation builds and manually validates a useful package, but
its checks are not durable release contracts:

- `pure-gl` is absent from the non-Linux workflow path filters and job steps.
- Build-tree Pure tests prepend their module directory to the inherited
  `PATH`; a passing test can therefore depend on undeclared MSYS2 DLLs.
- The installed-package verifier is a manually invoked script. It checks that
  26 paths exist, but accepts extra package files, altered interfaces and
  documentation, pre-existing collisions, and changes elsewhere in the
  portable prefix.
- FreeGLUT is found through ambient `MSYSTEM_PREFIX`; its DLL and license are
  not tied to one explicit, canonical CLANG64 prefix and known source hashes.
- PE validation checks selected imports and forbidden name fragments rather
  than an exact, recursive, path-resolved import graph.
- The public `make dist` archive omits the CMake build, Windows documentation,
  and test inputs needed to reproduce the Windows package.
- Test success is inferred from process status and empty stderr rather than an
  authenticated completion record owned by a supervising native process.

## Selected approach

Adopt the strict contract pattern already used by the audited `pure-glpk`,
`pure-audio`, and `pure-midi` packages, scaled to the smaller `pure-gl`
surface. Configuration records every external tool, runtime prefix, system
directory, and package input explicitly. Small native helpers supervise Pure
processes and filesystem-sensitive operations where CMake script mode cannot
provide sufficient Windows process and path guarantees. Registered negative
contracts demonstrate rejection of each formerly permissive case.

A CI-only patch was rejected because it would repeatedly execute weak tests.
A minimal verifier patch was rejected because it would leave source releases
and CI disconnected from the package claim.

## Build and configuration contract

The Windows build will require explicit absolute regular-file paths for
`pure.exe`, `llvm-readobj.exe`, `llvm-strings.exe`, `pkg-config.exe`, and GNU
`make`, plus explicit canonical directories for the staged Pure prefix,
CLANG64 FreeGLUT prefix, and Windows system directory. Tool discovery may
provide user-friendly defaults only outside strict audit mode; CI and contract
tests enable strict mode and prove that missing, directory-valued, aliased, or
wrong-prefix inputs fail configuration.

The module remains one AMD64 `pure-gl.dll` built from the seven existing
wrapper families with Clang, C11, `-Wall -Wextra -Werror`, native
`opengl32`/`glu32`, and CLANG64 FreeGLUT. The configure contract freezes the
identity of package sources and external runtime/license inputs so a later
mutation cannot silently change installation output.

## Hermetic execution contract

All automated Pure tests run through one bounded Windows supervisor. Its
inputs are explicit: Pure executable, test script, seven interface files,
module, FreeGLUT runtime, include/library directories, working directory,
allowed runtime directories, timeout, and a unique completion token. It clears
`PURELIB`, builds `PATH` solely from the staged Pure runtime, the package
runtime, and Windows system directories, captures stdout and stderr, kills the
complete child process tree on timeout, and rejects any output not conforming
to the expected completion protocol.

The load test continues to cover representative constants from all seven
wrapper families. The hidden-render test must create and hide a 32x32 RGBA
window, validate nonempty vendor/renderer/version strings, clear and read a
known pixel, check OpenGL errors at meaningful boundaries, destroy the window,
and emit the authenticated completion record. Tests must not require desktop
interaction and retain nested supervisor and CTest deadlines.

The visible triangle test remains opt-in. It uses the same supervisor and
explicit environment but is never registered as an ordinary CTest. Its
documented purpose is a human-observable desktop check, not evidence required
from headless CI.

## PE dependency contract

The verifier starts from the staged `pure-gl.dll` and `libfreeglut.dll`, parses
every normal PE import reported by the pinned `llvm-readobj`, and recursively
resolves non-system imports to explicit allowed roots. It rejects missing,
ambiguous, wrong-root, non-AMD64, reparse-point, MSYS/GNU-runtime, and
unreviewed dependencies. Windows system imports resolve only through the
explicit Windows system directory and are never package payloads.

For the pinned CI package versions, each audited binary has a complete,
normalized expected import set. A fixture contract proves rejection of both
an injected unexpected import and an omitted required import, including useful
expected/actual/missing/unexpected diagnostics, then reruns the pristine case.

## Installation and ownership contract

Installation is defined by a sealed inventory. Every runtime and documentation
file records component, relative destination, canonical source, SHA-256,
project/version/source URL/license identity, and the installed license mapping.
The FreeGLUT DLL must come from the explicit CLANG64 prefix and match the pinned
FreeGLUT package hash; its notice must come from the corresponding FreeGLUT
license path and match its own pinned hash.

The install contract begins with a separately built canonical portable Pure
prefix. It snapshots every relative path, type, size, and file hash, rejects
reparse points and case-folded duplicate destinations, installs runtime and
documentation as disjoint components, and requires the final tree to equal the
unchanged baseline plus the exact declared `pure-gl` delta. Tests cover an
extra owned file, a collision, altered installed bytes, wrong runtime/license
origins, and a change outside historical package globs.

Installed load and hidden-render tests run under the hermetic supervisor from
a working directory outside the source and build trees. Afterwards the exact
recursive staged PE audit is repeated and the prefix snapshot must be
unchanged, proving that tests create no package residue.

System OpenGL, GLU, GDI, User32, and WinMM binaries are explicitly forbidden
from the package delta. The documentation will distinguish these operating
system dependencies from the bundled FreeGLUT runtime.

## Source distribution contract

`make dist` will include `CMakeLists.txt`, all `cmake/` helpers and native
helper sources, `WINDOWS.md`, `THIRD_PARTY.md`, the three Pure tests, and all
existing package sources and examples. The archive contract runs the public
recipe from a source path containing spaces, validates an exact archive
inventory and source hashes, removes access to checkout-only driver inputs,
and configures/builds the extracted tree with explicit dependencies. Symlink,
missing-file, extra-file, and stale generated-input cases fail.

The legacy `clean`, `realclean`, `generate`, `dist`, and `distcheck` deletion
paths receive the same Windows-safe ownership guards used in recent package
audits: fixed internally derived child paths, sentinel validation, no reparse
components or protected descendants, and no expansion from an empty DLL
suffix. Negative probes must be non-destructive and followed by a pristine
positive run.

## CI integration

The existing Windows 2025 job will install the CLANG64 FreeGLUT and GNU make
prerequisites and add `pure-gl/**`, this design, its implementation plan, and
`TODO-35-windows-pure-gl.md` to both push and pull-request path filters. A
dedicated sequence will:

1. configure a fresh strict Release tree from a path containing spaces;
2. build with exactly four workers;
3. run the exact recursive PE target;
4. run every noninteractive `gl`-label CTest under a sanitized parent
   environment;
5. verify the public source distribution independently;
6. create a fresh portable Pure baseline and install both package components;
7. run the complete installed-package verifier; and
8. retain logs needed to diagnose any failed contract.

The repository workflow validator will assert the presence and execution
semantics of these steps so YAML edits cannot silently bypass the package gate.

## Documentation and completion evidence

`WINDOWS.md` will list exact prerequisites, strict configuration inputs,
noninteractive and interactive commands, package contents, runtime search
policy, and the system-DLL exclusion. `THIRD_PARTY.md` will record the exact
FreeGLUT project/version/source/license mapping used by installation.

`TODO-35-windows-pure-gl.md` remains historically closed while implementation
is in progress. It gains a dated follow-up audit entry only after a fresh
strict build passes all registered contracts and a separate final portable
stage passes the installed verifier. The entry records tool/package versions,
test count and duration, exact owned-file count, audited PE count, and any
platform limitation discovered during validation.

## Acceptance criteria

- A fresh strict Windows Release build succeeds with four workers.
- Every registered noninteractive `gl` contract passes with `PURELIB` absent
  and no MSYS2 directory in the runtime `PATH`.
- The installed tree is byte-for-byte the canonical Pure baseline plus the
  sealed and disjoint `pure-gl` runtime/documentation delta.
- Both build-tree and installed tests prove authenticated bounded completion.
- The exact recursive AMD64 PE graph contains only reviewed staged,
  FreeGLUT-prefix, and Windows-system dependencies.
- FreeGLUT runtime and license provenance is pinned and cross-checked.
- The public source archive alone can reproduce the strict build and tests.
- Windows CI and its semantic validator make all of these checks mandatory.
- The visible desktop test remains available and bounded but optional.
