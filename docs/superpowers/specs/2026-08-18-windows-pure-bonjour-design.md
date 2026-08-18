# Windows pure-bonjour Design

Date: 2026-08-18
Status: Approved
TODO: `pure/todo/TODO-45-windows-pure-bonjour.md`
Branch: `todo/45-windows-pure-bonjour`

## Goal

Build and package `pure-bonjour` for the 64-bit Windows CLANG64 Pure
distribution while preserving the existing `bonjour` Pure API. Implement the
Windows backend directly on the DNS Service Discovery functions supplied by
Windows instead of installing or redistributing Apple's Bonjour for Windows.

The supported Windows baseline is Windows 10 or later. The backend links to
the system `dnsapi.dll` and uses `DnsServiceRegister`, `DnsServiceBrowse`, and
`DnsServiceResolve`. It does not consume Apple's `dns_sd.h`, Bonjour SDK,
Bonjour service, or Bonjour runtime binaries.

## Decisions

- Target only 64-bit Windows in the CLANG64 Pure distribution.
- Require Windows 10 or later, matching the Microsoft DNS-SD API contract.
- Add a separate Windows implementation source rather than mixing the
  Microsoft and `dns_sd` lifecycle models in one file.
- Preserve `bonjour.pure` and the existing public Pure and native symbol names.
- Link only to the staged Pure runtime and Windows system libraries, including
  `dnsapi` and `ws2_32`.
- Do not download, install, or redistribute Apple Bonjour binaries.
- Package the result as the separate optional `PureBonjour` component.
- Keep every integration test bounded and ensure that it removes the service
  it registered even after failure.

## Dependency and Licensing Decision

Apple publishes the mDNSResponder source, but the separately distributed
Bonjour for Windows binary product has redistribution terms which do not
permit treating its SDK/runtime as an ordinary redistributable dependency.
The package therefore does not use or ship that product. This also removes an
external service-installation requirement from the Pure distribution.

Microsoft documents the selected DNS-SD API as part of the Windows SDK and
the implementation as part of `dnsapi.dll` on Windows 10 and later. The
package uses only those system interfaces. User documentation records the
minimum operating system and makes clear that installing Apple Bonjour is not
required.

The implementation and packaging must retain source references and the
applicable Pure license notices. No Apple header, import library, executable,
service, or DLL may enter the source tree, build inputs, installed component,
or CI artifact.

## Architecture and Boundaries

### Existing portable API

`bonjour.pure` remains the public language binding. Its `publish`, `check`,
`browse`, `avail`, and `get` operations keep their names, argument types,
return shapes, and garbage-collected cleanup behavior. The existing
`bonjour.c` remains the `dns_sd` implementation for platforms that already
use it and is not made responsible for Windows callback semantics.

### Windows backend

A separate `bonjour_windows.c` exports the same native functions consumed by
`bonjour.pure`. It owns UTF-8/UTF-16 conversion, DNS-SD name construction and
parsing, Windows callback contexts, synchronization, cancellation, and
conversion of resolved Windows instances into Pure expressions.

The backend is internally divided into small helpers for names and strings,
registration state, browse/resolve state, result-list ownership, error
translation, and shutdown. These are implementation boundaries inside one
Windows source module, not new public APIs.

### CMake target

The Windows-only CMake build selects `bonjour_windows.c`, creates
`bonjour.dll` without a `lib` prefix, exports the existing bridge entry
points, and links `dnsapi`, `ws2_32`, and the imported Pure target. The build
requires C11, strict warnings, and an x86-64 Windows target. It must fail at
configure time on an unsupported platform or missing staged Pure SDK.

### Optional component

`PureBonjour` installs only `bonjour.dll`, `bonjour.pure`, generated user
documentation, Pure license files, an example, Windows support notes, and an
authoritative ownership inventory. It installs no test program, SDK header,
import library, static library, external service, or dependency DLL.

## Registration Data Flow

`bonjour_publish` validates the UTF-8 service name, service type, and port.
It converts strings to UTF-16, constructs the fully qualified instance name
`<name>.<type>.local`, builds a `DNS_SERVICE_INSTANCE`, and starts an
asynchronous `DnsServiceRegister` request. The returned service object retains
all request, instance, synchronization, completion, and result storage needed
until cleanup.

The registration callback records success or a stable negative error and
signals completion. `bonjour_check` waits for that completion and returns the
same three-element result as the existing module: effective instance name,
service type, and port. It returns a negative integer on operational failure.
The wait is bounded so a missing callback cannot hang the Pure process.

`bonjour_unpublish` requests deregistration for a completed registration or
cancels a pending one, waits for callback quiescence, and then releases the
Windows instance and owned strings. Registration is also process-scoped by
Windows, but explicit cleanup remains mandatory for predictable tests and
garbage collection.

## Discovery Data Flow

`bonjour_browse` validates the service type, constructs
`<type>.local`, initializes synchronized browser state, and starts
`DnsServiceBrowse`. Browse callbacks parse matching PTR records and start
`DnsServiceResolve` for specific instance names. Each resolver owns its cancel
handle and callback context until it completes or the browser shuts down.

A successful resolve callback copies the effective service name, type,
domain, IPv4 or IPv6 presentation address, and host-order port into the
browser's result set. Entries are keyed by the service's fully qualified name
and interface so repeated callbacks update rather than duplicate them.
Removal callbacks delete the matching entry. Any observable change sets the
browser's availability flag.

