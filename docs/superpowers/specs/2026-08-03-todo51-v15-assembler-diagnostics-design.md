# TODO-51 v15 Assembler Diagnostics Design

> **Rejected on 2026-08-08.** Historical record only. Do not implement or
> resume this work without a new approved TODO.

## Context

The accepted v14 preflight ran outside the restricted sandbox and proved every
immutable input and the serviced Windows/API-set identity. The sole v14
assembler launch then exited with process/marker `1/1`, empty stdout and
stderr, and no JSON. Its partial stage and evidence remain preserved without
content inspection. The v14 wrapper used only redirected stderr for a caught
PowerShell error, so the failed run produced no admissible diagnostic payload.

A detached non-production throwing fixture reproduced the wrapper shape and
proved that `[Console]::Error.WriteLine` normally reaches redirected stderr.
This rules out a universal redirection failure, but it does not identify the
v14 assembler error. The next production attempt must therefore improve
failure evidence before it is allowed to run.

## Considered approaches

### 1. Dedicated external error evidence file — selected

The v15 wrapper writes one deterministic UTF-8 JSON error record beside its
PID/log/marker evidence from the top-level `catch`. The record is independent
of console redirection and contains the exception type, message,
fully-qualified error ID, category, script stack trace, and invocation
position. The existing stderr write remains a secondary channel.

This is the smallest change that directly addresses the missing diagnostic
boundary and can be tested without touching production inputs.

### 2. PowerShell transcript

A transcript captures substantially more host state and command output, but it
is broader than required, has host-dependent formatting, and is harder to
prove absent on success. It is rejected.

### 3. Windows event-log or process-monitor evidence

External system tracing can diagnose host termination, but availability and
audit policy vary and the output is not owned by the attempt. It remains a
last-resort follow-up if the wrapper cannot execute its `catch` or `finally`.

## V15 wrapper contract

The wrapper is derived from the preserved v14 wrapper. Apart from changing
the stage root and exit marker from v14 to v15, it adds exactly one literal
error-evidence path:

```text
C:\tmp\todo51-task3\stage-runtime-v15.assembler.error.json
```

The top-level `catch` constructs one object with these exact fields:

```text
TimestampUtc
ExceptionType
Message
FullyQualifiedErrorId
Category
ScriptStackTrace
InvocationPosition
```

It serializes the object with `ConvertTo-Json -Compress`, writes UTF-8 without
a BOM to the literal error path, also writes the rendered error to stderr, and
leaves the assembler exit code at `1`. The `finally` block writes the existing
exit marker after the diagnostic write. The diagnostic path is not a caller
parameter and cannot alter the 16-key assembler hashtable.

On successful assembler completion the error file must remain absent. A
pre-existing error file, marker, PID, stdout, stderr, helper, or stage path
invalidates v15 before launch.

## Test-first diagnostic gate

Before any v15 production helper or process is created, a disposable fixture
must exercise the actual diagnostic wrapper behavior through the same pinned
PowerShell 7.6.4 `ProcessStartInfo` boundary outside the sandbox.

The RED run uses the current stderr-only wrapper contract and requires an
external error JSON; it must fail because that file is absent. The GREEN run
uses the minimal diagnostic wrapper and requires:

- process exit and marker `1/1`;
- exactly one regular, non-reparse error JSON file;
- the seven exact fields above;
- the literal throwing-fixture sentinel in `Message`;
- a non-empty exception type and script stack trace;
- no staged or production path access.

A separate success fixture requires process/marker `0/0`, its expected stdout,
empty stderr, and an absent error JSON file. All disposable fixture paths are
outside v11-v15 production evidence and are removed only after their hashes and
results are recorded in the SDD report.

## Sole v15 production attempt

V11-v14 stages, helpers, logs, PID files, markers, and reports remain
preserved. The partial v14 stage is checked only for existence and is never
opened recursively or executed.

After the diagnostic gate passes, v15 uses new literal helpers and evidence
paths. Preflight and assembler launch-owner commands must run with
`sandbox_permissions = require_escalated`. Each has a fresh disposable host
write probe immediately before `ProcessStartInfo.Start()`.

The v15 preflight is launched once. Only an accepted preflight may unlock one
assembler launch. During either process, polling is limited to PID, log
lengths, and marker presence. There is no retry and no in-progress stage
inspection.

If the assembler fails, the attempt requires marker `1` and either the new
error JSON or an explicit report that `catch`/`finally` evidence was not
produced. The partial v15 stage is preserved and no post-audit, success test
gate, or commit occurs.

If the assembler succeeds, the diagnostic file must be absent and the prior
exact stage, Gnuplot, Windows, and API-set contracts remain unchanged. The
existing independent static post-audit and repository verification then gate
the report-only success commit.

## Reporting and scope

The existing uncommitted v13/v14 failure sections in
`pure-octave/probes/task-3-report.md` are preserved. V15 appends its diagnostic
fixture evidence and production result. No repository production code or test
harness changes are needed for this operational diagnostic boundary.

Runtime execution, partial-stage inspection, ACL/profile work, cleanup of any
preserved attempt, and changes to accepted manifests or pins remain out of
scope.
