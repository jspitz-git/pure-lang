# TODO-51 Task 3 report

## Status

The version-scoped generated-header gate and the fail-closed Octave 11.3.0
libtool-metadata normalizer are implemented.  Independent review rounds 1,
2, and 3 identified confinement, postcondition, manifest, and closure-scope
gaps; each now has isolated RED/GREEN coverage.  A final write-free `Plan`
against the pristine disposable toolchain copy passed every exact contract.
The separately authorized transactional `Apply` has now been performed only
on the pristine disposable toolchain copy, then independently audited below.
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
- rejects `\\?\`, `\\.\`, volume-GUID, UNC, and every other non-local
  drive-letter DOS spelling before filesystem access;
- requires the toolchain to be a strict child of an explicitly supplied
  disposable parent;
- rejects reparse points in the path and tree;
- performs all lexical, local-drive, permanent-path, strict-child, existence,
  and basic reparse validation before compiling its filesystem-identity
  helper;
- compiles that helper with `TEMP`, `TMP`, and `TMPDIR` temporarily redirected
  to one exact unique directory below the validated disposable parent,
  restores the original process environment in `finally`, and removes the
  exact compiler directory fail-closed;
- resolves the root through an open directory handle, compares volume/file
  identity and final DOS path against the permanent root, holds the root
  handle without delete sharing, and rechecks the identity before every write
  and after the replacement phase;
- requires the exact expected file count, byte count, and manifest SHA-256;
- accepts only ASCII libtool assignment and token forms exercised by the
  copied Octave metadata;
- requires a hashed, strict CRLF, role-tagged `.la` selection manifest below
  the disposable parent and outside the toolchain;
- requires a second hashed seed-library manifest, whose ordered 34-token
  contents must equal the built-in Octave 11.3.0 `LIBOCTAVE_LINK_DEPS`
  contract outside synthetic tests;
- normalizes only the selected transitive closure and proves all unselected
  `.la` files remain byte-identical;
- resolves libraries only through six explicit version-scoped search
  directories, never ambient `PATH`;
- maps only the 13 audited directory spellings;
- resolves absolute `.la` references only when exactly one regular copied
  candidate exists;
- rejects unknown, missing, ambiguous, quoted-unknown, and unsupported data;
- constructs and hashes the complete rewrite plan before writing;
- applies replacements transactionally with rollback backups outside the
  toolchain tree;
- verifies every unique emitted `-L`, `-R`, `libdir`, and `.la` target before
  and after replacement for containment, type, existence, reparse points, and
  final resolved path;
- verifies every changed-file hash, zero stale paths, stable root identity,
  and the exact predicted result manifest;
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
PASS Test-NamespaceRejection
PASS Test-NegativePathSkipsHelperCompilation
PASS Test-CompilerTempConfinementAndCleanup
PASS Test-RootIdentityGuard
PASS Test-RollbackBeforeSecondReplacement
PASS Test-EmittedTargetPostcondition
PASS Test-FailureInjectionScope
PASS Test-ManifestRejection
PASS Test-NoPartialWrites
PASS Test-PlanDoesNotWrite
PASS all 19 normalizer tests
```

Every negative mutation test compares the exact before/after tree-manifest
SHA-256 and file count.  The success test verifies both audited anomaly
mappings and unique candidate selection, then runs a second apply and requires
`ChangedFileCount = 0` with an unchanged exact manifest SHA-256.

## Independent-review fix round 1

