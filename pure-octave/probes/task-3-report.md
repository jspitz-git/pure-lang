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

## v9 production staging attempt: fail-closed cardinality blocker

The v6-v8 RED lineage, including the v8 inert-placeholder cardinality failure,
is recorded above.  Using accepted assembler commit `af82904f`, a new literal
hashtable wrapper was created only for the absent disposable target
`C:\tmp\todo51-task3\stage-runtime-v9` and its v9 exit marker.  Before the
single hidden invocation, the wrapper parsed cleanly; its decoded JSON had the
exact required 16 keys exactly once; every key resolved through the assembler
parameter metadata; and it contained neither `TestMode` nor hook text.  The
wrapper SHA-256 was
`7D0D51C9997E86E0088CBB7667799CD7483D4C2335C3217E28BD2B0899DDD5F8`; the
assembler SHA-256 was
`3F7458A3E1C237D21CBCCD3D974FCCA6C3B50FF952CB102621957049511C871A`.
The v9 target and marker were absent, and all parents, sources, and evidence
were regular/non-reparse (zero source-tree reparse points).

The permanent Octave preflight rehash was exact:
`59,533 / 2,797,722,287 /
95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD`, with
zero record mismatches and zero reparse points.

The one permitted hidden assembler process (PID 18188) was polled only through
its PID, redirected logs, and exit marker; no in-progress stage inspection and
no staged executable invocation occurred.  It eventually exited `1`, wrote a
zero-byte stdout log and a 424-byte stderr log, and recorded exit marker `1`.
The exact fail-closed blocker was the production static import cardinality
guard: it found `1,536` magic-byte PE files rather than the approved `1,535`,
while still finding the required one pinned inert placeholder and all `219`
PE `.oct` modules.  Consequently no post-audit, runtime execution, ACL,
AppContainer, profile, or source/permanent-tree mutation was performed.  The
partially created v9 stage and all prior retained stages/evidence are
preserved for diagnosis; this is explicitly not a successful staging
checkpoint and no success commit is made.

## v9 cardinality correction: 1,536 PE + 1 inert placeholder

The v9 fail-closed section above is preserved as the failed production
checkpoint. Its read-only whole-tree census established the root cause of the
prior hard-bound `1,535` count: the magic-byte count already excluded the
single pinned zero-byte Qt placeholder, so the earlier calculation subtracted
that placeholder a second time. The correct disjoint count is `791` `.dll` +
`492` `.exe` + `34` `.mex` + `219` `.oct` = `1,536` PE files, plus the one
separately pinned inert `mingw64/qt6/bin/qhelpgenerator.exe` placeholder.

The focused regression was added first and run against the prior production
constant. It exited 1 with:

```text
Production static-import contract must hard-bind 1,536 PE + 1 pinned inert
placeholder + 219 .oct files.
```

The minimal production correction changes only the approved PE cardinality and
the corresponding fail-closed diagnostic to `1,536`; the one-placeholder and
219-`.oct` guards, exact placeholder pin, and every other audit guard remain
unchanged. No new real stage was created, no staged executable was run, and no
ACL, AppContainer, profile, permanent tree, or source tree was mutated.

The final fresh full harness command exited 0 in 21.3 seconds and began with:

```text
PASS Test-HardBindsProductionAuditCardinalityTo1536PePlusOnePlaceholderAnd219Oct
PASS Test-AcceptsAndRecordsPinnedInertQtDocumentationPlaceholder
PASS Test-RejectsCallerControlledPinnedPlaceholderApproval
PASS Test-RejectsNonzeroOrWrongHashPinnedPlaceholder
PASS Test-RejectsAllOtherNonPeLoadableExtensionsAndSameNameElsewhere
PASS all task3 staging tests
```

PowerShell parsing of both staging scripts and `git diff --check` also exited
0. Static self-review confirmed the change is limited to the PE cardinality
literal and matching diagnostic, that the preserved v9 evidence is unchanged,
and that the placeholder and `.oct` guards are unchanged.

## v10 production staging attempt: fail-closed missing Pure-side import

Using independently accepted assembler commit `9179b092` (assembler SHA-256
`8BC7F35DE60F2790E69FA78B876FDB834F97C904BC78DC75DBF73D9C69EA5E9F`), a
literal-hashtable wrapper was created only for the absent disposable target
`C:\tmp\todo51-task3\stage-runtime-v10` and its v10 exit marker. Its own
SHA-256 was `19076B111315E311636FC8C9699F97647378CF9634B58EDE5FAF70C70F66CCA8`.
The decoded parameter JSON SHA-256 was
`7600FDD6A591FD19369DD1303CF13D8D64DB5E5B08F93A11322C2CE5BC88FF31`; it
contained the required 16 keys exactly once, every key was recognized by the
assembler, and it exposed neither `TestMode` nor hooks. The target and marker
were absent, and the disposable parent, inputs, evidence, and source trees
were regular/non-reparse before launch.

The read-only permanent-Octave preflight reproduced exactly
`59,533 / 2,797,722,287 /
95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD`, with
zero permanent or source-tree reparse points. The sole hidden assembler
invocation (PID 18860) was polled only through its PID, redirected logs, and
exit marker; no in-progress stage contents or staged binary were inspected or
executed.

It exited `1`, with a zero-byte stdout log, a 686-byte stderr log, and marker
`1`. The exact fail-closed blocker was:

```text
Missing effective import librsvg-2-2.dll needed by
C:\tmp\todo51-task3\stage-runtime-v10\pure\lib\gdk-pixbuf-2.0\2.10.0\loaders\pixbufloader_svg.dll
```

The partially created v10 stage is retained unchanged for diagnosis. No
post-success stage audit, staged execution, ACL/AppContainer/profile action,
or success commit was performed. A fresh 20-test staging harness passed in
20.3 seconds; PowerShell parsing of the assembler, harness, and v10 wrapper
passed; and `git diff --check` was clean before recording this failure.

## Immutable Pure SVG supplement v1 checkpoint

TDD RED was observed before either new artifact existed. The exact command
`& .\pure-octave\probes\test_prepare_task3_pure_rsvg_supplement.ps1` exited 1
at the harness gate with `TDD RED: preparer does not exist` for
`prepare_task3_pure_rsvg_supplement.ps1`. After implementation, the same
command passed five exact fail-closed cases (inexact set, SHA-256 mismatch,
unresolved import, reparse parent, and existing snapshot), exact Plan,
transactional rollback, real synthetic Apply, and idempotent Plan. The
injected post-first-copy failure left both final and `.tmp` roots absent and
all three source hashes unchanged; the exact synthetic root was removed.

Immediately before production Apply, the fixed v1 snapshot, its `.tmp`
sibling, and the contract `.tmp` sibling were absent. Every component of the
source, Pure, v5-manifest, objdump, snapshot-parent, and contract paths was
non-reparse. Production Plan accepted manifest SHA-256
`E142C07EDA4D71184D1892189834818B9DCE7AD44B8F0A6708A51C54FA56476F`
and predicted exactly `64,312 / 3,334,971,045 /
115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`,
with `1,539 / 219 / 1` audited PE, PE `.oct`, and pinned-placeholder counts.
The read-only permanent preflight matched all 59,533 snapshot records,
2,797,722,287 bytes, zero mismatches, zero reparse points, and approved
snapshot SHA-256
`95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD`.

The sole production command was:

```powershell
& pwsh.exe -NoProfile -NonInteractive -File '.\pure-octave\probes\prepare_task3_pure_rsvg_supplement.ps1' -SourceBin 'C:\msys64\clang64\bin' -PureRoot 'C:\tmp\Relocated Pure Gplot Final Bundle 20260729' -AcceptedStageManifest 'C:\tmp\todo51-task3\stage-runtime-v5\stage-manifest.tsv' -SnapshotRoot 'C:\tmp\todo51-task3\pure-rsvg-supplement-v1' -ContractOutput 'C:\pure-lang\pure-octave\probes\task3-pure-rsvg-supplement-contract.psd1' -Mode Apply
```

It exited 0. Captured stdout was 104,984 bytes with SHA-256
`33AD5491161499A73082B80516586F1303A9910278A1AE8204A7BE13B46F7FF6`;
stderr was zero bytes with SHA-256
`E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`.
The generated contract SHA-256 was
`692341FA19E6D7AC3CF4C02894DBDB92AFAE7A5DD154B659A5CFD099AD63F2CC`.
Its immutable snapshot manifest, in exact order, is:

```text
librsvg-2-2.dll  5882880  9F90DE3779E80F590B542AFDF79C105A403B0C566265D69EACBBF9B524338F89  pei-x86-64
libunwind.dll       63488  60FA3C200899BC6E4A5876B82E2C656FF72FC53EC55979D99CB7C4EF640A6D96  pei-x86-64
libxml2-16.dll    1294848  C6C34A810D86C19C034A1BC96C4C500BDE8FB789DED69B434E67EEE773605852  pei-x86-64
```

The recursive audit resolved 517 import edges: 429 system, 86 accepted-Pure,
and two supplement edges, with zero unresolved edges. The root non-system
edges were `librsvg-2-2.dll -> libcairo-2.dll, libgdk_pixbuf-2.0-0.dll,
libgio-2.0-0.dll, libglib-2.0-0.dll, libgobject-2.0-0.dll,
libpango-1.0-0.dll, libpangocairo-1.0-0.dll` from accepted Pure,
`librsvg-2-2.dll -> libunwind.dll, libxml2-16.dll` from the supplement, and
`libxml2-16.dll -> libiconv-2.dll, zlib1.dll` from accepted Pure. The hashed
stdout above records every transitive edge. All 38 Pure-provided closure
members were compared with their clang64 counterparts by length and SHA-256;
all matched byte-for-byte, including `libiconv-2.dll` and `zlib1.dll`.

After Apply, the three source DLLs retained the preflight lengths and hashes
shown in the snapshot manifest. The full permanent audit again returned
59,533 / 2,797,722,287 with zero mismatches and reparse points and the same
approved snapshot hash. Production Plan then reported `Changes = 0`. The v1
snapshot contains exactly three files / 7,241,216 bytes; its `.tmp` sibling,
the contract `.tmp` sibling, and the synthetic fixture root are absent. No
real stage was created, no staged binary was inspected or run, v1-v10 evidence
was not deleted, and no ACL, AppContainer, profile, accepted-Pure, permanent
Octave, or source-tree mutation was performed.

### Independent-review remediation

