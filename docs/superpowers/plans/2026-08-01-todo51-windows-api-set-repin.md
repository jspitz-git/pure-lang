# TODO-51 Windows API-set Baseline Repin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the serviced Windows API-set baseline with an exact build/UBR/file identity contract, then create and statically accept one new immutable Task 3 production stage v13.

**Architecture:** The assembler reads one non-overridable production platform identity from the Windows registry and canonical System32 API-set file, validates every field before import resolution, and reports it only through existing audit output and final JSON. Synthetic tests use one exact disposable identity plus fixed fault selectors; after review, a new v13 helper set performs one preflight and at most one assembler launch while preserving all v12 evidence.

**Tech Stack:** PowerShell 7/Windows PowerShell-compatible scripts, .NET Registry and filesystem APIs, Authenticode/WinSxS read-only evidence, existing Task 3 staging harness, SHA-256, Git.

## Global Constraints

- Accepted coarse OS version: `Microsoft Windows NT 10.0.26200.0`.
- Accepted registry identity: `CurrentBuild = 26200` of kind `String`; `UBR = 8973` of kind `DWord`.
- Accepted API-set path is the canonical `%WINDIR%\System32\apisetschema.dll`, regular and non-reparse.
- Accepted API-set file version: `10.0.26100.8972 (WinBuild.160101.0800)`.
- Accepted API-set product version: `10.0.26100.8972`.
- Accepted API-set length: 194,048 bytes.
- Accepted API-set SHA-256: `E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8`.
- The exact hash is the production integrity boundary; valid Microsoft signature and exact WinSxS hard-link provenance are acceptance/report evidence, not a signature-only fallback.
- No caller parameter may override any platform identity value.
- Preserve all v11 and v12 helpers, logs, markers, and roots; never retry, repair, or reuse the v12 attempt.
- The next production root is exactly the currently absent `C:\tmp\todo51-task3\stage-runtime-v13` with newly named v13 evidence files.
- No staged binary executes during this plan.
- The complete stage remains exactly 64,312 files, 3,334,971,045 bytes, manifest `115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`, 1,539 PE files, 219 PE `.oct` modules, and one inert placeholder.
- The Gnuplot loader contract remains exactly `65 / 63 / 1002 / 249 / 563 / 190 / 0`.
- Never mutate permanent Octave, accepted Pure, normalized toolchain, SVG supplement/source, ACL/AppContainer/profile state, or prior evidence.
- A failed v13 preflight or assembler attempt is preserved and never retried.
- Every implementation task receives independent spec-compliance and code-quality review before acceptance.

## File structure

- Modify `pure-octave/probes/stage_task3_runtime.ps1`: exact accepted platform constants, registry/file identity reader, assertion, TestMode fault gate, and final JSON fields.
- Modify `pure-octave/probes/test_stage_task3_runtime.ps1`: synthetic platform fixture, success/mutation/provenance/production-gate tests, and unchanged suite assertions.
- Modify `pure-octave/probes/task-3-report.md`: preserve the complete v12 fail-closed record, append repin TDD/review evidence, then append v13 production evidence.
- Create only outside Git under `C:\tmp\todo51-task3`: new v13 wrapper, preflight, post-audit, PID/log/marker files, and the v13 stage.

---

### Task 1: Bind the serviced Windows platform identity

**Files:**
- Modify: `pure-octave/probes/stage_task3_runtime.ps1:1-120,515-570,928-955,1074-1131`
- Modify: `pure-octave/probes/test_stage_task3_runtime.ps1:1-214,222-420`
- Modify: `pure-octave/probes/task-3-report.md`

**Interfaces:**
- Consumes: canonical System32 root, `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion`, and the exact accepted constants in Global Constraints.
- Produces: `Get-WindowsPlatformIdentity([string] $System32) -> pscustomobject`, `Assert-PlatformIdentity([pscustomobject] $Actual, [pscustomobject] $Expected)`, and final JSON fields `WindowsOsVersion`, `WindowsCurrentBuild`, `WindowsUbr`, `ApiSetSchemaPath`, `ApiSetSchemaFileVersion`, `ApiSetSchemaProductVersion`, `ApiSetSchemaLength`, and `ApiSetSchemaSha256`.
- `Get-WindowsPlatformIdentity` is production-only and closes its registry handle in `finally`; TestMode constructs a separate exact synthetic object and never reads production registry metadata.