All review RED and GREEN runs used the same full command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  C:\pure-lang\pure-octave\probes\test_normalize_octave_11_3_libtool_metadata.ps1
```

### Filesystem namespace and stable identity

The first RED run exited 1 because a permanent-tree spelling using
`\\?\C:\Tools\GNU Octave\11.3.0` with an equivalently aliased parent reached a
later failure instead of the lexical namespace guard:

```text
FAIL Test-NamespaceRejection
Namespaced path was not rejected lexically: \\?\C:\Tools\GNU Octave\11.3.0
```

The GREEN implementation rejects all four reviewed spelling classes before
enumeration and establishes a stable volume/file identity plus final DOS path
from held handles.  A separate identity-mismatch RED initially exposed a
broken rollback call: .NET rejected a null backup-path argument and retained
the transaction directory.  The atomic rollback now uses an explicit discard
file, and the identity test verifies exact restored file count, byte count,
manifest SHA-256, and zero transaction directories.

### Deterministic rollback after the first replacement

The dedicated RED exited 1 because the requested failure before replacement
2 was not yet implemented:

```text
FAIL Test-RollbackBeforeSecondReplacement
Expected normalization failure.
```

The test-only hook is accepted solely below a parent whose resolved path is
exactly `C:\tmp\todo51-normalizer-tests-<32 hex digits>`.  It fails before the
second replacement, after the first replacement has completed.  GREEN proves
that the original file count, total bytes, and manifest SHA-256 are restored
and that the transaction directory is absent.  `Test-FailureInjectionScope`
also proves that the hook is rejected before writes on a non-test disposable
root.

### Emitted-target postcondition

The emitted-target RED exited 1 because removing a planned emitted directory
after replacement did not make Apply fail:

```text
FAIL Test-EmittedTargetPostcondition
Expected normalization failure.
```

GREEN collects every unique directory and `.la` target from the complete
result text of every changed archive, not only from the rewritten line.  It
validates targets both before and after replacement, revalidates every write
destination immediately before `File.Replace`, detects the injected missing
directory, restores it, rolls back the archives byte-for-byte, and removes all
transaction state.

## Independent-review fix round 2

Review found that the inline C# filesystem-identity helper was compiled before
disposable-path validation.  Windows PowerShell 5.1 may write `Add-Type`
compiler artifacts through the process `TEMP`/`TMP`, so a rejected invocation
could write outside Task 3 confinement.

The RED used the standard full harness command shown above.  It set `TEMP`,
`TMP`, and `TMPDIR` to an external poison file and invoked a `\\?\` permanent
path:

```text
FAIL Test-NegativePathSkipsHelperCompilation
Helper compilation ran before negative path rejection.
```

The implementation now keeps the C# source as inert text until pure PowerShell
has verified:

- local drive-letter DOS spelling for root and parent;
- lexical exclusion of the permanent Octave root;
- existence and strict root-under-parent containment;
- parent containment strictly below `C:\tmp`; and
- absence of reparse points in every path component and the toolchain tree.

Only then does it create
`<validated-parent>\.todo51-add-type-<32 hex digits>`, save the exact process
values of `TEMP`, `TMP`, and `TMPDIR`, redirect all three for `Add-Type`,
restore them in `finally`, validate the exact cleanup target, and recursively
remove only that target.  Environment snapshots record both `WasPresent` and
`Value`, so an unset variable remains distinct from a present empty variable.
Failure to restore either presence/value or to clean is fatal.

`Test-NegativePathSkipsHelperCompilation` proves that rejected namespace paths
do not consult the poisoned compiler environment.  The separate
`Test-CompilerTempConfinementAndCleanup` verifies:

- the external poison directory's exact file count, byte count, and manifest
  SHA-256 remain unchanged;
- the reported compiler-temp path is an exact unique child of the synthetic
  disposable parent;
- process compiler variables are restored before normalization continues;
- mixed inherited state (`TEMP` set, `TMP` present-empty, `TMPDIR` unset) is
  restored with the exact original presence and value;
- no `.todo51-add-type-*` directory remains after successful compilation; and
- a test-scoped failure immediately after temp creation also restores the
  environment and leaves zero helper-temp directories.

The final fix-round-2 harness run exited 0:

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
PASS Test-NamespaceRejection
PASS Test-NegativePathSkipsHelperCompilation
PASS Test-CompilerTempConfinementAndCleanup
PASS Test-RootIdentityGuard
PASS Test-RollbackBeforeSecondReplacement
PASS Test-EmittedTargetPostcondition
PASS Test-FailureInjectionScope
PASS Test-ManifestRejection
PASS Test-NoPartialWrites
PASS Test-PlanDoesNotWrite
PASS all 19 normalizer tests
```

## Independent-review fix round 3

### Established manifest and pristine input

The established baseline contained zero-byte files.  The first exact-manifest
RED exposed both PowerShell 5.1's empty-array parameter binding and a format
mistake: the established manifest used PowerShell enumeration order and CRLF,
while the initial implementation assumed ordinal sorting and LF.  The
normalizer now declares `PowerShellTsvV1` explicitly and requires a separate
hashed three-field order reference.  Its path set must equal the current tree,
each record is strict UTF-8 without BOM and CRLF-terminated, and missing,
extra, duplicate, unsafe, reordered, or hash-changed references fail before
writes.

