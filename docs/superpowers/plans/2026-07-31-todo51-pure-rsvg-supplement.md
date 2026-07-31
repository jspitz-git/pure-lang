# TODO-51 Pure SVG Runtime Supplement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the exact three-DLL clang64 SVG runtime closure to the disposable Pure stage without mutating the accepted Pure or permanent Octave roots, then produce a fully audited production stage.

**Architecture:** A repo-owned preparer creates one immutable disposable supplement snapshot and a generated contract containing exact file, ABI, import-closure, and predicted-stage postconditions. The staging assembler loads only the contract beside itself, copies the three pinned DLLs into the separate Pure loader directory, and rejects every override, collision, mismatch, reparse point, or closure escape before any staged execution.

**Tech Stack:** PowerShell 7/Windows PowerShell-compatible scripts, .NET SHA-256 and PE inspection, MinGW/LLVM `objdump`, Git, the existing Task 3 manifest serializer and synthetic staging harness.

## Global Constraints

- The supplement contains exactly `librsvg-2-2.dll`, `libunwind.dll`, and `libxml2-16.dll` under `bin/`.
- Source DLLs come only from `C:\msys64\clang64\bin`; the disposable snapshot root is exactly `C:\tmp\todo51-task3\pure-rsvg-supplement-v1`.
- Fixed source values are:
  - `librsvg-2-2.dll`: 5,882,880 bytes, SHA-256 `9F90DE3779E80F590B542AFDF79C105A403B0C566265D69EACBBF9B524338F89`.
  - `libunwind.dll`: 63,488 bytes, SHA-256 `60FA3C200899BC6E4A5876B82E2C656FF72FC53EC55979D99CB7C4EF640A6D96`.
  - `libxml2-16.dll`: 1,294,848 bytes, SHA-256 `C6C34A810D86C19C034A1BC96C4C500BDE8FB789DED69B434E67EEE773605852`.
- The supplement adds exactly 3 files and 7,241,216 bytes; the new stage must contain exactly 64,312 files and 3,334,971,045 bytes.
- The new stage must audit exactly 1,539 magic-byte PE files, including exactly 219 `.oct` files, plus exactly one pinned inert `qhelpgenerator.exe` placeholder.
- Pure PE files resolve only through `stage/pure/bin` plus authoritative Windows system resolution; Octave PE files resolve only through `stage/mingw64/bin` plus authoritative Windows system resolution; bridge PE files use the explicitly audited union.
- Never modify `C:\tmp\Relocated Pure Gplot Final Bundle 20260729` or `C:\Tools\GNU Octave\11.3.0`.
- The permanent Octave baseline remains 59,533 files, 2,797,722,287 bytes, manifest `95D51222C8000706D235A309EF1CAEA6D986B08F1B04A08671475AD041A18CCD`, and zero reparse points.
- Never execute a staged binary, modify ACL/AppContainer/profile state, use global `PATH` resolution, or delete retained v1-v10 evidence during this plan.
- A failed snapshot or stage target is preserved and never recycled.

---

### Task 1: Build and audit the immutable supplement contract

**Files:**
- Create: `pure-octave/probes/prepare_task3_pure_rsvg_supplement.ps1`
- Create: `pure-octave/probes/test_prepare_task3_pure_rsvg_supplement.ps1`
- Create: `pure-octave/probes/task3-pure-rsvg-supplement-contract.psd1`
- Modify: `pure-octave/probes/task-3-report.md`

**Interfaces:**
- Consumes: accepted v5 manifest `C:\tmp\todo51-task3\stage-runtime-v5\stage-manifest.tsv`, matching clang64 source DLLs, and accepted Pure root `C:\tmp\Relocated Pure Gplot Final Bundle 20260729`.
- Produces: `prepare_task3_pure_rsvg_supplement.ps1 -SourceBin <path> -PureRoot <path> -AcceptedStageManifest <path> -SnapshotRoot <path> -ContractOutput <path> -Mode Plan|Apply`; `task3-pure-rsvg-supplement-contract.psd1` with `SnapshotRoot`, `Files`, `ReusedPureDependencies`, `AddedFileCount`, `AddedBytes`, `ExpectedStageFileCount`, `ExpectedStageBytes`, `ExpectedStageManifestSha256`, `ExpectedAuditedPeCount`, `ExpectedAuditedOctCount`, and `ExpectedPinnedPlaceholderCount`.

- [ ] **Step 1: Write the failing contract tests**

Add real synthetic-fixture cases that call the preparer and assert these exact failures:

```powershell
Assert-Throws { Invoke-Preparer -Files @('librsvg-2-2.dll','libunwind.dll') } 'Supplement file set is not exact'
Assert-Throws { Invoke-Preparer -Mutate 'libxml2-16.dll' } 'Supplement SHA-256 mismatch'
Assert-Throws { Invoke-Preparer -ExtraImport 'libunexpected.dll' } 'Unresolved supplement import'
Assert-Throws { Invoke-Preparer -ReparseSnapshotParent } 'contains a reparse point'
Assert-Throws { Invoke-Preparer -ExistingSnapshot } 'Snapshot root must be absent'
```

The success fixture must assert exact three-file ordering, total 7,241,216 bytes, PE machine `pei-x86-64`, a deterministic predicted stage manifest, and byte-identical reuse of `zlib1.dll`, `libiconv-2.dll`, and every other Pure-provided closure member.

- [ ] **Step 2: Run the new harness and verify RED**

Run:

```powershell
& .\pure-octave\probes\test_prepare_task3_pure_rsvg_supplement.ps1
```

Expected: nonzero exit because `prepare_task3_pure_rsvg_supplement.ps1` and its contract do not exist.

- [ ] **Step 3: Implement fail-closed Plan mode**

Implement these focused functions in the preparer:

```powershell
function Get-RegularPinnedFile([string] $Path, [long] $Length, [string] $Sha256)
function Get-PeImports([string] $ObjdumpPath, [string] $PePath)
function Resolve-SupplementClosure([string[]] $RootNames, [string] $SourceBin, [string] $PureBin)
function Get-PredictedStageManifest([string] $AcceptedManifest, [object[]] $SupplementFiles)
```

`Resolve-SupplementClosure` must resolve each non-system import exactly once, record whether it comes from the supplement or accepted Pure bin, compare reused Pure bytes with clang64, and reject a fourth missing DLL. `Get-PredictedStageManifest` must reuse the exact staging serializer/order and add only the three `pure/bin/<name>` rows.

- [ ] **Step 4: Run Plan tests and verify GREEN**

Run the new harness. Expected: every Plan and negative case passes with no warning/error noise.

- [ ] **Step 5: Implement transactional Apply mode**

Apply must require an absent exact snapshot root, copy to a temporary sibling, rehash and re-audit all three files, atomically rename to the final root, rehash source files afterward, and remove only its exact temporary sibling on pre-rename failure. It must never overwrite or recycle an existing snapshot.

- [ ] **Step 6: Verify synthetic rollback and idempotent Plan**

Add failure injection after the first copied file, guarded by an exact synthetic root. Expected: final snapshot absent, temporary sibling absent, source unchanged. A Plan against a successfully created synthetic snapshot must report zero changes.

- [ ] **Step 7: Execute the real supplement checkpoint**

Read-only verify the real snapshot root is absent and non-reparse, then run one real Apply. Audit the generated contract, exact DLL hashes, full import closure, reused Pure equality, predicted 64,312/3,334,971,045/1,539/219/1 postconditions, source immutability, and permanent Octave baseline. Do not create a real stage.

- [ ] **Step 8: Update report and commit**

Append exact command, stdout/stderr hashes, contract values, snapshot manifest, import edges, before/after evidence, and cleanup status to `task-3-report.md`.

```powershell
git add pure-octave/probes/prepare_task3_pure_rsvg_supplement.ps1 pure-octave/probes/test_prepare_task3_pure_rsvg_supplement.ps1 pure-octave/probes/task3-pure-rsvg-supplement-contract.psd1 pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Add pinned Pure SVG runtime supplement"
```

Independent review must approve this task before Task 2.

### Task 2: Integrate the pinned supplement into staging

**Files:**
- Modify: `pure-octave/probes/stage_task3_runtime.ps1`
- Modify: `pure-octave/probes/test_stage_task3_runtime.ps1`
- Read: `pure-octave/probes/task3-pure-rsvg-supplement-contract.psd1`
- Modify: `pure-octave/probes/task-3-report.md`

**Interfaces:**
- Consumes: Task 1's hard-coded sibling contract and immutable snapshot.
- Produces: staging production mode that copies exactly three verified supplement DLLs into `stage/pure/bin` and enforces the contract's exact final postconditions. No caller-visible supplement path, hash, count, or manifest override is permitted.

- [ ] **Step 1: Add failing staging regressions**

Extend the existing harness with named cases:

```powershell
Test-AcceptsExactPinnedPureRsvgSupplement
Test-RejectsMissingOrExtraSupplementFile
Test-RejectsChangedSupplementHashOrMachine
Test-RejectsSupplementReparseAndSourceSubstitution
Test-RejectsSupplementDestinationCollision
Test-RejectsFourthTransitiveDependency
Test-HardBindsSupplementStagePostconditions
```

The success fixture must reproduce the current `pixbufloader_svg.dll -> librsvg-2-2.dll` edge and prove that it fails before the supplement implementation exists.

- [ ] **Step 2: Run the staging harness and verify RED**

