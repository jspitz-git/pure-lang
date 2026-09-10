# Windows pure-midi Audit Hardening Design

## Context and objective

TODO-34 declared the Windows `pure-midi` package complete after building
`pmlib.dll` and `midifile.dll`, running two hardware-free smoke tests, manually
testing one MIDI output, and checking a sixteen-file installed delta. The
SuperPowers audit reproduced that baseline in MSYS2 CLANG64, but found unsafe
Standard MIDI File parsing and event conversion, incomplete stream lifecycle
handling, non-hermetic and destructively parameterized test runners, and weak
build, PE, installation, source-distribution, CI, documentation, and license
contracts.

The objective is a native Windows package which safely rejects malformed MIDI
files and invalid Pure values, closes or quarantines every PortMidi stream
deterministically, and produces independently reproducible binary and source
packages. MSYS2 remains the supported build environment; installed executables
and DLLs must not depend on the MSYS runtime. Existing public Pure names and
successful value shapes remain compatible.

## Supported interfaces and compatibility

The supported module set remains `midi`, `portmidi`, and `midifile`, backed by
`pmlib.dll`, `midifile.dll`, and the PortMidi runtime. The bundled example and
the existing two-track, 1632-event fixture remain part of the public package.

Valid Standard MIDI Files accepted by the existing API must continue to load,
round-trip, and expose the same event representation. Invalid constructors,
events, matrices, stream aliases, files, and sizes fail through the existing
false/null/error-code conventions where possible. No hardware device is opened
by mandatory tests. The historical Microsoft MIDI Mapper output result remains
historical evidence and is not generalized into a current hardware claim.

## Checked Standard MIDI File I/O

All file reads and writes use checked helpers which return success explicitly.
EOF, short I/O, failed seek/tell, arithmetic overflow, malformed variable-length
quantities, unsupported running status, invalid chunks, and data extending past
the enclosing chunk reject the file. Parser state never consumes bytes beyond
the declared track boundary.

The parser validates the header length, format, division, track count, event
status, channel data-byte ranges, meta and SysEx lengths, and end-of-track
encoding. Lengths are converted only after proving they fit `size_t`, the
library's native `int` fields, the remaining file/chunk extent, and allocation
arithmetic. A variable-length quantity consumes at most four bytes. Individual
event payloads and the complete input are bounded by the actual file extent;
no length from the file can initiate an allocation larger than its remaining
containing chunk.

Every allocation is checked before dereference. Failure destroys the partially
constructed event, track, and file graph in reverse ownership order and closes
the file. Save detects every failed write, seek, tell, flush, and close and
returns failure without claiming a valid output. The test contract may inject
short I/O and allocation failure without affecting production behavior.

## Pure event and matrix boundary

The C wrapper uses overflow-checked matrix allocation and treats allocation
failure as an ordinary failed conversion. List/tuple extraction arrays are
released on empty and failing paths. Decoding checks native lengths and pointers
before building Pure matrices.

Encoding requires an exact `(tick, bytes)` tuple. Tick values must fit signed
32-bit storage. The event matrix must be a contiguous integer vector with a
checked element count. Every byte is in `0..255`.

- Channel events require the exact MIDI length implied by their status: two
  bytes for program/channel pressure and three for the other channel messages.
- Meta events require at least status and type bytes; end-of-track must have no
  payload and is handled only by the serializer.
- SysEx begins with `0xf0` or `0xf7`, has a representable nonzero length, and
  cannot reach native code through a null or overflowed allocation.
- `midi::word`, `bytes`, `read`, `write`, `readmsg`, and `writemsg` reject wrong
  ranks, shapes, empty/oversized values, out-of-range bytes, and native lengths
  which do not fit the PortMidi ABI.

Failed `put_track` and `put_tracks` calls are transactional: tracks and events
created by that call are removed, leaving the original file unchanged.

## Stream ownership and lifecycle