- [ ] **Step 1: Add failing literal and JSON contract tests**

Extend the source-contract block with exact assertions for:

```powershell
$acceptedOsVersion = 'Microsoft Windows NT 10.0.26200.0'
$acceptedCurrentBuild = '26200'
$acceptedCurrentBuildKind = 'String'
$acceptedUbr = [int]8973
$acceptedUbrKind = 'DWord'
$acceptedApiSchemaFileVersion = '10.0.26100.8972 (WinBuild.160101.0800)'
$acceptedApiSchemaProductVersion = '10.0.26100.8972'
$acceptedApiSchemaLength = [long]194048
$acceptedApiSchemaSha256 = 'E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8'
```

Require the eight final JSON field names and assert that no parameter begins
with `ExpectedWindows`, `ExpectedUbr`, `ExpectedCurrentBuild`, or
`ExpectedApiSet`.

- [ ] **Step 2: Add the failing synthetic identity matrix**

Add one harness helper that creates the exact disposable schema path:

```powershell
function Reset-PlatformIdentityFixture {
    $root = Join-Path $testRoot 'synthetic-system32'
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    [IO.Directory]::CreateDirectory($root) | Out-Null
    Write-TestFile (Join-Path $root 'apisetschema.dll') 'synthetic-api-set-schema'
}
```

Add `-InjectPlatformIdentityFault` to `Invoke-Stage` and pass only one of the
fixed values:

```text
OsVersion, CurrentBuild, Ubr, MissingCurrentBuild, MissingUbr,
CurrentBuildKind, UbrKind, FileVersion, ProductVersion, Length, Sha256,
OutsideSystem32, ReparseSchema, NonRegularSchema
```

The success fixture asserts the eight JSON fields match the exact synthetic
identity. Each fault must fail a field-specific message. The reparse fixture
uses the already proven fixed WindowsApps app-execution reparse file under the
exact test root; the non-regular fixture replaces only the synthetic schema
leaf with a directory.

- [ ] **Step 3: Run the staging harness and verify RED**

Run:

```powershell
& .\pure-octave\probes\test_stage_task3_runtime.ps1
```

Expected: nonzero exit at the first new literal/JSON contract assertion
because the current implementation knows only coarse OS version and old
schema hash.

- [ ] **Step 4: Implement the accepted constants and production reader**

Replace the old API-set constants with the literal assignments from Step 1.
Add this focused production reader beside the API-set resolver:

```powershell
function Get-WindowsPlatformIdentity([string] $System32) {
    $schema = Get-CanonicalExistingPath (Join-Path $System32 'apisetschema.dll') 'Windows API-set schema'
    Assert-SourceBoundary $schema $System32 'Windows API-set schema'
    Assert-RegularFile $schema 'Windows API-set schema'
    Assert-NoReparsePath $schema 'Windows API-set schema'
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion', $false)
    if ($null -eq $key) { throw 'Windows CurrentVersion registry key is missing.' }
    try {
        $currentBuild = $key.GetValue('CurrentBuild', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $ubr = $key.GetValue('UBR', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $currentBuild) { throw 'Windows CurrentBuild registry value is missing.' }
        if ($null -eq $ubr) { throw 'Windows UBR registry value is missing.' }
        $currentBuildKind = $key.GetValueKind('CurrentBuild').ToString()
        $ubrKind = $key.GetValueKind('UBR').ToString()
    }
    finally { $key.Dispose() }
    $item = Get-Item -LiteralPath $schema -Force
    return [pscustomobject]@{
        OsVersion=[Environment]::OSVersion.VersionString
        CurrentBuild=[string]$currentBuild; CurrentBuildKind=$currentBuildKind
        Ubr=[int]$ubr; UbrKind=$ubrKind
        ApiSetSchemaPath=$schema
        FileVersion=$item.VersionInfo.FileVersion
        ProductVersion=$item.VersionInfo.ProductVersion
        Length=[long]$item.Length
        Sha256=Get-Sha256File $schema
    }
}
```

