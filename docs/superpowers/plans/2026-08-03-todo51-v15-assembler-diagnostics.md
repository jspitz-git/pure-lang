# TODO-51 v15 Assembler Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add independently testable top-level assembler error evidence, then perform one fail-closed v15 production staging attempt outside the restricted sandbox.

**Architecture:** Task 1 derives a v15 wrapper from preserved v14, proves its catch behavior through the same detached PowerShell 7.6.4 boundary using disposable failure and success fixtures, and records the reviewed diagnostic checkpoint. Task 2 creates new v15 audit helpers, runs exactly one preflight and at most one assembler outside the sandbox, then either preserves a failed attempt or accepts an independently audited static stage.

**Tech Stack:** PowerShell 7.6.4, Windows `System.Diagnostics.ProcessStartInfo`, SHA-256 evidence, Git.

## Global Constraints

- Preserve every v11-v14 helper, PID, log, marker, stage, and report artifact byte-for-byte; check partial `stage-runtime-v14` only for existence and never enumerate, read, execute, modify, or delete its contents.
- Preserve the existing uncommitted v13/v14 sections in `pure-octave/probes/task-3-report.md`.
- All disposable diagnostic fixtures live under `C:\tmp\todo51-task3\wrapper-diagnostic-v15`; they must not access any stage or immutable production input.
- The v15 production error path is exactly `C:\tmp\todo51-task3\stage-runtime-v15.assembler.error.json`, is not a caller parameter, and is absent on success.
- The error JSON has exactly `TimestampUtc`, `ExceptionType`, `Message`, `FullyQualifiedErrorId`, `Category`, `ScriptStackTrace`, and `InvocationPosition`.
- Every command owning diagnostic, preflight, or assembler `ProcessStartInfo`, PID writes, or polling uses `sandbox_permissions = require_escalated` and pinned PowerShell 7.6.4 at `C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe`, SHA-256 `DB6DD81183FE57D22E03B911EC9A30A2FD7C40542E97743615355A6FB44F458F`.
- V15 permits exactly one preflight launch and, only after accepted preflight, exactly one assembler launch. There is no retry or recycle.
- During production processes inspect only PID, stdout/stderr lengths, and marker presence. Never inspect an in-progress stage or execute a staged binary.
- Accepted platform identity remains `Microsoft Windows NT 10.0.26200.0`, `CurrentBuild 26200`, `UBR 8973`, API-set file/product version `10.0.26100.8972 (WinBuild.160101.0800)` / `10.0.26100.8972`, length `194048`, SHA-256 `E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8`.
- Accepted stage remains 64,312 files, 3,334,971,045 bytes, manifest `115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`, 1,539 PE files, 219 `.oct` files, one inert placeholder, three Pure-RSVG supplements, and Gnuplot `65 / 63 / 1002 / 249 / 563 / 190 / 0`.
- A failed production attempt appends exact evidence but creates no success commit. A successful attempt is accepted only after static post-audit, full repository verification, and clean task review.

---

### Task 1: Prove and bind the v15 diagnostic wrapper

**Files:**
- Create outside Git: `C:\tmp\todo51-task3\wrapper-diagnostic-v15\test_v15_wrapper_diagnostics.ps1`
- Create outside Git: `C:\tmp\todo51-task3\wrapper-diagnostic-v15\throw-child.ps1`
- Create outside Git: `C:\tmp\todo51-task3\wrapper-diagnostic-v15\success-child.ps1`
- Create outside Git: `C:\tmp\todo51-task3\stage_v15_wrapper.ps1`
- Modify: `pure-octave/probes/task-3-report.md`

**Interfaces:**
- Consumes: preserved `C:\tmp\todo51-task3\stage_v14_wrapper.ps1`, reviewed repository HEAD, and the existing v13/v14 report append.
- Produces: a reviewed v15 wrapper hash, a disposable RED/GREEN fixture report, and a clean report checkpoint for the production task.

- [ ] **Step 1: Verify immutable starting state**

Require branch `todo/51-windows-strict-write-confinement`, record HEAD, and require `git status --short` to contain only the preserved modification to `pure-octave/probes/task-3-report.md`. Verify recorded hashes for v12-v14 helpers/evidence. Require `stage-runtime-v14` to exist using only `Test-Path`; do not enumerate it. Require every Task 1 diagnostic fixture path and `stage_v15_wrapper.ps1` absent.

