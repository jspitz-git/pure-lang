# TODO-51 Gnuplot Application Loader Domain Implementation Plan

> **Rejected on 2026-08-08.** Historical record only. Do not implement or
> resume this work without a new approved TODO.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Audit the bundled Windows Gnuplot tree with its real application-directory loader semantics, then create and statically accept one new immutable Task 3 production stage.

**Architecture:** The existing stage assembler gains one exact `pure-gnuplot-app` domain for regular magic-byte PE files directly under `pure/tools/gnuplot/bin`. Its resolver searches only that same directory and authoritative Windows API-set/System32 mappings; production pins the directory and edge cardinalities, while synthetic fixtures exercise the boundary without weakening the pins.

**Tech Stack:** PowerShell 7/Windows PowerShell-compatible scripts, .NET filesystem and SHA-256 APIs, MinGW/LLVM `objdump`, the existing synthetic staging harness, Git.

## Global Constraints

- The dedicated relative root is exactly `pure/tools/gnuplot/bin`; no similarly named, nested, or sibling directory inherits this domain.
- Gnuplot application imports resolve only in that exact directory, then through authoritative Windows API-set/System32 resolution.
- Never fall back from the Gnuplot domain to `pure/bin`, `mingw64/bin`, global `PATH`, or an installed runtime.
- The production Gnuplot root has exactly 65 direct regular files, 63 direct magic-byte PE files, and 1,002 audited import edges: 249 application-directory, 563 API-set, 190 System32, zero unresolved/cross-domain.
- `Qt6Core.dll` is 7,481,344 bytes with SHA-256 `7C9D615B82CE3971A05484D610DC4D920FD889525096F53A0820B1A150D89F6F` and resolves beside `gnuplot_qt.exe`.
- The complete stage remains exactly 64,312 files, 3,334,971,045 bytes, manifest SHA-256 `115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`, 1,539 magic-byte PE files, 219 PE `.oct` modules, and one pinned inert placeholder.
- Preserve `C:\tmp\todo51-task3\stage-runtime-v11` and all prior stage/snapshot evidence; never repair or recycle a failed root.
- The next production root is exactly the currently absent `C:\tmp\todo51-task3\stage-runtime-v12`.
- Never modify `C:\tmp\Relocated Pure Gplot Final Bundle 20260729`, `C:\Tools\GNU Octave\11.3.0`, the normalized toolchain, the SVG supplement snapshot, ACLs, profiles, or global environment.
- No staged binary executes during this plan. AppContainer runtime verification resumes only after the static v12 stage is accepted.
- Every implementation task receives independent spec-compliance review followed by code-quality review before its commit is accepted.

## File structure

- Modify `pure-octave/probes/stage_task3_runtime.ps1`: classify the exact Gnuplot domain, construct its private filename set, resolve and count its edges, enforce production pins, and report the result.
- Modify `pure-octave/probes/test_stage_task3_runtime.ps1`: build synthetic Gnuplot fixtures and cover successful, isolated, malformed, and postcondition-fault cases.
- Modify `pure-octave/probes/task-3-report.md`: retain the v11 failure/root-cause evidence and record reviewed implementation plus the sole v12 production outcome.
- Create only disposable evidence under `C:\tmp\todo51-task3`: new v12 wrapper, preflight, logs, marker, and accepted stage; no generated evidence file enters the repository.

---

### Task 1: Implement the isolated application-directory resolver

**Files:**
- Modify: `pure-octave/probes/stage_task3_runtime.ps1:770-890`
- Modify: `pure-octave/probes/test_stage_task3_runtime.ps1:79-192,201-448`