An earlier disposable `toolchain-root` had five MSYS scratch-path records in
`libbfd.la` and the `libctf*.la` family, so it was rejected as contaminated.
The final Plan used only
`C:\tmp\todo51-task3\toolchain-normalize-pristine`.  An independent post-Plan
rehash in the established reference order confirmed the unchanged exact
baseline:

- files: 59,533
- bytes: 2,797,722,287
- manifest SHA-256:
  `95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD`

### Selection and transitive closure

A broad 214-file Plan failed closed on the five scratch records and on a real
`libiberty` dependency that has no copied library candidate.  The accepted
scope is therefore the exact metadata closure of the nine external `.la`
roots used by `liboctave`, not every unrelated archive shipped in the
toolchain.

The disposable role-tagged selection manifest has 22 unique records (nine
`root`, thirteen `dependency`) and SHA-256
`590987916CCF773D1ADAC0C663A5C2D442A4F7743C816BF663D98420E0591514`.
Outside synthetic tests the implementation additionally requires the exact
nine version-scoped root paths, exactly 22 selected files, and an exact
30-edge transitive closure.  Explicit `.la` references and recursively found
`-l` tokens must resolve uniquely through the six audited directories.
Missing, extra, duplicate, escaping, reparse, ambiguous, and unreachable
selection entries all fail before writes.  Cycles terminate through a visited
set.

The exact ordered Octave 11.3.0 seed contract contains 34 unique library
tokens.  Its disposable strict-CRLF manifest SHA-256 is
`EBFE170E0DD3A1C1C9AE3DCE47B996BF7E054BB3F6DB945FDDFCE3999730B270`.
The same ordered allowlist is versioned in the normalizer and compared
record-by-record in non-synthetic mode.  Its selected `.la` resolutions must
equal the nine declared roots exactly.  Unioning these seed tokens with the
recursive closure must yield exactly 44 unique and 44 resolved `-l` tokens.

The selection/seed TDD sequence recorded:

- RED: 27/27 existing tests failed because the new manifest parameters did
  not yet exist;
- intermediate GREEN: 22/28, then 26/28 and 27/28, exposing validation-order
  and prefixless synthetic-fixture assumptions;
- final GREEN: 28/28, including unrelated scratch bytes unchanged, selected
  scratch and escape rejection, missing/extra/duplicate selection rejection,
  recursive `-l`, cycles, unique resolution, and missing/extra/changed/hash-
  changed seed plus root-resolution mismatch rejection.

Every negative case runs `Apply` against a synthetic fixture, compares its
exact before/after inventory, and proves zero retained transaction
directories.  The final full harness output ended with:

```text
PASS Test-SeedLibraryContractRejections
PASS Test-PlanDoesNotWrite
PASS all 28 normalizer tests
```

### Final real write-free Plan

The final process exited 0 with empty stderr and `Mode = Plan`:

- selection: 22 files, nine roots, 192 unselected archives
- seed libraries: 34
- closure edges: 30
- unique/resolved `-l` tokens: 44/44
- audited search directories: six
- changed-file prediction: exactly 22 files
- baseline: 59,533 files, 2,797,722,287 bytes,
  `95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD`
- predicted result: 59,533 files, 2,797,722,565 bytes,
  `9417DC1DC935E33ACADACA3A0AD86389F500B937F7670E3D177A8D58B3C68CED`
- stdout: 9,869 bytes, SHA-256
  `734416EABBBDB693F1A53D736158839E8CB687B8EE0AC9DC9726F4D223404CEA`
- stderr: zero bytes, SHA-256
  `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`
- retained helper directories: zero
- retained transaction directories: zero

Independent checks prove that the 22 predicted changed paths equal the
selection exactly with no duplicates, no selected scratch or `libiberty`
path, and that all 192 unselected `.la` hashes still match the pristine
reference.  The full 59,533-file post-Plan rehash also reproduced the exact
baseline above.  No `Apply` invocation occurred.

## Selected-closure Apply, idempotence, and independent audit

The only real Apply used the established strict-CRLF baseline order reference,
the 22-record role-tagged selection, and the 34-token seed contract against
`C:\tmp\todo51-task3\toolchain-normalize-pristine`.  Its retained JSON reports
exactly 22 changed files and the exact result:

- files: 59,533
- bytes: 2,797,722,565
- ordered path/size/SHA-256 manifest SHA-256:
  `9417DC1DC935E33ACADACA3A0AD86389F500B937F7670E3D177A8D58B3C68CED`

