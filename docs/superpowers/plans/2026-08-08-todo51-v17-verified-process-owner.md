# TODO-51 v17 Verified Process Owner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the untested inline production launcher with one behaviorally verified, hash-pinned process owner, then use it for a single immutable v17 preflight/assembler/post-audit attempt.

**Architecture:** A repository-owned PowerShell script consumes one strict JSON launch contract, validates every executable, script, path, and hash, starts one child, copies both redirected base streams concurrently, and writes independent PID/exit/error evidence. The exact owner is tested in a disposable root before three immutable external v17 contracts may invoke preflight, assembler, and post-audit sequentially.

**Tech Stack:** PowerShell 7.6.4, Windows `.NET` `System.Diagnostics.ProcessStartInfo`, asynchronous `Stream.CopyToAsync`, strict BOM-less UTF-8 JSON, SHA-256, Git.

## Global Constraints

- Preserve every v11-v16 helper, PID, log, marker, error JSON, report record, and stage byte-for-byte.
- Check protected partial `stage-runtime-v14`, `stage-runtime-v15`, and `stage-runtime-v16` only with `Test-Path`; never enumerate, read, execute, modify, clean, or recycle their contents.
- Preserve the uncommitted v16 BLOCKED append in `pure-octave/probes/task-3-report.md` until the reviewed v17 owner checkpoint explicitly commits it.
- V16 remains BLOCKED with immutable launch counts `1 / 0 / 0`; there is no v16 retry.
- Use pinned PowerShell 7.6.4 at `C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe`, SHA-256 `DB6DD81183FE57D22E03B911EC9A30A2FD7C40542E97743615355A6FB44F458F`.
- The process owner accepts only `-ContractPath`; it has no `TestMode`, injection hook, caller-controlled script block, inventory override, or production-only branch.
- Production invokes the exact reviewed owner file at `C:\pure-lang\pure-octave\probes\invoke_task3_process_owner.ps1`; inline `ProcessStartInfo` ownership is forbidden.
- Every production owner invocation uses explicit `sandbox_permissions = require_escalated`.
- V17 permits at most one preflight launch, one assembler launch after accepted preflight, and one post-audit launch after accepted assembler success. There is no retry or recycle.
- The owner never terminates its child. The interruption test may terminate only its disposable test-owner process and must let the disposable child exit naturally.
- A catchable owner validation or lifecycle failure exits the owner process with fixed code `125`; a valid owner-exit record distinguishes a child that independently returned `125`.
- During production execution inspect only PID state, stdout/stderr lengths, and declared marker presence. Never inspect an in-progress stage or execute a staged binary.
- The accepted staged payload remains exactly 64,312 files, 3,334,971,045 bytes, manifest SHA-256 `115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`, 1,539 PE files, 219 PE `.oct` modules, one inert placeholder, and three Pure-RSVG supplements.
- The direct Gnuplot audit remains `65 / 63 / 1002 / 249 / 563 / 190 / 0`; the platform-plugin audit remains `2 / 2 / 38 / 6 / 15 / 17 / 0`.
- Accepted platform identity remains `Microsoft Windows NT 10.0.26200.0`, `CurrentBuild 26200`, `UBR 8973`, API-set file/product version `10.0.26100.8972 (WinBuild.160101.0800)` / `10.0.26100.8972`, length `194048`, SHA-256 `E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8`.
- A failed production phase preserves all evidence, records exact launch counts, and stops without retry, downstream launch, cleanup, staged-binary execution, or success commit.
- Every successful implementation task receives a specification-compliance review followed by a code-quality review before its commit is accepted.

## File Structure

- Create `pure-octave/probes/invoke_task3_process_owner.ps1`: closed-contract validation, one-shot process lifecycle, stream capture, and atomic owner evidence.
- Create `pure-octave/probes/test_invoke_task3_process_owner.ps1`: disposable RED/GREEN, safety, deadlock, interruption, AST, and production-absence tests for the exact owner.
- Modify `pure-octave/probes/task-3-report.md`: preserve the v16 blocker, record the reviewed v17 owner/helper gate, and append the immutable v17 production result.
- Create outside Git under `C:\tmp\todo51-task3`: v17 wrapper, preflight, post-audit, three launch contracts, distinct PID/log/owner-exit/owner-error/child-marker evidence, and `stage-runtime-v17`.