**Interfaces:**
- Consumes: stage-relative PE paths, `$pureSet`, `$octaveSet`, and one direct-file set rooted at `stage/pure/tools/gnuplot/bin`.
- Produces: `Get-LoaderDomain([string] $Relative) -> string`, `New-DirectLoaderSet([string] $Root, [string] $Description) -> hashtable`, and `Get-EffectiveLoaderSet([string] $Domain, [hashtable] $PureSet, [hashtable] $OctaveSet, [hashtable] $GnuplotSet) -> hashtable`.
- Domain names are exactly `pure`, `octave`, `bridge`, and `pure-gnuplot-app`; `stage-import-closure.tsv` records `pure-gnuplot-app` in its existing group column.

- [ ] **Step 1: Add the failing exact-directory success regression**

Extend the fixture before the first `Invoke-Stage` call:

```powershell
function Add-GnuplotFixture([hashtable] $Imports) {
    Write-TestPe (Join-Path $pure 'tools\gnuplot\bin\gnuplot_qt.exe') 'gnuplot-qt'
    Write-TestPe (Join-Path $pure 'tools\gnuplot\bin\Qt6Core.dll') 'qt6-core'
    $Imports['pure/tools/gnuplot/bin/gnuplot_qt.exe'] = @('Qt6Core.dll')
    $Imports['pure/tools/gnuplot/bin/Qt6Core.dll'] = @()
    return $Imports
}

function Remove-GnuplotFixture {
    $root = Join-Path $pure 'tools\gnuplot'
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

$gnuplotSuccess = Invoke-Stage 'gnuplot-appdir-success' (Add-GnuplotFixture (New-BaseImports))
Assert-True ($gnuplotSuccess.ExitCode -eq 0) "Gnuplot application-directory fixture failed: $($gnuplotSuccess.Output)"
$closure = Get-Content -LiteralPath (Join-Path $gnuplotSuccess.Stage 'stage-import-closure.tsv') -Raw
Assert-True ($closure -match 'gnuplot_qt\.exe"\tpure-gnuplot-app\tQt6Core\.dll\t"[^"\r\n]+\\pure\\tools\\gnuplot\\bin\\Qt6Core\.dll"') 'Gnuplot Qt6Core import did not resolve in its exact application directory.'
Remove-GnuplotFixture
```

- [ ] **Step 2: Run the staging harness and verify RED**

Run:

```powershell
& .\pure-octave\probes\test_stage_task3_runtime.ps1
```

Expected: nonzero exit; `gnuplot_qt.exe` is classified as `pure` and fails with `Missing effective import Qt6Core.dll` because `Qt6Core.dll` is not in `pure/bin`.

- [ ] **Step 3: Add exact loader-domain classification and set construction**

Add these functions beside the existing PE/import helpers:

```powershell
function Get-LoaderDomain([string] $Relative) {
    $gnuplotPrefix = 'pure/tools/gnuplot/bin/'
    if ($Relative.StartsWith($gnuplotPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $leaf = $Relative.Substring($gnuplotPrefix.Length)
        if ($leaf.Length -gt 0 -and $leaf.IndexOf('/') -lt 0) { return 'pure-gnuplot-app' }
    }
    if ($Relative.StartsWith('pure/', [StringComparison]::OrdinalIgnoreCase)) { return 'pure' }
    if ($Relative.StartsWith('bridge/', [StringComparison]::OrdinalIgnoreCase)) { return 'bridge' }
    return 'octave'
}

function New-DirectLoaderSet([string] $Root, [string] $Description) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "$Description is absent or is not a directory: $Root" }
    Assert-NoReparsePath $Root $Description
    $set = @{}
    foreach ($item in Get-ChildItem -LiteralPath $Root -File -Force) {
        Assert-NoReparsePath $item.FullName "$Description file"
        $key = $item.Name.ToLowerInvariant()
        if ($set.ContainsKey($key)) { throw "$Description has an ambiguous case-insensitive filename: $($item.Name)" }
        $set[$key] = @($item.FullName)
    }
    return $set
}

function Get-EffectiveLoaderSet([string] $Domain, [hashtable] $PureSet, [hashtable] $OctaveSet, [hashtable] $GnuplotSet) {
    switch ($Domain) {
        'pure' { return $PureSet }
        'octave' { return $OctaveSet }
        'pure-gnuplot-app' { return $GnuplotSet }
        'bridge' {
            $union = @{}
            foreach ($set in @($PureSet,$OctaveSet)) {
                foreach ($key in $set.Keys) {
                    if (-not $union.ContainsKey($key)) { $union[$key] = @() }
                    $union[$key] += $set[$key]
                }
            }
            return $union
        }
        default { throw "Unknown staged loader domain: $Domain" }
    }
}
```