Independent read-only review of `69fd2160..b7522757` found no Critical issues
and two Important fail-closed gaps. TDD regressions were added before their
fixes. A fabricated but syntactically valid API-set name was initially trusted
by prefix, and Plan initially ignored an extra nested snapshot directory. The
test assertion helper was also corrected so absence of an expected exception
cannot satisfy `Assert-Throws`; the API-set regression then produced genuine
RED before production changed.

System imports are now resolved only to regular, non-reparse files under the
authoritative local `System32`: API-set names require strict contract syntax
and successful `LoadLibraryExW` mapping, with the returned handle always freed.
Plan now inventories every top-level snapshot child and rejects directories,
reparse points, nested content, or any other contaminant before reporting zero
changes. Focused re-review also required rejection of truncated
`GetModuleFileNameW` output and failed `FreeLibrary`; both are now checked,
module release failure is a guarded synthetic regression, and the handle
lifecycle no longer returns from inside its release-protected block. The fresh
harness passes eleven named cases with no warning/error noise.

A post-review production Plan against the immutable v1 snapshot exited 0 with
`Changes = 0`, re-resolved all 517 import edges, and placed all 429 system
edges under `C:\Windows\System32` with zero outside hosts. Its captured stdout
was 107,633 bytes / SHA-256
`9AC8D2F152F8DBDD8A8620579AEE9279CF7EC229F495559EA8F4F6BD2DE8C27D`;
stderr remained zero bytes / SHA-256
`E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`.
The real snapshot, contract, accepted inputs, and permanent/source baselines
were not modified by this read-only remediation audit.

## Pinned Pure SVG staging integration checkpoint

Task 2 followed strict TDD. Seven named staging regressions were present before
production changed. The unchanged assembler exited 1 at the new success fixture
with `Missing effective import librsvg-2-2.dll needed by` the exact staged
`pure/lib/gdk-pixbuf-2.0/2.10.0/loaders/pixbufloader_svg.dll`. After integration,
the full harness passed 27 named checks (the prior 20 plus seven) and its final
aggregate PASS. The independent supplement-preparer harness retained all 15
named PASS checks and its aggregate PASS.

The assembler now imports only the fixed sibling
`task3-pure-rsvg-supplement-contract.psd1`, whose approved SHA-256 is
`692341FA19E6D7AC3CF4C02894DBDB92AFAE7A5DD154B659A5CFD099AD63F2CC`.
There is no caller supplement path, contract, hash, count, or manifest
override. It fail-closes on any contract schema, exact pin, root, 38-member
reuse closure, or fixed-arithmetic mismatch. Before the first stage write, it
validates the immutable snapshot and original `C:\msys64\clang64\bin` copies
by exact file set, length, SHA-256, non-reparse status, and x86-64 PE machine.

Exactly `librsvg-2-2.dll`, `libunwind.dll`, and `libxml2-16.dll` are copied
through the tracked-copy mechanism to `stage/pure/bin`, with collision and
mapping-identity checks. Both snapshot and original-source pins are rehashed
after copying and after the full audit. The full-tree PE audit requires every
supplement DLL exactly once in the Pure loader group and the SVG loader edge to
resolve uniquely to `stage/pure/bin/librsvg-2-2.dll`. Pure/Octave loader
separation, authoritative API-set handling, bridge collision rejection, 219
`.oct` files, and the single pinned inert Qt placeholder remain unconditional.

Production postconditions are hard-bound to 64,312 files / 3,334,971,045
bytes / `115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`,
with 1,539 audited PE files, 219 PE `.oct` files, and one inert placeholder.
Negative coverage rejects missing/extra supplement files, hash/machine change,
reparse/source substitution, destination collision, tracked mapping mismatch,
a fourth transitive dependency, schema/arithmetic change, and a caller root
argument. All test-only injections remain within the existing exact GUID
synthetic-root gate.

Fresh parser checks for the assembler and staging harness and `git diff
--check` exited 0. Fresh read-only hashes showed all three real snapshot and
clang64 source DLLs unchanged. No real stage was created or inspected; no
staged binary was executed; and no ACL, AppContainer, profile, accepted-Pure,
permanent-Octave, normalized-toolchain, patched-artifact, immutable-snapshot,
or v1-v10 evidence mutation occurred.

## v11 supplemented production staging attempt: fail-closed Qt import

Task 3 selected only the exact absent root
`C:\tmp\todo51-task3\stage-runtime-v11`. A literal 16-key hashtable wrapper
was validated through `Get-Command`; it contained no `TestMode`, synthetic,
injection, or hook key. Wrapper, assembler, contract, and decoded-parameter
JSON SHA-256 values were respectively
`FF6B21D3AF1C87E31AC9D9705F75809D0A18D0A55FA5692D8EED9E89CCA1160F`,
`3C9DB35270340A2E39601C0CFA54DD23D7472A8509D7F160441FE6DEC2A32163`,
`692341FA19E6D7AC3CF4C02894DBDB92AFAE7A5DD154B659A5CFD099AD63F2CC`,
and `F751F7EC214F30FEE5117AA07D750AE51F6B487B06B454F2A91A46F1F242B8BB`.

The exact pwsh 7.6.4 bootstrap and final hidden read-only preflight both
completed with marker 0, one JSON object, and empty stderr. The full preflight
reproduced the immutable permanent, normalized, accepted-Pure, bridge, patched
liboctave, canonical libgcc, accepted-v5, supplement snapshot/source, 38-member
reuse-closure, repository-test, build-evidence, and authoritative API-set pins.
Its stdout was 1,361 bytes / SHA-256
`91E9A366C952BE51EB6A019052D15DE3E890BFB4E7ED657BFF677FFD7A610936`;
stderr was empty. The target and assembler marker were absent immediately
before launch.

The one permitted hidden assembler invocation (PID 31864) was polled only
through PID, separate stdout/stderr logs, and its exit marker. No in-progress
stage file was inspected and no staged binary was executed. It ended with
marker `1`, zero-byte stdout / SHA-256
`E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`,
and 387-byte stderr / SHA-256
`9DA403FD36B841C2779FF88D7D86AA267DB0AAA709B6D0D2EBCE31A517B3B2B2`.
The exact blocker was:

```text
Missing effective import Qt6Core.dll needed by
C:\tmp\todo51-task3\stage-runtime-v11\pure\tools\gnuplot\bin\gnuplot_qt.exe
```

The partial v11 stage is preserved. Per the reviewed failure policy there was
no retry, implicit v12 selection, post-success static audit, regression suite,
runtime execution, cleanup, or success commit. No ACL/AppContainer/profile,
accepted-Pure, permanent-Octave, normalized-toolchain, supplement, or v1-v10
evidence mutation was performed. The plan requires amendment before another
stage version can be selected.


## Tasks 1-2 Gnuplot loader-domain diagnosis and contract

The preserved v11 attempt remains the decisive fail-closed production evidence.
Its only assembler invocation ended at the exact unresolved edge
`gnuplot_qt.exe -> Qt6Core.dll` under
`pure/tools/gnuplot/bin`; marker 1, stdout/stderr identities, wrapper hashes,
and the preserved partial-stage policy remain recorded above. Tasks 1-2 did
not retry v11 or select another stage version.

The prior reviewed read-only diagnosis established that the exact preserved
v11 Gnuplot application directory contains 65 direct files, of which 63 are PE
members. Those 63 members expose 1,002 static import edges: 249 resolve inside
that same application directory, 563 resolve through authoritative API-set
contracts, 190 resolve through ordinary System32 names, and zero are missing.
The three resolved origins sum exactly to 1,002. The required application
member is `Qt6Core.dll`, 7,481,344 bytes, SHA-256
`7C9D615B82CE3971A05484D610DC4D920FD889525096F53A0820B1A150D89F6F`;
the preserved v11 copy is byte-identical to the accepted relocated Pure
Gnuplot source copy. This identity was established by that prior read-only
diagnosis; Tasks 1-2 did not reopen either preserved root to derive it.

Task 1 introduced the exact direct-file `pure-gnuplot-app` loader domain,
case-insensitive collision rejection, non-reparse direct-member validation,
and application-directory-only effective set. Its negative tests continue to
reject fallback into Pure, Octave, PATH, sibling directories, and nested
directories, as well as case collisions, non-PE loadable files, and reparse
roots or members.

Task 2 hard-binds the non-overridable production root
`pure/tools/gnuplot/bin` and exact `65 / 63 / 1,002 / 249 / 563 / 190 / 0`
file, PE, total-edge, application-directory, API-set, System32, and unresolved
cardinalities. `Assert-GnuplotLoaderPostconditions` checks all seven values
and the origin-sum invariant. The existing final JSON now reports the seven
`GnuplotLoader*` fields. `stage-import-closure.tsv` remains the per-edge
evidence; no new staged report file or other inventory member was added, so
the existing 64,312-file final manifest contract is unchanged.

The expanded two-PE synthetic fixture records exactly
`2 / 2 / 3 / 1 / 1 / 1 / 0` and exercises Qt6Core application-directory,
mapped API-set, and explicit ordinary System32 origins. Seven guarded
post-audit mutations each fail their matching postcondition. Additional
negatives reject an unknown Gnuplot API-set contract, a manifest-unlisted
ordinary System32 DLL, and an injected API-set release failure with
`API-set contract mapping could not be freed`. Both new switches are
TestMode-only and production rejects them before input validation.

TDD RED was observed before production changes. The full staging harness
exited 1 after the existing audit-cardinality test with:

```text
Production Gnuplot loader contract omits exact literal assignment:
$acceptedGnuplotRelativeRoot = 'pure/tools/gnuplot/bin'
```

After the minimal implementation, fresh GREEN verification completed with
`PASS all supplement preparer tests` (15/15) and
`PASS all task3 staging tests` (43 named tests). Both changed PowerShell
scripts parsed with zero errors and `git diff --check` exited 0.

The repository-owned verification used only exact GUID TestMode roots under
`C:\tmp`. No new production stage was created or inspected, and no staged
binary was executed in either Task 1 or Task 2. Accepted-Pure,
permanent-Octave, normalized-toolchain, supplement snapshot/source, patched
artifact, bridge, probe, immutable-snapshot, ACL/AppContainer/profile, and
v1-v11 evidence roots were not modified; the pre-existing source and inventory
evidence remains unchanged.

### Final Task 2 review ruling