The retained evidence hashes are:

- `normalizer-apply-selected.stdout.json`: 9,870 bytes,
  `8709CFA082F28EF8D2C60F29D2E86E8C963A32B919C9D9DCFE99873BB538138F`
- `normalizer-apply-selected.stderr.log`: 0 bytes,
  `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`
- `normalizer-idempotence-plan.stdout.json`: 2,079 bytes,
  `6CEE19EC051D986700ADBA26C3A30AC9B0744C43975724BE265A6D6E4CDA1074`
- `normalizer-idempotence-plan.stderr.log`: 0 bytes,
  `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`
- `normalizer-idempotence-apply.stdout.json`: 2,080 bytes,
  `FA3FD0315B4B32B68A0C3FD860D83DCAE8A268E978B5C576A64006912428AF59`
- `normalizer-idempotence-apply.stderr.log`: 0 bytes,
  `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`

The subsequent retained `Plan` and `Apply` idempotence JSONs both report
`ChangedFileCount = 0` and the same
`59,533 / 2,797,722,565 / 9417DC1DC935E33ACADACA3A0AD86389F500B937F7670E3D177A8D58B3C68CED`
result.  All three stderr files are empty.

An independent, read-only audit rehashed every file in the exact baseline TSV
order.  It reproduced the result manifest above; the 22 differing paths equal
the selection manifest exactly, every selected file matches the first Apply
JSON's reported new SHA-256, and all 192 unselected `.la` files remain
byte-identical to the baseline.  The 22 selected files contain zero stale
`/usr`, permanent-Octave, Task-3 scratch, or `libiberty` references.  All 18
unique emitted directory and `.la` targets exist and are non-reparse.  The
normalized tree has zero reparse points, zero extra paths, and zero retained
`.todo51-add-type-*` or `.todo51-la-normalize-*` helper/transaction
directories.

The permanent `C:\Tools\GNU Octave\11.3.0` tree was separately rehashed in
the same 59,533-record baseline order after Apply.  It remains exactly
`59,533 / 2,797,722,287 /
95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD`,
with zero baseline record mismatches and zero reparse points.  No permanent
toolchain path was written during this Apply/audit checkpoint.

## Next verified step

After this report-only checkpoint is independently reviewed, a fresh,
separately authorized clean configure, generated-header gate, and sole
`liboctave/liboctave.la` target may use the normalized disposable toolchain.

## Confined liboctave build checkpoint

The initial fresh normalized configure was retained as RED evidence: its
`config.log` recorded 113 compiler intermediates in MSYS user temp.  MSYS
maps `/tmp` to the user temp mount.  A minimal copied GCC/G++ probe confirmed
that setting process-local `TEMP`, `TMP`, and `TMPDIR` to a validated
disposable Windows directory confines all temporary paths and cleans them.

Fresh `build-normalized-confined` and `build-temp-confined` roots were then
configured with those three variables set. Configure exited 0; all 113
compiler temporary paths resolved below the confined directory, with zero
residual files/reparse points. Config, Makefile, and logs had zero user-temp,
permanent-Octave, or global-msys paths.

The generated-header gate exited 0 with 372 unique `BUILT_INCS` and 374
unique present regular non-reparse files. The sole build command,
`make -j4 liboctave/liboctave.la`, exited 0. Its complete log is 2,355,813
bytes, SHA-256 `842678BFBBC560B4258EE15920C1E36B030D334B2B8BC948C6768CA6613E3608`.
There were zero error/fatal diagnostics and 13 `warning:` diagnostics: eight
accepted old-style C-cast warnings from the shared helper header, three from
`oct-sysdep`, one from `unistd-wrappers`, and one `setlocale.c`
discarded-const warning.  The helper header is deliberately C-compatible but
is compiled in a C++ context, so its C-style casts trigger those eight
nonfatal warnings; their strict C/C++ behavior is already covered by the
Task 2 behavior matrix.

The x86-64 PE `liboctave-13.dll` is 283,425,385 bytes, SHA-256
`A10BBD461B628379F02CF87E059F89C2F4485F69D88AD2C51466E8789DAF2663`; its
import library is 12,671,822 bytes, SHA-256
`A34F1B10250412439366306BCCC2A3B4C4C745B4E8315ABB57709577417B6065`.
The compiled `file-ops.o` contains canonicalization entry points and strings
for `pure_windows_system_volume_canonical_path` and the shared helper header.

