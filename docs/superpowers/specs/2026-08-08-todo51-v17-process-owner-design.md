# TODO-51 v17 Verified Process Owner Design

## Context

The sole v16 preflight child was started successfully, but its inline process
owner failed on the immediately following statement. PowerShell identifiers
are case-insensitive, so assigning `$pid = $process.Id` attempted to overwrite
the automatic read-only `$PID` variable. The production launch was consumed
before PID or redirected-stream evidence could be persisted. The child exited
naturally, no retry was attempted, and v16 remains immutably BLOCKED with
launch counts `1 / 0 / 0`.

Changing the local name to `$childPid` would address the immediate defect, but
would leave the broader gap unchanged: the complete inline production owner
would still differ from the artifact exercised before the one-shot launch.
V17 therefore makes the process owner a separately reviewed, behaviorally
tested, and hash-pinned artifact.

## Goals

- Exercise the exact process-owner implementation before any production v17
  path is created or launched.
- Use one owner implementation for preflight, assembler, and post-audit.
- Persist enough independent evidence to distinguish child failure, owner
  failure, and owner interruption after a successful start.
- Preserve the one-shot, no-retry, no-child-termination, and strict stage
  non-inspection rules used by the existing TODO-51 production attempts.
- Keep every v11-v16 helper, evidence file, report record, and partial stage
  immutable.

## Non-goals

- V17 does not alter the staged Windows payload or the accepted Gnuplot
  platform-plugin contract.
- It does not execute a staged binary or begin the AppContainer runtime tests.
- It does not clean, recycle, enumerate, or read a protected partial stage.
- It does not provide a general-purpose process launcher for unrelated tasks.

## Architecture

V17 introduces one standalone PowerShell process-owner script. The owner is
separate from the preflight, assembler wrapper, and post-audit scripts and is
responsible only for validating a launch contract, starting one child,
capturing process evidence, and waiting for natural child termination.

The same owner file is used without a production-only or test-only code path.
Disposable tests and production phases differ only in their independently
validated JSON contracts. The owner file is parsed, behaviorally tested, and
SHA-256 pinned before production contract creation. Every production caller
must require that exact hash; inline `ProcessStartInfo` ownership is forbidden.

The owner must use a local name that cannot collide with PowerShell automatic
variables, specifically `$childPid` for the returned process identifier. A
static AST gate rejects case-insensitive assignment to every variable reported
as `ReadOnly` or `Constant` by the pinned `-NoProfile` PowerShell process. It
also rejects assignment to `HOME`, `Error`, `Args`, `Input`, `Matches`,
`MyInvocation`, `PSBoundParameters`, `PSScriptRoot`, `PSCommandPath`, and
`LASTEXITCODE`, even when the runtime does not mark one of them read-only.

## Launch Contract

The owner accepts exactly one input: the path of an immutable JSON contract.
Each contract has a closed schema containing:

- schema version;
- phase: `Preflight`, `Assembler`, or `PostAudit`;
- exact owner path and SHA-256, which must match `$PSCommandPath` and the
  owner's current bytes;
- exact PowerShell executable path and SHA-256;
- exact child-script path and SHA-256;
- an argument array passed without shell evaluation;
- exact working directory;
- exact evidence root;
- distinct PID, stdout, stderr, owner-exit, and owner-error paths.

Unknown fields, missing fields, duplicate evidence paths, unsupported phases,
and non-canonical paths are rejected. The executable, child script, working
directory, evidence root, and existing parents must be regular non-reparse
objects of the expected type. Production evidence paths must be absent and
must resolve beneath the exact v17 evidence root. The contract itself is
regular, non-reparse, strict BOM-less UTF-8 JSON and is SHA-256 pinned by the
production gate.

Production uses three immutable contracts, one per phase. Parameterization is
limited to the closed contract schema; there is no `TestMode`, injection hook,
synthetic inventory, or caller-controlled script block.

## Owner State Machine and Evidence

The owner follows these states:

1. `Validating`: validate the contract, hashes, paths, and absence rules.
2. `EvidenceReady`: exclusively create and open empty stdout and stderr files
   without overwrite semantics.
3. `Started`: call `Process.Start()` exactly once, begin binary copying of both
   redirected `BaseStream` objects into the already-open files with
   `CopyToAsync`, and atomically write the returned `$childPid`.
4. `Draining`: wait for natural child exit and completion of both stream-copy
   operations.
5. `Completed`: flush and close the stream files, then atomically write the
   owner-exit evidence.