Two independent read-only reviews found no Critical or Important issue. The
three suggested minor points were adjudicated against the production source.
The unresolved production pin already had an exact literal source assertion,
so no change was required for that suggestion. The resolver concern was
confirmed: its production catch incremented the unresolved counter for every
API-set exception, including path-read and release failures. A focused
source-contract regression first exited 1 with `Production Gnuplot API-set
accounting must count only missing or cross-domain resolution failures as
unresolved edges.` The catch now increments only for no authoritative local
OS mapping, a host escaping System32, or a missing mapped host; path-read,
release, and reparse failures still abort but are not reclassified as missing
edges. The combined production-injection PASS label was also renamed to cover
case-collision, post-audit, and API-set-release switches accurately.

After that remediation, the full staging harness exited 0 with all 43 named
checks and `PASS all task3 staging tests`; the supplement harness exited 0
with 15/15 and `PASS all supplement preparer tests`. Both changed PowerShell
scripts parsed with zero errors, `git diff --check` exited 0, and the worktree
contained exactly the three authorized Task 2 files with no added inventory
file. The existing no-stage and no-staged-execution statement above remains
unchanged.

## v12 production preflight: BLOCKED by changed API-set schema identity

Task 3 began from exact `e06d904bbc4bef5a304f669859283970cda70be8`
with a clean worktree. Preserved v11 was present, all 23 selected v12
target/evidence/helper paths were absent, the disposable parent was a regular
non-reparse directory, and the permanent Octave, accepted Pure, normalized
Octave, bridge-binary, SVG-supplement snapshot, and clang64 source-bin roots
were reparse-free before either v12 helper was created.

The new wrapper is the literal v11 wrapper with only the v12 exit-marker and
stage-root values changed. Its SHA-256 is
`26B519558047D0E79A22E3FF83B81D8E10A6E3CBF2C321B0612723EFA766F9F2`.
`Get-Command` accepted all 16 literal bound keys; the decoded parameter JSON
SHA-256 is
`A7C2DAC8F284EB48B68A90DBC91BED72232509AC9F263D99D03DC9C586B17C8F`.
The wrapper and preflight parsed with zero errors, and the wrapper contained no
`TestMode`, synthetic, injection, hook, or inventory-override surface. The v12
preflight SHA-256 is
`DE4646ECF9624894D5199F085DCB3B86D14CA3ED6E00542EA64959AD10A02862`.
It retained the reviewed v11 checks, changed only v11-owned names, replaced the
assembler pin with
`466092C4AAC99E7342D17938B0238BB01B8981DF067594667191ED397E6C35C9`,
and added fresh literal repository pins for the preparer
(`95382BEB41DCBAAF4925494455A03A603E4898670967C3C8E8713CC0A3404950`),
preparer harness
(`4D94E1BDE1F73678CC0040F544540C6825CD464766FE0EDC890CDD5EFF1E2793`),
and staging harness
(`3A118AD04C31288448E450D4016C0E4259B99254A39CEB3381B17E95006612FF`).

The full preflight ran hidden under exact PowerShell 7.6.4 at
`C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe`,
SHA-256
`DB6DD81183FE57D22E03B911EC9A30A2FD7C40542E97743615355A6FB44F458F`,
as PID 6248. It started at `2026-08-01T11:16:08.5015190Z` and wrote its
marker at `2026-08-01T12:07:02.2976952Z`. The PID file is 6 bytes / SHA-256
`B5A7E7F51E88215DAB9273B9E1BC1F5F572C85DDDDBE75749D1A0FC06C36D0CA`.
The exit marker is `1`, 3 bytes / SHA-256
`F1B2F662800122BED0FF255693DF89C4487FBDCF453D3524A42D4EC20C3D9C04`.
Stdout is empty, 0 bytes / SHA-256
`E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`.
Stderr is 287 bytes / SHA-256
`2F82EE30C8B44DEFFBC99E45BC6CEC1AACBFB3917BE1F11AD643E41B23F1802A`.
The exact terminating error is:

```text
Exception: C:\tmp\todo51-task3\stage_v12_preflight_audit.ps1:240
Authoritative API-set baseline mismatch.
```

The reported OS identity still equals the pin,
`Microsoft Windows NT 10.0.26200.0`, but the current regular
`C:\WINDOWS\System32\apisetschema.dll` is 194,048 bytes / SHA-256
`E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8`,
not the reviewed immutable pin
`8FFADF5FF3D8D3843FC393E9D03C2091AC5DDFC6227B8097DC182E2A8F8463FC`.

The preflight therefore failed closed before the production gate. The v12
stage root is absent, all assembler PID/stdout/stderr/marker paths are absent,
and the assembler launch count is zero. Preserved v11 and all v12 helper and
preflight evidence remain in place. Per the no-recycle rule there was no
preflight retry, assembler launch, staged-binary inspection or execution,
static post-audit, regression harness, success review, cleanup, or commit.

## Task 1: serviced Windows platform identity repin

Read-only root-cause evidence identifies a Windows servicing transition rather
than source, stage, supplement, or loader-domain corruption. The previously
accepted WinSxS API-set component was `10.0.26100.8521`, 194,040 bytes,
SHA-256
`8FFADF5FF3D8D3843FC393E9D03C2091AC5DDFC6227B8097DC182E2A8F8463FC`.
The current System32 hard link resolves to WinSxS component
`10.0.26100.8972`, 194,048 bytes, SHA-256
`E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8`.
The System32 and WinSxS paths are byte-identical hard links, and the current
component has a valid Authenticode signature from Microsoft Windows. The
coarse OS string remained `Microsoft Windows NT 10.0.26200.0` while the
registry reports `CurrentBuild = 26200` as `String` and `UBR = 8973` as
`DWord`; relevant updates were installed on 2026-07-31 and 2026-08-01.

The accepted production identity is now exactly:

- OS version `Microsoft Windows NT 10.0.26200.0`;
- CurrentBuild `26200` / `String`, UBR `8973` / `DWord`;
- canonical `C:\WINDOWS\System32\apisetschema.dll`, regular and non-reparse;
- file version `10.0.26100.8972 (WinBuild.160101.0800)`;
- product version `10.0.26100.8972`;
- length 194,048;
- SHA-256
  `E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8`.

`Get-WindowsPlatformIdentity` reads this complete production identity and
disposes the Windows CurrentVersion registry handle in `finally`.
`Assert-PlatformIdentity` checks every string ordinally and both numeric
fields numerically before import resolution. TestMode instead validates its
exact disposable `synthetic-system32\apisetschema.dll` leaf and constructs
a separate fixed synthetic identity; it never reads production registry
metadata. Final JSON now records all eight platform fields. The existing
`stage-api-set-contracts.tsv` format still uses the observed OS string,
canonical schema path, and observed hash, remains excluded from the manifest,
and no staged evidence file was added.

TDD RED was observed with staging harness exit 1 at
`Test-HardBindsWindowsPlatformIdentityContract`:

```text
Production platform identity contract omits exact literal assignment:
$acceptedCurrentBuild = '26200'
```

GREEN then emitted all four new platform PASS markers and the final
`PASS all task3 staging tests` sentinel: 47/47 named staging tests, comprising
the existing 43 plus four platform-identity tests. The exact synthetic success
identity reached the eight JSON fields. All 14 fixed faults failed with their
field-specific errors, including missing/wrong-kind registry fields,
outside-System32, reparse, and non-regular schema cases. A no-TestMode
`OsVersion` injection failed before input validation with
`Platform identity fault injection is TestMode-only and has no production
access.`; source-contract inspection also found no parameter beginning with
`ExpectedWindows`, `ExpectedUbr`, `ExpectedCurrentBuild`, or
`ExpectedApiSet`.

The focused supplement harness passed 15/15 and emitted
`PASS all supplement preparer tests`. Both changed PowerShell files parsed
with zero errors and `git diff --check` exited 0. The final stage pins remain
64,312 files / 3,334,971,045 bytes / manifest
`115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`,
with 1,539 PE files, 219 PE `.oct` modules, and one inert placeholder. The
Gnuplot loader contract remains `65 / 63 / 1002 / 249 / 563 / 190 / 0`.

Task 1 did not perform production staging or start any staged binary. The
assembler launch count remains zero, `C:\tmp\todo51-task3\stage-runtime-v12`
remains absent, and all preserved v11/v12 helpers, logs, markers, and evidence
remain unchanged.

## v13 production preflight launch: BLOCKED by restricted evidence write

Task 2 began from exact `16b0391dd7e4ac300c90f414e1891e6f5d4e2947`
on branch `todo/51-windows-strict-write-confinement` with a clean worktree.
The precreation audit required all 16 literal v13 target/helper/PID/log/marker
paths to be absent, preserved v11 to exist, the v12 stage root to remain
absent, and the disposable/permanent/Pure/normalized/bridge/probe/patched/
supplement/clang64 roots to contain zero reparse points. All assertions
passed before any v13 helper was created.

The three new static helpers are preserved outside Git:

- wrapper: 2,380 bytes / SHA-256
  `67FDE491EAD1ACE3394DAB454E4B8A6F6CCA9AAF2D5FA30A3A7220999FE715D7`;
- preflight: 21,025 bytes / SHA-256
  `4AA13A140EC1F1D6171802066C92FE64FE2DB93EAB556E9B57A0EF58C3883FFE`;
- post-audit: 18,765 bytes / SHA-256
  `3819645916A1F2418C9F1262F3EF120CB71B6040A689DECFB65D14183D0ACA65`.

All three parsed with zero errors. The wrapper is byte-for-byte equal to the
v12 wrapper after only the v13 stage-root and assembler-marker substitutions.
`Get-Command` decoded exactly 16 unique parameters, all recognized by the
reviewed assembler, with zero TestMode/synthetic/injection/hook or
inventory/stage-postcondition overrides. The compact sorted decoded-parameter
JSON SHA-256 is
`05D2030AF3F9A906F7B3E17A2BBC8459D8A10ACDEB69A80FD3E6C25D749142E7`.
The reviewed assembler and staging-harness SHA-256 values are respectively
`894518C893E44E0257546781B530E2CE4DFDC045F41744EEF919FC067163BF63`
and
`4109B42925EEF9994A166F4DF0428E242D436A955C43AA947F2D71C720E89E86`.
The pinned executable was exact PowerShell 7.6.4 at
`C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe`,
SHA-256
`DB6DD81183FE57D22E03B911EC9A30A2FD7C40542E97743615355A6FB44F458F`.

The preflight was launched through `System.Diagnostics.ProcessStartInfo`
exactly once. `Process.Start()` returned success, but the restricted host then
failed before it could record the returned child PID:

```text
System.UnauthorizedAccessException: Access to the path
C:\tmp\todo51-task3\stage-runtime-v13.preflight.pid.txt was denied.
```

