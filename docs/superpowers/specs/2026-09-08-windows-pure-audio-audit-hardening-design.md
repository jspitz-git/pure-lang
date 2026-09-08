# Windows pure-audio Audit Hardening Design

## Context and objective

TODO-33 declared the Windows `pure-audio` package complete after building five
modules, exercising two no-hardware smoke tests, manually checking playback and
capture, and staging a forty-file package. A SuperPowers audit reproduced a
non-hermetic baseline and found unsafe callback-buffer handling, unchecked
matrix capacities and size arithmetic, ABI-width errors, incomplete stream
lifecycle handling, fall-through conversions, test false positives, unsafe
cleanup, and incomplete PE, install, source-distribution, CI, documentation, and
license contracts.

The objective is a native Windows package whose public operations are memory
safe, whose interleaved and non-interleaved PortAudio modes are fully supported,
whose tests are deterministic without audio hardware, and whose claimed source
and binary package boundaries are independently reproducible. Existing public
Pure names and successful-path value shapes remain compatible unless the old
declaration is ABI-invalid.

## Supported modules and compatibility

The supported module set remains `audio`, `fftw`, `srcprocess`, `sfinfo`, and
`realtime`, with their six existing Pure interfaces. The build uses MSYS2
CLANG64 development tools, but installed executables and DLLs must not depend on
the MSYS runtime, libgcc, or libstdc++.

`Pa::NonInterleaved` remains a supported public format flag. Both callback and
blocking Pure APIs must produce the same logical frame/channel ordering as the
interleaved mode. Existing PortAudio sample-format constants remain accepted
where the implementation advertises conversion support.

The libsndfile interface changes every `sf_count_t` parameter and return from
Pure `int` to the correct signed 64-bit FFI type. Values representable by the
old interface continue to behave identically; truncation to 32 bits is never
permitted.

## Frame representation and callback data flow

The internal ring queues use one canonical interleaved sequence of complete
frames. Queue capacity, readable length, writable length, and every transfer
are expressed in frames plus an overflow-checked bytes-per-frame conversion.
No operation may enqueue, dequeue, discard, or report a partial frame.

An interleaved PortAudio callback transfers complete frames directly between
the callback buffer and the canonical queue. A non-interleaved callback treats
the PortAudio value as an array of per-channel pointers and gathers input or
scatters output frame-by-frame. Null channel buffers, invalid channel counts,
unsupported format combinations, and overflow fail closed without dereferencing
untrusted pointers.

Output underflow is filled with the format's encoded silence: zero for signed
integer and floating-point formats and 128 for unsigned 8-bit audio. Input
overflow drops only whole frames and preserves subsequent channel alignment.
Playback drain completion is measured by frames consumed by the callback, not
merely frames accepted into the local queue.

## Bounds, conversions, and ABI safety

All public frame counts, channel counts, sample counts, byte counts, and queue
sizes are validated before conversion. Checked helpers reject negative values,
zero where invalid, unsupported formats, multiplication/addition overflow, and
values not representable by the receiving native API. Allocation size and loop
bounds must derive from the same checked count.

Pure matrix wrappers verify element type and exact minimum capacity before
calling native audio or samplerate routines. Required capacity is
`frames * channels`; output capacity also accounts for the resampling ratio and
the native API's returned frame counts. Short buffers fail before FFI entry.

The `Int16`, `Int8`, and `UInt8` conversion branches terminate independently
and have exact-value tests in both directions. FFT helpers reject unsupported
input shapes explicitly rather than silently reconstructing a different-sized
signal.

## Stream state and concurrency

Each stream has an explicit state machine: allocated, opened, started,
stopping, closed, and failed. Initialization of mutexes, conditions, queues,
and PortAudio handles is tracked independently so every failure path unwinds
only resources that were successfully initialized and in reverse order.

Device indices and `Pa_GetDeviceInfo` results are validated before access.
Every PortAudio return value from initialize, open, start, stop, abort, and
close is handled. A failed start closes the native stream and returns the exact
error; it never exposes a usable Pure stream.

Native operations acquire a reference/activity count before using stream
state. Close marks the stream closing, stops callback production, wakes blocked
readers and writers, waits for callback and active operations to leave, and only
then destroys synchronization objects and memory. Stop, restart, explicit
close, finalization, aliases, and repeated close are deterministic. Once
closed, all aliases and sentries reject queries or I/O without touching the old
`PaStream`.

Blocked I/O wakes and fails on stop, close, callback error, device loss, or
other terminal state. Queue indices and state shared with the callback use the
same mutex/condition protocol or C11 atomics; `volatile` alone is not accepted
as synchronization.

## Deterministic native and Pure tests

A test-only PortAudio dispatch seam defaults to the real API in production and
can be replaced by a deterministic fake backend only in fault-test targets.
The fake supplies device descriptions, interleaved and non-interleaved
callbacks, controlled consumption/drain, and injected failures for every
lifecycle call. It never opens physical audio hardware.

The native fault harness covers invalid devices, initialize/open/start/stop/
close failures, callback errors, device loss, blocked-I/O wakeup, concurrent
close, aliases/finalization, all sample formats, one and multiple channels,
frame alignment, UInt8 silence, allocation/overflow boundaries, and zero net
tracked resources. Matrix-capacity and `sf_count_t` boundary tests exercise the
public Pure path as well as native helpers.

