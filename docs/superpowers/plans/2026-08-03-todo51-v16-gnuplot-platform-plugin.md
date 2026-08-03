# TODO-51 v16 Gnuplot Platform Plugin Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Audit the two bundled Qt platform plugins against the exact Gnuplot application root, then create and statically accept one new immutable Task 3 production stage.

**Architecture:** Keep the existing direct-file `pure-gnuplot-app` domain unchanged and add one allowlisted `pure-gnuplot-platform-plugin` domain for exactly `platforms/qminimal.dll` and `platforms/qwindows.dll`. Both plugin imports resolve only against direct files in `pure/tools/gnuplot/bin`, then authoritative Windows API-set/System32 mappings; independent production counters bind the new domain without changing the staged payload.

**Tech Stack:** PowerShell 7.6.4, Windows PowerShell-compatible scripts, .NET filesystem and SHA-256 APIs, LLVM/MinGW `objdump`, `System.Diagnostics.ProcessStartInfo`, Git.

## Global Constraints

- Preserve every v11-v15 helper, PID, log, marker, error JSON, stage, and report artifact byte-for-byte. Check partial `stage-runtime-v14` and `stage-runtime-v15` only with `Test-Path`; never enumerate, read, execute, modify, clean, or recycle either partial stage.
- Preserve the uncommitted v15 BLOCKED section in `pure-octave/probes/task-3-report.md` until the reviewed v16 diagnostic checkpoint commits it.
- The existing `pure-gnuplot-app` domain remains restricted to regular PE files directly under exact relative root `pure/tools/gnuplot/bin`.
- The new domain name is exactly `pure-gnuplot-platform-plugin` and its only members are `pure/tools/gnuplot/bin/platforms/qminimal.dll` and `pure/tools/gnuplot/bin/platforms/qwindows.dll`.
- No other direct, sibling, similarly named, or nested path inherits the plugin domain.
- Plugin imports resolve only in the direct Gnuplot root, then through authoritative Windows API-set/System32 resolution. Never fall back to the plugin directory, `pure/bin`, `mingw64/bin`, the bridge union, process `PATH`, or an installed runtime.
- The existing direct Gnuplot contract remains `65 / 63 / 1002 / 249 / 563 / 190 / 0` for direct files, direct PEs, total edges, Gnuplot-root edges, API-set edges, System32 edges, and unresolved edges.
- The plugin contract is exactly `2 / 2 / 38 / 6 / 15 / 17 / 0` for files, PEs, total edges, Gnuplot-root edges, API-set edges, System32 edges, and unresolved edges.
- Diagnostic combined Gnuplot totals are `65 PE / 1040 edges / 255 Gnuplot-root / 578 API-set / 207 System32 / 0 unresolved`; independent direct and plugin postconditions remain authoritative.
- The complete stage remains exactly 64,312 files, 3,334,971,045 bytes, manifest SHA-256 `115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`, 1,539 PE files, 219 PE `.oct` modules, one inert placeholder, and three Pure-RSVG supplements.
- Accepted platform identity remains `Microsoft Windows NT 10.0.26200.0`, `CurrentBuild 26200`, `UBR 8973`, API-set file/product version `10.0.26100.8972 (WinBuild.160101.0800)` / `10.0.26100.8972`, length `194048`, SHA-256 `E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8`.
- Every process owner uses pinned PowerShell 7.6.4 at `C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe`, SHA-256 `DB6DD81183FE57D22E03B911EC9A30A2FD7C40542E97743615355A6FB44F458F`, and explicit `sandbox_permissions = require_escalated`.
- V16 permits exactly one preflight launch, then exactly one assembler launch after accepted preflight, then exactly one post-audit launch after accepted assembler success. There is no retry or recycle.
- During a production process inspect only PID, stdout/stderr lengths, and marker presence. Never inspect an in-progress stage or execute a staged binary.
- A failed production attempt appends exact evidence but creates no success commit. A successful attempt requires independent static post-audit, full repository verification, task review, and whole-branch review.
- Every task receives an independent specification-compliance review followed by a code-quality review before its commit is accepted.

## File Structure