The child exited and no matching process remained. No PID file, stdout,
stderr, or exit marker was created, so there is no valid preflight PASS and
the child PID is unavailable. No retry or evidence recycling was performed.
Root-cause comparison with the Task 1 handoff shows that this sole launcher
was mistakenly left under the restricted-token sandbox even though that
handoff recorded the need for approved host execution for writes in these
fixture/evidence roots.
The assembler launch count is exactly zero; all assembler PID/log/marker
paths and `stage-runtime-v13` remain absent. The post-audit and repository
regression gates were not run because they are success-only downstream gates.
No staged binary was inspected or executed. Preserved v11 and all six
reported v12 wrapper/preflight/PID/log/marker artifacts remain byte-identical
to their recorded SHA-256 values. This v13 attempt is BLOCKED and has no
success commit.

## v14 production attempt: accepted preflight, fail-closed assembler exit

The human explicitly authorized one new v14 attempt outside the restricted
sandbox while keeping the v13 no-retry stop final. Task 2 retained HEAD
`16b0391dd7e4ac300c90f414e1891e6f5d4e2947`, the dirty scope remained only
this report, preserved v11 existed, v12/v13 stage roots remained absent, all
six recorded v12 artifacts and all three v13 helpers matched their recorded
SHA-256 values, all 12 v13 runtime evidence paths were absent, all 16 intended
v14 paths were absent, and ten immutable roots contained zero reparse points.

The v14 helper gate passed with zero parser errors, an exact v13 wrapper with
only the v14 stage-root and assembler-marker substitutions, exactly 16 unique
`Get-Command`-recognized parameters, and no TestMode/synthetic/injection/hook
or inventory/stage-postcondition override surface:

- wrapper: 2,380 bytes /
  `95295DCE7C8CD5DE30B4301214F92A061928CFF5143C33BAC7FADB8D58D39C33`;
- preflight: 22,658 bytes /
  `DB909F02A6A520B8024549D4E5B577DD4E4D3D3DB9F1B30F7B5A88352D93D687`;
- post-audit: 18,766 bytes /
  `1E8B0F001403A4CAC50C36392FE74C22CB5590198117AEB90B0A18989321043D`;
- compact decoded-parameter JSON:
  `81327F4707576A9FF6A5C80C35AA45C0655F662A0F45828C42A3EE2D2C1711AA`.

### Accepted v14 preflight

The command owning `ProcessStartInfo`, PID evidence, and polling ran through
explicit `require_escalated` host execution. Immediately before `Start()` it
created, verified, removed, and required absence of a disposable
`HOST_WRITE_SMOKE_PASS` probe outside all evidence paths. The pinned
PowerShell 7.6.4 executable retained SHA-256
`DB6DD81183FE57D22E03B911EC9A30A2FD7C40542E97743615355A6FB44F458F`.

The one v14 preflight launch was PID 30416, started at
`2026-08-01T21:46:56.1751445Z` and exited at
`2026-08-01T22:30:07.1407682Z`. During execution only PID, log lengths, and
marker presence were polled. It returned process exit 0, marker 0, empty
stderr, and exactly one PASS JSON object:

| Evidence | Bytes | SHA-256 |
|---|---:|---|
| preflight PID | 7 | `856D95095F7A2EE43AB0638F6ACF8573E8E29015C00B8D9415EE5133F1C07731` |
| preflight stdout | 1764 | `8A02D4E7144E3765F31CD0BA220BE75D966FDB4FC7790D1D21ECB53B052D5BEA` |
| preflight stderr | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` |
| preflight marker | 3 | `13BF7B3039C63BF5A50491FA3CFD8EB4E699D1BA1436315AEF9CBE5711530354` |

```json
{"Result":"PASS","WrapperSha256":"95295DCE7C8CD5DE30B4301214F92A061928CFF5143C33BAC7FADB8D58D39C33","AssemblerSha256":"894518C893E44E0257546781B530E2CE4DFDC045F41744EEF919FC067163BF63","ContractSha256":"692341FA19E6D7AC3CF4C02894DBDB92AFAE7A5DD154B659A5CFD099AD63F2CC","PostAuditSha256":"1E8B0F001403A4CAC50C36392FE74C22CB5590198117AEB90B0A18989321043D","DecodedParameterJsonSha256":"81327F4707576A9FF6A5C80C35AA45C0655F662A0F45828C42A3EE2D2C1711AA","DecodedParameterCount":16,"Permanent":{"FileCount":59533,"TotalBytes":2797722287,"ManifestSha256":"95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD"},"Normalized":{"FileCount":59533,"TotalBytes":2797722565,"ManifestSha256":"B19A1BAB6293EBAAD7D0076B43D5E8F466BA896EAADFD81EED7E0C7C8F96FB31"},"NormalizedManifestSha256":"9417DC1DC935E33ACADACA3A0AD86389F500B937F7670E3D177A8D58B3C68CED","Pure":{"FileCount":4769,"TotalBytes":260533868,"Sha256":"52DA19745D9F33DEC4CEAF09E24E3836C04E82E1651BB695990D18B14D667FE3"},"Bridge":{"FileCount":2,"TotalBytes":4771866,"Sha256":"974C07999D4EBC62C218F0EDA7D271B6CCC7AFDEBD1EBFA063C7A25109C4CE11"},"AcceptedV5FileCount":64309,"AcceptedV5Bytes":3327729829,"SupplementFileCount":3,"SupplementBytes":7241216,"ReusedPureDependencyCount":38,"WindowsOsVersion":"Microsoft Windows NT 10.0.26200.0","WindowsCurrentBuild":"26200","WindowsCurrentBuildKind":"String","WindowsUbr":8973,"WindowsUbrKind":"DWord","ApiSetSchemaPath":"C:\\WINDOWS\\System32\\apisetschema.dll","ApiSetSchemaFileVersion":"10.0.26100.8972 (WinBuild.160101.0800)","ApiSetSchemaProductVersion":"10.0.26100.8972","ApiSetSchemaLength":194048,"ApiSetSchemaSha256":"E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8","TargetAbsent":true,"AssemblerMarkerAbsent":true,"ReparsePointCount":0}
```

This accepted the exact serviced platform identity:
`Microsoft Windows NT 10.0.26200.0 / 26200 / 8973`, API-set file/product
version `10.0.26100.8972 (WinBuild.160101.0800) / 10.0.26100.8972`,
194,048 bytes, and SHA-256
`E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8`.

### Sole v14 assembler launch and blocker

Only after preflight acceptance, a second explicit `require_escalated` host
owner rechecked absent target/marker/evidence paths, all helper and immutable
preflight hashes, all 16 decoded parameters, and a fresh
`HOST_WRITE_SMOKE_PASS` probe which was removed and absent before `Start()`.

The one production assembler launch was PID 29572, started at
`2026-08-01T22:32:42.1231632Z` and exited at
`2026-08-01T23:00:12.3873456Z`. During execution only PID, stdout/stderr
lengths, and marker presence were polled. No in-progress stage path was
opened. The exact immutable result was:

```text
Process exit: 1
Assembler marker: 1
Stdout: 0 bytes
Stderr: 0 bytes
Assembler JSON objects: 0
```

| Evidence | Bytes | SHA-256 |
|---|---:|---|
| assembler PID | 7 | `2AFD8356A169F20FE5BC8E819110132B6C0B72CF38DF94A1F2B7CCA1BD9BE1E8` |
| assembler stdout | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` |
| assembler stderr | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` |
| assembler marker | 3 | `F1B2F662800122BED0FF255693DF89C4487FBDCF453D3524A42D4EC20C3D9C04` |

The partial `C:\tmp\todo51-task3\stage-runtime-v14` root and every v14
helper/evidence file are preserved. The nonzero process/marker result, empty
logs, and absence of the required single JSON object are the exact blocker.
Per the no-retry rule there was no second assembler launch, no static
post-audit, no repository success gate, no stage-content inspection, no
staged-binary execution, and no success commit. Preflight launch count is one,
assembler launch count is one, and post-audit launch count is zero.

## v15 assembler diagnostic wrapper gate

Task 1 began on `todo/51-windows-strict-write-confinement` at
`972ff33c27065df0988546cd8106596dd58032a3`, with this report as the only dirty
path. `C:\tmp\todo51-task3\stage-runtime-v14` was verified only with
`Test-Path` and existed; every Task 1 fixture and `stage_v15_wrapper.ps1` path
was initially absent. Root-level v12-v14 preservation hashes all matched:
v12 wrapper/preflight `26B519558047D0E79A22E3FF83B81D8E10A6E3CBF2C321B0612723EFA766F9F2` /
`DE4646ECF9624894D5199F085DCB3B86D14CA3ED6E00542EA64959AD10A02862`; v13
wrapper/preflight/post-audit `67FDE491EAD1ACE3394DAB454E4B8A6F6CCA9AAF2D5FA30A3A7220999FE715D7` /
`4AA13A140EC1F1D6171802066C92FE64FE2DB93EAB556E9B57A0EF58C3883FFE` /
`3819645916A1F2418C9F1262F3EF120CB71B6040A689DECFB65D14183D0ACA65`; v14
wrapper/preflight/post-audit `95295DCE7C8CD5DE30B4301214F92A061928CFF5143C33BAC7FADB8D58D39C33` /
`DB909F02A6A520B8024549D4E5B577DD4E4D3D3DB9F1B30F7B5A88352D93D687` /
`1E8B0F001403A4CAC50C36392FE74C22CB5590198117AEB90B0A18989321043D`.
Recorded v12/v14 PID/log/marker evidence also matched its report hashes.

RED copied v14 into a disposable SUT and substituted only assembler, marker,
and stage-root literals. The host-owned pinned PowerShell 7.6.4
`ProcessStartInfo` launch gave process/marker `1/1`, stderr containing
`V15_DIAGNOSTIC_THROW_SENTINEL`, and absent independent JSON; the harness
failed exactly `Expected independent error JSON was not created.` Preserved RED
replay bytes/SHA-256: SUT 2410 /
`D824F05F221840834D3BBA35F4E093292E6D113110EB476208ABF5FC21354382`, stdout
0 / `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`, stderr
217 / `8D00442BBCEC2DFF35681FACB6AB359DAEBD826A2759049A3B4D08F24933DFEE`, marker
3 / `F1B2F662800122BED0FF255693DF89C4487FBDCF453D3524A42D4EC20C3D9C04`; error
JSON absent.

The minimal external v15 wrapper is 3265 bytes /
`91F21C4722B4CEC56A64131F26B8545F97801FADB926C4B5A0572FD8901DA212`; it adds
only v15 literals, pre-existing-error rejection, and the seven-field caught
`ErrorRecord` diagnostic before the existing `finally` marker. Harness SHA-256
is `86A3C94028A0746C0116F28F4886FBD3352A970A1E68B27F1DB30DADDFD2B0AE` (5412
bytes), derived from v15 by exact literal substitution. GREEN failure passed
process/marker `1/1`, regular non-reparse UTF-8 JSON with exactly
TimestampUtc/ExceptionType/Message/FullyQualifiedErrorId/Category/
ScriptStackTrace/InvocationPosition, sentinel message/stderr, and nonempty
ExceptionType/ScriptStackTrace. Its SUT/stdout/stderr/marker/JSON bytes and
hashes were 3328 / `5AFF9CFE6D9616D7AA7E36C134A66EBD20AD18DE696954E81888D3E38D26E2B2`,
0 / `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`, 217 /
`8D00442BBCEC2DFF35681FACB6AB359DAEBD826A2759049A3B4D08F24933DFEE`, 3 /
`F1B2F662800122BED0FF255693DF89C4487FBDCF453D3524A42D4EC20C3D9C04`, 699 /
`C6C3FE9D4E74013FE55706CC9B846B6C305D3CB7ACBAD1E4780E12F76671FC59`.
GREEN success passed `0/0`, exact stdout sentinel, empty stderr, and absent
error JSON; stdout/stderr/marker were 33/0/3 bytes with hashes
`1CC780D6B7474089B4AA0B33F43F6B5882501BDD6D7DAEB45EFEF9F0235579B1` /
`E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` /
`13BF7B3039C63BF5A50491FA3CFD8EB4E699D1BA1436315AEF9CBE5711530354`.
The aggregate result was `PASS all v15 wrapper diagnostic tests`.

Wrapper and harness parsed with zero PowerShell errors. `-PrintBoundParams`
decoded through `Get-Command` to 16 unique recognized keys; TestMode,
Synthetic, Inject, Hook, Inventory, StagePostcondition, and caller-controlled
diagnostic surfaces numbered zero. Normalizing solely v14/v15 stage/marker
literals and the new diagnostic-catch block found no unrelated difference.
`git diff --check` exited 0. No v15 production preflight, assembler process,
production marker/error evidence, or `stage-runtime-v15` production stage was
created; no staged content or binary was inspected or executed.
## Review fix 1: bind stale diagnostic evidence

Review verification confirmed that the v15 pre-existing-error guard threw inside
the same top-level `try` whose `catch` unconditionally called `WriteAllText`.
A real fixture now seeds literal hand-written bytes for
`V15_STALE_EVIDENCE_SENTINEL`, derives a SUT from the actual v15 wrapper only by
literal substitution, and requires guard stderr, process/marker `1/1`, and
byte-for-byte preservation. The fixture catches the production mutation that
would make an existing diagnostic evidence file writable.

### RED exact command and output

```powershell
& 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe' -NoProfile -NonInteractive -File 'C:\tmp\todo51-task3\wrapper-diagnostic-v15\test_v15_wrapper_diagnostics.ps1'; exit $LASTEXITCODE
```

```text
Exception: C:\tmp\todo51-task3\wrapper-diagnostic-v15\test_v15_wrapper_diagnostics.ps1:19
Line |
  19 |      if (-not $Condition) { throw $Message }
     |                             ~~~~~~~~~~~~~~
     | Expected stale error evidence bytes to remain unchanged.