- [ ] **Step 2: Write the failing behavioral diagnostic test**

Create `throw-child.ps1`:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
throw 'V15_DIAGNOSTIC_THROW_SENTINEL'
```

Create `success-child.ps1`:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
'V15_DIAGNOSTIC_SUCCESS_SENTINEL'
```

Create `test_v15_wrapper_diagnostics.ps1` so it:

1. copies the preserved v14 wrapper into a disposable current-contract SUT;
2. replaces only assembler, marker, and stage-root literals with fixture literals;
3. launches the SUT through pinned PowerShell 7.6.4 using redirected stdout/stderr;
4. requires process/marker `1/1` and exact error JSON path existence;
5. fails with `Expected independent error JSON was not created.` when the current wrapper has only stderr evidence.

The expected JSON fields and values are hand-written literals; the test must not compute them using wrapper code.

- [ ] **Step 3: Run RED outside the sandbox**

Run the test owner with `sandbox_permissions = require_escalated`.

Expected: exit 1 with exactly `Expected independent error JSON was not created.` Confirm process/marker `1/1`, stderr contains `V15_DIAGNOSTIC_THROW_SENTINEL`, and the error JSON is absent. Record hashes and byte counts of RED fixture evidence.

- [ ] **Step 4: Create the minimal v15 wrapper**

Derive `stage_v15_wrapper.ps1` from preserved v14. Change only v14-owned stage/marker literals and add:

```powershell
$errorEvidence = 'C:\tmp\todo51-task3\stage-runtime-v15.assembler.error.json'
```

Before invoking the assembler, throw if `$errorEvidence` already exists. In the existing top-level `catch`, use the caught `ErrorRecord` to create:

```powershell
$record = $_
$diagnostic = [ordered]@{
    TimestampUtc          = [DateTime]::UtcNow.ToString('o')
    ExceptionType         = $record.Exception.GetType().FullName
    Message               = $record.Exception.Message
    FullyQualifiedErrorId = $record.FullyQualifiedErrorId
    Category              = $record.CategoryInfo.ToString()
    ScriptStackTrace      = $record.ScriptStackTrace
    InvocationPosition    = $record.InvocationInfo.PositionMessage
}
[IO.File]::WriteAllText(
    $errorEvidence,
    (($diagnostic | ConvertTo-Json -Compress -Depth 3) + [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false))
[Console]::Error.WriteLine(($record | Out-String))
```

Keep the 16-key assembler hashtable unchanged except `StageRoot`, and keep marker writing in `finally` after the diagnostic write.

- [ ] **Step 5: Run GREEN failure and success fixtures**

Update the harness to derive each disposable SUT from the actual v15 wrapper by exact literal substitution only. For the throwing child require:

- process/marker `1/1`;
- one regular, non-reparse UTF-8 JSON file;
- exactly the seven global-constraint fields;
- `Message = V15_DIAGNOSTIC_THROW_SENTINEL`;
- non-empty `ExceptionType` and `ScriptStackTrace`;
- stderr containing the sentinel.

For the success child require process/marker `0/0`, stdout exactly `V15_DIAGNOSTIC_SUCCESS_SENTINEL`, empty stderr, and absent error JSON. Require the aggregate sentinel `PASS all v15 wrapper diagnostic tests`.

- [ ] **Step 6: Verify production wrapper invariants**

Parse the wrapper and harness with zero PowerShell parser errors. Decode `-PrintBoundParams` through `Get-Command`; require 16 unique recognized keys and zero `TestMode`, `Synthetic`, `Inject`, `Hook`, inventory, stage-postcondition, or caller-controlled diagnostic surfaces. Compare v14 and v15 wrappers after normalizing only the v14/v15 stage, marker, and new diagnostic-catch block; reject all unrelated changes. Run `git diff --check`.

- [ ] **Step 7: Record and commit the diagnostic checkpoint**

Append v13/v14 preservation, RED evidence, GREEN failure/success evidence, wrapper/harness hashes, parser results, and an explicit statement that no v15 production process or stage was created to `task-3-report.md`. Stage only that report, run cached diff checks, and commit:

```powershell
git add pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Record v15 assembler diagnostic gate"
```

The controller performs a task-scoped review. Task 2 remains locked until the review is clean.

---

### Task 2: Perform the sole v15 production attempt