`bonjour_avail` reads the availability or terminal error under the browser
lock without blocking. `bonjour_get` copies the current result set to the
existing Pure list of five-element tuples and atomically clears the
availability flag. It never returns storage that a later callback may mutate.

`bonjour_close` marks shutdown first, cancels browsing and all outstanding
resolves, waits for callbacks to become quiescent, then frees result entries,
request strings, synchronization primitives, and the browser itself.

## Error Handling and Concurrency

All external strings must be valid UTF-8, the service name and type must form
a valid bounded DNS-SD name, and the port must be in the range 0 through
65535. Allocation, conversion, construction, or immediate Windows API failure
returns a null service/browser object and releases partial state.

Asynchronous Windows status values are exposed as stable negative integers.
Tests and documentation rely on failure categories and bounded behavior, not
on complete localized Windows messages. Cancellation is a normal lifecycle
event during finalization and must not overwrite a previously completed
success or surface as a use-after-free.

Every callback enters through a context whose owner is still alive, holds the
appropriate lock only while copying or changing state, and signals any waiter
after publishing the final state. Code must not call cancellation or other
potentially reentrant Windows APIs while holding the state lock. Shutdown
waits have explicit limits and report a failure rather than silently leaking
live callbacks or freeing their contexts early.

## Testing

Deterministic native tests cover UTF conversion, fully qualified name
construction and decomposition, invalid names and ports, Windows-to-Pure
error mapping, duplicate result updates, removal, and success/failure/cancel
lifecycle transitions. Test seams are internal to the test target and are not
exported or installed.

The integration test uses a unique service instance and type plus an
OS-assigned or otherwise dynamically selected port. It starts a browser,
registers the temporary service, waits with bounded retries for registration,
discovery, and resolve, validates the name, type, domain, address, and port,
then deregisters it and verifies its removal. Cleanup runs after every partial
failure. No persistent service, fixed public endpoint, or internet access is
used.

Where the Windows API offers a local-only scope, the test uses it. Otherwise
it exercises only the local-link DNS-SD mechanism with a unique ephemeral
record and documents that narrow multicast boundary. CI and local runners
apply process and CTest timeouts so firewall policy or disabled multicast
cannot hang the job.

Negative tests verify invalid input, immediate API rejection, cancellation of
pending registration/browse/resolve operations, repeated cleanup, and a
bounded no-result browse. Since the selected backend is a Windows system DLL
rather than an optional Bonjour daemon, the original TODO's absent-service
case is resolved as API failure, cancellation, firewall/policy denial, and
no-result behavior; tests do not attempt to remove or disable a Windows
system component.

## Packaging and Validation

The component is installed beneath a fresh prefix containing spaces and then
copied to a different path. Its smoke test runs from outside the source and
build trees with `PURELIB` unset and `PATH` limited to the staged Pure runtime
and Windows system directories.

The package verifier checks the exact owned file set, sizes, hashes, absence
of build-machine paths, and recursive PE imports. `bonjour.dll` may depend on
`libpure.dll`, `dnsapi.dll`, `ws2_32.dll`, UCRT, and other allowlisted Windows
system libraries only. It must not import `dnssd.dll`, an Apple service, an
MSYS2 runtime DLL, or any undeclared third-party library.

Fresh installation, same-version overlay, relocation, and exact component
removal must preserve all unrelated files in a shared Pure prefix. CI builds
and tests the component on a clean Windows runner, installs only
`PureBonjour`, repeats sanitized-runtime verification, creates a deterministic
archive, and uploads it as a separate artifact.

## Documentation

The README and Windows notes explain the preserved Pure API, Windows 10+
requirement, native Microsoft DNS-SD implementation, firewall and local-link
behavior, and the absence of an Apple Bonjour installation requirement. They
also distinguish system/API unavailability and policy failures from an empty
service result.

Licensing notes cite the Microsoft system dependency and explain why Apple
Bonjour binaries are neither required nor redistributed. The documentation
does not imply endorsement by Apple or claim that the Windows backend is an
Apple Bonjour binary distribution.

## Shipping Decision

Ship `PureBonjour` only if all of these conditions hold:

- the Windows backend preserves the existing Pure API and passes strict
  x86-64 CLANG64 compilation;
- temporary registration, browse, resolve, deregistration, and removal pass
  with bounded cleanup on a clean Windows runner;
- API rejection, cancellation, no-result, and repeated cleanup paths do not
  hang, crash, or leak callback-owned state;
- the staged and relocated component passes with a sanitized runtime
  environment;
- recursive dependency inspection finds only declared Pure and Windows system
  libraries and no Apple or MSYS2 runtime;
- installation ownership, provenance, documentation, and license notices are
  complete.

If the Microsoft DNS-SD API cannot reliably preserve the existing observable
Pure contract, if callback cancellation cannot be made memory-safe, or if the
clean-runner integration test cannot be bounded without publishing a
persistent service, record the reproducible evidence in TODO-45 and defer the
package. Do not fall back to redistributing Apple Bonjour binaries.

## Completion Criteria

TODO-45 is complete when the native Windows backend and optional component are
implemented, deterministic and integration tests pass on a clean runner,
the installed dependency closure and lifecycle are verified, documentation
records the Windows 10+ Microsoft backend decision, and the final ship-or-defer
decision is captured in the TODO progress log.