The two no-hardware smoke tests remain mandatory. Optional playback and capture
remain separate, bounded tests, but playback passes only after the callback has
consumed the requested silent frames. Stored results name the tested device,
channel count, sample rate, and date without generalizing to other hardware.

## Hermetic runner and cleanup contract

One native Windows runner launches Pure with a fixed timeout, captures stdout
and stderr without pipe deadlock, and returns the exact child exit status. Each
script prints an unpredictable per-run completion token only after every
assertion. Success requires exit zero, exactly one matching completion token,
and no unexpected diagnostics; parser errors and unhandled Pure exceptions
therefore cannot pass.

The runner replaces `PATH` with the staged Pure bin, exact audited runtime
directories, and Windows system directories. It removes `PURELIB`,
`PURE_INCLUDE`, and `PURE_LIBRARY`, owns its current directory, and validates
all executable/module/script inputs as canonical regular non-reparse paths
before the first launch.

Recursive cleanup is allowed only below a fixed contract root created by the
test, with an exact ownership sentinel and rejection of symlink, junction, or
other reparse components. Parallel runs use unique leaves. Legacy `make clean`
may remove only enumerated owned build outputs after validating the module
suffix; it may not use broad recursive globs.

## Strict build and PE closure

Normal upstream configuration remains available. An opt-in strict Windows
audit mode requires explicit canonical regular paths for Clang 22 targeting
`x86_64-w64-windows-gnu`, Ninja, pkgconf, Pure 0.68, the CLANG64 prefix, headers,
import libraries, runtime DLLs, `llvm-readobj`, and the Windows system
directory. It rejects alternate origins, architectures, missing inputs, and
malformed or duplicate declarations.

The PE verifier parses complete `llvm-readobj` records fail-closed. It checks
AMD64/PE32+ and exact import sets for the five modules plus every recursively
staged non-system DLL, including `libpure.dll`. Every non-system import resolves
to exactly one staged file whose expected source was fixed at configure time;
system imports resolve only through the authoritative Windows directory.
Forbidden MSYS/libgcc/libstdc++ names are matched case-insensitively. No extra,
missing, delay, malformed, or duplicate import is accepted.

## Exact installation and licensing

Installation separates runtime and documentation components. Before mutation,
the contract records a sorted SHA-256 manifest of every regular file in a fresh
copy of the portable prefix. It records each component install manifest,
requires their exact disjoint ownership, and compares the full post-install
tree to the baseline plus one declared delta. Existing files must remain
byte-identical; collisions and extra files fail before or after installation.

Every installed module, interface, document, example, test fixture, runtime
DLL, and license is hash-matched to its configured source. Reused runtime files
must be byte-identical rather than silently overwritten. The installed smoke
runs through the hermetic runner and the installed PE closure is rechecked.

Every distributed third-party DLL must have a locally packaged license text
and an entry mapping the exact binary to its project, version, source, and
license. FFTW, Vorbis, and LAME are included in this rule. If an exact license
text cannot be sourced from the installed package or repository, that DLL is
not distributable until the inventory is completed; links alone are not a
substitute for the bundled text. This is an artifact-completeness rule, not a
new legal interpretation.

## Source distribution

`make dist` declares every C/C++ source, Pure interface, generated-independent
CMake helper, native harness/runner, Pure test and data fixture, Windows guide,
third-party inventory, bundled license, README, example, and package license.
It rejects non-regular or reparse-ancestor inputs and quotes paths containing
spaces.

The archive contract runs the real distribution target, extracts beneath a
path containing spaces, removes access to the checkout-side driver, verifies
an exact file/hash manifest, and performs strict configure, four-worker build,
all mandatory tests, PE verification, component installation, and installed
verification solely from extracted sources. Cache, output, and generated files
must not contain a checkout path in any Windows casing.

## Windows CI and documentation

The non-Linux release workflow covers changes to `pure-audio/**`, TODO-33,
workflow helpers, and the workflow itself for pushes and pull requests. After
portable Pure staging it installs every explicit prerequisite, configures
strict Release mode, builds and PE-checks with exactly four workers, runs the
complete no-hardware/fault/contract label under the sanitized environment,
installs both components into a fresh stage, invokes the installed verifier,
and runs the source-distribution contract.

A structural YAML test uses PyYAML to validate mappings, filters, prerequisites,
step order, explicit inputs, exactly two four-worker build invocations, runtime
sanitization, component manifests, and complete verifier arguments. It must
reject semantic mutations and may not rely on source-text grep.

`WINDOWS.md` provides exact standalone prerequisites and commands. README
instructions no longer direct the supported Windows path through an obsolete
Makefile/import name. TODO-33 preserves its historical log, reopens before
implementation, records exact RED/GREEN commands and limitations, and closes
only after per-task reviews, a whole-branch review, and a fresh final run all
pass.

## Verification and residual boundaries

Closure requires a never-before-used strict Release build directory, exact
four-worker build and PE target, native fault tests under ASan where supported,
all mandatory CTests, exact component install and installed smoke/PE verifier,
the extracted-source contract, YAML semantic validation, and a clean branch
diff. Hardware playback/capture remains optional and is never required for CI.

The package does not certify every codec supported transitively by libsndfile,
every Windows audio device, elevated realtime priorities, or external audio
hardware. Exact runtime/import manifests are intentionally version-sensitive
and require re-audit after relevant toolchain, SDK, dependency, or Windows ABI
changes.