Build `$gnuplotSet` only from `Join-Path $StageRoot 'pure\tools\gnuplot\bin'`, replace the inline group expression with `Get-LoaderDomain`, and replace the inline effective-set expression with `Get-EffectiveLoaderSet`.

Production always requires the exact Gnuplot root. To preserve unrelated synthetic tests, TestMode uses an empty hashtable when the synthetic Gnuplot root is absent; when present it must still pass the full direct-set validation.

- [ ] **Step 4: Run the exact-directory regression and full harness GREEN**

Run the entire staging harness. Expected: the new Gnuplot test and all existing 27 named staging tests pass; the closure line names `pure-gnuplot-app` and the exact staged Qt6Core target.

- [ ] **Step 5: Add failing isolation regressions**

Create separate fixtures asserting these failures:

```powershell
$onlyPure = Add-GnuplotFixture (New-BaseImports)
$onlyPure['pure/tools/gnuplot/bin/gnuplot_qt.exe'] = @('libpure.dll')
Assert-Failure (Invoke-Stage 'gnuplot-no-pure-fallback' $onlyPure) 'Missing effective import libpure\.dll' 'Gnuplot Pure fallback'

$onlyOctave = Add-GnuplotFixture (New-BaseImports)
$onlyOctave['pure/tools/gnuplot/bin/gnuplot_qt.exe'] = @('liboctave-13.dll')
Assert-Failure (Invoke-Stage 'gnuplot-no-octave-fallback' $onlyOctave) 'Missing effective import liboctave-13\.dll' 'Gnuplot Octave fallback'
```

Also add named cases that put `path-only.dll` in a temporary directory prepended to process `PATH`, put a sibling DLL under `pure/tools/other/bin`, and put a nested DLL under `pure/tools/gnuplot/bin/plugins`; each import must still fail as missing. Restore process `PATH` in `finally`.

Call Remove-GnuplotFixture after every specialized case, and from the harness finally block, so later legacy fixtures cannot inherit Gnuplot files without matching import-manifest rows.

- [ ] **Step 6: Add malformed-domain regressions**

Add named tests for a non-PE `pure/tools/gnuplot/bin/bad.dll`, a reparse file/root, and a duplicate-by-case resolver candidate. Because the last condition cannot be created portably on a case-insensitive filesystem, add a `TestMode`-only `-InjectGnuplotCaseCollision` switch that appends a second `qt6core.dll` candidate after `New-DirectLoaderSet`; reject the switch before production input validation when `-TestMode` is absent.

Expected patterns:

```powershell
'Staged loadable file does not contain a PE image'
'reparse point'
'Ambiguous effective staged import Qt6Core.dll|ambiguous case-insensitive filename'
```

- [ ] **Step 7: Run full verification and commit Task 1**

Run:

```powershell
& .\pure-octave\probes\test_stage_task3_runtime.ps1
$tokens = $null; $errors = $null
[void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\pure-octave\probes\stage_task3_runtime.ps1), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
git diff --check
```

Expected: every named test passes, parser errors are zero, and `git diff --check` exits 0. Obtain independent spec and quality approval, then commit only the two files:

```powershell
git add pure-octave/probes/stage_task3_runtime.ps1 pure-octave/probes/test_stage_task3_runtime.ps1
git diff --cached --check
git commit -m "Audit Gnuplot application loader domain"
```

