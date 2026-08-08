# TODO-51 Windows API-set Baseline Repin Design

> **Rejected on 2026-08-08.** Historical record only. Do not implement or
> resume this work without a new approved TODO.

## Context

The reviewed Gnuplot-aware Task 3 preflight for production attempt v12 ran
under the pinned PowerShell 7.6.4 executable and failed closed before the
assembler was launched:

```text
Authoritative API-set baseline mismatch.
```

The v12 production state is unambiguous:

- preflight exit marker: `1`;
- assembler launch count: zero;
- `C:\tmp\todo51-task3\stage-runtime-v12`: absent;
- staged binary inspection or execution count: zero;
- v11 and v12 evidence: preserved.

Read-only root-cause analysis established that Windows Update replaced the
authoritative API-set component while the coarse
`Environment.OSVersion.VersionString` remained
`Microsoft Windows NT 10.0.26200.0`. The previously accepted WinSxS component
was version `10.0.26100.8521`, 194,040 bytes, SHA-256
`8FFADF5FF3D8D3843FC393E9D03C2091AC5DDFC6227B8097DC182E2A8F8463FC`.
The current System32 hard link resolves to WinSxS component version
`10.0.26100.8972`, 194,048 bytes, SHA-256
`E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8`.

The current component is signed by Microsoft Windows with a valid
Authenticode signature. Its System32 and WinSxS hard-link paths are
byte-identical. Windows reports `CurrentBuild = 26200`, `UBR = 8973`, and
the relevant updates were installed on 2026-07-31 and 2026-08-01. This is a
platform servicing change, not source, stage, supplement, or loader-domain
corruption.

## Accepted platform identity

Production staging continues to accept exactly one local Windows/API-set
baseline. The assembler and preflight bind all of these values together:

- `Environment.OSVersion.VersionString`:
  `Microsoft Windows NT 10.0.26200.0`;
- registry `CurrentBuild`: `26200`;
- registry `UBR`: `8973`;
- API-set path: `%WINDIR%\System32\apisetschema.dll` after canonicalization;
- API-set file version:
  `10.0.26100.8972 (WinBuild.160101.0800)`;
- API-set product version: `10.0.26100.8972`;
- API-set length: 194,048 bytes;
- API-set SHA-256:
  `E485E3CF63919CD5DC5EC8624E94C3645E8BF3C4445AE937FBA045BEA3D88BB8`.

The file must remain a regular, non-reparse System32 file. The exact hash is
the production integrity boundary; the valid Microsoft signature and exact
WinSxS hard-link provenance are recorded as acceptance evidence rather than
replacing the hash check. No caller can override any accepted platform value.

This strengthens the old contract: a future cumulative update that changes
the UBR or API-set identity fails explicitly even when the coarse OS version
string remains unchanged.

## Assembler architecture

The staging assembler adds focused production-only platform identity helpers:

1. read `CurrentBuild` and `UBR` from
   `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion`;
2. canonicalize and validate the existing System32 API-set path;
3. read its file version, product version, byte length, and SHA-256;
4. compare the complete observed identity with the non-overridable accepted
   constants before import resolution;
5. include the observed build, UBR, version, length, and hash in the final
   JSON evidence.

The existing authoritative API-set resolver, `FreeLibrary` handling, Gnuplot
edge accounting, loader-domain rules, stage inventory, and manifest
serialization do not change. TestMode uses fixed synthetic identity values
inside its exact disposable fixture boundary and never reads or substitutes
production registry/file values.

No new staged evidence file is created. Platform identity appears only in the
assembler's final JSON and repository report, so the deterministic stage
inventory remains unchanged.

## Failure handling

The assembler and preflight fail before stage acceptance when any identity
field is absent, malformed, or unequal, including:

- coarse OS version, CurrentBuild, or UBR mismatch;
- registry value type mismatch;
- API-set path outside canonical System32;
- missing, non-regular, or reparse API-set file;
- file version, product version, length, or SHA-256 mismatch;
- authoritative API-set resolution or handle-release failure.

Failure never falls back to an older WinSxS component, a copied schema, a
signature-only trust decision, a version range, or caller-provided values.
It preserves the attempt's helpers, logs, marker, and any partial stage and
does not retry or repair them in place.

## Test design

Implementation follows test-driven development. New tests first fail on the
old single coarse-version/hash contract, then prove:

- all accepted build, UBR, version, length, and hash constants are exact and
  production-non-overridable;
- the exact complete synthetic platform identity succeeds;
- independent mutations of coarse OS version, CurrentBuild, UBR, file
  version, product version, length, and SHA-256 each fail closed;
- missing or wrongly typed registry values fail;
- an API-set file outside System32, a reparse file, or a non-regular file
  fails;
- release/path/provenance failures remain distinct from unresolved import
  counts and still abort;
- the seven Gnuplot loader-domain postconditions remain exact;
- the complete supplement and staging regression suites remain green;
- no caller-visible platform identity parameter or staged evidence file is
  introduced.

Production helper scripts independently verify the same literal platform
identity and their own reviewed hashes before any assembler launch.

## Production continuation

Attempt v12 is a preserved failed preflight attempt even though its stage root
was never created. It is never reused. After the repin implementation, tests,
and independent review, the next production attempt uses only the currently
absent root `C:\tmp\todo51-task3\stage-runtime-v13` and newly named v13 helper,
PID, log, and marker files.

The v13 sequence is:

1. verify all v13 targets/evidence paths are absent and v11/v12 evidence is
   preserved;
2. run one full immutable-input preflight with the new exact platform pins;
3. if preflight succeeds, launch the assembler exactly once with the same
   reviewed 16 production parameters and no test/injection/inventory
   overrides;
4. require marker zero, empty stderr, one JSON object, the exact platform
   identity, and every existing static stage postcondition;
5. independently recompute the static stage, loader-domain, API-set, source,
   and permanent-runtime evidence without executing staged binaries;
6. run fresh regression/parser/diff checks and commit only the repository
   report after independent review.

The accepted stage remains exactly 64,312 files, 3,334,971,045 bytes,
manifest SHA-256
`115AC1F8843FFC60A4FFD103DCB7CD9C3099CAE14F2B3B674EF5D6230DF22DE0`,
1,539 magic-byte PE files, 219 PE `.oct` modules, one inert placeholder, and
the Gnuplot loader split `65 / 63 / 1002 / 249 / 563 / 190 / 0`.

If v13 fails, it is preserved and execution stops for a new root-cause
analysis. Only an accepted v13 static stage returns TODO-51 to the strict
AppContainer runtime, canonicalization, embed, and bridge tests.

## Rejected alternatives

- Replacing only the old SHA-256 was rejected because the unchanged coarse
  OS version does not identify cumulative servicing state.
- Accepting any validly Microsoft-signed API-set schema was rejected because
  it weakens deterministic production inputs to a moving trust range.
- Reusing v12 was rejected because its completed failed preflight evidence is
  already bound to the old pins; a new root keeps every attempt immutable and
  auditable.