---

### Task 1: Implement the closed launch-contract boundary

**Files:**
- Create: `pure-octave/probes/invoke_task3_process_owner.ps1`
- Create: `pure-octave/probes/test_invoke_task3_process_owner.ps1`

**Interfaces:**
- Consumes: `-ContractPath <absolute-json-path>` and no other parameter.
- Produces: validation failure with no child launch, or a validated in-memory contract with exactly these fields: `SchemaVersion`, `Phase`, `OwnerPath`, `OwnerSha256`, `PowerShellPath`, `PowerShellSha256`, `ChildScriptPath`, `ChildScriptSha256`, `Arguments`, `WorkingDirectory`, `EvidenceRoot`, `PidPath`, `StdoutPath`, `StderrPath`, `OwnerExitPath`, `OwnerErrorPath`.
- `Arguments` is a JSON array of strings appended after `-NoProfile`, `-NonInteractive`, `-File`, and the exact `ChildScriptPath`.

- [ ] **Step 1: Write the test harness and the first failing contract tests**

Create a unique root below `C:\tmp\todo51-task3\process-owner-tests-<guid>`, a BOM-less UTF-8 child script, and this contract writer:

```powershell
function Write-Contract([string] $Path, [hashtable] $Overrides = @{}) {
    $contract = [ordered]@{
        SchemaVersion = 1
        Phase = 'Preflight'
        OwnerPath = $ownerPath
        OwnerSha256 = (Get-FileHash -LiteralPath $ownerPath -Algorithm SHA256).Hash
        PowerShellPath = $pinnedPwsh
        PowerShellSha256 = $pinnedPwshSha256
        ChildScriptPath = $childPath
        ChildScriptSha256 = (Get-FileHash -LiteralPath $childPath -Algorithm SHA256).Hash
        Arguments = [string[]]@()
        WorkingDirectory = $repoRoot
        EvidenceRoot = $evidenceRoot
        PidPath = Join-Path $evidenceRoot 'child.pid.txt'
        StdoutPath = Join-Path $evidenceRoot 'child.stdout.log'
        StderrPath = Join-Path $evidenceRoot 'child.stderr.log'
        OwnerExitPath = Join-Path $evidenceRoot 'owner.exit.json'
        OwnerErrorPath = Join-Path $evidenceRoot 'owner.error.json'
    }
    foreach ($key in $Overrides.Keys) { $contract[$key] = $Overrides[$key] }
    $json = $contract | ConvertTo-Json -Depth 4 -Compress
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}
```

Add tests that require rejection of an unknown field, a missing field, `SchemaVersion = 2`, unsupported phase, duplicate evidence paths, a relative path, an evidence path outside `EvidenceRoot`, an incorrect owner path/hash, incorrect PowerShell hash, incorrect child hash, and a pre-existing evidence path. Each test records the process list before and after and requires no fixture child marker and no new matching child process.

- [ ] **Step 2: Run the focused harness to verify RED**

Run outside the broken sandbox:

```powershell
& 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe' `
  -NoProfile -NonInteractive -File `
  .\pure-octave\probes\test_invoke_task3_process_owner.ps1
```

Expected: exit nonzero because `invoke_task3_process_owner.ps1` does not exist or does not yet enforce the closed schema; no production v17 path exists.

- [ ] **Step 3: Implement strict JSON and path validation**

Start the owner with:

```powershell
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string] $ContractPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8NoBom = [Text.UTF8Encoding]::new($false, $true)
$allowedFields = [string[]]@(
    'SchemaVersion','Phase','OwnerPath','OwnerSha256','PowerShellPath',
    'PowerShellSha256','ChildScriptPath','ChildScriptSha256','Arguments',
    'WorkingDirectory','EvidenceRoot','PidPath','StdoutPath','StderrPath',
    'OwnerExitPath','OwnerErrorPath'
)
```