The owner never retries `Process.Start()` and never terminates its child. It
does not interpret or access a stage. It does not classify phase-specific JSON
or child markers; that remains the responsibility of the phase gate after the
owner has completed.

The owner-exit evidence is distinct from any marker written by the child. It
records the phase, child PID, child exit code, owner terminal state, and the
hashes needed to bind the result to the owner and contract. It is written only
after both redirected streams are fully drained.

After the owner has independently validated the evidence root and exact error
path, a catchable exception causes an atomic strict JSON owner-error record
containing the phase, last reached state, exception type, message, and the
child PID when known. An earlier validation failure must not write through a
path supplied by the untrusted contract; it is reported only through the
owner process exit and stderr. If the child has already started, the owner does
not kill it; it waits for natural exit and makes a best effort to finish
preserving both streams before reporting the owner failure. Temporary files
used for atomic writes are unique exact siblings and are removed only when the
owner can prove it created them and the final rename did not occur.

## Fail-closed Classification

- Failure before `Started` leaves the production phase launch count at zero.
- Once `Process.Start()` succeeds, the phase launch count is one even if PID or
  owner-exit evidence is incomplete.
- A PID without a valid owner-exit record consumes the one permitted launch and
  classifies the phase as `BLOCKED`.
- A valid owner-exit with a nonzero child exit preserves all evidence and lets
  the phase-specific gate classify the child failure; it never unlocks the
  next phase.
- Only a complete, internally consistent owner-exit, PID, stdout, stderr, and
  phase-specific evidence set may unlock the following phase.

Preflight, assembler, and post-audit are sequential. Each may launch at most
once. An incomplete or failed phase forbids every downstream launch, retry,
success test, cleanup, staged-binary execution, and success commit.

## Verification Before Production

The exact owner artifact is tested in a disposable root that is disjoint from
all production v17 paths. Tests cover:

- a successful child with exact PID, stdout, stderr, and exit evidence;
- a child returning a nonzero exit code;
- concurrent stdout and stderr volumes large enough to detect pipe deadlock;
- owner rejection of incorrect executable or child-script hashes, plus an
  external gate rejecting modified owner or contract bytes against their
  independently pinned hashes;
- unknown JSON fields, missing fields, and unsupported phases;
- duplicate, pre-existing, non-canonical, or out-of-root evidence paths;
- file and parent-directory reparse points;
- interruption of a test owner after it starts a short-lived disposable child,
  requiring preserved PID/log evidence, absent owner-exit, and `BLOCKED`
  classification without terminating the child;
- a case-insensitive AST rejection for assignment to `$PID` and every reviewed
  reserved automatic variable;
- an explicit regression assertion that the PID file contains the actual child
  PID produced by the successful exact owner.

Tests may remove only their literally enumerated disposable fixtures after a
successful assertion. They must prove that every production v17 helper,
contract, evidence, and stage path remains absent throughout the owner test
gate.

Before the production attempt, the gate also requires zero parser errors,
closed-schema and forbidden-surface checks, exact owner and contract hashes,
the complete existing supplement and staging harnesses, clean diff checks, and
the preserved v16 repository-report append as the only pre-existing worktree
modification.

## Immutable V17 Production Attempt

V17 uses new, literally enumerated wrapper, preflight, post-audit, contract,
stage, PID, stdout, stderr, owner-exit, owner-error, and child-marker paths.
Before creating them, the gate verifies the accepted repository HEAD and every
preserved helper/evidence hash. Protected v14-v16 partial stages are checked
only for existence with `Test-Path`; their contents are never enumerated,
opened, executed, changed, or deleted.

The preflight contract is launched through the verified owner exactly once.
Only a fully accepted preflight permits creation and one launch of the
assembler contract. Only a fully accepted assembler stage permits one
post-audit launch. During a running production child, observation is limited
to PID state, stdout/stderr lengths, and declared marker presence. The
in-progress stage is never inspected.

Any failure preserves all v17 evidence, records exact launch counts and the
last owner state, appends the immutable result to
`pure-octave/probes/task-3-report.md`, and stops without retry or success
commit. A successful post-audit must still pass the existing full repository
harnesses, parser and diff gates, task-scoped review, and whole-branch review
before v17 can return TODO-51 to the strict AppContainer runtime work.

## Repository Scope

The implementation may add the reviewed owner and its focused test harness to
`pure-octave/probes`, add v17 design/plan documents, and append production
evidence to `pure-octave/probes/task-3-report.md`. V17-specific contracts,
helpers, runtime evidence, and stage contents remain external under the exact
TODO-51 disposable root. Unrelated source, package, installer, and TODO files
are out of scope.
