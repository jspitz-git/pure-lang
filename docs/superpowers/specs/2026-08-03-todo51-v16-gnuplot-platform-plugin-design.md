# TODO-51 v16 Gnuplot Qt Platform Plugin Design

> **Rejected on 2026-08-08.** Historical record only. Do not implement or
> resume this work without a new approved TODO.

## Goal

Create one new immutable Task 3 production-stage version that audits the two
bundled Qt platform plugins with their real Windows deployment semantics,
without broadening the existing Gnuplot application loader domain or changing
the staged payload.

## Root Cause

The accepted Pure runtime stores `Qt6Gui.dll`, `Qt6Core.dll`, and `libc++.dll`
directly in `pure/tools/gnuplot/bin`, while Qt platform plugins are correctly
stored in its `platforms` subdirectory. The current `Get-LoaderDomain`
implementation grants `pure-gnuplot-app` only to direct files under the
Gnuplot `bin` root. It therefore classifies
`platforms/qminimal.dll` and `platforms/qwindows.dll` as generic `pure` files
and tries to resolve their Qt imports from `pure/bin`. The v15 assembler fails
closed on the first such edge, `qminimal.dll -> Qt6Gui.dll`.

The synthetic Gnuplot fixture modeled only direct files and did not exercise
the real platform-plugin layout. This is an audit-model defect, not a missing
file in the accepted Gnuplot bundle.

## Architecture

Keep `pure-gnuplot-app` unchanged and restricted to regular magic-byte PE
files directly under the exact relative root `pure/tools/gnuplot/bin`.

Add a separate loader domain named `pure-gnuplot-platform-plugin`. Exactly two
stage-relative paths belong to it:

- `pure/tools/gnuplot/bin/platforms/qminimal.dll`
- `pure/tools/gnuplot/bin/platforms/qwindows.dll`

No other direct, sibling, similarly named, or nested path inherits this
domain. The allowlist is ordinal-ignore-case for lookup but must reject
ambiguous case-insensitive filesystem candidates and reparse points.

The effective loader set for this domain consists only of the regular direct
files in `pure/tools/gnuplot/bin`. Imports not found there may resolve only
through the existing authoritative Windows API-set and System32 mechanisms.
There is no fallback to `pure/bin`, `mingw64/bin`, the bridge union, process
`PATH`, an installed runtime, a sibling directory, or the plugin directory
itself.

## Pinned Production Contract

The existing direct Gnuplot contract remains unchanged: 65 direct regular
files, 63 direct PE files, and 1,002 direct-domain import edges split into 249
application-directory, 563 API-set, 190 System32, and zero unresolved edges.

The new platform-plugin contract is pinned independently:

- 2 regular PE files;
- 38 import edges;
- 6 Gnuplot application-directory edges;
- 15 API-set edges;
- 17 System32 edges;
- 0 unresolved edges.

For diagnostic aggregation only, the complete Gnuplot tree therefore has 65
audited PE files and 1,040 import edges split into 255 Gnuplot-root, 578
API-set, 207 System32, and zero unresolved edges. The independent direct and
plugin pins remain the authoritative postconditions.

The staged payload does not change. A successful v16 stage must retain the
accepted whole-stage contract of 64,312 files, 3,334,971,045 bytes, manifest
SHA-256 `115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`,
1,539 magic-byte PE files, 219 PE `.oct` modules, one pinned inert placeholder,
and three supplement files.

## Test Design

First extend the synthetic fixture to reproduce the real tree: put the exact
two plugin names below `platforms`, put their Qt/runtime dependencies only in
the direct Gnuplot root, and declare representative application-directory,
API-set, and System32 imports. Before the implementation change this test must
fail on `qminimal.dll -> Qt6Gui.dll`; after the change it must pass with the
exact plugin cardinalities.

Add fail-closed regressions for:

- any unapproved third PE plugin under `platforms`;
- a PE in another nested or sibling directory;
- a missing Gnuplot-root dependency;
- an ambiguous case-insensitive Gnuplot-root dependency;
- attempted fallback to Pure, Octave, bridge, `PATH`, or the plugin directory;
- a reparse plugin directory or file;
- every platform-plugin post-audit cardinality mismatch;
- every production-only test-injection surface.

Run the complete staging harness after the focused RED/GREEN cycle. The
existing direct-domain boundary tests must remain unchanged in meaning and
continue to pass.

## Immutable v16 Production Attempt

Preserve v15, its partial stage, logs, marker, and seven-field error JSON. Do
not enumerate, execute, recycle, clean, or retry the v15 stage.

Create distinct v16 wrapper, preflight, post-audit, stage, PID, stdout, stderr,
marker, and seven-field diagnostic JSON paths. Derive the production helpers
from reviewed predecessors and bind them to reviewed repository and helper
hashes, exact parameter surfaces, immutable input manifests, the serviced
Windows/API-set identity, and the new plugin contract.

Preflight, assembler, and post-audit may each launch at most once. Owners run
with explicit host permission. While the assembler is alive, polling is
limited to PID state, stdout/stderr lengths, and marker presence; the stage is
not inspected. Staged binaries are never executed.

On assembler failure, validate only the independent external evidence,
preserve the partial v16 stage, and stop without retry, post-audit, success
tests, cleanup, or success commit. On assembler success, run the independent
static post-audit, then the full supplement and staging harnesses and the
repository parser/diff gates before recording the verified production result.

## Commit Boundaries

Commit each verified repository step separately: the focused test and domain
implementation, the production pins and complete regression gate, the v16
helper/diagnostic gate, and the successful production report. A blocked
production attempt is documented but does not receive a success commit.

## Rejected Alternatives

Granting the Gnuplot domain to the entire `bin` subtree would allow future,
unreviewed nested PE files to inherit loader rights. Copying Qt DLLs into the
`platforms` directory would duplicate payload, change the accepted manifest,
and model neither the approved bundle nor the intended Qt deployment layout.
Removing platform plugins would reduce functionality and is unnecessary.