Implement `Get-CanonicalPath`, `Assert-RegularNonReparseFile`,
`Assert-RegularNonReparseDirectory`, `Assert-NoReparseComponents`,
`Get-Sha256File`, and `Read-StrictContract`. Decode bytes with
`UTF8Encoding($false,$true)`, reject a BOM, use
`ConvertFrom-Json -NoEnumerate`, require exactly one `PSCustomObject`, compare
the sorted property names to `$allowedFields`, and require the exact types.

Canonicalize every path with `[IO.Path]::GetFullPath`. Require ordinal-ignore-
case equality with its input, distinct evidence paths, and an evidence prefix
equal to `EvidenceRoot + [IO.Path]::DirectorySeparatorChar`. Require the
contract and evidence root to equal or be strict descendants of the fixed
`C:\tmp\todo51-task3` root, require the child script to be a strict descendant
of that root, and require `WorkingDirectory` to equal `C:\pure-lang`. Require
`PowerShellPath` and `PowerShellSha256` to equal the pinned literal values from
Global Constraints, not merely to agree with each other. Require
`$PSCommandPath` to equal `OwnerPath`, then hash owner, pinned PowerShell, and
child script independently. `Assert-RegularNonReparseFile` must reject a
`ReparsePoint` attribute and every nonempty `LinkType`, including hard links.
Do not create evidence or start a process in this task.

- [ ] **Step 4: Run the focused harness to verify GREEN validation**

Run the command from Step 2.

Expected: every validation sentinel passes; the harness ends with
`PASS owner contract validation tests`; every production v17 path remains
absent.

- [ ] **Step 5: Review and commit the contract boundary**

Run parser checks for both scripts, `git diff --check`, and inspect the AST for
`Invoke-Expression`, `Start-Process`, `cmd.exe`, `TestMode`, script-block
parameters, wildcard deletion, and environment `PATH` lookup. Obtain the two
task reviews, then commit only the two new scripts:

```powershell
git add -- pure-octave/probes/invoke_task3_process_owner.ps1 `
  pure-octave/probes/test_invoke_task3_process_owner.ps1
git diff --cached --check
git commit -m "Validate strict process owner contracts"
```

Keep `pure-octave/probes/task-3-report.md` unstaged.

---

### Task 2: Implement the one-shot process lifecycle and evidence

**Files:**
- Modify: `pure-octave/probes/invoke_task3_process_owner.ps1`
- Modify: `pure-octave/probes/test_invoke_task3_process_owner.ps1`

**Interfaces:**
- Consumes: the validated contract from Task 1.
- Produces: exclusive stdout/stderr files, atomic PID text, exact seven-field owner-exit JSON on a fully drained child, or exact seven-field owner-error JSON after the error path becomes trusted.
- Owner-exit fields: `SchemaVersion`, `Phase`, `State`, `ChildPid`, `ChildExitCode`, `OwnerSha256`, `ContractSha256`.
- Owner-error fields: `SchemaVersion`, `Phase`, `State`, `ExceptionType`, `Message`, `ChildPid`, `ContractSha256`.

- [ ] **Step 1: Add failing lifecycle tests**

Add three disposable children:

```powershell
# success-child.ps1
[Console]::Out.Write("OWNER_STDOUT_SENTINEL CHILD_PID=$PID")
[Console]::Error.Write('OWNER_STDERR_SENTINEL')
exit 0

# failure-child.ps1
[Console]::Error.Write('OWNER_FAILURE_SENTINEL')
exit 23