- Modify `pure-octave/probes/stage_task3_runtime.ps1`: classify the exact plugin allowlist, reuse the Gnuplot-root loader set, maintain independent plugin counters, enforce production pins, and expose plugin evidence in the final JSON.
- Modify `pure-octave/probes/test_stage_task3_runtime.ps1`: reproduce the real `platforms` layout and cover success, allowlist, isolation, reparse, cardinality, and production-surface failures.
- Modify `pure-octave/probes/task-3-report.md`: preserve v15 failure evidence, record the reviewed v16 helper gate, and record the sole v16 production result.
- Create only external evidence under `C:\tmp\todo51-task3`: disposable wrapper diagnostics plus distinct v16 wrapper, preflight, post-audit, PID, logs, markers, error JSON, and stage paths.

---

### Task 1: Implement the exact Qt platform-plugin loader domain

**Files:**
- Modify: `pure-octave/probes/stage_task3_runtime.ps1:429-469,922-960,1065-1135`
- Modify: `pure-octave/probes/test_stage_task3_runtime.ps1:107-118,250-487`

**Interfaces:**
- Consumes: normalized stage-relative paths and Task 3's existing `$gnuplotSet` created by `New-DirectLoaderSet` from `pure/tools/gnuplot/bin`.
- Produces: `Test-GnuplotPlatformPluginRelative([string] $Relative) -> bool`, `Get-LoaderDomain([string] $Relative) -> string`, and an added `pure-gnuplot-platform-plugin` branch in `Get-EffectiveLoaderSet(...) -> hashtable`.
- The existing `stage-import-closure.tsv` group column records `pure-gnuplot-platform-plugin`; no new staged evidence file is created.

- [ ] **Step 1: Extend the synthetic fixture with the real plugin layout**

Add this helper beside `Add-GnuplotFixture`:

```powershell
function Add-GnuplotPlatformPluginFixture([hashtable] $Imports) {
    Write-TestPe (Join-Path $pure 'tools\gnuplot\bin\platforms\qminimal.dll') 'qminimal'
    Write-TestPe (Join-Path $pure 'tools\gnuplot\bin\platforms\qwindows.dll') 'qwindows'
    $Imports['pure/tools/gnuplot/bin/platforms/qminimal.dll'] = @('Qt6Gui.dll','Qt6Core.dll','kernel32.dll')
    $Imports['pure/tools/gnuplot/bin/platforms/qwindows.dll'] = @('Qt6Gui.dll','Qt6Core.dll','user32.dll')
    return $Imports
}
```

Create a focused success case by applying `Add-GnuplotFixture` and then `Add-GnuplotPlatformPluginFixture`. Require process exit zero and two closure rows whose group is exactly `pure-gnuplot-platform-plugin` and whose `Qt6Gui.dll`/`Qt6Core.dll` targets are direct children of the staged Gnuplot `bin` root.

- [ ] **Step 2: Run the focused case and verify RED**

Run:

```powershell
& .\pure-octave\probes\test_stage_task3_runtime.ps1
```

Expected: nonzero exit with `Missing effective import Qt6Gui.dll` for `platforms\qminimal.dll`, because the current classifier returns `pure` and searches `pure/bin`.

- [ ] **Step 3: Implement the minimal exact allowlist**

Add exact normalized constants and classification before the direct-file branch:

```powershell
$acceptedGnuplotPlatformPluginRelatives = @(
    'pure/tools/gnuplot/bin/platforms/qminimal.dll',
    'pure/tools/gnuplot/bin/platforms/qwindows.dll'
)

function Test-GnuplotPlatformPluginRelative([string] $Relative) {
    foreach ($approved in $acceptedGnuplotPlatformPluginRelatives) {
        if ($Relative.Equals($approved, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
```

In `Get-LoaderDomain`, return `pure-gnuplot-platform-plugin` for an approved path. If a PE path starts with exact prefix `pure/tools/gnuplot/bin/platforms/` but is not approved, throw `Unapproved Gnuplot platform plugin PE: <relative>`. Keep the existing direct-leaf branch unchanged. Add this exact effective-set branch:

```powershell
'pure-gnuplot-platform-plugin' { return $GnuplotSet }
```

- [ ] **Step 4: Run focused and full GREEN verification**

Run the full staging harness. Require the focused success sentinel, exact closure group/targets, all pre-existing Gnuplot boundary sentinels, and final `PASS all task3 staging tests`.

- [ ] **Step 5: Add allowlist and isolation regressions**

Add named cases with these exact outcomes:

```powershell
# third platform PE
Write-TestPe (Join-Path $pure 'tools\gnuplot\bin\platforms\qthird.dll') 'qthird'
$imports['pure/tools/gnuplot/bin/platforms/qthird.dll'] = @()
# => Unapproved Gnuplot platform plugin PE

# plugin-directory fallback
$imports['pure/tools/gnuplot/bin/platforms/qminimal.dll'] = @('qwindows.dll')
# => Missing effective import qwindows.dll

# cross-domain fallbacks
$imports['pure/tools/gnuplot/bin/platforms/qminimal.dll'] = @('libpure.dll')
# => Missing effective import libpure.dll
$imports['pure/tools/gnuplot/bin/platforms/qminimal.dll'] = @('liboctave-13.dll')
# => Missing effective import liboctave-13.dll
```

Also put `path-only.dll` on a temporary prepended `PATH` and require it missing from a plugin import. Restore `PATH` in `finally`. Existing sibling/nested direct-domain tests must continue to fail with their existing messages.

- [ ] **Step 6: Add exact plugin-path safety regressions**

Use test-only fixture setup to create a reparse `platforms` directory and a reparse approved plugin file; require the existing `reparse point` guard to reject each. Require a non-PE approved `.dll` to fail with `Staged loadable file does not contain a PE image`. Do not add a production caller parameter for the allowlist.

- [ ] **Step 7: Verify, review, and commit Task 1**

Run:

```powershell
& .\pure-octave\probes\test_stage_task3_runtime.ps1
foreach ($path in @('.\pure-octave\probes\stage_task3_runtime.ps1','.\pure-octave\probes\test_stage_task3_runtime.ps1')) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$path`n$($errors | Out-String)" }
}
git diff --check
```

Require all named tests plus the aggregate sentinel, zero parser errors, and clean diff check. Obtain task-scoped spec and quality review, then commit only the two implementation files:

```powershell
git add pure-octave/probes/stage_task3_runtime.ps1 pure-octave/probes/test_stage_task3_runtime.ps1
git diff --cached --check
git commit -m "Audit Gnuplot platform plugin domain"
```

### Task 2: Bind independent production plugin cardinalities

**Files:**
- Modify: `pure-octave/probes/stage_task3_runtime.ps1:93-100,376-419,960-980,1056-1165,1220-1244`
- Modify: `pure-octave/probes/test_stage_task3_runtime.ps1:250-487`

**Interfaces:**
- Consumes: Task 1's exact plugin classification and direct `$gnuplotSet` resolution.
- Produces: `Assert-GnuplotPlatformPluginPostconditions(...)`, seven non-overridable production constants, seven `GnuplotPlatformPlugin*` JSON fields, and one `TestMode`-only `-InjectGnuplotPlatformPluginPostAuditFault` surface.

- [ ] **Step 1: Add failing source-pin and evidence tests**

Require these exact production literals:

```powershell
$acceptedGnuplotPlatformPluginFileCount = 2
$acceptedGnuplotPlatformPluginPeFileCount = 2
$acceptedGnuplotPlatformPluginImportEdgeCount = 38
$acceptedGnuplotPlatformPluginApplicationDirectoryEdgeCount = 6
$acceptedGnuplotPlatformPluginApiSetEdgeCount = 15
$acceptedGnuplotPlatformPluginSystem32EdgeCount = 17
$acceptedGnuplotPlatformPluginUnresolvedEdgeCount = 0
```

Extend the synthetic plugin fixture with one mapped API-set and one mapped ordinary System32 import per plugin. Require final JSON fields to report the exact observed synthetic split. Add `-InjectGnuplotPlatformPluginPostAuditFault` with `ValidateSet('FileCount','PeCount','ImportEdgeCount','ApplicationDirectoryEdgeCount','ApiSetEdgeCount','System32EdgeCount','UnresolvedEdgeCount')`; require production use without `-TestMode` to fail before input validation.

- [ ] **Step 2: Run the full harness and verify RED**

Expected: nonzero exit because the constants, independent counters, assertion, JSON fields, and guarded injection do not exist.

- [ ] **Step 3: Implement independent counters and postconditions**

Add `Assert-GnuplotPlatformPluginPostconditions` with seven actual and seven expected integer arguments, including the invariant:

```powershell
if ($ImportEdgeCount -ne ($ApplicationDirectoryEdgeCount + $ApiSetEdgeCount + $System32EdgeCount + $UnresolvedEdgeCount)) {
    throw 'Gnuplot platform plugin import edge origins do not sum to the total.'
}
```

Count exactly the two allowlisted PE records after full-tree classification. For every import whose group is `pure-gnuplot-platform-plugin`, increment one plugin total and exactly one origin using the same decision tree as `pure-gnuplot-app`. Increment unresolved immediately before throwing for missing ordinary, missing/invalid API-set, or ambiguous effective imports.

In production compare with the seven fixed constants. In `TestMode`, snapshot observed values before applying one guarded fault. Keep the existing direct Gnuplot counters and `Assert-GnuplotLoaderPostconditions` byte-for-byte in meaning.

- [ ] **Step 4: Expose exact evidence and combined diagnostic invariants**

Add these final JSON fields only; do not create a staged file:

```powershell
GnuplotPlatformPluginFileCount
GnuplotPlatformPluginPeFileCount
GnuplotPlatformPluginImportEdgeCount
GnuplotPlatformPluginApplicationDirectoryEdgeCount
GnuplotPlatformPluginApiSetEdgeCount
GnuplotPlatformPluginSystem32EdgeCount
GnuplotPlatformPluginUnresolvedEdgeCount
```

Assert diagnostic sums `65 / 1040 / 255 / 578 / 207 / 0` from the independently validated direct/plugin counters in production. Do not replace either independent assertion with combined-only pins.

- [ ] **Step 5: Add every cardinality fault regression**

Loop over all seven injection values and require the matching exact failure:

```powershell
$messages = @{
    FileCount = 'Gnuplot platform plugin file count does not match the expected postcondition'
    PeCount = 'Gnuplot platform plugin PE file count does not match the expected postcondition'
    ImportEdgeCount = 'Gnuplot platform plugin import edge count does not match the expected postcondition'
    ApplicationDirectoryEdgeCount = 'Gnuplot platform plugin application-directory edge count does not match the expected postcondition'
    ApiSetEdgeCount = 'Gnuplot platform plugin API-set edge count does not match the expected postcondition'
    System32EdgeCount = 'Gnuplot platform plugin System32 edge count does not match the expected postcondition'
    UnresolvedEdgeCount = 'Gnuplot platform plugin unresolved edge count does not match the expected postcondition'
}
```

Require missing/unknown API-set, missing System32, missing Gnuplot-root, and ambiguous Gnuplot-root imports to increment plugin unresolved evidence before failing. Reuse the existing case-collision injection only in `TestMode`; do not add a second collision surface.

- [ ] **Step 6: Run complete GREEN verification**

Run:

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

Require supplement 15/15 plus `PASS all supplement preparer tests`, every staging sentinel plus `PASS all task3 staging tests`, zero parser errors, and clean diff check.

- [ ] **Step 7: Review and commit Task 2**

Obtain task-scoped spec and quality review. Commit only the reviewed assembler and harness:

```powershell
git add pure-octave/probes/stage_task3_runtime.ps1 pure-octave/probes/test_stage_task3_runtime.ps1
git diff --cached --check
git commit -m "Bind Gnuplot platform plugin audit"
```

### Task 3: Prove and bind the v16 diagnostic/helper gate

**Files:**
- Create outside Git: `C:\tmp\todo51-task3\wrapper-diagnostic-v16\test_v16_wrapper_diagnostics.ps1`
- Create outside Git: `C:\tmp\todo51-task3\wrapper-diagnostic-v16\throw-child.ps1`
- Create outside Git: `C:\tmp\todo51-task3\wrapper-diagnostic-v16\success-child.ps1`
- Create outside Git: `C:\tmp\todo51-task3\stage_v16_wrapper.ps1`
- Modify: `pure-octave/probes/task-3-report.md`

**Interfaces:**
- Consumes: reviewed Task 2 HEAD, preserved reviewed v15 wrapper/harness behavior, and the uncommitted v15 BLOCKED report append.
- Produces: reviewed v16 wrapper hash, exact seven-field error contract, disposable RED/GREEN evidence, and one clean report checkpoint before production.

- [ ] **Step 1: Verify immutable start and absent v16 paths**

Require the Task 2 HEAD and a worktree whose only modification is the preserved `pure-octave/probes/task-3-report.md`. Verify hashes of all v15 wrapper/error/PID/log/marker evidence. Check `stage-runtime-v15` only with `Test-Path=True`. Require every v16 diagnostic fixture, wrapper, stage, PID, log, marker, and error path absent.

- [ ] **Step 2: Write the v16 RED/GREEN wrapper fixture**

Derive disposable SUTs from the preserved reviewed v15 wrapper using exact assembler/stage/marker/error substitutions. The throwing child contains only:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
throw 'V16_DIAGNOSTIC_THROW_SENTINEL'
```

