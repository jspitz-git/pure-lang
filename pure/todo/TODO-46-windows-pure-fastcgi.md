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

- Validated commit: `9a18ba773d84a48db3ce34378ea6d905e20dcf13`.
- Clean workflow run:
  https://github.com/jspitz-git/pure-lang/actions/runs/32164621545
- Required job (`Windows PureFastCGI package`):
  https://github.com/jspitz-git/pure-lang/actions/runs/32164621545/job/95801413633
- Uploaded artifact (`windows-pure-fastcgi`):
  https://github.com/jspitz-git/pure-lang/actions/runs/32164621545/artifacts/9335160401
- Clean-runner FastCGI tests: 12/12 passed in 109.90 seconds.
- Pure build: 132.312 seconds with one worker; PureFastCGI build: 5.908
  seconds with one worker.
- Staged package: 6 files, 111891 bytes; `fastcgi.dll`: 94208 bytes.
- Inventory SHA-256:
  `70ff8167791066a34315c4d0f9405d4edff0435a911ea67714c692fa3ca5ea23`.
- Deterministic inner ZIP: 46874 bytes, SHA-256
  `7c57ddf5c8263b33b3f41383dbe0fb7df0defcd461726b33d7b0df256403e91e`.
- GitHub artifact wrapper: 46611 bytes, SHA-256
  `4a3b62d4de250d2488c5ac675699057bbd060559af5195c0a3de5198c169601a`.
- Independent download verification safely extracted the ZIP into a fresh path
  containing spaces, reconstructed the six-file hash oracle, and verified 6
  exact files, 5 inventory rows, 11 recursive PE files, and the real protocol
  smoke with no MSYS2 directory on the runtime `PATH`.

## Progress Log

- 2026-07-25: Created as an optional server Windows package investigation.
- 2026-08-18: Selected pinned fcgi2 2.4.7, implemented the optional component,
  and recorded a successful clean Windows package job and independently checked
  the artifact. Decision: ship the optional `PureFastCGI` component.