```

The minimal wrapper correction leaves the guard inside `try`, but makes the
catch write diagnostic JSON only when the evidence path is absent. Thus the
guard still emits the caught error to stderr and the existing `finally` writes
marker `1`, while stale bytes remain untouched. No strict UTF-8 decoding change
was made. Final wrapper/harness are 3,343 / 6,536 bytes with SHA-256
`ACF8DEFED19F5CE21F85EBFF54E6174FBA520CFA0748FC0725F54A209450584C` /
`EBC877656DE090A8EB0925542A8A5B2F5BD8EC54653845589DED828DCE80B0E7`.

### GREEN exact command and output

```powershell
& 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe' -NoProfile -NonInteractive -File 'C:\tmp\todo51-task3\wrapper-diagnostic-v15\test_v15_wrapper_diagnostics.ps1'; exit $LASTEXITCODE
```

```text
PASS all v15 wrapper diagnostic tests
```

The full parser/parameter/diff gate then emitted exactly:

```text
PASS parsers 0; keys 16/16; surfaces 0; normalized diff none; production paths absent; git diff --check 0
```

No v15 production preflight, assembler process, production marker/error path,
or `stage-runtime-v15` stage was created.
## v15 production attempt: accepted preflight, diagnostic assembler failure

The sole v15 attempt began from exact clean HEAD
1f8bb56692f5464e7dfb3f440e4616ecf0e83677 on
todo/51-windows-strict-write-confinement. The precreation gate matched 21
preserved helper/evidence pins, required 16 literal v15 helper/stage/runtime
paths to be absent, verified ten immutable roots reparse-free, and checked the
preserved partial v14 stage only with Test-Path=True; it was not enumerated
or read.

The external v15 helpers passed their static gate with zero parser errors,
exactly 16 recognized wrapper parameters, zero forbidden TestMode/synthetic/
injection/hook/inventory/stage-postcondition surface, and the pinned
PowerShell 7.6.4/platform identities:

- wrapper: 3,343 bytes /
  ACF8DEFED19F5CE21F85EBFF54E6174FBA520CFA0748FC0725F54A209450584C;
- preflight: 23,346 bytes /
  68187605B19AABADC6E741DD8464B1ABD5D498452B3989F1AF1EC4FD490E09B7;
- post-audit: 18,766 bytes /
  0BB416C320D2A33AECE4723D1BBDB6916C603BF4DDB2904419C46330FEFDED7D;
- compact decoded-parameter JSON:
  2BED5FAFFD7A87F4F740C8F5BDB3C911E018101DF12B9231C0FEDB1A81AD5F8E.

### Accepted sole v15 preflight

The ProcessStartInfo/PID/poll owner ran through explicit require_escalated
execution after a fresh HOST_WRITE_SMOKE_PASS create/read/remove/absence
probe. PID 14664 ran from 2026-08-03T08:05:37.0595194Z through
2026-08-03T08:43:48.4557415Z. During execution only PID, log lengths, and
marker presence were polled. Process/marker were 0/0, stderr was empty, and
stdout contained exactly one PASS JSON object with every pinned source
manifest and the exact serviced Windows platform identity.

| Evidence | Bytes | SHA-256 |
|---|---:|---|
| preflight PID | 7 | 1335E0C5EB130881A5E03F6AAD5C0CCDB45C13183480AB2FC0D618832BAFF40D |
| preflight stdout | 1,816 | 5A28DC7055DE3DB16671F8803DDD989BD4D593D48CED9CEC8E08D9A3F13DD5F3 |
| preflight stderr | 0 | E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 |
| preflight marker | 3 | 13BF7B3039C63BF5A50491FA3CFD8EB4E699D1BA1436315AEF9CBE5711530354 |

### Sole v15 assembler launch and immutable blocker

After accepted preflight, the second explicit require_escalated owner
rechecked absent stage/PID/log/marker/error paths, every helper and preflight
hash, all 16 decoded parameters, and a fresh host-write probe. PID 22952 ran
from 2026-08-03T08:45:33.1447831Z through
2026-08-03T09:11:25.0940810Z. Polling was restricted to PID, stdout/stderr
lengths, and marker presence; no in-progress stage path was opened.

The immutable result was process/marker 1/1, zero-byte stdout, 395-byte
stderr, and a new regular non-reparse BOM-less UTF-8 diagnostic JSON. The JSON
is 978 bytes, SHA-256
918F028B0397A235F1DA7DC18472B2834E3FB55DCABE5DE013C84C55CBC27468,
and contains exactly one object with exactly the seven reviewed fields:

~~~json
{"TimestampUtc":"2026-08-03T09:11:24.9546929Z","ExceptionType":"System.Management.Automation.RuntimeException","Message":"Missing effective import Qt6Gui.dll needed by C:\\tmp\\todo51-task3\\stage-runtime-v15\\pure\\tools\\gnuplot\\bin\\platforms\\qminimal.dll","FullyQualifiedErrorId":"Missing effective import Qt6Gui.dll needed by C:\\tmp\\todo51-task3\\stage-runtime-v15\\pure\\tools\\gnuplot\\bin\\platforms\\qminimal.dll","Category":"OperationStopped: (Missing effective i…tforms\\qminimal.dll:String) [], RuntimeException","ScriptStackTrace":"at <ScriptBlock>, C:\\pure-lang\\pure-octave\\probes\\stage_task3_runtime.ps1: line 1132\r\nat <ScriptBlock>, C:\\tmp\\todo51-task3\\stage_v15_wrapper.ps1: line 46","InvocationPosition":"At C:\\pure-lang\\pure-octave\\probes\\stage_task3_runtime.ps1:1132 char:25\r\n+ …             throw \"Missing effective import $dll needed by $($pe.File …\r\n+               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"}
~~~

| Evidence | Bytes | SHA-256 |
|---|---:|---|
| assembler PID | 7 | 632E317C3F4C6DCF616CE03996FC7971F127E5C125A01EFB6B6A30214D6C5137 |
| assembler stdout | 0 | E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 |
| assembler stderr | 395 | 9688E42642AD58FD43F71E5E8FA717B9DE6EB6B00ACE14EFA2D563494DAABE1C |
| assembler marker | 3 | F1B2F662800122BED0FF255693DF89C4487FBDCF453D3524A42D4EC20C3D9C04 |
| assembler error JSON | 978 | 918F028B0397A235F1DA7DC18472B2834E3FB55DCABE5DE013C84C55CBC27468 |

The partial C:\tmp\todo51-task3\stage-runtime-v15 root is preserved and was
checked only with Test-Path=True; it was never enumerated or read. This v15
attempt is BLOCKED at the exact missing qminimal.dll -> Qt6Gui.dll import. Per
the no-retry failure contract there was no second preflight or assembler
launch, no post-audit, no supplement or staging success harness, no
parser/diff success gate, no staged-binary execution, and no commit. Launch
counts are preflight one, assembler one, and post-audit zero; every post-audit
evidence path remains absent.

## v16 diagnostic/helper gate

Task 3 began on branch `todo/51-windows-strict-write-confinement` at reviewed
Task 2 HEAD `7015dd1d09053ca02c99bb4db6a03a335d38532e`. The sole worktree
modification was this preserved report. Before this append it was 85,559 bytes,
SHA-256 `0A957FF067216F5C5ABA82734211D217A3F0D08F156B4DD3066C0BCF9A70B89B`;
its existing v15 evidence and meaning were retained.

The preserved partial `C:\tmp\todo51-task3\stage-runtime-v15` was checked only
with literal `Test-Path=True`. It was not enumerated, read, executed, modified,
or cleaned. The immutable v15 helpers and runtime evidence matched their
recorded byte counts and SHA-256 values:

| Preserved v15 artifact | Bytes | SHA-256 |
|---|---:|---|
| wrapper | 3,343 | `ACF8DEFED19F5CE21F85EBFF54E6174FBA520CFA0748FC0725F54A209450584C` |
| preflight | 23,346 | `68187605B19AABADC6E741DD8464B1ABD5D498452B3989F1AF1EC4FD490E09B7` |
| post-audit | 18,766 | `0BB416C320D2A33AECE4723D1BBDB6916C603BF4DDB2904419C46330FEFDED7D` |
| preflight PID | 7 | `1335E0C5EB130881A5E03F6AAD5C0CCDB45C13183480AB2FC0D618832BAFF40D` |
| preflight stdout | 1,816 | `5A28DC7055DE3DB16671F8803DDD989BD4D593D48CED9CEC8E08D9A3F13DD5F3` |
| preflight stderr | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` |
| preflight marker | 3 | `13BF7B3039C63BF5A50491FA3CFD8EB4E699D1BA1436315AEF9CBE5711530354` |
| assembler PID | 7 | `632E317C3F4C6DCF616CE03996FC7971F127E5C125A01EFB6B6A30214D6C5137` |
| assembler stdout | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` |
| assembler stderr | 395 | `9688E42642AD58FD43F71E5E8FA717B9DE6EB6B00ACE14EFA2D563494DAABE1C` |
| assembler marker | 3 | `F1B2F662800122BED0FF255693DF89C4487FBDCF453D3524A42D4EC20C3D9C04` |
| assembler error JSON | 978 | `918F028B0397A235F1DA7DC18472B2834E3FB55DCABE5DE013C84C55CBC27468` |

The reviewed v15 diagnostic harness and exact throw/success children remained
pinned: 6,536 / `EBC877656DE090A8EB0925542A8A5B2F5BD8EC54653845589DED828DCE80B0E7`,
101 / `93450D105758B968B68EC988E3B3A6E352DD8B4654CBC48AEC75D5141AB04519`,
and 97 / `F2767CD7ED33E7156B19BB2995CA4F82261D0B36E6D5F45F8BB0C40220E7316D`.
Every intended v16 diagnostic fixture, wrapper, helper, stage, PID, log,
marker, and error path was absent at the initial gate.

The immutable v15 production blocker remains process/marker `1/1`, empty
stdout, 395-byte stderr, and one seven-field diagnostic object whose exact
message is the missing effective `Qt6Gui.dll` import required by
`stage-runtime-v15\pure\tools\gnuplot\bin\platforms\qminimal.dll`. Task 3 did
not retry, inspect, or alter that failed production attempt.

### Task 1-2 reviewed production prerequisites

Task 1 RED exited 1 at the missing effective `Qt6Gui.dll` import for
`platforms\qminimal.dll`; GREEN ended with `PASS all task3 staging tests` after
binding only the two exact approved plugin paths and direct-Gnuplot loader
domain. Commits were `1bcd1755` (`Audit Gnuplot platform plugin`) and fixture
contract correction `011bc56b` (`Restore fixed Gnuplot test fixture contract`).

Task 2 RED exited 1 because the exact production plugin cardinality assignment
was absent. Its review-fix RED exited 1 because the combined diagnostic was not
the required direct/plugin PE sum. GREEN bound the seven independent plugin
cardinalities and ended with both repository harnesses passing. Commits were
`80374c0b` (`Bind Gnuplot platform plugin audit`) and reviewed correction
`7015dd1d` (`Count inconsistent plugin API-set mappings`).

### v16 wrapper RED

The exact throwing child contains only strict mode, stop-on-error, and
`throw 'V16_DIAGNOSTIC_THROW_SENTINEL'`. The success child emits exactly
`V16_DIAGNOSTIC_SUCCESS_SENTINEL`. Before the v16 wrapper existed, the harness
used a 2,380-byte v15-derived SUT with only the diagnostic variable, guard, and
catch diagnostic block removed. The exact host command was:

```powershell
& 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe' -NoProfile -NonInteractive -File 'C:\tmp\todo51-task3\wrapper-diagnostic-v16\test_v16_wrapper_diagnostics.ps1'; exit $LASTEXITCODE
```

It exited 1 for the intended reason:

```text
Exception: C:\tmp\todo51-task3\wrapper-diagnostic-v16\test_v16_wrapper_diagnostics.ps1:19
Line |
  19 |      if (-not $Condition) { throw $Message }
     |                             ~~~~~~~~~~~~~~
     | Expected independent error JSON was not created.