Effective future resolution is staged `bin` plus System32. All 19 non-system
imports resolve uniquely in normalized `mingw64\bin`. The canonical staged
`libgcc_s_seh-1.dll` SHA-256 is
`592E6966F66D7993726D3CE329E81B658188E5CB286ACE9DE56C2FAB939EA491`.
The distinct global `mingw64\lib\gcc` duplicate
`C01AC5BFCCDC91BCE10CDA45075D73E6E0964440FC3673C2DD2A63B0BE2D4699` is
outside that search and must not be staged. No DLL was run, installed, or
staged. Confined temp and build processes were empty at completion. Final
post-build normalized-toolchain rehash compared all 59,533 records with the
pre-build normalized capture: `59,533 / 2,797,722,565`, zero differences,
and zero reparse points. This preserves the independently established
normalized manifest `9417DC1DC935E33ACADACA3A0AD86389F500B937F7670E3D177A8D58B3C68CED`.
Final permanent Octave rehash remained `59,533 / 2,797,722,287 /
95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD`, with
zero baseline differences and zero reparse points.

## Staged runtime checkpoint

The disposable v5 stage was assembled without running a staged executable:
`64,309 / 3,327,729,829 / E142C07EDA4D71184D1892189834818B9DCE7AD44B8F0A6708A51C54FA56476F`.
Its patched `mingw64/bin/liboctave-13.dll` is `A10BBD461B628379F02CF87E059F89C2F4485F69D88AD2C51466E8789DAF2663`; canonical
`libgcc_s_seh-1.dll` is `592E6966F66D7993726D3CE329E81B658188E5CB286ACE9DE56C2FAB939EA491`.
The static import audit completed with no ordinary missing/ambiguous import and zero reparse entries. Pure and Octave keep separate loader directories; bridge imports are audited against their explicit union. API-set contracts are separately recorded for Windows 10.0.26200.0 with regular `apisetschema.dll` SHA-256 `8FFADF5FF3D8D3843FC393E9D03C2091AC5DDFC6227B8097DC182E2A8F8463FC`; their runtime binding is deferred to the later loader gate. The normalized/Pure/bridge/module sources were fully hashed before and after copy. v1-v4 remain untouched for explicit later cleanup.

## Static staging independent-review fix round 1

This round was code, test, and report only. It did not create a new real
stage, run a staged executable, change an ACL/AppContainer/profile, delete any
retained stage, or mutate a permanent/source runtime root. The accepted
checkpoint under repair was commit `bf2756e1`; its small uncommitted hardening
diff was preserved and completed.

### RED and versioned synthetic fixture

The expanded harness was written first and run against the accepted staging
implementation. The first regression group exited 1 before any stage write
because the production script had no exact Pure-inventory contract:

```text
A parameter cannot be found that matches parameter name
'ExpectedPureFileCount'.
```

The final test fixture is permitted only at an exact
`C:\tmp\todo51-stage-tests-<32 lowercase hex>\parent` root. Its Pure,
bridge, patched-DLL, libgcc, module, probe, and build-evidence contents have
versioned literal hashes and inventories in the assembler; caller-supplied
expectations must equal those literals. `TestMode` therefore does not skip
closure logic or redefine accepted inputs. It injects only two external tool
boundaries: the static-import result for every detected synthetic PE and the
authoritative OS contract-to-host mapping. Both injected manifests must be
regular non-reparse files strictly inside that exact fixture.

### Immutable production inputs and provenance

Non-test staging now rejects every caller override that differs from the
versioned checkpoint. It binds the exact permanent, normalized, Pure,
repository bridge, bridge-binary, probe, patched-artifact, objdump, snapshot,
and idempotence-evidence paths. The approved copied inputs are:

- Pure: `4,769 / 260,533,868 /
  52DA19745D9F33DEC4CEAF09E24E3836C04E82E1651BB695990D18B14D667FE3`;
- bridge binaries: `2 / 4,771,866 /
  974C07999D4EBC62C218F0EDA7D271B6CCC7AFDEBD1EBFA063C7A25109C4CE11`;