# volume-child.ps1
$out = [byte[]]::new(1048576); [Array]::Fill[byte]($out, 0x4f)
$err = [byte[]]::new(1048576); [Array]::Fill[byte]($err, 0x45)
[Console]::OpenStandardOutput().Write($out, 0, $out.Length)
[Console]::OpenStandardError().Write($err, 0, $err.Length)
exit 0
```

Require the success case to parse the child's own `$PID` from stdout and match
it to both the PID file and owner-exit `ChildPid`, then require exact remaining
sentinel bytes, absent owner-error, and an exact owner-exit object. Require the
failure case to preserve exit code 23 and stderr. Require the volume case to
finish without a timeout and produce exactly 1,048,576 bytes in each stream.

- [ ] **Step 2: Run the harness to verify lifecycle RED**

Run the Task 1 harness command.

Expected: validation tests pass, then lifecycle fails because no process is
started and no PID/stream/exit evidence exists.

- [ ] **Step 3: Implement exclusive evidence and concurrent stream copying**

Use this lifecycle shape after validation:

```powershell
$state = 'EvidenceReady'
$stdoutStream = [IO.File]::Open($contract.StdoutPath, 'CreateNew', 'Write', 'Read')
$stderrStream = [IO.File]::Open($contract.StderrPath, 'CreateNew', 'Write', 'Read')
$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $contract.PowerShellPath
$startInfo.WorkingDirectory = $contract.WorkingDirectory
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
[void] $startInfo.ArgumentList.Add('-NoProfile')
[void] $startInfo.ArgumentList.Add('-NonInteractive')
[void] $startInfo.ArgumentList.Add('-File')
[void] $startInfo.ArgumentList.Add($contract.ChildScriptPath)
foreach ($argument in [string[]] $contract.Arguments) {
    [void] $startInfo.ArgumentList.Add($argument)
}
$childProcess = [Diagnostics.Process]::new()
$childProcess.StartInfo = $startInfo
if (-not $childProcess.Start()) { throw 'Process.Start returned false.' }
$state = 'Started'
$stdoutCopy = $childProcess.StandardOutput.BaseStream.CopyToAsync($stdoutStream)
$stderrCopy = $childProcess.StandardError.BaseStream.CopyToAsync($stderrStream)
$childPid = $childProcess.Id
Write-AtomicUtf8 -Path $contract.PidPath -Text ([string]$childPid + "`n")
$state = 'Draining'
$childProcess.WaitForExit()
[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutCopy,$stderrCopy))
```

Implement `Write-AtomicUtf8` with one unique sibling temporary file opened by
`CreateNew`, BOM-less UTF-8 bytes, flush-to-disk, and a same-directory atomic
rename that refuses an existing destination. Close both stream files before
atomically writing owner-exit. Retain the initially validated hashes of the
owner, contract, PowerShell executable, and child script; rehash all four after
the child exits and fail if any changed. Record the initial owner and contract
hashes in owner-exit only after this equality check. Exit the owner process
with the child's exit code.

After the evidence root and `OwnerErrorPath` are independently trusted, wrap
the lifecycle in `try/catch/finally`. On a catchable failure, retain the last
state and known nullable `$childPid`; if the child started, wait for natural
exit and best-effort drain both copy tasks. Write owner-error only through the
already trusted exact path. Never call `Kill`, `Stop-Process`, or task
cancellation in the owner. Exit `125` for every catchable owner failure; when
validation fails before the error path is trusted, emit the diagnostic only to
stderr and still exit `125`.

- [ ] **Step 4: Run the full owner harness to verify GREEN lifecycle**

Run the Task 1 harness command.

Expected: validation, success, exit-23, and concurrent-volume sentinels pass;
the final sentinel is `PASS owner lifecycle tests`.

- [ ] **Step 5: Review and commit the lifecycle**

Review disposal ordering, asynchronous-task exceptions, exclusive file modes,
atomic rename behavior using `[IO.File]::Move($temporary,$Path,$false)`, and
the absence of child termination. Run parser and
diff checks and obtain both task reviews. Commit only the owner and harness:

```powershell
git add -- pure-octave/probes/invoke_task3_process_owner.ps1 `
  pure-octave/probes/test_invoke_task3_process_owner.ps1
git diff --cached --check
git commit -m "Capture strict process owner evidence"
```

---

