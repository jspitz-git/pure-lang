# Windows pure-fastcgi Design

Date: 2026-08-18
Status: Approved
TODO: `pure/todo/TODO-46-windows-pure-fastcgi.md`
Branch: `todo/46-windows-pure-fastcgi`

## Goal

Build and package `pure-fastcgi` on 64-bit Windows from an exactly pinned,
security-fixed FastCGI source. Preserve the existing Pure API, statically link
the FastCGI implementation into the module, and validate the real FastCGI
protocol without requiring IIS, Apache, or another web server.

The selected upstream baseline is release 2.4.7 of
`FastCGI-Archives/fcgi2` at commit
`47f2c03b7771f0ef61d887734ef91e6fa747f837`. It includes the fix for
CVE-2025-23016 and retains the `fcgi_stdio` API consumed by `pure-fastcgi`.
Implementation must record the archive SHA-256 before the source is accepted.

## Decisions

- Build only 64-bit Windows support for the CLANG64 Pure distribution.
- Build `fcgi2` from an exactly pinned upstream source release.
- Statically link the required `fcgi2` code into `fastcgi.dll`.
- Preserve the public API in `fastcgi.pure`.
- Use a Windows named pipe for automated FastCGI protocol validation.
- Do not require or install a web server, FastCGI service, or TCP listener.
- Package the result as the separate optional `PureFastCGI` component.
- Keep web-server-specific deployment configuration outside the installer.

## Source and Build Contract

The dependency-fetch step accepts one declared upstream URL, release, full
commit identity, and archive SHA-256. It downloads only when explicitly
requested. A normal configure or rebuild consumes an existing verified source
archive or tree and never follows a branch, resolves a moving tag, or silently
updates the dependency.

The CMake build compiles only the upstream sources required for `fcgi_stdio`,
`fcgiapp`, and the Windows transport into an internal static library. That
library is linked into `fastcgi.dll` together with the existing Pure bridge,
GMP, and MPFR support. The internal library, upstream headers, test client,
and build tools are not installed.

Small Windows or CLANG64 corrections may be carried as separate patches. Each
patch has a stable filename, SHA-256, affected upstream file, and documented
reason. Source verification occurs before patching, and the build fails if a
patch no longer applies exactly. The build records the source identity,
archive hash, patch hashes, compiler and tool versions, configure options,
elapsed time, and staged size.

## Components and Boundaries

### Dependency verification

Focused CMake modules own source identity checks, archive verification, patch
application, and provenance generation. They do not implement FastCGI
protocol behavior.

### Internal FastCGI library

The internal target builds the selected upstream implementation without
installing or exporting it. Its public boundary is the upstream `fcgi_stdio`
API already consumed by the bridge. No separate `libfcgi` DLL may appear in
the build or installed runtime closure.

### Pure bridge and module

`fastcgi.c`, `fastcgi_extra.c`, and `fastcgi.pure` retain their existing
responsibilities and public names. Required Windows portability changes stay
inside the native bridge or narrowly scoped platform configuration. The port
must not replace the public API with `fcgiapp`-specific objects or expose
test-only controls to Pure users.

### Protocol test harness

The harness is a build-tree test tool. It owns creation of the unique named
pipe, launch and cleanup of the Pure worker, FastCGI record encoding and
decoding, timeout enforcement, and test diagnostics. It is never installed.

### Optional runtime component

`PureFastCGI` contains only the Pure module, `fastcgi.dll`, user-facing
documentation, applicable license notices, provenance, and the authoritative
ownership inventory. It contains no compiler, source archive, headers, static
library, test launcher, web server, or separate FastCGI runtime DLL.

## Protocol Test Data Flow

The test launcher creates a uniquely named pipe under the upstream Windows
FastCGI pipe namespace. It starts a one-request Pure worker with the listener
handle inherited as standard input and with the standard-handle arrangement
required by the upstream Windows transport. Only handles required by this
contract are inheritable.

The launcher connects the client endpoint and sends a complete responder
request:

1. `BEGIN_REQUEST` with a fixed request identifier;
2. `PARAMS` records containing controlled CGI and FastCGI environment values;
3. a terminating empty `PARAMS` record;
4. non-empty request data in `STDIN`;
5. a terminating empty `STDIN` record.

The Pure worker calls `fastcgi::accept`, verifies the environment and request
body, writes a deterministic response and a distinct diagnostic marker, sets
an explicit application status, finishes the request, and exits. The launcher
separately collects and validates `STDOUT`, `STDERR`, and `END_REQUEST`, then
waits for normal worker termination.

Every blocking pipe, process, and record operation has a bounded timeout. On
failure the harness closes its endpoints and handles, terminates only the
worker process it created, waits for cleanup, and reports the phase and last
valid FastCGI record. No TCP port is opened. A unique pipe name prevents test
collisions and stale global state.

## Error Handling and Lifecycle

The build fails closed on a source identity or hash mismatch, an
unapplicable patch, a missing required symbol, or an unexpected runtime
dependency. It also fails if the staged component contains `libfcgi*.dll`, an
undeclared file, or a retained build or stage prefix.

Runtime tests cover successful accept and finish, environment and body input,
separate standard output and error streams, explicit status, input stream
termination, and cleanup after success. They also send a malformed or
prematurely terminated request and verify bounded failure without leaving a
worker, pipe, or owned handle behind. Repeated `finish` calls must be safe and
must not emit a second response or double-release request state.

Diagnostics assert stable failure categories and phases rather than complete
upstream wording. Test cleanup is process-scoped and never searches for or
terminates unrelated processes by executable name.

## Packaging and Validation

The staged component is installed beneath a prefix containing spaces. Runtime
tests run with MSYS2 build variables removed and `PATH` limited to the staged
Pure prefix and Windows system directories. The prefix is copied to a
different path and the protocol smoke test is repeated against the relocated
module.

The package verifier compares the exact file set against the authoritative
inventory, checks every size and SHA-256, and recursively audits PE imports.
Only declared Pure, GMP, MPFR, compiler-runtime, and Windows system
dependencies are accepted. In particular, no dynamic FastCGI dependency is
allowed. Every installed file records its relative path, purpose, origin,
version or source identity, SHA-256, size, and applicable license.

Installation validation stages a fresh install, overlays the same version,
and removes exactly the files owned by `PureFastCGI`. Unrelated files beneath
the shared Pure prefix must be byte-identical after each operation. TODO-49
must consume the same component name and ownership inventory whether the
payload is embedded in or downloaded by the installer.

## Documentation Boundary

User documentation explains that a deploying web server or process manager
must provide a compatible FastCGI listener and request environment. It may
include a generic protocol-level example, but it does not install, configure,
or endorse an IIS, Apache, nginx, or other server integration. Server-specific
deployment remains the user's responsibility.

## Shipping Decision

Ship `PureFastCGI` only when all of these conditions hold:

- the exact pinned `fcgi2` source builds reproducibly on a clean CLANG64
  runner;
- `fastcgi.dll` preserves the existing Pure API and statically contains the
  FastCGI implementation;
- the named-pipe test validates request parameters, body, response, error
  stream, application status, termination, and cleanup with bounded timeouts;
- the staged and relocated component passes with a sanitized runtime
  environment;
- source, patches, licenses, installed files, and native dependency closure
  have complete provenance;
- fresh installation, same-version overlay, and exact removal preserve all
  unrelated Pure files;
- TODO-49 receives a stable optional-component and ownership contract.

If these conditions require a substantial fork of the upstream Windows
transport, or if security, provenance, or redistribution terms cannot be
established, record the reproducible evidence in TODO-46 and defer the
package. Do not ship a partial component, fall back to an unpinned dependency,
or require an external `libfcgi` runtime.

## Completion Criteria

TODO-46 is complete when the selected source and build are exactly pinned,
the bridge and self-contained protocol tests pass on a clean Windows runner,
the installed runtime closure and license inventory are verified, relocation
and installation lifecycle checks pass, measured build and package data are
recorded, and the final ship-or-defer decision is documented for TODO-49.