- bridge module: `51A4FADE279C91CB63103EFD7A0A97FB1DF9E674F807A7E0BF65991D6E6066F0`;
- embed probe: `8924A6A2FC79FB1C0F0B97248014079D685D1724C1708523FE08240CA87424A5`;
- `basic.pure`: `23C378107498CF605C4777132C817CDAE6D090306007F0E67A83CCD4D726346D`;
- `RunEmbedProbe.cmake`: `73BEE376A8D2A23897D9FBA85277F5B59439C45BE442300B43AC63388F003DCB`;
- `RunPureTest.cmake`: `A45618D605CB6B70F6D5008351731F786F7C3D97CF0537A4BEFC47DEF2BA08CB`.

The patched DLL is production-hard-bound to
`A10BBD461B628379F02CF87E059F89C2F4485F69D88AD2C51466E8789DAF2663`;
the canonical loader libgcc remains hard-bound to
`592E6966F66D7993726D3CE329E81B658188E5CB286ACE9DE56C2FAB939EA491`.
The confined build log, artifact audit, and patched-object audit are now
required at their exact retained paths with respective SHA-256 values
`842678BFBBC560B4258EE15920C1E36B030D334B2B8BC948C6768CA6613E3608`,
`C56E0746AA0673447F6BD64117772BEC9D450321C53F508A96352818F7EB964C`,
and `DFB6BA01DCDDCBDDEDA4FAA278556284F68C89B2AA79E417FDDFDA463893B9F0`.
The accepted patch and shared header are also path- and hash-bound.

`BridgeRoot` is now the repository provenance boundary containing
`BridgeModuleSource`; the distinct `BridgeBinaryRoot` is the exact audited
two-DLL build output. Every copy helper asserts its source against an explicit
provenance root. The permanent root, repository root, every repository
test-script source, patched artifact, evidence file, and copied tree are
checked for reparse traversal. Source manifests and individual hashes are
rechecked after staging.

The unsafe Pure/bridge merge path and opt-in separate-root switch no longer
exist. Pure stays below `pure\bin`, Octave below `mingw64\bin`, and bridge
imports are resolved only against their explicit union. The final pre-audit
stage is required to equal the accepted v5 postcondition exactly:
`64,309 / 3,327,729,829 /
E142C07EDA4D71184D1892189834818B9DCE7AD44B8F0A6708A51C54FA56476F`.

### Complete PE and API-set audit

A read-only magic-byte census of retained v5 opened each file only as data.
It found 1,536 PE files. The previous three top-level-directory audit had
records for 536 unique PEs; 1,000 PEs were outside that scope, including all
219 `.oct` modules. The hardened assembler discovers every `MZ` PE anywhere
in the staged tree and invokes only the trusted external objdump on each file.
It never executes a staged file. Missing and ambiguous ordinary imports fail
closed under the Pure, Octave, or explicit bridge-union loader set.

API/ext lookalikes must first match the strict contract grammar. Production
then uses `LoadLibraryExW(LOAD_LIBRARY_SEARCH_SYSTEM32)`, obtains the exact
host through `GetModuleFileNameW`, proves that host is a regular non-reparse
System32 file, hashes it, records contract/host/hash, and calls `FreeLibrary`
for every successful load. Resolver compilation has `TEMP`, `TMP`, and
`TMPDIR` confined to a unique temporary child of the stage and restores the
process environment before deleting that exact child.

A separate read-only resolver check against the retained 16-contract v5 list
mapped all 16 and freed every handle. There were two unique hosts:
`KERNELBASE.dll` SHA-256
`8E8499FC4750EBC487A30CD07DC7DB635BA6DBE9B66F83EC695A5AF70B71C07C`
and `ucrtbase.dll` SHA-256
`5E7709A6B71BB818260B6F05C5BB3B6CA0C3CA9BC2F58C6242C1CD9D826D0079`.
The bound OS/schema evidence remained Windows `10.0.26200.0` and
`apisetschema.dll`
`8FFADF5FF3D8D3843FC393E9D03C2091AC5DDFC6227B8097DC182E2A8F8463FC`.

### GREEN