PortMidi streams are represented by an owned native wrapper rather than a bare
`PortMidiStream*`. The wrapper records input/output kind, open/closing/closed/
failed state, the native handle, active operations, and synchronization needed
to exclude use during close. All public I/O obtains a live reference before
touching the handle and rejects closed, closing, failed, or wrong-direction
streams.

Open validates the device record, direction, buffer size, latency, allocation,
and every PortMidi result. Failure releases the wrapper and native handle in
reverse order. Close marks the wrapper closing, excludes new operations, waits
for active operations, then calls `Pm_Close`. A successful close invalidates
all aliases. A failed native close permanently quarantines the wrapper and its
handle until process exit; it is never presented as reusable and is never
freed beneath an alias. Repeated close and finalization are deterministic.

`midi::stop` cannot silently terminate PortMidi while a live wrapper exists.
It closes all owned streams first and reports the first failure; quarantined
handles prevent unsafe reinitialization. Timer start/stop state is tracked so
restarts, partial initialization, and repeated shutdown do not leak resources.
Blocking reads wake or time out when the stream enters a terminal state.

## Deterministic native and Pure tests

A test-only PortMidi dispatch seam defaults to the real library in production
and accepts a deterministic fake only in fault-test targets. It supplies device
records, time, input/output data, controlled blocking, and injected initialize,
open, read/write, abort, close, terminate, timer, allocation, and I/O failures.
No mandatory test opens a physical or virtual MIDI port.

The native fault harness covers lifecycle transitions, invalid devices and
directions, aliases, repeated and failed close, termination with active
operations, concurrent close/I/O, matrix shapes and ABI limits, MIDI status and
byte ranges, truncated and malformed file corpora, chunk arithmetic, allocation
failure, transactional rollback, short output writes, and zero net tracked
resources. Release and AddressSanitizer variants run the same deterministic
cases. The public Pure tests cover the corresponding value-level rejection and
retain the valid fixture round-trip.

Optional output and loopback tests remain separate explicit targets with hard
timeouts. They require an explicit selector or an unambiguous supported default,
print the exact interface/device/result, always send Note Off on cleanup, and
never turn absence of hardware into a mandatory failure or a passing loopback.

## Hermetic runner and owned cleanup

One native Windows runner launches Pure with a fixed timeout, drains stdout and
stderr without pipe deadlock, and preserves the exact child exit status. A test
passes only after all assertions emit one unpredictable per-run completion
token. Parser diagnostics or unhandled Pure expressions cannot be mistaken for
success.

The runner replaces `PATH` with the built or staged module directory, exact
audited runtime directories, and Windows system directories. It removes
`PURELIB`, `PURE_INCLUDE`, and `PURE_LIBRARY`. Executable, interface, module,
script, fixture, and working-directory paths are canonical regular paths with
no reparse ancestor.

Recursive cleanup is restricted to a unique leaf beneath a fixed contract root
created by the test. The leaf contains an unpredictable ownership sentinel;
cleanup rejects a missing or mismatched sentinel and any symlink, junction, or
other reparse component. No caller-controlled arbitrary path is recursively
deleted. Legacy Make clean targets remove only enumerated outputs after the
module suffix is validated.

## Strict Windows build and dependency selection

Normal upstream configuration remains available. An opt-in strict audit mode
requires explicit canonical inputs for Clang 22 targeting
`x86_64-w64-windows-gnu`, Ninja, pkgconf, Pure 0.68, PortMidi headers/import
library/runtime, `llvm-readobj`, the CLANG64 prefix, and the authoritative
Windows system directory. It rejects ambient discovery, alternate origins,
wrong architectures, reparse inputs, missing files, and malformed overrides.

All sizes crossing the Pure, PortMidi, and C runtime boundaries use fixed-width
or proven-representable types. Strict warning flags apply to both modules and
fault harnesses. The build exposes separate normal, fault, sanitizer, PE,
package, source-distribution, and optional hardware targets.

## Recursive PE closure

The verifier parses complete `llvm-readobj` file-header and import records and
fails on malformed, missing, duplicate, delay-load, or unsupported records. It
requires AMD64 PE32+ for both modules and every recursively staged non-system
DLL. Imports are compared case-insensitively using exact DLL names.