- [ ] **Step 5: Implement exact assertion and synthetic isolation**

`Assert-PlatformIdentity` compares every field with ordinal string or numeric
equality and emits one unique message per field. Production builds the
expected object solely from accepted constants and the canonical expected
schema path. TestMode builds a fixed synthetic object after validating the
real exact fixture leaf, applies only the fixed fault selector, snapshots the
unmodified object as expected, then calls the same assertion.

Guard before input validation:

```powershell
if ($InjectPlatformIdentityFault -and -not $TestMode) {
    throw 'Platform identity fault injection is TestMode-only and has no production access.'
}
```

Do not expose a path, expected value, registry root, or metadata override.

- [ ] **Step 6: Preserve existing staged audit serialization and add JSON**

Continue writing `stage-api-set-contracts.tsv` in its existing format using
the observed OS version, canonical schema path, and observed SHA-256. Do not
add a new staged file. Add the eight platform fields to the final JSON object;
the audit TSV remains excluded by the existing `$excluded` list, so the stage
manifest/count/bytes stay unchanged.

- [ ] **Step 7: Run focused and full GREEN verification**

Run:

```powershell
& .\pure-octave\probes\test_prepare_task3_pure_rsvg_supplement.ps1
& .\pure-octave\probes\test_stage_task3_runtime.ps1
foreach ($path in @('.\pure-octave\probes\stage_task3_runtime.ps1','.\pure-octave\probes\test_stage_task3_runtime.ps1')) {
    $tokens=$null; $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path),[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw "$path`n$($errors | Out-String)" }
}
git diff --check
```

Expected: supplement 15/15, all existing 43 staging tests plus the new
platform identity tests pass, both parsers report zero errors, and diff check
exits 0.

- [ ] **Step 8: Record v12 and repin evidence**

Preserve the existing uncommitted v12 section in `task-3-report.md`. Append
the root-cause evidence (8521 to 8972 servicing transition, build/UBR,
signature and WinSxS hard-link provenance), RED/GREEN output, exact accepted
identity, production-injection failures, unchanged Gnuplot/stage pins, and a
statement that assembler launch count remains zero and v12 stage remains
absent.

- [ ] **Step 9: Commit and review Task 1**

After the fresh verification from Step 7, commit exactly:

```powershell
git add pure-octave/probes/stage_task3_runtime.ps1 pure-octave/probes/test_stage_task3_runtime.ps1 pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Repin Windows API-set baseline"
```

The SDD controller then performs independent spec-compliance and code-quality review over the complete Task 1 commit range. Apply and re-review any required fixes; do not begin Task 2 until the review gate is clean.

### Task 2: Produce and accept the sole production stage v13

**Files:**
- Modify: `pure-octave/probes/task-3-report.md`
- Read: `pure-octave/probes/stage_task3_runtime.ps1`
- Read: `pure-octave/probes/test_stage_task3_runtime.ps1`
- Create outside Git: `C:\tmp\todo51-task3\stage_v13_wrapper.ps1`, `stage_v13_preflight_audit.ps1`, `stage_v13_postaudit.ps1`, v13 PID/log/marker files, and `stage-runtime-v13`

**Interfaces:**
- Consumes: reviewed Task 1 assembler/tests/report and every immutable source pin from v12.
- Produces: one immutable static-only stage at `C:\tmp\todo51-task3\stage-runtime-v13`, or one preserved failed v13 attempt and a fail-closed stop.

- [ ] **Step 1: Require absent v13 and preserved v11/v12 evidence**

Verify `stage-runtime-v11` exists, all recorded v12 preflight helpers/logs/PID/
marker remain byte-identical to the report, and `stage-runtime-v12` remains
absent. Enumerate every intended v13 target, helper, PID, stdout, stderr, and
marker path literally and throw if any exists. Validate the disposable parent
and immutable roots as regular/non-reparse.

- [ ] **Step 2: Create and verify v13 helper scripts**

Create new helpers without modifying v12. The wrapper keeps exactly the same
16-key hashtable as v12 and changes only:

```powershell
$exitMarker = 'C:\tmp\todo51-task3\stage-runtime-v13.assembler.exit.txt'
StageRoot = 'C:\tmp\todo51-task3\stage-runtime-v13'
```

The preflight and post-audit use the reviewed Task 1 script/harness hashes and
the complete accepted platform identity. Parse all helpers with zero errors,
decode the wrapper through `Get-Command`, require exactly 16 recognized keys,
and reject text or parameters containing `TestMode`, `Synthetic`, `Inject`,
`Hook`, or inventory/stage-postcondition overrides.

- [ ] **Step 3: Run one full v13 preflight**

Launch the preflight hidden with the pinned PowerShell 7.6.4 executable via
`System.Diagnostics.ProcessStartInfo`, avoiding the known duplicate
`Path`/`PATH` `Start-Process` failure. Record PID, separate stdout/stderr, and
exit marker; poll only PID/log lengths/marker.

Require exit zero, empty stderr, one JSON object, all immutable source pins,
and this exact platform identity:

```text
Microsoft Windows NT 10.0.26200.0 / CurrentBuild 26200 / UBR 8973
apisetschema.dll 10.0.26100.8972 / 194048 bytes
E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8
```

If preflight fails, preserve all v13 evidence, append the exact failure to the
report, do not launch the assembler, and stop without a success commit.

- [ ] **Step 4: Launch the production assembler exactly once**

Immediately recheck target/marker absence, helper hashes, and decoded
parameters. Launch `stage_v13_wrapper.ps1` hidden under pinned PowerShell
7.6.4, record PID, and poll only process state, log lengths, and marker. Never
inspect an in-progress stage or launch a second assembler against v13.

- [ ] **Step 5: Require exact assembler result**

On success require marker zero, empty stderr, and one JSON object containing:

```text
FileCount 64312; TotalBytes 3334971045
ManifestSha256 115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0
AuditedPeFileCount 1539; AuditedOctFileCount 219
PinnedInertPlaceholderCount 1; PinnedPureRsvgSupplementCount 3
Gnuplot 65 / 63 / 1002 / 249 / 563 / 190 / 0
Windows Microsoft Windows NT 10.0.26200.0 / 26200 / 8973
API-set 10.0.26100.8972 / 194048 / E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8
```

Any other result preserves v13 and stops without retry or success commit.

- [ ] **Step 6: Perform independent static post-audit**

Without executing staged binaries, independently recompute the manifest,
counts, bytes, reparse status, PE/`.oct` inventory, placeholder, supplement,
Gnuplot edge split, complete import closure, API-set hosts and platform
identity, patched liboctave/libgcc hashes, and unchanged source/permanent
manifests. Require every exact value from Global Constraints.

- [ ] **Step 7: Run fresh repository verification**

Run both full harnesses, parse assembler/harness/v13 helpers, and run
`git diff --check`. Require all PASS sentinels, zero parser errors, and no
external/source/permanent mutation.

- [ ] **Step 8: Record, commit, and review accepted v13**

Append exact helper hashes, decoded parameters, preflight/assembler PIDs and
markers, log byte counts/hashes, JSON, independent post-audit, test output,
and no-execution/no-mutation evidence to `task-3-report.md`, then:

```powershell
git add pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Record repinned Task 3 runtime stage"
```

The SDD controller performs independent evidence/spec and code-quality review over the report commit. Only a clean review accepts v13.

Only an accepted v13 returns TODO-51 to the original strict AppContainer
runtime work. Runtime execution, ACL/profile creation, and cleanup remain
outside this repin plan.