### Task 3: Bind adversarial safety and the automatic-variable regression

**Files:**
- Modify: `pure-octave/probes/invoke_task3_process_owner.ps1`
- Modify: `pure-octave/probes/test_invoke_task3_process_owner.ps1`

**Interfaces:**
- Consumes: Task 2's exact owner lifecycle.
- Produces: one complete owner harness that proves reparse rejection, reserved-variable safety, interrupted-owner classification, cleanup confinement, and production-v17 absence.

- [ ] **Step 1: Add the failing reserved-variable AST gate**

Parse owner source with `Parser.ParseFile`. Collect case-insensitive assignment
targets and reject every variable whose pinned `-NoProfile` runtime options
contain `ReadOnly` or `Constant`, plus this explicit set:

```powershell
$reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($name in @('HOME','Error','Args','Input','Matches','MyInvocation',
    'PSBoundParameters','PSScriptRoot','PSCommandPath','LASTEXITCODE')) {
    [void] $reserved.Add($name)
}
```

Create a memory-only mutated source replacing `$childPid` with `$pid`; require
the AST checker to reject it with `Reserved automatic variable assignment:
pid`. Require the real owner to pass and the success fixture PID file to equal
the observed child PID.

- [ ] **Step 2: Run the focused AST test to verify RED**

Run the owner harness.

Expected: failure at the new AST assertion because the checker is not yet
implemented; no production v17 path exists.

- [ ] **Step 3: Implement the AST assertion and adversarial fixtures**

Add `Assert-NoReservedVariableAssignment` to the harness, not the production
owner. Add cases for a junction in an evidence path component using
`New-Item -ItemType Junction`, a file reparse fixture using
`New-Item -ItemType SymbolicLink` under escalated test execution, a hard-linked
child-script fixture, an existing stdout file, duplicate PID/stdout paths, a
canonical `..` escape, a sibling-prefix escape such as
`C:\tmp\todo51-task3-escape`, and an untrusted early `OwnerErrorPath` outside
the evidence root. Require both link kinds and both root escapes to be rejected
and early failures to write nothing through the untrusted error path.

For interruption, start the exact owner as a disposable process with a child
that writes a start sentinel, sleeps five seconds, writes an end sentinel, and
exits zero. Wait for the PID evidence, terminate only the disposable owner
process, then poll the child PID until it exits naturally. Require retained
PID/log files, absent owner-exit, no child termination by the harness, and the
external classifier result `BLOCKED`.

- [ ] **Step 4: Run all owner and repository harnesses**

Run under pinned PowerShell 7.6.4:

```powershell
& .\pure-octave\probes\test_invoke_task3_process_owner.ps1
& .\pure-octave\probes\test_prepare_task3_pure_rsvg_supplement.ps1
& .\pure-octave\probes\test_stage_task3_runtime.ps1
```

Expected: all focused owner sentinels, `PASS all supplement preparer tests`,
and `PASS all task3 staging tests`; all literal production v17 paths remain
absent before and after the run.

- [ ] **Step 5: Review and commit the complete owner gate**

Run parser checks, the reserved-variable source mutation proof, forbidden-
surface scan, `git diff --check`, and a fresh complete three-harness run.
Obtain both reviews and commit only the two scripts:

```powershell
git add -- pure-octave/probes/invoke_task3_process_owner.ps1 `
  pure-octave/probes/test_invoke_task3_process_owner.ps1