**Files:**
- Read: `pure-octave/probes/stage_task3_runtime.ps1`
- Read: `pure-octave/probes/test_stage_task3_runtime.ps1`
- Read outside Git: `C:\tmp\todo51-task3\stage_v15_wrapper.ps1`
- Create outside Git: `C:\tmp\todo51-task3\stage_v15_preflight_audit.ps1`
- Create outside Git: `C:\tmp\todo51-task3\stage_v15_postaudit.ps1`
- Create outside Git: v15 PID/stdout/stderr/marker/error evidence and `C:\tmp\todo51-task3\stage-runtime-v15`
- Modify: `pure-octave/probes/task-3-report.md`

**Interfaces:**
- Consumes: cleanly reviewed Task 1 diagnostic wrapper/report commit and all immutable v14 preflight/source pins.
- Produces: one accepted static-only v15 stage or one preserved failed v15 attempt with independent top-level error evidence.

- [ ] **Step 1: Require absent v15 and preserved v11-v14 evidence**

Verify Task 1 commit/clean worktree, preserved v11-v14 helper/evidence hashes, v12/v13 absence rules, and v14 partial-stage existence without enumeration. Enumerate every intended v15 helper, stage, PID, stdout, stderr, marker, and error path literally and throw if any exists. Validate the disposable parent and ten immutable roots as regular/non-reparse.

- [ ] **Step 2: Create and verify v15 audit helpers**

Create preflight and post-audit helpers from reviewed v14 helpers by changing v14-owned paths/hashes only and adding the reviewed v15 wrapper/error-file contract. Parse all helpers; verify exact wrapper hash, 16 decoded parameters, forbidden-surface count zero, pinned PowerShell identity, repository hashes, source manifests, and exact platform identity.

- [ ] **Step 3: Launch the v15 preflight once outside the sandbox**

The `ProcessStartInfo`, PID writer, and polling owner command must use `sandbox_permissions = require_escalated`. Immediately before `Start()`, create/read/remove an exact disposable host-write probe outside evidence paths and require its absence. Record PID before polling only PID/log lengths/marker.

Require process/marker `0/0`, empty stderr, exactly one PASS JSON object, all immutable manifests, and the exact platform identity from Global Constraints. Any failure preserves evidence, appends the failure report, leaves assembler launch count zero, and stops without retry or commit.

- [ ] **Step 4: Launch the v15 assembler once outside the sandbox**

Only after accepted preflight, recheck absent stage/marker/PID/log/error paths, helper hashes, decoded parameters, and a fresh host-write probe. Launch the reviewed wrapper through an escalated owner, record PID, and poll only PID/log lengths/marker. Never inspect the in-progress stage.

- [ ] **Step 5: Classify the immutable assembler result**

On marker `1`, require process exit nonzero. If error JSON exists, verify it is regular/non-reparse, has exactly seven fields, and record its bytes, SHA-256, and values without opening partial stage contents. If it is absent, report that `catch` diagnostic evidence was not produced. Preserve the attempt; run no post-audit or success gate and create no commit.

On marker `0`, require process exit zero, empty stderr, exactly one JSON object, absent error JSON, and all exact stage/platform values from Global Constraints. Any mismatch is a failed attempt with no retry or success commit.

- [ ] **Step 6: Perform the independent static post-audit after success only**

Without executing staged binaries, recompute manifest, counts, bytes, reparse status, PE/`.oct` inventory, placeholder, supplement, Gnuplot edge split, complete import closure, API-set hosts/platform identity, patched liboctave/libgcc hashes, and unchanged source/permanent manifests. Require every exact Global Constraint value.

- [ ] **Step 7: Run fresh repository verification after success only**

Run the supplement harness and require 15/15 plus `PASS all supplement preparer tests`. Run the staging harness and require 48/48 plus `PASS all task3 staging tests`. Parse assembler, harness, wrapper, preflight, post-audit, and diagnostic harness with zero errors. Require `git diff --check`, unchanged external manifests, and zero staged-binary executions.

- [ ] **Step 8: Record and commit an accepted v15 stage**

Append exact helper/evidence hashes, PIDs, markers, JSON, independent post-audit, test results, and no-execution/no-mutation evidence to `task-3-report.md`. Stage only that report, run cached checks, and commit:

```powershell
git add pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Record diagnostic Task 3 runtime stage"
```

The controller performs task-scoped review and then a whole-branch review. Only clean reviews accept v15 and complete this repin plan.