The success child emits exactly `V16_DIAGNOSTIC_SUCCESS_SENTINEL`. Before installing the v16 wrapper, point the fixture at a v15-derived wrapper with its diagnostic block removed and require RED: process/marker `1/1`, stderr sentinel, absent JSON, and harness error `Expected independent error JSON was not created.`

- [ ] **Step 3: Create the minimal v16 wrapper**

Derive `stage_v16_wrapper.ps1` from accepted v15. Change only v15-owned stage, marker, and error paths:

```powershell
$exitMarker = 'C:\tmp\todo51-task3\stage-runtime-v16.assembler.exit.txt'
$errorEvidence = 'C:\tmp\todo51-task3\stage-runtime-v16.assembler.error.json'
StageRoot = 'C:\tmp\todo51-task3\stage-runtime-v16'
```

Retain the exact 16-key assembler hashtable and the reviewed pre-existing-error guard. The catch writes BOM-less UTF-8 only when the error path is absent, with exactly `TimestampUtc`, `ExceptionType`, `Message`, `FullyQualifiedErrorId`, `Category`, `ScriptStackTrace`, and `InvocationPosition`.

- [ ] **Step 4: Run GREEN failure, success, and stale-evidence cases outside sandbox**

Through pinned PowerShell 7.6.4 require:

- failure process/marker `1/1`, strict BOM-less UTF-8, exactly one seven-field JSON object, sentinel message/stack/stderr;
- success process/marker `0/0`, exact stdout sentinel, empty stderr, absent JSON;
- pre-existing error evidence causes process/marker `1/1` and remains byte-for-byte unchanged;
- aggregate `PASS all v16 wrapper diagnostic tests`.

- [ ] **Step 5: Verify helper surfaces and normalized diff**

Parse wrapper/harness/children with zero errors. Decode `-PrintBoundParams`; require 16 unique recognized keys and zero `TestMode`, `Synthetic`, `Inject`, `Hook`, inventory, postcondition, or caller-controlled diagnostic surfaces. Normalize only v15/v16 stage, marker, error, and sentinel literals; require no other v15-v16 wrapper diff. Require all production v16 paths still absent.

- [ ] **Step 6: Record, review, and commit the v16 gate**

Append the v15 immutable blocker, Task 1-2 RED/GREEN results and commits, v16 diagnostic RED/GREEN/stale evidence, exact hashes, parser/surface/diff gates, and explicit no-v16-production statement to `task-3-report.md`. Run both full repository harnesses and `git diff --check`, obtain task-scoped review, then:

```powershell
git add pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Record v16 Gnuplot plugin gate"
```

### Task 4: Perform the sole v16 production attempt

**Files:**
- Read: `pure-octave/probes/stage_task3_runtime.ps1`
- Read: `pure-octave/probes/test_stage_task3_runtime.ps1`
- Read outside Git: `C:\tmp\todo51-task3\stage_v16_wrapper.ps1`
- Create outside Git: `C:\tmp\todo51-task3\stage_v16_preflight_audit.ps1`
- Create outside Git: `C:\tmp\todo51-task3\stage_v16_postaudit.ps1`
- Create outside Git: v16 PID/stdout/stderr/marker/error evidence and `C:\tmp\todo51-task3\stage-runtime-v16`
- Modify: `pure-octave/probes/task-3-report.md`

**Interfaces:**
- Consumes: cleanly reviewed Task 3 commit, all immutable v15 input/helper pins, Task 2's independent plugin contract, and the exact v16 wrapper.
- Produces: one accepted static-only v16 stage or one preserved failed v16 attempt with independent seven-field diagnostics.

- [ ] **Step 1: Require preserved history and absent v16 production paths**

Verify Task 3 clean HEAD; all preserved v11-v15 helper/evidence hashes; v12/v13 absence rules; and v14/v15 partial-stage existence using only `Test-Path`. Enumerate every intended v16 helper, stage, PID, stdout, stderr, marker, error, and post-audit path literally and require absence before helper creation. Validate the disposable parent and all immutable source roots as regular/non-reparse.

- [ ] **Step 2: Create and statically verify v16 audit helpers**

