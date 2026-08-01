# TODO-51 Gnuplot Application Loader Domain Design

## Context

The sole production Task 3 stage v11 was created at
`C:\tmp\todo51-task3\stage-runtime-v11` and failed closed during the static
import audit:

```text
Missing effective import Qt6Core.dll needed by
C:\tmp\todo51-task3\stage-runtime-v11\pure\tools\gnuplot\bin\gnuplot_qt.exe
```

The dependency is not absent. The exact application directory contains
`Qt6Core.dll` (7,481,344 bytes, SHA-256
`7C9D615B82CE3971A05484D610DC4D920FD889525096F53A0820B1A150D89F6F`),
and it is byte-identical to the file in the accepted relocated Pure Gnuplot
source tree. The failure occurred because the current audit assigns every PE
below `pure` to the generic Pure loader domain and searches only `pure/bin`
before authoritative Windows system resolution.

Gnuplot is a separately managed Windows application tree. The Pure Gplot
bridge launches its exact `tools/gnuplot/bin/gnuplot.exe` path with
`CreateProcessW`; Windows consequently uses that executable's application
directory when resolving its private DLLs. A read-only audit of the exact v11
directory found 65 files, of which 63 are magic-byte PE files, and 1,002
import edges: 249 resolve in the same application directory, 563 are Windows
API-set contracts, 190 resolve in System32, and none are missing.

The approved design adds a narrow loader domain for this exact managed
directory. It does not add, remove, replace, or move any staged file. The
failed v11 tree remains preserved as evidence and is never reused.

## Loader-domain architecture

The stage audit recognizes the exact relative directory
`pure/tools/gnuplot/bin` as the `pure-gnuplot-app` loader domain. Classification
occurs before the generic Pure classification. Every regular, non-reparse,
magic-byte PE file directly in that directory belongs to the dedicated
domain; no similarly named or nested directory receives this treatment.

For a PE in `pure-gnuplot-app`, each non-system import resolves only through:

1. a case-insensitive filename match in the same exact
   `pure/tools/gnuplot/bin` directory;
2. authoritative Windows API-set mapping or System32 resolution.

The resolver never falls back to `pure/bin`, Octave's `mingw64/bin`, the
process `PATH`, the installed Gnuplot tree, or any other source or stage
directory. A dependency available only in one of those excluded locations is
missing for this domain and fails the audit. An unrelated file with the same
name outside the domain is ignored. The existing Pure, Octave, and explicit
bridge loader domains retain their current search rules.

This rule models the deployed launch boundary without generalizing
application-directory resolution to arbitrary nested executables. In
particular, `pure/tools/other/bin` and descendants of the Gnuplot directory do
not acquire a new loader domain.

## Domain contract and data flow

The assembler first verifies the complete staged inventory and reparse
policy, then classifies PE files into loader domains. The dedicated Gnuplot
domain is constructed only when the exact managed root is a regular,
non-reparse directory with the production-pinned contents.

For each Gnuplot PE, the import auditor parses direct imports and records each
edge as one of `application-directory`, `api-set`, or `system32`. Resolution
of an application-directory edge records the exact staged target. System
lookups continue to use the existing authoritative operating-system
mechanism, and every verification handle must be released.

The accepted production contract is exact:

- domain root: `pure/tools/gnuplot/bin`;
- total files in the root: 65;
- magic-byte PE files in the root: 63;
- audited import edges: 1,002;
- application-directory edges: 249;
- API-set edges: 563;
- System32 edges: 190;
- unresolved or cross-domain edges: zero.

These cardinalities are production postconditions, not discovery defaults or
caller overrides. The audit report identifies the dedicated domain and its
edge split so that a future Gnuplot update must be deliberately repinned and
reviewed.

## Stage invariants

Changing loader-domain interpretation must not change the deterministic stage
inventory. A successful next production stage remains hard-bound to:

- 64,312 files;
- 3,334,971,045 bytes;
- manifest SHA-256
  `115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`;
- 1,539 magic-byte PE files;
- 219 PE `.oct` modules;
- one separately pinned inert Qt documentation placeholder.

The accepted Pure and Octave source trees, the permanent Octave installation,
ACLs, profiles, and global environment remain unchanged. No staged binary is
executed while validating this static loader-domain correction.

## Failure handling

The assembler fails closed before runtime verification when any of the
following occurs:

- the exact Gnuplot root is absent, renamed, a reparse point, or replaced by a
  non-directory object;
- a file within the domain is a reparse point;
- a loadable-extension candidate is not a valid PE file;
- case-insensitive duplicate names or ambiguous targets exist in the domain;
- a non-system import is absent from the application directory, even if it is
  present in `pure/bin`, Octave, an installed tree, or `PATH`;
- an import attempts to cross into another loader domain;
- authoritative API-set or System32 resolution fails, is ambiguous, or leaks
  a verification handle;
- any Gnuplot domain or whole-stage production cardinality differs from its
  pinned value.

Failure preserves the new stage root and its invocation evidence. A failed
root is never repaired in place or retried.

## Test design

Implementation follows test-driven development. The first new regression
test reproduces the current failure by showing that the old generic Pure
domain cannot resolve `gnuplot_qt.exe -> Qt6Core.dll`. Subsequent tests prove:

- the exact application-directory dependency succeeds;
- all 63 production Gnuplot PE files close over exactly the pinned 1,002-edge
  split with no missing or cross-domain edge;
- a dependency present only in `pure/bin` fails;
- a dependency present only in Octave's `mingw64/bin` fails;
- process `PATH` and installed runtime files cannot satisfy an import;
- `pure/tools/other/bin` receives no dedicated-domain behavior;
- nested directories do not inherit the Gnuplot application domain;
- missing, extra, renamed, changed, duplicate-by-case, non-PE, or reparse
  content fails closed;
- API-set/System32 failure and verification-handle leaks fail closed;
- the existing staging regression suite remains green;
- the unchanged whole-stage inventory, manifest, PE, `.oct`, and placeholder
  postconditions remain exact.

Synthetic fixtures exercise negative cases without weakening production
pins. Production inputs, paths, hashes, cardinalities, and search domains
cannot be overridden through test parameters or hooks.

## Production continuation

After implementation, regression verification, and independent review, the
next production attempt uses the currently absent exact root
`C:\tmp\todo51-task3\stage-runtime-v12`. The full immutable-source preflight
runs first. The assembler then receives one production invocation with the
same pinned inputs and no synthetic or test overrides. A successful static
post-audit must prove both the dedicated Gnuplot contract and every unchanged
whole-stage invariant above.

Stage v11 remains preserved. If v12 fails, it is also preserved and execution
stops for a new root-cause analysis; it is not recycled. Only after v12 passes
does the original TODO-51 Task 3 resume with the strict AppContainer runtime,
legacy RED and strict GREEN write-confinement tests, canonicalization
regression, public embed probe, and basic bridge test.

## Rejected alternatives

- A general application-directory domain for every nested executable was
  rejected because it broadens trusted loader behavior beyond the observed
  Gnuplot boundary and could conceal cross-component dependency mistakes.
- Omitting optional Gnuplot was rejected because it would remove an already
  accepted Windows bundle component instead of auditing its actual launch
  semantics.
- Copying Qt DLLs into `pure/bin` was rejected because it changes the stage,
  merges independently managed runtime domains, and risks ambiguous Qt
  resolution.
