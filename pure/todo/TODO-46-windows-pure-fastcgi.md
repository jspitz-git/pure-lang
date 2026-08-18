# TODO-46 - Windows pure-fastcgi Package

Status: Closed — ship the optional `PureFastCGI` component
Branch: windows-bundle

## Purpose

Determine whether `pure-fastcgi` can be built and supported with a maintained
Windows FastCGI library.

## Scope

- Identify a compatible and redistributable FastCGI implementation.
- Build the native bridge and validate request, response, environment, and cleanup.
- Keep web-server-specific deployment outside the core installer.

## Task List

1. [x] Select and reproduce a Windows FastCGI dependency.
2. [x] Build the module and audit its runtime requirements.
3. [x] Add a self-contained protocol smoke test.
4. [x] Decide whether to ship or defer the package.

## Guardrails

- Do not require IIS or another full web server for basic automated tests.
- Avoid exposing a network listener beyond loopback during validation.

## Validation Plan

- Exchange one controlled FastCGI request and response with bounded timeouts.
- Run on a clean VM and inspect all native dependencies.

## Decision

Ship `pure-fastcgi` only through the optional CMake component `PureFastCGI`.
The component embeds the required fcgi2 objects statically and does not install
or validate IIS, Apache, nginx, or another FastCGI listener. TODO-49 may consume
only this optional component and must preserve that deployment boundary.

The selected dependency is FastCGI-Archives/fcgi2 2.4.7 at commit
`47f2c03b7771f0ef61d887734ef91e6fa747f837`. Its source archive is 263969 bytes
with SHA-256
`e41ddc3a473b555bdc0cbd80703dcb1f4610c1a7700d3b9d3d0c14a416e1074b`.

## Shipping Evidence

- Validated commit: `b94368ba81571b2ffc6bf614e0475049c1377228`.
- Clean workflow run:
  https://github.com/jspitz-git/pure-lang/actions/runs/32177457979
- Required job (`Windows PureFastCGI package`):
  https://github.com/jspitz-git/pure-lang/actions/runs/32177457979/job/95842552076
- Uploaded artifact (`windows-pure-fastcgi`):
  https://github.com/jspitz-git/pure-lang/actions/runs/32177457979/artifacts/9339731766
- Clean-runner FastCGI tests: 12/12 passed in 106.49 seconds.
- Staged package: 6 files, 112403 bytes; `fastcgi.dll`: 94720 bytes.
- Inventory SHA-256:
  `ed27b9188db2a64ecc58934ab9ac985fe999f6f1019bb460fe61732643dcdc3c`.
- Deterministic inner ZIP: 47046 bytes, SHA-256
  `df890dc3a793aa0a8534eb94b2c95271bd139750707b3e03fe78a8d4790b5608`.
- GitHub artifact wrapper: 46783 bytes.
- Independent download verification safely extracted the ZIP into a fresh path
  containing spaces and Unicode and verified 6 exact files and all 5 inventory
  hashes and sizes. The clean job independently verified 11 recursive PE files
  and the real protocol smoke with no MSYS2 directory on the runtime `PATH`.

## Progress Log

- 2026-07-25: Created as an optional server Windows package investigation.
- 2026-08-18: Selected pinned fcgi2 2.4.7, implemented the optional component,
  and recorded a successful clean Windows package job and independently checked
  the artifact. Decision: ship the optional `PureFastCGI` component.
