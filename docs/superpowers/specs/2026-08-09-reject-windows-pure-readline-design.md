# Reject Windows pure-readline Design

Status: Approved
Date: 2026-08-09
Affected TODO: `pure/todo/TODO-48-windows-pure-readline.md`

## Goal

Close the Windows `pure-readline` investigation by excluding the separate
package from the Windows distribution. The Windows interpreter already builds
and operates with GNU readline, so maintaining another module linked to the
same process-global library does not justify its packaging cost or conflict
risk.

## Evidence to Record

- The Windows core build requires the readline package and defines the
  interpreter's readline feature checks through CMake.
- The interpreter uses readline for interactive input, editing, history,
  completion, EOF handling, and console interruption behavior.
- `pure-readline` is a thin script-facing wrapper around the same library. Its
  distinct feature is a separately managed history for calls made by Pure
  scripts, not functionality required by the Windows interpreter or standard
  REPL.
- The wrapper temporarily changes process-global readline state. Shipping it
  would add another native module that must remain ABI-compatible with the
  exact readline library used by the interpreter.

## Scope

- Mark `pure/todo/TODO-48-windows-pure-readline.md` as rejected on 2026-08-09.
- Replace the open investigation with an explicit decision that Windows
  packaging must not build, stage, or install `pure-readline`.
- Record static and bounded automated evidence for the core readline linkage
  and behavior already covered by the Windows runtime.
- Add or extend a packaging-manifest check only if an active Windows manifest
  can currently admit the module or a second readline/terminal DLL.

## Exclusions

- Do not delete or modify the portable `pure-readline/` sources. They remain
  available to non-Windows users and batch-compiled applications.
- Do not expose the package's script-facing API from the interpreter core.
- Do not build the rejected package merely to reproduce functionality already
  supplied by the Windows interpreter.
- Do not add unbounded interactive tests or require Windows Terminal for the
  automated acceptance path.
- Do not change unrelated Windows package decisions.

## Implementation

1. Capture the core CMake linkage and interpreter code paths that demonstrate
   the Windows runtime's readline integration.
2. Inventory any existing automated coverage for input, history, completion,
   EOF, and interruption; add only bounded tests needed to substantiate the
   rejection decision.
3. Check active Windows staging and installer inputs for `pure-readline`, its
   module DLL, or a duplicate readline/terminal DLL. Add a focused negative
   assertion if the packaging machinery has an applicable manifest boundary.
4. Mark TODO-48 rejected and append the evidence, validation results, and
   Windows-only disposition to its progress log.

## Safety and Error Handling

- Treat the readline DLL used by the core as the single permitted readline
  runtime in the Windows distribution.
- Fail packaging validation if `pure-readline` or an additional readline or
  terminal DLL is staged as a separate package payload.
- Keep console-dependent checks bounded and preserve a static or redirected-I/O
  substitute for environments without an interactive console.
- Stage only files directly related to TODO-48 and review the complete diff
  before committing.

## Verification

- Configure/build evidence shows that the Windows interpreter resolves the
  same GNU readline dependency selected by the core CMake configuration.
- Bounded tests or existing runtime tests substantiate line input, history,
  completion, EOF, and interruption behavior without requiring manual input.
- A repository search finds no active Windows package or installer selection
  for `pure-readline` after the disposition.
- Any applicable staging-manifest test rejects the module and duplicate
  readline/terminal DLL payloads.
- The portable `pure-readline/` source tree remains unchanged.
- `git diff --check` and all focused tests pass.

Manual checks in Windows Terminal and a plain console may supplement the
automated evidence, but they are not required to close TODO-48 when the bounded
tests and code-path audit establish the same behavior.

## Acceptance

The change is accepted when TODO-48 is visibly rejected, the decision cites the
core Windows readline integration, the Windows distribution cannot select the
separate package or introduce conflicting readline/terminal DLLs, and the
portable package sources remain intact.