git diff --cached --check
git commit -m "Harden verified process owner gate"
```

---

### Task 4: Create and commit the immutable v17 helper checkpoint

**Files:**
- Read: `pure-octave/probes/invoke_task3_process_owner.ps1`
- Read: `pure-octave/probes/test_invoke_task3_process_owner.ps1`
- Modify: `pure-octave/probes/task-3-report.md`
- Create outside Git: `C:\tmp\todo51-task3\stage_v17_wrapper.ps1`
- Create outside Git: `C:\tmp\todo51-task3\stage_v17_preflight_audit.ps1`
- Create outside Git: `C:\tmp\todo51-task3\stage_v17_postaudit.ps1`
- Create outside Git: `C:\tmp\todo51-task3\stage-runtime-v17.preflight.owner-contract.json`
- Create outside Git: `C:\tmp\todo51-task3\stage-runtime-v17.assembler.owner-contract.json`
- Create outside Git: `C:\tmp\todo51-task3\stage-runtime-v17.postaudit.owner-contract.json`

**Interfaces:**
- Consumes: reviewed Task 3 owner/test hashes, all preserved v11-v16 pins, exact v16 wrapper/preflight/post-audit semantics, and the accepted v16 Gnuplot plugin contract.
- Produces: three parsed and hash-pinned v17 helpers, three strict contracts bound to the exact owner, and one clean repository report checkpoint before any v17 production launch.

- [ ] **Step 1: Verify the immutable starting gate**

Require the Task 3 commit at HEAD, the v16 report as the only worktree change,
and an empty index. Verify all recorded v15/v16 helper and evidence hashes.
Check each protected partial stage only with literal `Test-Path`. Enumerate every
intended v17 helper, contract, stage, evidence, child marker, and error path in
an explicit array and require all of them absent. Verify the owner-test
disposable roots have been removed and no test child remains.

- [ ] **Step 2: Derive and statically verify the three v17 helpers**

Derive `stage_v17_wrapper.ps1` from the exact v16 wrapper by changing only
v16-owned stage, assembler child-marker, and assembler diagnostic paths to:

```text
C:\tmp\todo51-task3\stage-runtime-v17
C:\tmp\todo51-task3\stage-runtime-v17.assembler.child.exit.txt
C:\tmp\todo51-task3\stage-runtime-v17.assembler.error.json
```

Derive preflight and post-audit from the v16 helpers, changing only v16-owned
paths/hashes and adding exact pins for the reviewed owner and owner harness.
Retain stage pins `64312 / 3334971045 /
115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`,
direct Gnuplot `65 / 63 / 1002 / 249 / 563 / 190 / 0`, and plugin
`2 / 2 / 38 / 6 / 15 / 17 / 0`.

Parse all helpers with zero errors. Normalize only v16/v17 owned literals and
require no other wrapper semantic diff. Decode exactly the accepted 16
assembler parameters with zero forbidden surface. Re-run the full owner,
supplement, and staging harnesses before contract creation.

- [ ] **Step 3: Create the three strict production contracts**

Write BOM-less UTF-8 one-object JSON using the exact 16-field schema. All three
contracts bind:

```text
OwnerPath = C:\pure-lang\pure-octave\probes\invoke_task3_process_owner.ps1
PowerShellPath = C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe
WorkingDirectory = C:\pure-lang
EvidenceRoot = C:\tmp\todo51-task3
```

Use the freshly measured exact owner and PowerShell hashes. Bind each exact
child helper and hash. Give each phase distinct paths ending in
`.pid.txt`, `.stdout.log`, `.stderr.log`, `.owner.exit.json`, and
`.owner.error.json`. The assembler contract arguments are the reviewed wrapper
arguments only; no shell command string is permitted. Re-read every contract
strictly, require 16 unique fields, and record its byte count and SHA-256.

- [ ] **Step 4: Append the v16 blocker and v17 checkpoint report**

Preserve the existing v16 append byte-for-byte. Append owner RED/GREEN evidence,
all three implementation commits, parser/AST/forbidden-surface results, exact
owner/test/helper/contract byte counts and SHA-256 values, full harness output,
proof that no production v17 process or stage path was created during tests,
and current launch counts `0 / 0 / 0`.

- [ ] **Step 5: Review and commit the report-only checkpoint**

Obtain evidence/spec and quality reviews. Run a fresh three-harness gate,
parser checks, `git diff --check`, and verify the index contains only the
report. Commit:

```powershell
git add -- pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Record v17 process owner gate"
```

After commit, require a clean worktree and re-verify every external helper and
contract hash. No production v17 process has yet launched.

---

### Task 5: Perform the sole immutable v17 production attempt

**Files:**
- Read: `pure-octave/probes/invoke_task3_process_owner.ps1`
- Read: external v17 helpers and contracts from Task 4
- Modify: `pure-octave/probes/task-3-report.md`
- Create outside Git: distinct v17 PID/log/owner-exit/owner-error/child-marker/error evidence and `C:\tmp\todo51-task3\stage-runtime-v17`

**Interfaces:**
- Consumes: clean Task 4 checkpoint and exact recorded owner/helper/contract hashes.
- Produces: one preserved failed v17 phase with immutable evidence, or one accepted static-only v17 stage with launch counts `1 / 1 / 1`.

- [ ] **Step 1: Re-run the no-launch production gate**

Require clean Task 4 HEAD, exact hashes, three strict contracts, all preserved
history, literal absence of every v17 runtime evidence/stage path, regular
non-reparse roots, and a fresh create/read/remove/absence host-write probe.
Run the complete owner, supplement, and staging harnesses. Any mismatch stops
with launch counts `0 / 0 / 0`.

- [ ] **Step 2: Launch preflight exactly once through the owner**

Run outside the sandbox:

```powershell
& 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe' `
  -NoProfile -NonInteractive -File `
  'C:\pure-lang\pure-octave\probes\invoke_task3_process_owner.ps1' `
  -ContractPath 'C:\tmp\todo51-task3\stage-runtime-v17.preflight.owner-contract.json'