```

The child process/marker result was `1/1`, stderr contained the exact throw
sentinel, and error JSON was absent. Preserved RED SUT/stdout/stderr/marker
bytes and SHA-256 values are 2,380 /
`1DBC5E422818B8AE21A4C0B6C8C0CD1C950F9444ADB5E26F9314F7BD92A48FF8`,
0 / `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`,
217 / `DA452A1BEF58358DE08B68A6DE46CE2488154F6269BA1831118912362A9E1C2A`,
and 3 / `F1B2F662800122BED0FF255693DF89C4487FBDCF453D3524A42D4EC20C3D9C04`.

### Minimal wrapper and GREEN/stale cases

The external v16 wrapper is the accepted v15 wrapper with only its exact
stage-root, assembler-marker, and assembler-error literals changed from v15
to v16. It retains the 16-key assembler hashtable and reviewed
pre-existing-error guard. The catch writes its diagnostic only if that path is
absent and uses `[Text.UTF8Encoding]::new($false)`.

Final wrapper/harness/throw-child/success-child byte counts and SHA-256 values:

- wrapper: 3,343 / `4CD4946325A56700EFB00B7EB0E7580775E07F7DA34256D212D42B8CB4436311`;
- harness: 7,889 / `6D4EEB09F9B372F97EC045D7BFB848CADD12886018B2E9D7331620A317EC92DC`;
- throw child: 101 / `4DBC5033D52B0BE64C9A9C54AF32DE440919475E083E7AC169D8EA8AB0592138`;
- success child: 97 / `E67DF93447AFEC8E13AB4A3D6FFBDFE2BFEA8B1C0C920A2CF3A1AFACEF34E77B`.

The harness decodes JSON with `[Text.UTF8Encoding]::new($false, $true)` and
`ConvertFrom-Json -NoEnumerate`. Invalid UTF-8 throws. It rejects a BOM,
arrays/non-objects, anything other than one object with exactly
`TimestampUtc`, `ExceptionType`, `Message`, `FullyQualifiedErrorId`,
`Category`, `ScriptStackTrace`, and `InvocationPosition`, a non-sentinel
message/FQID, and a stack that does not identify `throw-child.ps1`.

The exact GREEN command was the same pinned host command as RED and exited 0:

```text
PASS failure process/marker 1/1; strict BOM-less UTF-8; one seven-field JSON; sentinel message/stack/stderr
PASS stale evidence process/marker 1/1; bytes unchanged
PASS success process/marker 0/0; exact stdout; empty stderr; error JSON absent
PASS all v16 wrapper diagnostic tests
```

Failure stdout/stderr/marker/JSON were 0 / 217 / 3 / 728 bytes with SHA-256
`E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`,
`DA452A1BEF58358DE08B68A6DE46CE2488154F6269BA1831118912362A9E1C2A`,
`F1B2F662800122BED0FF255693DF89C4487FBDCF453D3524A42D4EC20C3D9C04`,
and `26E62E6F2137BCE27647FC40C148C0D124B62EB81E4F36F271DA1F7B5D40E770`.

The stale case seeded the literal 29 bytes
`V16_STALE_EVIDENCE_SENTINEL\r\n`, SHA-256
`E8BD2FA1B5129463B2D1CFF447C6D0694BAF04EDA55DAF50D3DE41756007BFC5`.
After process/marker `1/1` and the guard error on stderr, the file remained
exactly 29 bytes with the same SHA-256. Success stdout/stderr/marker were
33 / 0 / 3 bytes with SHA-256
`6AB887404F160BC26D701A2287E2880D6167DE7D9FF6611883EDAC468638CC10`,
`E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`,
and `13BF7B3039C63BF5A50491FA3CFD8EB4E699D1BA1436315AEF9CBE5711530354`;
the success error path was absent.

### Static binding and repository regression gates

Wrapper, harness, and both children parsed with zero errors. Decoding
`-PrintBoundParams` produced 16 keys, all unique and recognized by the
reviewed assembler. TestMode, synthetic, injection, hook, inventory,
postcondition, diagnostic, and error-evidence caller surfaces numbered zero.
The compact decoded JSON was 1,525 BOM-less UTF-8 bytes, SHA-256
`16BB59A9D1CF662EE26BE8DD546C962191D95DDF920FBAB8E2CD2715BCEF9938`.
Normalizing only exact v15/v16 stage-root, marker, and error literals made the
wrapper diff empty. The combined gate emitted:

```text
PASS parsers 0; keys 16/16; surfaces 0; normalized diff none; production paths absent
```

Fresh full pinned PowerShell 7.6.4 repository runs exited 0. The supplement
harness passed all 15 named cases and ended `PASS all supplement preparer
tests`. The staging harness passed all named cases and ended `PASS all task3
staging tests`.

No v16 production preflight/post-audit helper, production PID, stdout/stderr
log, marker, error JSON, or `stage-runtime-v16` stage was created. No v16
production assembler or preflight was launched. No staged content or binary
was inspected or executed. Only disposable diagnostic wrapper children ran,
each through explicit `require_escalated` host execution with pinned
PowerShell 7.6.4.

### Task-scoped review

Independent review found one Important issue: PowerShell pipeline enumeration
could unwrap a one-element top-level JSON array before the PSCustomObject type
check. The harness was corrected to use `ConvertFrom-Json -NoEnumerate`, then
the full diagnostic harness, static binding gate, supplement harness, and
staging harness all passed freshly. The refreshed harness and JSON hashes above
bind that correction. Read-only fix-round review found no Critical, Important,
or Minor issue and assessed the gate ready to commit.

## v16 sole production attempt: BLOCKED by PID-evidence owner failure

Task 4 began from exact clean HEAD
`7bb1338f8c7b2243f08d29d7b9932932339fff38` on
`todo/51-windows-strict-write-confinement`. Before helper creation, all 16
literal v16 helper/stage/PID/log/marker/error/post-audit paths were absent, ten
immutable roots were regular and reparse-free, v12/v13 stage roots were absent,
and preserved partial v14/v15 were checked only with `Test-Path=True`.
Root-level v11-v15 helper/evidence files and the v15 diagnostic fixture retained
their recorded SHA-256 identities.

The reviewed v15 audit helpers were copied and changed only for v16-owned
paths/hashes plus Task 2's seven Gnuplot platform-plugin fields and exact
`2 / 2 / 38 / 6 / 15 / 17 / 0` pins. Final static identities were:

- wrapper: 3,343 bytes / `4CD4946325A56700EFB00B7EB0E7580775E07F7DA34256D212D42B8CB4436311`;
- preflight: 25,525 bytes / `4DF6908340D5AC7A40EAD452C2BE7F1121360898121FE425E380FCE98C35B134`;
- post-audit: 23,358 bytes / `C120D8399B053EAA7C2B905783B48D60ABAD6A954DFE14F99160B16C5DC8CB15`;
- Task 2 assembler: 99,557 bytes / `9DCA19AC3227D3CACC8F614759DD03CF8194EDAD0C524E371F0F5A0F1F9A6E59`;
- Task 2 staging harness: 64,191 bytes / `C3C9D44A270A04DABDC25FDD0FEF47EE43DF68C13A886BFA98F35767801867EB`.

All eight wrapper/helper/diagnostic/assembler/harness files parsed with zero
PowerShell errors. The wrapper decoded to 16/16 unique recognized parameters
with zero forbidden caller surfaces. Compact parameter-array JSON was 1,431
bytes / `E2351D8379B0A73F84A305C087B4C8A9D7AC7D2A6E8E3DA502DF90E6A1BC485C`;
compact full decoded wrapper JSON was 1,525 bytes /
`16BB59A9D1CF662EE26BE8DD546C962191D95DDF920FBAB8E2CD2715BCEF9938`.
The v15/v16 wrapper normalized diff was empty, the current serviced Windows
platform identity was exact, all 14 v16 runtime paths were absent, and Git was
clean at the required HEAD. Pinned PowerShell was exact 7.6.4
(file version 7.6.4.500), SHA-256
`DB6DD81183FE57D22E03B911EC9A30A2FD7C40542E97743615355A6FB44F458F`.

Immediately before the sole preflight `Process.Start()`, the explicit
`require_escalated` owner rechecked all v16 runtime paths absent, exact
wrapper/preflight/post-audit/assembler/harness/PowerShell hashes, clean HEAD,
protected v14/v15 presence by `Test-Path` only, and a create/read/remove/absence
`HOST_WRITE_SMOKE_PASS` probe. It launched pinned PowerShell 7.6.4 with
`-NoProfile -NonInteractive -File
C:\tmp\todo51-task3\stage_v16_preflight_audit.ps1`, hidden, no shell, and
redirected anonymous stdout/stderr pipes.

`Process.Start()` returned true exactly once. The owner then failed before it
could record the returned child PID:

```text
WriteError at $pid=$process.Id
Cannot overwrite variable PID because it is read-only or constant.
```

PowerShell variable names are case-insensitive, so `$pid` collided with the
read-only automatic `$PID`. There was no retry. PID-only monitoring found two
persistent candidates, 812 and 2796. Both were alive from the first observation
at `2026-08-04T00:20:46.6689104Z`; PID 812 exited naturally at
`2026-08-04T01:00:25.7558595Z` while PID 2796 remained alive, identifying PID
812 as the preflight child by the state delta. The observable elapsed lower
bound is 39 minutes 39.0869491 seconds; exact StartUtc was held only in the
failed owner and was not emitted. While the child was alive, only those PID
existence states were inspected. No process command line, redirect evidence,
or stage path was opened.

After PID 812 exited, all 13 external v16 preflight/assembler/post-audit
PID/stdout/stderr/marker/error paths were absent. In particular, preflight PID,
stdout, stderr, and marker evidence were never created; `Process.Start()` used
anonymous pipes and the owner never reached its post-exit file writes. Thus
there is no valid preflight PASS JSON, exit marker, stderr, or evidence hash to
accept. All v16 helper/repository hashes remained exact after failure.

This sole v16 production attempt is therefore **BLOCKED**. Launch counts are
preflight one, assembler zero, and post-audit zero. The v16 stage path was not
inspected after launch, and no staged binary was inspected or executed. There
was no preflight retry, assembler launch, post-audit, supplement/staging success
harness, parser/diff success gate, cleanup, staging, commit, or success review.
This report append is intentionally left uncommitted under the fail-closed
contract.

## v17 reviewed process-owner and immutable helper checkpoint

Task 4 began at exact Task 3 HEAD
`84616246add57dfaf83053f627ea646324b10ddc` on
`todo/51-windows-strict-write-confinement`. The sole worktree modification was
this preserved report and the index was empty. Before this append the report
was exactly 99,362 bytes, SHA-256
`DBF5C52A8324ABBE6D7A9AF7CFB80066BA0BF05C552880DB5AC3FFF385303195`.
Those 99,362 bytes are the immutable prefix of this checkpoint.

The initial gate matched 45 recorded v15/v16 helper, diagnostic-fixture, and
runtime-evidence byte/hash pins. Protected partial stages were checked only by
literal `Test-Path`: v14 `True`, v15 `True`, and v16 `False`. They were never
enumerated or read. All 24 intended v17 helper, contract, stage, owner-evidence,
child-marker, and assembler-diagnostic paths were absent. There were zero
`process-owner-tests-*` roots, zero `todo51-task3-escape-*` roots, zero matching
test children, and zero v17 production processes.

### Reviewed owner RED/GREEN history

The closed process owner was developed and reviewed through these commits:

- `3539030e00a5378600069af719eb53c0c9d99d21`, `Validate strict process owner contracts`: 453 insertions in the exact owner and harness. RED had no compliant owner/closed schema; GREEN rejected unknown, missing, incorrectly typed, noncanonical, hash-mismatched, duplicate, pre-existing, reparse, hard-link, and escaping contracts before child launch.
- `addd227dc2930d8277aa7006c92229a2d4c0519a`, `Capture strict process owner evidence`: 542 insertions and 13 deletions. Lifecycle RED had no PID, stream, exit, or error evidence; GREEN proved the observed child PID, success and exit-23 propagation, concurrent 1 MiB stdout/stderr draining, atomic evidence, post-exit rehashing, and owner failure code 125 without child termination.
- `84616246add57dfaf83053f627ea646324b10ddc`, `Harden verified process owner gate`: 356 insertions and 7 deletions in the harness. RED rejected missing unscoped and scoped reserved-variable AST protection; GREEN rejected `$pid` and `$script:pid` mutations while accepting the real owner. The final harness also covered junctions, file symbolic links, hard links, canonical and sibling-prefix escapes, stale/duplicate evidence, interruption classification, cleanup confinement, and owner-only parameterless `Kill()`.

Task 4 static contract preparation then found a load-bearing phase-domain RED:
the reviewed owner accepted only `Phase = Preflight`, so truthful `Assembler`
and `PostAudit` contracts would have failed validation. Contract creation,
report mutation, and production launch stopped with counts `0 / 0 / 0`; no
three-`Preflight` workaround was created. GREEN commit
`0ceb91607c8cb91c0d3bf723226bf2dec973b503`,
`Accept strict process owner phases`, added an ordinal closed set containing
exactly `Preflight`, `Assembler`, and `PostAudit`, propagated exact phase values
through owner-exit and owner-error evidence tests, and added exact rejection
coverage for unsupported, empty, wrong-case, and non-string phases. Its diff is
91 insertions and 24 deletions across the exact owner and harness. Scoped
re-review found the phase-domain finding addressed, no new Critical or
Important finding, and assessed the fix Ready.

Final repository identities at HEAD
`0ceb91607c8cb91c0d3bf723226bf2dec973b503` are:

| Reviewed repository file | Bytes | SHA-256 |
|---|---:|---|
| process owner | 20,664 | `F7AA04BC52E2013E96F0899ADA34B17877859A4F9D18420FBA6D5DC06616A281` |
| owner harness | 45,047 | `7998CC544241F0CA1C7AFEF6F8A7AEC0B7D806771211584BD4ED7A934C9E7BFF` |

Both parsed with zero errors. The owner exposes only `-ContractPath`, has the
exact 16-field schema and exact three-value phase domain, and contains zero
`Invoke-Expression`, `Start-Process`, `Stop-Process`, `cmd.exe`, `Kill`, or
cancellation invocations. The harness retains one `Kill()` invocation; its
receiver is exactly `$OwnerProcess` and it has zero arguments. Both the
unscoped and scoped reserved-variable memory mutations occur exactly once.

### Exact elevated owner gate

The implementer did not open UAC. The controller ran the exact symlink-inclusive
owner harness once with an Administrator token after the phase fix and while
all seven production-v17 stage/helper/contract paths were absent. Controller
exit was 0. Captured stdout is 180 bytes / SHA-256
`17E83A4FF25CFDBFF169CE4F6DEA7758C4404D913E2EBDE173AD627DCF5605C2`:

```text
PASS owner contract validation tests
PASS owner phase domain tests
PASS owner adversarial safety tests
PASS owner interruption classification tests
PASS owner lifecycle tests
```

Captured stderr is 0 bytes / SHA-256
`E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`.
No production helper, contract, runtime evidence, stage, child marker, or
assembler diagnostic was created by the owner tests.

### Immutable v17 helpers and static bindings

The final helpers were regenerated from the exact v16 sources after the phase
fix, so no provisional stale owner or harness pin survived. The obsolete three
hash-held helper copies were removed only after these final paths were written
and verified; they remain reproducible from the exact v16 sources and guarded
substitutions.

| External v17 helper | Bytes | SHA-256 |
|---|---:|---|
| wrapper | 3,349 | `29137E754BF0F2546646DE3062FA277B8C07B25C1289320B2CB5638C99B29B74` |
| preflight | 26,160 | `BE1BD6EDF814282A96BAE67C104F46CFFCBC54DBCFD6D58F19F2404F6F8D1BF1` |
| post-audit | 23,942 | `7DA98F05EA7E04B12F54EC77049B83BCCCA36E1659ABE910C82DF915AA2C65AA` |

All three are BOM-less UTF-8 and parse with zero errors. The wrapper differs
from v16 only in the exact v17 stage root,
`stage-runtime-v17.assembler.child.exit.txt`, and
`stage-runtime-v17.assembler.error.json`; normalizing those three owned
literals makes the semantic diff empty. Non-executing AST decoding found
exactly 16 unique assembler parameters, all recognized by the reviewed
assembler, with zero TestMode/synthetic/injection/hook/inventory/postcondition/
diagnostic/error-evidence/command/script-block surface. Compact sorted
parameter JSON is 1,431 bytes / SHA-256
`633A9B3CB63408948D078607607DCD17DAA17F2DFF64544E4F0C2D71E2704E41`.
The helper ASTs contain zero forbidden shell/process command surface.

Preflight and post-audit both bind the exact final owner and owner-harness
hashes. They retain stage pins 64,312 files / 3,334,971,045 bytes / manifest
`115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`,
direct Gnuplot `65 / 63 / 1002 / 249 / 563 / 190 / 0`, and platform-plugin
`2 / 2 / 38 / 6 / 15 / 17 / 0`.

### Strict production contracts

The three contracts are BOM-less strict UTF-8, each decodes as exactly one
`PSCustomObject` with exactly 16 unique closed-schema fields, and each has an
empty JSON string-array `Arguments`. The empty assembler argument array is the
reviewed wrapper's normal production interface; no shell command string exists.
All bind exact owner, pinned PowerShell 7.6.4, `C:\pure-lang`, and
`C:\tmp\todo51-task3`, plus their exact helper and hash.

| Phase / external contract | Bytes | SHA-256 |
|---|---:|---|
| Preflight / `stage-runtime-v17.preflight.owner-contract.json` | 1,042 | `B265511694D28F010FDFCDED256F1515C2FB27B70233C70DA0D22CB7E0B3821C` |
| Assembler / `stage-runtime-v17.assembler.owner-contract.json` | 1,034 | `8806FEE700BB53EDBA6CA996B1E78A500D612DAD8852A0A4FCD6FC1521E327C6` |
| PostAudit / `stage-runtime-v17.postaudit.owner-contract.json` | 1,036 | `1CDF913C4911B4DDFDE8E1B37F3535E734254E300450D3D1BB3843FF974B6921` |

The phase values are exactly `Preflight`, `Assembler`, and `PostAudit`.
Fifteen PID/stdout/stderr/owner-exit/owner-error paths are globally distinct,
strict descendants of the fixed evidence root, and absent. The independent
assembler child marker and seven-field diagnostic paths are also absent.

### Fresh complete verification gate

Pinned executable:
`C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe`,
SHA-256
`DB6DD81183FE57D22E03B911EC9A30A2FD7C40542E97743615355A6FB44F458F`.
After contract creation, the two repository harnesses ran freshly and exited 0
in 158.3 seconds. Together with the exact elevated owner output above, the full
three-harness gate is:

```text
PASS owner contract validation tests
PASS owner phase domain tests
PASS owner adversarial safety tests
PASS owner interruption classification tests
PASS owner lifecycle tests
PASS Test-RejectsProductionPinMutation
PASS Test-RejectsInexactSupplementSet
PASS Test-RejectsSupplementHashMismatch
PASS Test-RejectsUnresolvedSupplementImport
PASS Test-RejectsFabricatedApiSetImport
PASS Test-RejectsApiSetReleaseFailure
PASS Test-RejectsTruncatedApiSetPath
PASS Test-RejectsReparseSnapshotParent
PASS Test-RejectsExistingSnapshotOnApply
PASS Test-GoldenFileAssertionRejectsMutation
PASS Test-GoldenClosureAssertionRejectsOmission
PASS Test-PlansExactImmutableContract
PASS Test-RollsBackInjectedCopyFailure
PASS Test-AppliesTransactionallyAndPlansIdempotently
PASS Test-RejectsContaminatedExistingSnapshot
PASS all supplement preparer tests
PASS Test-HardBindsProductionAuditCardinalityTo1536PePlusOnePlaceholderAnd219Oct
PASS Test-HardBindsWindowsPlatformIdentityContract
PASS Test-SnapshotsSingleSyntheticPlatformIdentityBeforeFaultInjection
PASS Test-HardBindsProductionGnuplotLoaderContract
PASS Test-HardBindsProductionGnuplotPlatformPluginContract
PASS Test-ReportsExactSyntheticWindowsPlatformIdentity
PASS Test-RejectsEverySyntheticWindowsPlatformIdentityFault
PASS Test-RejectsProductionPlatformIdentityInjection
PASS Test-ReportsExactGnuplotLoaderCardinalitiesAndOrigins
PASS Test-ReportsExactGnuplotPlatformPluginCardinalitiesAndOrigins
PASS Test-ResolvesApprovedGnuplotPlatformPluginsOnlyInDirectGnuplotLoaderRoot
PASS Test-RejectsChangedCanonicalGnuplotFixtureInventory
PASS Test-RejectsUnapprovedGnuplotPlatformPluginPe
PASS Test-RejectsGnuplotPlatformPluginDirectoryFallback
PASS Test-RejectsGnuplotPlatformPluginCrossDomainFallbacks
PASS Test-RejectsGnuplotPlatformPluginPathFallback
PASS Test-RejectsNonPeApprovedGnuplotPlatformPlugin
PASS Test-RejectsGnuplotPlatformPluginDirectoryReparsePoint
PASS Test-RejectsApprovedGnuplotPlatformPluginReparsePoint
PASS Test-RejectsEveryGnuplotPostAuditCardinalityFault
PASS Test-RejectsEveryGnuplotPlatformPluginPostAuditCardinalityFault
PASS Test-RecordsEveryFailedGnuplotPlatformPluginImportAsUnresolved
PASS Test-HardBindsCombinedGnuplotDiagnosticSums
PASS Test-RejectsUnknownGnuplotApiSetMapping
PASS Test-RejectsMissingGnuplotSystem32Mapping
PASS Test-RejectsGnuplotApiSetReleaseFailure
PASS Test-RejectsGnuplotPureFallback
PASS Test-RejectsGnuplotOctaveFallback
PASS Test-RejectsGnuplotPathFallback
PASS Test-RejectsGnuplotCaseCollision
PASS Test-RejectsGnuplotSiblingFallback
PASS Test-RejectsGnuplotNestedFallback
PASS Test-RejectsGnuplotNonPeFile
PASS Test-RejectsGnuplotLoaderRootReparsePoint
PASS Test-RejectsGnuplotLoaderFileReparsePoint
PASS Test-RejectsProductionGnuplotTestInjections
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
PASS Test-AcceptsExactPinnedPureRsvgSupplement
PASS Test-RejectsMissingOrExtraSupplementFile
PASS Test-RejectsChangedSupplementHashOrMachine
PASS Test-RejectsSupplementReparseAndSourceSubstitution
PASS Test-RejectsSupplementDestinationCollision
PASS Test-RejectsFourthTransitiveDependency
PASS Test-HardBindsSupplementStagePostconditions
PASS Test-RejectsReparseParent
PASS all task3 staging tests
```

After the gate all six helper/contract byte counts and hashes remained exact.
There were zero disposable owner-test roots, zero sibling-escape roots, zero
matching test or production processes, and zero runtime evidence paths. The
v17 stage, child marker, and assembler diagnostic remained absent. No v17
preflight, assembler, or post-audit child was launched; launch counts are
exactly `0 / 0 / 0`. No in-progress or protected stage was inspected and no
staged binary was executed.

### Review sequencing correction and final contract creation

The first Task 4 evidence/spec review found no Critical, Important, or Minor
issue and returned `Ready`. It independently verified the immutable 99,362-byte
prefix, exact report suffix, all helper and contract hashes, parser and wrapper
diff gates, truthful phases, closed schemas, absent evidence, elevated log, and
report-only repository scope.

The first quality/security review returned `Not Ready` with one Important
chronology finding and no Critical or Minor finding: although the exact
post-phase-fix elevated owner run predated contract creation, the report's fresh
supplement and staging run occurred after contract creation and therefore did
not establish the brief's complete pre-contract gate.

The finding was resolved fail-closed. All three never-launched contracts were
first rehashed at their recorded identities, then only those exact files were
removed. All three contract paths and every runtime evidence/stage/marker/error
path were confirmed absent; launch counts remained `0 / 0 / 0`. At unchanged
HEAD `0ceb91607c8cb91c0d3bf723226bf2dec973b503`, pinned PowerShell 7.6.4 then
ran the complete supplement and staging harnesses while the contracts were
absent. The command exited 0 in 195 seconds. Its complete output was exactly
the repository-harness portion reproduced in the `Fresh complete verification
gate` block above, including every named PASS line and both aggregate sentinels:

```text
PASS all supplement preparer tests
PASS all task3 staging tests
```

Together with the already captured exact elevated owner run at the same HEAD,
owner/harness hashes, and absent contract paths, this establishes all three
required harnesses before the final contract creation.

Only after that passing gate, the three contracts were deterministically
recreated from the same ordered 16-field objects. Strict BOM-less UTF-8 parsing
again found one object, 16 unique fields, exact phase, and zero arguments in
each contract. Their byte/hash identities are unchanged:

- Preflight: 1,042 / `B265511694D28F010FDFCDED256F1515C2FB27B70233C70DA0D22CB7E0B3821C`;
- Assembler: 1,034 / `8806FEE700BB53EDBA6CA996B1E78A500D612DAD8852A0A4FCD6FC1521E327C6`;
- PostAudit: 1,036 / `1CDF913C4911B4DDFDE8E1B37F3535E734254E300450D3D1BB3843FF974B6921`.

No production owner, helper, or child was invoked during correction. Runtime
paths remained absent and launch counts remain exactly `0 / 0 / 0`.

The scoped evidence/spec re-review of the corrected chronology reports zero
Critical, Important, or Minor findings and verdict `Ready`. The scoped
quality/security re-review reports the sequencing finding addressed, zero
Critical, Important, or Minor findings, and verdict `Ready`. Both independently
rechecked the immutable prefix, report-only scope, external identities, strict
phase contracts, absent runtime paths, and launch counts `0 / 0 / 0`.

### Final post-review gate

After both clean re-review verdicts, the exact elevated owner stdout/stderr
hashes and all five sentinels were revalidated. Pinned PowerShell then reran the
complete supplement and staging harnesses; the command exited 0 in 191.4
seconds with the same full named PASS output reproduced above and both aggregate
sentinels. No production child launched and counts remained `0 / 0 / 0`.