### Task 2: Bind and report the production Gnuplot contract

**Files:**
- Modify: `pure-octave/probes/stage_task3_runtime.ps1:74-105,775-927`
- Modify: `pure-octave/probes/test_stage_task3_runtime.ps1:201-448`
- Modify: `pure-octave/probes/task-3-report.md`

**Interfaces:**
- Consumes: Task 1's `pure-gnuplot-app` classification and effective set.
- Produces: `Assert-GnuplotLoaderPostconditions(...)`, exact non-overridable production constants, and final JSON fields `GnuplotLoaderFileCount`, `GnuplotLoaderPeFileCount`, `GnuplotLoaderImportEdgeCount`, `GnuplotLoaderApplicationDirectoryEdgeCount`, `GnuplotLoaderApiSetEdgeCount`, `GnuplotLoaderSystem32EdgeCount`, and `GnuplotLoaderUnresolvedEdgeCount`.

- [ ] **Step 1: Add failing production-pin and edge-count tests**

Add source-level assertions for these literal assignments:

```powershell
$acceptedGnuplotRelativeRoot = 'pure/tools/gnuplot/bin'
$acceptedGnuplotFileCount = 65
$acceptedGnuplotPeFileCount = 63
$acceptedGnuplotImportEdgeCount = 1002
$acceptedGnuplotApplicationDirectoryEdgeCount = 249
$acceptedGnuplotApiSetEdgeCount = 563
$acceptedGnuplotSystem32EdgeCount = 190
```

Extend the successful two-PE synthetic fixture so `gnuplot_qt.exe` imports `Qt6Core.dll`, one mapped API-set contract, and one mapped ordinary System32 DLL. Expand the synthetic system manifest parser only in `TestMode` to accept ordinary safe DLL names as explicit System32 mappings. Assert `2 / 2 / 3 / 1 / 1 / 1 / 0` in the JSON fields.

Add `-InjectGnuplotPostAuditFault` with the exact `ValidateSet` values `FileCount`, `PeCount`, `ImportEdgeCount`, `ApplicationDirectoryEdgeCount`, `ApiSetEdgeCount`, `System32EdgeCount`, and `UnresolvedEdgeCount`; every injected value must fail the corresponding postcondition. Add unknown-API-set and missing-System32 cases, plus a guarded `TestMode`-only `-InjectGnuplotApiSetReleaseFailure` case that must fail with `API-set contract mapping could not be freed`; production rejects that switch before input validation.

- [ ] **Step 2: Run the new tests and verify RED**

Run the full staging harness. Expected: nonzero exit because the production constants, JSON fields, fault switch, and Gnuplot postcondition assertion do not yet exist.

- [ ] **Step 3: Implement exact cardinality and edge accounting**

Add `Assert-GnuplotLoaderPostconditions` with seven actual and seven expected numeric arguments. Immediately after PE classification, count direct files and direct Gnuplot PE members. During import resolution, increment exactly one Gnuplot edge origin:

```powershell
if ($pe.Group -ceq 'pure-gnuplot-app') {
    $gnuplotImportEdgeCount++
    if ($effective.ContainsKey($key)) { $gnuplotApplicationDirectoryEdgeCount++ }
    elseif ($key.StartsWith('api-ms-win-') -or $key.StartsWith('ext-ms-win-')) { $gnuplotApiSetEdgeCount++ }
    else { $gnuplotSystem32EdgeCount++ }
}
```

Increment `$gnuplotUnresolvedEdgeCount` immediately before throwing for a missing or cross-domain import. In production, compare against the seven fixed constants; in `TestMode`, snapshot the fixture's observed values as expectations before applying a guarded fault injection. Require the sum of the three resolved origin counts plus unresolved count to equal the total edge count.