Derive preflight and post-audit helpers from reviewed v15 helpers by changing v15-owned paths/hashes and adding the reviewed Task 2 assembler/test hashes plus all seven plugin JSON fields and exact `2 / 2 / 38 / 6 / 15 / 17 / 0` pins. Parse every helper; verify exact wrapper hash, 16 decoded parameters, forbidden-surface count zero, pinned PowerShell identity, immutable manifests, serviced platform identity, and absent production paths.

- [ ] **Step 3: Launch the v16 preflight exactly once**

Use an escalated `ProcessStartInfo` owner. Immediately before `Start()`, recheck absent evidence, exact helper/repository hashes, and a create/read/remove/absence host-write probe. Record PID and poll only PID, stdout/stderr lengths, and marker presence.

Require process/marker `0/0`, empty stderr, exactly one PASS JSON object, all immutable manifests, exact platform identity, exact repository/helper hashes, and absent stage/assembler/error paths. Any failure preserves evidence, records launch counts `1/0/0`, and stops without retry or commit.

- [ ] **Step 4: Launch the v16 assembler exactly once**

Only after accepted preflight, recheck absent stage/PID/log/marker/error/post-audit paths, helper hashes, decoded parameters, and a fresh host-write probe. Launch the reviewed wrapper with an escalated owner, record PID, and poll only PID/log lengths/marker. Never inspect the in-progress stage.

- [ ] **Step 5: Classify the immutable assembler result**

On marker `1`, require nonzero process exit and independently validate a regular/non-reparse BOM-less strict UTF-8 error JSON with exactly seven fields. Record bytes, SHA-256, and values without reading the partial stage. Preserve everything; launch no post-audit, success harness, cleanup, or retry, and create no success commit.

On marker `0`, require process exit zero, empty stderr, exactly one JSON object, absent error JSON, and these values:

```text
FileCount                                                   64312
TotalBytes                                                  3334971045
ManifestSha256                                              115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0
AuditedPeFileCount                                          1539
AuditedOctFileCount                                         219
PinnedInertPlaceholderCount                                1
PinnedPureRsvgSupplementCount                              3
GnuplotLoaderFileCount                                     65
GnuplotLoaderPeFileCount                                   63
GnuplotLoaderImportEdgeCount                               1002
GnuplotLoaderApplicationDirectoryEdgeCount                 249
GnuplotLoaderApiSetEdgeCount                               563
GnuplotLoaderSystem32EdgeCount                             190
GnuplotLoaderUnresolvedEdgeCount                           0
GnuplotPlatformPluginFileCount                             2
GnuplotPlatformPluginPeFileCount                           2
GnuplotPlatformPluginImportEdgeCount                       38
GnuplotPlatformPluginApplicationDirectoryEdgeCount         6
GnuplotPlatformPluginApiSetEdgeCount                       15
GnuplotPlatformPluginSystem32EdgeCount                     17
GnuplotPlatformPluginUnresolvedEdgeCount                   0
```

Any mismatch is an immutable failure without retry or success commit.

- [ ] **Step 6: Launch one independent static post-audit after success only**

The escalated post-audit recomputes whole-stage manifest/count/bytes, zero-reparse status, PE/`.oct` inventory, placeholder, supplement, direct Gnuplot and plugin path/edge splits, combined Gnuplot diagnostic sums, complete import closure, authoritative API-set hosts/platform identity, patched liboctave/libgcc hashes, and unchanged source/permanent manifests. It never executes a staged binary.

- [ ] **Step 7: Run fresh repository verification after accepted post-audit only**

Require supplement 15/15 with `PASS all supplement preparer tests`; every staging sentinel with `PASS all task3 staging tests`; zero parser errors across assembler, harness, wrapper, preflight, post-audit, and diagnostic harness; `git diff --check`; unchanged immutable manifests; and zero staged-binary executions.

- [ ] **Step 8: Record, review, and commit an accepted v16 stage**

Append exact helper/evidence hashes, PIDs, markers, JSON, post-audit, tests, launch counts `1/1/1`, and no-execution/no-mutation evidence. Stage only the report, run cached checks, obtain task-scoped review, and commit:

```powershell
git add pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Record Gnuplot plugin aware Task 3 stage"
```

Perform a whole-branch review after the task review is clean. Only then accept v16 and return to the original TODO-51 strict AppContainer runtime work.