Run `test_stage_task3_runtime.ps1`. Expected: the new success case fails with missing effective import `librsvg-2-2.dll`.

- [ ] **Step 3: Load the contract from the fixed sibling path**

Use only:

```powershell
$supplementContractPath = Join-Path $PSScriptRoot 'task3-pure-rsvg-supplement-contract.psd1'
$supplementContract = Import-PowerShellDataFile -LiteralPath $supplementContractPath
```

Validate the contract file is regular/non-reparse, contains exactly the declared schema keys, exactly three files, exact source/snapshot roots, and exact fixed arithmetic. Do not add a parameter that can replace it.

- [ ] **Step 4: Copy and track the exact supplement**

Before any stage write, validate snapshot identity and source before-hashes. During stage creation, copy each contract file to `pure/bin/<name>` through the existing tracked-copy mechanism. Reject any existing destination, name collision, unlisted snapshot file, or mapping mismatch. Rehash snapshot and original clang64 source after copying.

- [ ] **Step 5: Enforce the new full-tree audit**

Require the contract's exact 64,312 files, 3,334,971,045 bytes, predicted manifest SHA, 1,539 audited PE, 219 `.oct`, and one inert placeholder. The `pixbufloader_svg.dll` import must resolve uniquely to `stage/pure/bin/librsvg-2-2.dll`; all three supplement DLLs and their transitive dependencies must remain in the Pure loader group.

- [ ] **Step 6: Run full GREEN verification**

Run:

```powershell
& .\pure-octave\probes\test_stage_task3_runtime.ps1
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\pure-octave\probes\stage_task3_runtime.ps1), [ref]$null, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
git diff --check
```

Expected: all old and new named tests pass; parser and diff check exit 0.

- [ ] **Step 7: Update report and commit**

Record RED/GREEN, exact contract binding, collision/closure negative tests, and unchanged permanent/source evidence. Do not run a real stage.

```powershell
git add pure-octave/probes/stage_task3_runtime.ps1 pure-octave/probes/test_stage_task3_runtime.ps1 pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Stage pinned Pure SVG runtime closure"
```

Independent review must approve this task before Task 3.

### Task 3: Produce and accept the supplemented production stage

**Files:**
- Modify: `pure-octave/probes/task-3-report.md`
- Read: all Task 1 and Task 2 scripts/contracts

**Interfaces:**
- Consumes: reviewed snapshot/contract and reviewed staging assembler.
- Produces: one accepted, static-only production stage at the currently absent exact root `C:\tmp\todo51-task3\stage-runtime-v11`, plus report evidence and a report-only commit.

- [ ] **Step 1: Select and preflight one new stage root**

Use only `C:\tmp\todo51-task3\stage-runtime-v11`; verify the target, marker, and all parents are absent/regular/non-reparse immediately before launch. Preserve v1-v10. If v11 is no longer absent, stop and amend the reviewed plan rather than selecting another path implicitly.

- [ ] **Step 2: Re-audit every immutable input**

Verify the permanent Octave baseline, normalized toolchain evidence, accepted Pure inventory, bridge/probe/test inputs, patched `liboctave-13.dll`, canonical `libgcc_s_seh-1.dll`, supplement snapshot, and supplement contract. Any mismatch stops before launch.

- [ ] **Step 3: Launch exactly once in the background**

Use a literal hashtable wrapper with keys validated through `Get-Command`, no `TestMode` or hook keys, recorded wrapper/assembler/contract SHA values, hidden process, separate stdout/stderr, and an exit marker. Poll only PID/log/marker until completion; never inspect or execute an in-progress stage.

- [ ] **Step 4: Require clean process evidence**

Expected: exit marker `0`, empty stderr, and one final JSON object. Any other result preserves the partial stage and ends this task without a success commit.

- [ ] **Step 5: Perform independent static post-audit**

Recompute and require the contract's exact manifest SHA, 64,312 files, 3,334,971,045 bytes, zero reparse, 1,539 PE split by extension, 219 `.oct`, one inert placeholder, three supplement DLLs, patched Octave hash, canonical libgcc hash, complete unique import closure, authoritative API-set mappings, and unchanged source/permanent manifests.

- [ ] **Step 6: Run fresh regression suites**

Run both supplement and staging harnesses, parse all changed PowerShell files, and run `git diff --check`. Expected: zero failures and clean output.

- [ ] **Step 7: Record and commit the accepted stage**

Append launcher, stdout/stderr/exit, inventory, supplement, PE/import, API-set, source/permanent, and no-execution evidence.

```powershell
git add pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Record supplemented Task 3 runtime stage"
```

Independent review must approve the static stage. The controller then returns to the existing Task 3 brief for strict AppContainer runtime execution; runtime execution and cleanup are not part of this supplement plan.