```

While it runs, poll only PID state, stdout/stderr lengths, and declared marker
presence. Require owner process success, exact PID/owner-exit hashes, empty
stderr, one preflight PASS JSON object, exact immutable source/platform/helper
pins, and absent stage/assembler paths. Any failure records launch counts
`1 / 0 / 0` and stops without retry.

- [ ] **Step 3: Launch assembler exactly once after accepted preflight**

Recheck all hashes, the accepted preflight evidence, absent assembler/stage/
post-audit paths, and a fresh host-write probe. Invoke the same exact owner with
the assembler contract. Poll only the permitted evidence; never inspect the
in-progress stage.

If the child marker is nonzero or owner evidence is incomplete, independently
validate any seven-field strict diagnostic JSON without opening the partial
stage, append the immutable blocker, record launch counts `1 / 1 / 0`, and
stop. There is no retry.

- [ ] **Step 4: Launch post-audit exactly once after accepted assembler**

Only for process/owner/child-marker success, validate assembler stdout as one
JSON object with the exact stage and direct/plugin counters. Recheck the owner,
contract, helper, stage-manifest, and evidence hashes. Invoke the same owner
with the post-audit contract exactly once. Require its independent result to
match all accepted stage, PE, import-edge, supplement, source, platform, and
reparse pins. Do not execute a staged binary.

- [ ] **Step 5: Run final repository verification and reviews**

For an accepted post-audit, run fresh under pinned PowerShell:

```powershell
& .\pure-octave\probes\test_invoke_task3_process_owner.ps1
& .\pure-octave\probes\test_prepare_task3_pure_rsvg_supplement.ps1
& .\pure-octave\probes\test_stage_task3_runtime.ps1
git diff --check
```

Parse every repository and external v17 script with zero errors, rehash all
evidence, confirm launch counts `1 / 1 / 1`, and obtain task-scoped evidence/
spec and quality reviews followed by a whole-branch review.

- [ ] **Step 6: Record the immutable result**

Append exact PIDs, timestamps, launch counts, byte counts, hashes, JSON values,
review verdicts, and explicit no-staged-binary/no-protected-stage-access
evidence to `task-3-report.md`.

For any blocked result, leave the append uncommitted and preserve all external
evidence. For a fully accepted result only, stage the report, verify the cached
scope, and commit:

```powershell
git add -- pure-octave/probes/task-3-report.md
git diff --cached --check
git commit -m "Accept v17 verified Windows stage"
```

Only that accepted commit returns TODO-51 to its original strict AppContainer
runtime work.