For synthetic ordinary System32 mappings, resolve only a manifest-listed safe DLL name to `synthetic-system32\<host>`; an unlisted name remains missing. Keep the production branch unchanged: it must validate the real System32 file and its non-reparse path. The Gnuplot API-set release injection runs only after a mapped synthetic contract and proves that a release failure aborts rather than producing an accepted edge.

- [ ] **Step 4: Expose audit evidence without changing stage inventory**

Add the seven fields to the existing final JSON object only. Keep `stage-import-closure.tsv` as the per-edge evidence and do not create another staged report file, because any added staged file would violate the pinned 64,312-file manifest.

- [ ] **Step 5: Run all GREEN verification**

Run both repo-owned suites and parse every changed script:

```powershell
& .\pure-octave\probes\test_prepare_task3_pure_rsvg_supplement.ps1
& .\pure-octave\probes\test_stage_task3_runtime.ps1
foreach ($path in @('.\pure-octave\probes\stage_task3_runtime.ps1','.\pure-octave\probes\test_stage_task3_runtime.ps1')) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$path`n$($errors | Out-String)" }
}
git diff --check
```

Expected: supplement 15/15 and the expanded staging harness pass, parser errors are zero, and diff check exits 0.

- [ ] **Step 6: Record v11 diagnosis and reviewed implementation**

Append to `task-3-report.md` the preserved v11 failure, proof that its exact Gnuplot directory has 65 files/63 PEs/1,002 edges split 249/563/190 with zero missing, Qt6Core identity, TDD RED/GREEN output, no-fallback negatives, exact production pins, and unchanged inventory/source evidence. State explicitly that no new stage or staged execution occurred in Tasks 1-2.

- [ ] **Step 7: Review and commit Task 2**

Obtain independent spec-compliance and code-quality approval, then run fresh suites once more and commit only the reviewed implementation and report:

```powershell
git add pure-octave/probes/stage_task3_runtime.ps1 pure-octave/probes/test_stage_task3_runtime.ps1 pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Bind Gnuplot loader domain audit"
```

### Task 3: Create and accept the sole production stage v12

**Files:**
- Modify: `pure-octave/probes/task-3-report.md`
- Read: `pure-octave/probes/stage_task3_runtime.ps1`
- Read: `pure-octave/probes/test_stage_task3_runtime.ps1`
- Read: `pure-octave/probes/task3-pure-rsvg-supplement-contract.psd1`
- Create outside Git: `C:\tmp\todo51-task3\stage_v12_wrapper.ps1`, `stage_v12_preflight_audit.ps1`, v12 logs/markers, and `stage-runtime-v12`

**Interfaces:**
- Consumes: reviewed Task 2 assembler and tests plus all immutable v11 input pins.
- Produces: one immutable static-only stage at `C:\tmp\todo51-task3\stage-runtime-v12`, or one preserved failed v12 artifact and a fail-closed stop.

- [ ] **Step 1: Verify the one permitted target and preserved evidence**

Require all of these assertions before creating any v12 helper:

```powershell
if (-not (Test-Path -LiteralPath 'C:\tmp\todo51-task3\stage-runtime-v11' -PathType Container)) { throw 'Preserved v11 evidence is absent.' }
foreach ($path in @(
    'C:\tmp\todo51-task3\stage-runtime-v12',
    'C:\tmp\todo51-task3\stage-runtime-v12.assembler.exit.txt',
    'C:\tmp\todo51-task3\stage-runtime-v12.assembler.stdout.log',
    'C:\tmp\todo51-task3\stage-runtime-v12.assembler.stderr.log')) {
    if (Test-Path -LiteralPath $path) { throw "v12 target/evidence must be absent: $path" }
}
```

Validate `C:\tmp\todo51-task3` and every immutable source root as regular/non-reparse using the reviewed v11 preflight logic.

- [ ] **Step 2: Create and verify new v12 helpers**

Create new files; never edit the v11 helpers. `stage_v12_wrapper.ps1` must retain the v11 literal 16-key hashtable exactly except for these two values:

```powershell
$exitMarker = 'C:\tmp\todo51-task3\stage-runtime-v12.assembler.exit.txt'
StageRoot = 'C:\tmp\todo51-task3\stage-runtime-v12'
```

Use the same fixed permanent, Pure, normalized, bridge, probe, patched-DLL, libgcc, objdump, snapshot, and idempotence-evidence values shown in `stage_v11_wrapper.ps1`. Clone the reviewed v11 preflight checks, change only v11-owned output/target names to v12, and replace its assembler/test hashes with freshly computed literal SHA-256 values. Verify `Get-Command` reports exactly 16 bound parameters and none contains `TestMode`, `Synthetic`, `Inject`, `Hook`, or an inventory override.

- [ ] **Step 3: Run the full immutable-input preflight**

Launch the v12 preflight under the same pinned PowerShell 7.6.4 executable used for v11, with separate stdout, stderr, PID, and exit marker files. Require marker 0, empty stderr, one JSON object, all 59,533 normalized/permanent snapshot records, accepted Pure/bridge/probe hashes, patched liboctave and canonical libgcc hashes, SVG supplement/source/38-member reuse closure, repository test files, build evidence, OS/API-set pins, and absent v12 stage/assembler marker.

- [ ] **Step 4: Launch the assembler exactly once**

Start `stage_v12_wrapper.ps1` hidden with separate exact stdout/stderr files and record its PID. Poll only process state, log lengths, and the exit marker; do not inspect the in-progress stage. Never launch a second assembler against v12.

- [ ] **Step 5: Branch on the immutable result**

If marker is nonzero, stderr is nonempty, stdout is not one JSON object, or the wrapper disappears without a marker: preserve all v12 files, append the exact hashes/error to `task-3-report.md`, do not commit a success, and stop for root-cause analysis.

For success, require marker 0 and empty stderr. Parse the single JSON object and require:

```text
FileCount                                      64312
TotalBytes                                     3334971045
ManifestSha256                                 115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0
AuditedPeFileCount                             1539
AuditedOctFileCount                            219
PinnedInertPlaceholderCount                   1
PinnedPureRsvgSupplementCount                  3
GnuplotLoaderFileCount                        65
GnuplotLoaderPeFileCount                      63
GnuplotLoaderImportEdgeCount                  1002
GnuplotLoaderApplicationDirectoryEdgeCount    249
GnuplotLoaderApiSetEdgeCount                  563
GnuplotLoaderSystem32EdgeCount                190
GnuplotLoaderUnresolvedEdgeCount              0
```

- [ ] **Step 6: Perform an independent static post-audit**

Without executing any staged binary, recompute the complete manifest/count/bytes, zero-reparse status, PE and `.oct` cardinalities, placeholder and SVG supplement identities, patched liboctave/canonical libgcc hashes, all import edges, authoritative API-set hosts, and the exact Gnuplot 65/63/1,002 split. Rehash every immutable source and compare the permanent Octave tree to its 59,533-file, 2,797,722,287-byte, `95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD` baseline.

- [ ] **Step 7: Run fresh repository regressions**

Run the two full harnesses, parse the assembler/harness/wrapper/preflight scripts, and run `git diff --check`. Expected: all tests pass, parser errors are zero, and no source/permanent/evidence mutation is observed.

- [ ] **Step 8: Record, review, and commit the accepted stage**

Append exact helper hashes, decoded parameters, preflight/assembler PID and markers, stdout/stderr byte counts and hashes, JSON, independent post-audit, test output, and no-execution/no-mutation evidence to `task-3-report.md`. Obtain independent evidence/spec review, then:

```powershell
git add pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Record Gnuplot-aware Task 3 runtime stage"
```

After this commit, return to the original TODO-51 Task 3 strict AppContainer runtime work. Runtime execution, ACL/profile creation, and cleanup are outside this loader-domain plan.