The fresh full command was:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  C:\pure-lang\pure-octave\probes\test_stage_task3_runtime.ps1
```

It exited 0 in 14,043 ms:

```text
PASS Test-SuccessUsesSeparateLoaderRootsAndAuditsImports
PASS Test-RejectsUnsafeTestModeFixture
PASS Test-RejectsUnsafeLoaderOverride
PASS Test-RejectsCallerControlledProductionEvidence
PASS Test-BindsExactProductionEvidencePath
PASS Test-BindsExactInputInventory
PASS Test-RejectsMissingImport
PASS Test-RejectsBridgeUnionCollision
PASS Test-RecordsAuthoritativeApiSetMapping
PASS Test-RejectsUnknownApiSetLookalike
PASS Test-AuditsLoadablePeOutsideBin
PASS Test-RejectsBridgeModuleOutsideBridgeRoot
PASS Test-RejectsSameLengthSameMtimeContentChange
PASS Test-RejectsExistingStage
PASS Test-RejectsPermanentOctaveRoot
PASS Test-RejectsReparseParent
PASS all task3 staging tests
```

## Static staging independent-review fix round 2: pinned inert Qt placeholder

This round was code, test, and report only. It did not create a real stage,
execute a staged binary, change an ACL/AppContainer/profile, delete v1-v8, or
mutate a permanent or source runtime root.

### v8 fail-closed root cause and RED

The v8 assembler correctly stopped at
`stage_task3_runtime.ps1:565`, but its generic extension guard classified the
Qt documentation-tool packaging placeholder
`mingw64/qt6/bin/qhelpgenerator.exe` as a loadable executable solely from its
`.exe` suffix. A read-only comparison found that the permanent Octave tree,
normalized source, and v8 stage all contain the same regular zero-byte file
with SHA-256
`E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`.
It is the only zero-length `.exe`, `.dll`, or `.oct` in the normalized source;
it is a Qt documentation packaging placeholder, not a PE image and cannot be
loaded or executed.

The minimal regression first added only that exact zero-byte path to the
existing guarded synthetic fixture and ran the full harness against the
pre-fix assembler. It exited 1 at the intended guard:

```text
Success fixture failed: Staged loadable file does not contain a PE image:
...\mingw64\qt6\bin\qhelpgenerator.exe
```

### GREEN and retained fail-closed scope

The production assembler now hard-binds exactly one inert artifact: the
literal relative path above, length zero, and the exact empty-file SHA-256.
It validates that record in both the normalized source and copied stage,
records it in `stage-pinned-inert-placeholders.tsv`, and excludes only that
exact verified artifact from the PE-import loop. There is no production
caller parameter for placeholder approval; an attempted caller override is
rejected at parameter binding. The final content inventory/hash contract is
unchanged because the separately generated report is excluded alongside the
pre-existing generated stage reports.

Production audit cardinality is explicit and fail-closed: `1,535` magic-byte
PE files are import-audited plus `1` pinned inert placeholder, and all `219`
`.oct` files are among the audited PEs. Every other non-PE `.exe`, `.dll`,
`.oct`, `.mex`, or `.mexw64` still fails at the generic guard; there is no
broad extension exemption.

The fresh full command was:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  C:\pure-lang\pure-octave\probes\test_stage_task3_runtime.ps1
```

It exited 0 in 20.2 seconds:

```text
PASS Test-AcceptsAndRecordsPinnedInertQtDocumentationPlaceholder
PASS Test-RejectsCallerControlledPinnedPlaceholderApproval
PASS Test-RejectsNonzeroOrWrongHashPinnedPlaceholder
PASS Test-RejectsAllOtherNonPeLoadableExtensionsAndSameNameElsewhere
PASS Test-RejectsUnsafeTestModeFixture
PASS Test-RejectsUnsafeLoaderOverride
PASS Test-RejectsCallerControlledProductionEvidence
PASS Test-BindsExactProductionEvidencePath
PASS Test-BindsExactInputInventory
PASS Test-RejectsMissingImport
PASS Test-RejectsBridgeUnionCollision
PASS Test-RecordsAuthoritativeApiSetMapping
PASS Test-RejectsUnknownApiSetLookalike
PASS Test-AuditsLoadablePeOutsideBin
PASS Test-RejectsBridgeModuleOutsideBridgeRoot
PASS Test-RejectsSameLengthSameMtimeContentChange
PASS Test-RejectsExistingStage
PASS Test-RejectsPermanentOctaveRoot
PASS Test-RejectsReparseParent
PASS all task3 staging tests
```

The final PowerShell parser check of `stage_task3_runtime.ps1` and
`git diff --check` both exited 0. Static self-review confirmed that the
exception is keyed by the exact verified relative path rather than filename or
extension, that it is unavailable to production callers, and that all other
magic-byte PEs remain on the existing audit path.
