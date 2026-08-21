# PurePad Lifecycle Hardening Design

## Purpose

Close the correctness and validation gaps found by the TODO-20 audit without
rewriting the MFC user interface. PurePad must start, interrupt, stop, restart,
and shut down its sibling `pure.exe` deterministically, including failures and
requests which race process startup.

## Scope

- Replace the ad-hoc process/thread ownership in `CPipe` with a focused,
  testable Win32 lifecycle component.
- Preserve the existing stdin/stdout protocol and the named
  `PURE_SIGINT-<pid>` / `PURE_SIGTERM-<pid>` event protocol.
- Add native Windows lifecycle tests and continuous integration coverage.
- Remove file-association registration from application startup and assign it
  to the TODO-49 installer.
- Document the Microsoft VC/MFC runtime deployment boundary for TODO-49.
- Record the audit and fresh validation in TODO-20.

The editor UI, command history format, Pure language protocol, installer
implementation, and general MFC modernization are outside this change.

## Architecture

### Process lifecycle component

Add `purepad/ProcessSession.h` and `purepad/ProcessSession.cpp`. The component
owns the child process, inheritable pipe endpoints, named signal events, and
reader/writer/start worker threads. `CPipe` remains the MFC-facing adapter which
owns the input/output `CBuffer` objects and posts existing window messages.

The component exposes only these operations:

- `Start(const ProcessLaunch&, ProcessCallbacks)`: synchronously completes all
  startup work needed to report success, including `CreateProcess`, creation of
  both named events, thread creation, and resuming the suspended child.
- `Write(std::string)`: queues UTF-8 bytes for the child while running.
- `Break()`: signals the current child's break event, or does nothing if no
  process is running.
- `Stop()`: idempotently requests graceful termination, closes/cancels I/O,
  waits for all workers, applies a bounded child-process fallback, and returns
  with no owned process or thread.
- `IsRunning()`: reports state under the component's synchronization primitive
  without acquiring a lock inside a Boolean expression.

`ProcessLaunch` carries the absolute executable, raw argument vector, script
path, and working directory. The component constructs the Windows command line
with the documented backslash-before-quote rules while continuing to pass the
absolute executable as `lpApplicationName`.

`ProcessCallbacks` carries output and lifecycle notifications. Worker code must
not call MFC or access a window directly; `CPipe` supplies callbacks which write
to its buffers and post the existing messages.

### State and synchronization

The internal states are `Idle`, `Starting`, `Running`, and `Stopping`. Every
transition is serialized by one lock, but no blocking Win32 operation occurs
while that lock is held.

- `Idle -> Starting` reserves one generation and clears stale queues.
- `Starting -> Running` occurs only after every required handle and thread was
  created and the child was resumed.
- Any startup failure moves to `Stopping`, joins everything already created,
  then returns to `Idle` before `Start` reports failure.
- `Break` in `Idle`, `Starting`, or `Stopping` is a no-op.
- `Stop` in any state is safe and converges on `Idle`.
- A new `Start` first performs `Stop`, so generations cannot share handles or
  callbacks.

All handles use a move-only RAII wrapper. No production or test path may call
`TerminateThread`. The stop sequence is:

1. mark the session stopping and signal its stop event;
2. signal the child's named terminate event when available;
3. close the parent's child-stdin write endpoint;
4. cancel synchronous worker I/O and close parent-owned duplicate endpoints;
5. wait for the child for the existing one-second graceful interval;
6. use `TerminateProcess` only as the bounded child-process fallback;
7. wait without a short timeout for worker completion after their I/O has been
   made cancellable;
8. release handles and return to `Idle`.

### Failure injection

Production uses a default `Win32ProcessApi` implementation. Tests can supply a
small API table whose thread-creation operation fails at a selected ordinal.
This is dependency injection for real Win32 operations, not a separate
test-only code path in `ProcessSession`.

The component returns a structured result containing a stable error category
and the originating Win32 error. `CPipe` converts it to the existing synchronous
PurePad error dialog. A failed start must never return success to the UI.

## File Association Ownership

Remove `RegisterShellFileTypes(TRUE)` from `CQpadApp::InitInstance`. PurePad must
not silently attempt registry writes on every launch. TODO-49 owns optional
`.pure` association installation, upgrade, and removal in both per-user and
administrative installer modes.

PurePad continues to accept `.pure` paths through its normal command-line and
DDE document handling; only registration ownership changes.

## Build and Deployment

Keep the supported Visual Studio 2022 x64 shared-MFC build. Add install rules
for a `PurePad` component so TODO-49 has a declared artifact boundary. The
component does not copy arbitrary Visual Studio files. Documentation and the
package verifier state that `mfc140u.dll`, `MSVCP140.dll`, `VCRUNTIME140.dll`,
and `VCRUNTIME140_1.dll` are supplied through the matching Microsoft Visual C++
Redistributable selected by TODO-49.

## Testing

Add a native helper executable which implements the existing named-event
contract and controllable stdin/stdout behavior. A lifecycle test executable
uses the real `ProcessSession` and helper for:

1. start, UTF-8 round trip, graceful stop, and zero surviving child;
2. immediate start followed by break;
3. immediate start followed by stop;
4. repeated start/stop generations;
5. nonexistent executable and invalid working directory;
6. injected failure at each worker-thread creation ordinal;
7. repeated `Break` and `Stop` in every state;
8. command-line arguments containing spaces, quotes, and trailing backslashes.

CTest also runs contract checks which reject `TerminateThread` and
`RegisterShellFileTypes` in active PurePad sources, inspect the Release PE as an
x64 GUI executable, and verify the manifest and declared VC/MFC imports.

The Windows workflow installs the Visual Studio MFC component, configures
PurePad from a path containing spaces, builds Release and Debug with four
workers, and runs all PurePad CTests. Runtime UI automation remains limited to
the process adapter; full visual editor automation is not introduced here.

## Documentation and Closure

Update TODO-20 with an audit entry dated 2026-08-22. Preserve its original
`Closed on 2026-07-26` history, but do not describe the audit remediation as
complete until all new tests, both configurations, and the Windows CI contract
pass. Update the PurePad build documentation with CTest commands, the sibling
`pure.exe` requirement, installer-owned association, and VC/MFC runtime
boundary.

## Acceptance Criteria

- Release and Debug Visual Studio 2022 x64 builds complete without warnings.
- Every lifecycle CTest passes repeatedly with at least 100 start/stop
  generations.
- No active PurePad source imports or calls `TerminateThread`.
- Failed process or worker startup returns failure synchronously and leaks no
  child, thread, event, or pipe handle.
- Immediate Break, Stop, restart, and application shutdown cannot deadlock.
- PurePad never writes file-association registry keys during normal startup.
- The CI workflow performs the build and tests from a path containing spaces.
- TODO-20 records exact commands, counts, timings, and the TODO-49 deployment
  handoff.
