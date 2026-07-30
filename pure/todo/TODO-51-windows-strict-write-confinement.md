# TODO-51 - Windows Strict Write Confinement

Status: Open
Branch: todo/51-windows-strict-write-confinement

## Purpose

Resolve the one remaining TODO-43 blocker: prove that staged Windows
Pure/Octave tests can write only below their controlled work directory without
weakening the accepted memory-ownership, lifecycle, permanent-root, or runtime
ownership gates.

## Scope

- Select a Windows isolation mechanism whose discretionary access controls
  deny writes to adversarial Low-integrity siblings as well as Medium- and
  High-integrity paths.
- Resolve or avoid the upstream Octave 11.3 AppContainer incompatibility in
  `octave::sys::canonicalize_file_name`.
- Add fail-closed token, ACL, process-lifecycle, write-audit, and cleanup
  regressions around the full staged Pure/Octave bridge.
- Keep installer and bundling policy in TODO-43; this TODO supplies only the
  missing strict-confinement evidence.

## Task List

1. [ ] Reproduce the current Low-integrity sibling escape with an adversarial
       writable sibling and retain it as a strict RED regression.
2. [ ] Choose an isolation design that starts both the Windows loader and the
       full staged Pure/Octave bridge while denying every write outside the
       controlled work directory.
3. [ ] Resolve the Octave 11.3 canonicalization failure, through an upstream or
       rebuilt Octave fix or another isolation primitive, and add a direct
       canonical-path regression.
4. [ ] Integrate bounded process creation, pre-resume token validation,
       write auditing, and fail-closed cleanup without modifying installed
       runtime ACLs or SACLs.
5. [ ] Re-run the complete permanent-root and runtime-ownership acceptance
       suite, including all callback, recovery, conversion, and lifecycle
       coverage inherited from TODO-43.

## Guardrails

- Strict confinement means a fresh child can write only under its controlled
  work directory. It must be denied an adversarial Low-integrity sibling even
  when the owner or Authenticated Users would otherwise have ordinary write
  permission.
- Audit the effective DACL and token. No ambient or broadly shared restricted
  SID may retain a write ACE outside the controlled work directory.
- Validate the exact child token before resuming it, use bounded timeouts, and
  fail closed on launch, validation, audit, termination, or cleanup failure.
- Do not mutate ACLs or SACLs on installed Pure or Octave runtimes. Any staging
  and access-control changes must remain disposable test/development/CI state.
- Do not weaken memory ownership: opaque Octave values remain allocated and
  freed inside the bridge, Pure callback conversions stay inside the Octave C++
  frame, and chained sentry finalizers remain exact.
- Do not weaken the 20-fresh-process lifecycle gate: each process still runs
  100 cycles and observes 100 finalizers, for 2,000 cycles and 2,000 exact
  finalizers.
- Preserve error recovery, callbacks, conversions, function values, canonical
  permanent-root identity and signer fingerprint, loader/bridge PE ownership,
  and the Pure `libc++` versus Octave `libstdc++` runtime split.

## Validation Plan

- Prove the adversarial Low-integrity sibling write is RED under the current
  runner, then prove it is denied by the selected strict isolation mechanism.
- Inspect the child token and audit-root DACL before resume; assert exact
  isolation identities and the absence of ambient outside write permission.
- Require a direct regression in the isolated child showing
  `octave::sys::canonicalize_file_name` returns the correct nonempty canonical
  paths for existing staged `m` roots and `__all_opts__.m`.
- Require the system loader, a minimal probe, and the full staged Pure/Octave
  basic and lifecycle tests to start and finish within bounded time.
- Run the full permanent-root suite with MSYS2 absent from `PATH`: at least the
  existing 39/39 baseline plus all new confinement and canonicalization
  regressions must pass.
- Re-run the independent PE/runtime ownership audit and verify cleanup of every
  disposable profile, staging tree, helper, and probe.

## Open Questions

- Whether upstream or rebuilt Octave can make canonicalization AppContainer
  compatible without changing Pure/Octave semantics.
- Whether a different Windows isolation primitive can provide the same strict
  DAC confinement while retaining ordinary loader compatibility.

## Progress Log

- 2026-07-30: Created from the product owner's BLOCKED disposition for TODO-43.
  Commit `7ea1646c` remains the baseline and must not be weakened.
- 2026-07-30: Recorded the investigated no-go paths.
  - Current Low-only runner: an adversarial writable Low-integrity sibling was
    modified outside both the audit and allowed roots, confirming that Low MIC
    alone is not strict discretionary write confinement.
  - Users plus an Untrusted restricting token: staged Pure and system
    `cmd.exe` both exited `0xC0000022`.
  - Low plus one unique restricting SID: both system-loader and staged-command
    probes exited `0xC0000022`; system files grant loader access to Users, ALL
    APPLICATION PACKAGES, and ALL RESTRICTED APPLICATION PACKAGES, not the
    arbitrary unique SID.
  - Zero-capability AppContainer: a minimal staged command passed with the exact
    package SID, zero capabilities, Low/NO_WRITE_UP, controlled-work writes,
    Low-sibling denial, and clean profile removal. The full staged tree matched
    its source exactly:
    - Pure: 4,769 files, 260,533,868 bytes,
      SHA-256 `d532ad467b964874ec3c2125eae0926e58273733edd1879417e9384c2370d30a`.
    - Octave: 59,533 files, 2,797,722,287 bytes,
      SHA-256 `8964e922b2fdf3743a69169d439a1652d99bdd3497be4b721e74b666d1112366`.
    - Source: 53 files, 277,454 bytes,
      SHA-256 `b0d462a1d22bc9398ffed73965aedf620b4d835d392cd43183e9a112789cdef6`.
    - Bridge: 2 files, 4,771,866 bytes,
      SHA-256 `6d67e6b5bd323be50fab3ad9d534d0d8f6c32810f6c36105d6f46404e56a4005`.
  - The AppContainer staging ACLs were read/execute on the staged tree,
    package modify plus Low on work, and package read/execute plus Low outside
    work. The Medium staged lifecycle test passed, but AppContainer basic and
    lifecycle processes crashed with `0xC0000374` in `ntdll`.
  - A focused standalone probe localized the incompatibility:
    `get_load_path().set` reported
    `no such file, <work>\__all_opts__.m`. Direct absolute and relative Win32
    opens and directory enumeration passed, and
    `octave::directory_path::find_first("__all_opts__.m")` found the staged
    file. Medium
    `octave::sys::canonicalize_file_name` returned the correct paths, while the
    AppContainer call returned empty strings and empty errors for existing
    `m`, `optimization`, and `__all_opts__.m` paths.
  - Initializing before setting the load path did not help. Excluding
    `optimization` allowed set, execute, and `feval` to run but merely shifted
    the failure to trusted startup loading of `<work>\ispc.m`, so it was not a
    safe workaround. The AppContainer profile and staging tree were removed.
  - The final restricted-token design proposed exactly two restricting SIDs:
    ALL RESTRICTED APPLICATION PACKAGES (`S-1-15-2-2`) plus a unique stage SID.
    The disposable root granted the unique SID read/execute, work granted it
    modify plus Low, and the outside root granted it read/execute plus Low; no
    ARAP ACE, including no ARAP write ACE, was present.
  - `CreateRestrictedToken` rejected the two-SID token with error 87 before
    child creation. Focused results were `ARAP_ONLY OK=0 ERROR=87`,
    `UNIQUE_ONLY OK=1 ERROR=0`, and
    `ARAP_AND_UNIQUE OK=0 ERROR=87`. All stage/helper fixtures were removed and
    the repository remained clean.
