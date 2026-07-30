# TODO-51 Task 3 report

## Status

The version-scoped generated-header gate and the fail-closed Octave 11.3.0
libtool-metadata normalizer are implemented and independently verified.  The
normalizer has not yet been applied to the real disposable toolchain copy.
No permanent Octave file was used as an executable or modified.  All source,
build, and toolchain paths used by Task 3 are disposable children of
`C:\tmp\todo51-task3`.

The exact audited baseline of the copied toolchain is:

- files: 59,533
- bytes: 2,797,722,287
- sorted path/size/SHA-256 manifest SHA-256:
  `95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD`
- reparse points: 0

The permanent `C:\Tools\GNU Octave\11.3.0` tree was restored after the earlier
MSYS initialization and remains at the same exact baseline.

## Smallest reproducible build architecture

Octave 11.3.0's direct `liboctave/liboctave.la` target omits generated-header
prerequisites that the canonical aggregate build supplies indirectly.  The
accepted architecture is a version-scoped supplemental makefile,
`octave-11.3.0-task3-liboctave-generated.mk`, whose gate depends on Octave's
own `$(BUILT_INCS)` variable plus the independently generated
`octave-config.h` and `liboctave/version.h`.  It deliberately does not copy
Octave's generated-header inventory.

RED was captured before the supplemental makefile existed:

```text
make: C:\pure-lang\pure-octave\probes\octave-11.3.0-task3-liboctave-generated.mk: No such file or directory
make: *** No rule to make target ... Stop.
GATE_RED_EXIT=2
```

The GREEN gate used the copied GNU Make and completed with exit 0.  Its full
log is `C:\tmp\todo51-task3\generated-gate.log`:

- log bytes: 140,103
- log SHA-256:
  `B2E179867D45D3EDDD8534E95E40724FB871F1CE0A54F74A05C9991EDA81DDFD`
- diagnostics matching `warning:`, `error:`, or `fatal:`: 0
- paths escaping to permanent Octave or `C:\msys64`: 0

GNU Make expanded exactly 372 upstream `BUILT_INCS` entries, all unique.
Adding the two independent headers yielded exactly 374 unique regular files
under the disposable build root, with no rooted or `..` paths and no reparse
points:

- total bytes: 450,805
- sorted path/size/SHA-256 manifest SHA-256:
  `10C16F4BAD6E21EE11F1CC003E4C26CBF090D6DE862FB131F26A91EA50EBC224`
- `octave-config.h` SHA-256:
  `1AAD68F83BB8FADF32B59095CC725DBE82EDB555A668CB62A0CC1F2464A0C06B`
- `liboctave/version.h` SHA-256:
  `4AF5A8632A824C66273AE759821493FE4123A97F63CC5D11EEC0C29BDF80B31B`
- expected generated markers, include guards, and Octave version 11.3.0: pass

## Compiler-path diagnosis

The first direct build used copied Bash but inherited its default
`/usr/local/bin:/usr/bin:/bin:/opt/bin:...` path.  That omitted
`/mingw64/bin`.  A direct `cc1plus --version` therefore exited 127 because
`libzstd.dll` could not be found.

Prepending only the copied
`/c/tmp/todo51-task3/toolchain-root/mingw64/bin` made `cc1plus` exit 0.
Replaying the exact `CNDArray` compile with only that PATH change succeeded;
the resulting object SHA-256 was
`1638961FD9DFD033FBF6D148AB623C99F82F2FFBD6A1714F2E3C1E79A5F7DBFF`.

A fresh `C:\tmp\todo51-task3\build-path-fixed` configure used the exact PATH
`/mingw64/bin:/usr/bin`.  Its `gcc` and `g++` were 15.2, GNU Make was 4.4.1,
binutils were 2.45, and pkg-config was 0.29.2.  Every resolved tool was a
regular non-reparse file under the disposable copy.  Configure succeeded,
the generated tree and log had zero permanent-Octave or `C:\msys64` escapes,
and the generated-header gate again passed 372/374 with no diagnostic.

## Causal libtool failure

Only `make -j4 liboctave/liboctave.la` was invoked in the fresh path-fixed
build.  It compiled for about 21 minutes and then failed at the first link:

```text
/usr/bin/grep: /usr/lib/gcc/x86_64-w64-mingw32/15.2.0/libssp.la: No such file
```

The complete log is `C:\tmp\todo51-task3\liboctave-path-fixed.log`:

- log bytes: 2,336,189
- log SHA-256:
  `23937BFCF9B966B61BFD87040876AEFFC47DA49C99176275C2BD30E46848200F`
- active build processes after failure: 0

The copied `libstdc++.la` contains
`-L/usr/lib -L/usr/mingw/lib` and an absolute
`/usr/lib/gcc/x86_64-w64-mingw32/15.2.0/libssp.la` dependency.  Both
`g++ -print-file-name=libssp.la` and the corresponding import library resolve
correctly below the copied `mingw64` tree, so this is stale package metadata,
not a missing library.

The full copied-tree audit found:

- 214 `.la` files
- 214/214 containing `/usr/lib`; 1,020 occurrences
- 26 `/usr/mingw` and 6 `/usr/x86_64` occurrences
- 0 permanent-Octave-prefix occurrences
- 608 absolute `.la` references, 53 unique
- all 53 literal `/usr` references missing as written
- exactly one regular same-basename candidate below copied `mingw64` for
  every reference; 0 ambiguous and 0 absent
- 450 directory-metadata occurrences, 13 exact spellings
- 11 direct `/usr/...` to `/mingw64/...` mappings plus the audited anomalies
  `/usr//usr/lib` and `/usr/mingw/lib`

No existing Octave runtime, source, repository script, `post-install.bat`, or
`--enable-relocate-all` implementation normalizes these `.la` records.

## Fail-closed normalizer

`normalize_octave_11_3_libtool_metadata.ps1` is deliberately scoped to the
audited Octave 11.3.0 layout.  It:

- rejects the permanent Octave root before enumeration;
- requires the toolchain to be a strict child of an explicitly supplied
  disposable parent;
- rejects reparse points in the path and tree;
- requires the exact expected file count, byte count, and manifest SHA-256;
- accepts only ASCII libtool assignment and token forms exercised by the
  copied Octave metadata;
- maps only the 13 audited directory spellings;
- resolves absolute `.la` references only when exactly one regular copied
  candidate exists;
- rejects unknown, missing, ambiguous, quoted-unknown, and unsupported data;
- constructs and hashes the complete rewrite plan before writing;
- applies replacements transactionally with rollback backups outside the
  toolchain tree;
- verifies every changed-file hash, zero stale paths, and the exact predicted
  result manifest;
- reports an exact changed-file inventory; and
- supports write-free `Plan` mode and idempotent `Apply`.

The test harness first produced the intended RED because the normalizer did
not exist.  Intermediate GREEN runs exposed and fixed a PowerShell 5
one-element `Generic.List` conversion and a stale-path detector that initially
missed `-L/usr/...`.

The final command was:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  C:\pure-lang\pure-octave\probes\test_normalize_octave_11_3_libtool_metadata.ps1
```

It exited 0 with:

```text
PASS Test-SuccessAndAnomalies
PASS Test-AmbiguousCandidate
PASS Test-MissingCandidate
PASS Test-UnknownAbsolutePath
PASS Test-UnsupportedAssignment
PASS Test-UnsupportedQuoteForm
PASS Test-NonAsciiRejection
PASS Test-ReparseRejection
PASS Test-PermanentRootRejection
PASS Test-ManifestRejection
PASS Test-NoPartialWrites
PASS Test-PlanDoesNotWrite
PASS all 12 normalizer tests
```

Every negative mutation test compares the exact before/after tree-manifest
SHA-256 and file count.  The success test verifies both audited anomaly
mappings and unique candidate selection, then runs a second apply and requires
`ChangedFileCount = 0` with an unchanged exact manifest SHA-256.

## Next verified step

After this checkpoint is committed and independently reviewed, the next step
is a write-free `Plan` against the exact copied-toolchain baseline.  Only if
the complete 214-file audit and predicted inventory pass will one
transactional `Apply` be allowed.  A second dry run must be idempotent before
a new clean configure, generated-header gate, and the sole
`liboctave/liboctave.la` target are attempted.