Every non-system import resolves to exactly one staged file whose expected
source and SHA-256 were fixed at configure time. System imports resolve only
through the authoritative Windows system directory and known API-set/UCRT
loader policy. `msys-2.0.dll`, libgcc, libstdc++, and any undeclared runtime are
forbidden. Closure includes `libpure.dll`, `libportmidi.dll`, and their complete
non-system dependency graph rather than only three preselected files.

## Exact installation and licensing

Runtime and documentation remain disjoint CMake components. The install
contract starts with a fresh copy of the portable Pure prefix, records a sorted
path/type/size/SHA-256 baseline, installs each component separately, and requires
the final tree to equal that baseline plus one exact declared delta. Baseline
files stay byte-identical; collisions, extra files, missing files, hardlinks,
reparse points, path escapes, and inconsistent manifests fail closed.

Every installed module, interface, document, example, test, fixture, runtime,
and license is hash-matched to its configured source. Installed Pure tests run
through the hermetic runner, and the recursive PE closure is repeated using only
the stage.

The full upstream PortMidi license text is stored in the repository rather than
looked up through ambient `MSYSTEM_PREFIX` during installation. An origins
inventory maps `libportmidi.dll` to project, installed version, authoritative
source URL, license, local payload, and SHA-256. This is an artifact-completeness
contract, not a new legal interpretation.

The cooperating-installer threat boundary matches the hardened Windows package
contracts already used in this repository: owned reservations, canonical
ancestors, retained handles, serialization, controlled rollback, and verified
component manifests are required. Resistance to an actively malicious process
running as the same principal and durable whole-tree atomicity across power loss
are not claimed.

## Source distribution

`make dist` explicitly declares every required C source/header, Pure interface,
CMake helper, runner, harness, test, fixture, example, document, license, and
origins record. Inputs must be regular non-reparse files and paths containing
spaces must work. The archive has deterministic ordering, metadata, timestamps,
and content and excludes checkout/build/cache artifacts.

The source contract creates the public archive twice, compares hashes, extracts
under a path containing spaces, removes access to checkout-side helpers, checks
an exact file/hash manifest, and performs strict configure, four-worker build,
Release/ASan mandatory tests, recursive PE verification, both component
installs, and installed verification solely from extracted sources. Generated
files and logs must not embed checkout paths in any Windows casing.

## Windows CI and documentation

The non-Linux release workflow covers `pure-midi/**`, TODO-34, its semantic
validator, and the workflow itself on the existing push and pull-request branch
policy. After portable Pure staging it installs explicit CLANG64 prerequisites,
configures a fresh short strict Release build, builds and PE-checks with exactly
four workers, runs all mandatory no-hardware/fault/contract tests, installs both
components into a fresh stage, verifies the installed package, and runs public
`make distcheck`.

The structural YAML validator checks path filters, runner and expression
contexts, prerequisites, exact input origins, step order, failure propagation,
runtime sanitization, component and verifier commands, nonempty test selection,
and exactly four workers. Mutation tests prove each required atom is enforced.

`WINDOWS.md` documents exact standalone commands and separates mandatory,
optional output, and true loopback evidence. README no longer presents obsolete
download/build directions as the supported Windows path. TODO-34 preserves its
historical log, reopens during implementation, records exact commands, counts,
versions, limitations, and reviews, and closes only after a fresh final run.

## Verification and residual boundaries

Closure requires a never-before-used strict Release directory, a four-worker
normal build and PE target, the deterministic native and public suites under
Release and ASan, all mandatory CTests, exact runtime/documentation installation,
installed smoke and PE verification, two identical source archives, extracted-
source verification, workflow mutation tests, and a clean branch diff.

Windows ThreadSanitizer is not required when unavailable; deterministic stress,
barriers, timeouts, and resource counters cover concurrency instead. Physical
MIDI hardware, driver-specific timing accuracy, real loopback, native POSIX
behavior, and hosted-CI runtime budget are explicit residual boundaries and are
never inferred from the mandatory Windows tests.
