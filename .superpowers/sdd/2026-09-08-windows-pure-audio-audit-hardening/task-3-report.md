# Task 3 report — Deterministic Stream Lifecycle and Concurrent Close

Status: DONE_WITH_CONCERNS. Implementation, self-review, and final verification
are complete. The platform/test-infrastructure limitations are recorded below.

Base: `6fe4d9eb`.

## Scope and implementation

- `pure-audio/audio.c`: monotonic sentry identities, registry activity pins,
  explicit allocated/opened/started/stopping/closed/failed states, one stream
  mutex for queue indices and state, checked initialization and reverse unwind,
  checked native lifecycle dispatch, terminal-aware I/O, finished-callback and
  timed active-query device-loss detection, protected queries and CPU load.
- `pure-audio/audio.pure`: `streamp` validates the shared identity; all CPU-load
  queries use the protected native wrapper; repeated close is a defined no-op.
- `pure-audio/audio_test_api.h`: expands the existing test-only dispatch seam.
- `pure-audio/tests/audio_fault_harness.c`: deterministic native backend,
  allocation/synchronization fault injection and reverse-order resource stack,
  real Pure sentry objects and aliases, blocked reader/writer tests, paused
  callback entry, simultaneous alias close, and stress iteration control.
- `pure-audio/CMakeLists.txt`: the one narrowly required registration change
  increases the native fault timeout from 30 to 90 seconds. Creating a real
  Pure interpreter for sentry tests brings ASan startup plus the test to about
  29 seconds; the old limit failed under concurrent verification. Internal
  concurrency waits remain independently bounded at two seconds.
- This report.

The existing untracked `build/` was neither edited nor used. All new outputs
are in `C:\pure-lang\task3-normal` and `C:\pure-lang\task3-asan`. No later-task
runner, PE, installation, distribution, CI, or hardware work was implemented.

## Ownership and synchronization contract

The Pure pointer keeps its successful PortAudio-pointer shape. Its sentry
argument is now an opaque, never-reused numeric identity, not a descriptor
address. Registry lookup pins a descriptor before acquiring its mutex; stale
aliases cannot dereference freed memory even when malloc reuses an address.
An unrelated sentry is rejected by symbol identity before its argument is used.

The lifecycle mutex serializes open/start/stop/close. The registry mutex owns
list links, identities, and operation/callback counts. It is released before
the stream data mutex is acquired. The stream mutex owns state, queues,
counters, and time. The leave path releases it before decrementing registry
activity. No volatile synchronization is used. Test allocation and event
counters that cross threads are C11 atomics.

Shutdown marks terminal state and broadcasts both conditions, stops or aborts
production without holding the stream mutex, closes public admission, drains
activity, and calls native close. It then unlinks, drains any callback admitted
at the native close boundary, destroys initialized conditions/mutex in reverse
order, and releases buffers and descriptor. Numeric conversion buffers remain
inside the public activity reference. A terminal wake returns `-1`, including
when some frames were transferred before shutdown.

PortAudio close errors require special handling: its front end removes the
native stream from its open list before the close result is known. The pointer
must never be retried. This was checked against the official implementation:
[Pa_CloseStream in pa_front.c](https://github.com/PortAudio/portaudio/blob/master/src/common/pa_front.c).
On close error the wrapper forgets the native pointer and retains only invalid
callback userdata until successful termination. If termination also fails,
the retained state remains inaccessible and new opens return the exact error.
A later successful termination releases it, and one `start` initializes a
fresh backend. This deliberately retains resources while callback cessation
cannot be established; it does not free potentially live userdata.

## RED evidence

All commands ran from `C:\pure-lang\.worktrees\todo33-audit`. Normal commands
used this environment:

```powershell
$env:MSYSTEM_PREFIX='C:\msys64\clang64'
$env:PKG_CONFIG_PATH='C:\pure-lang\pure\build\windows-clang64-prefix\lib\pkgconfig;C:\msys64\clang64\lib\pkgconfig'
$env:PATH='C:\pure-lang\pure\build\windows-clang64-prefix\bin;C:\msys64\clang64\bin;C:\Windows\System32;C:\Windows'
```

Initial configure and behavioral RED, with the start assertions added before
changing production lifecycle code:

```powershell
C:\msys64\clang64\bin\cmake.exe -S pure-audio -B C:\pure-lang\task3-normal -G 'MinGW Makefiles' '-DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/mingw32-make.exe' -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
C:\msys64\clang64\bin\cmake.exe --build C:\pure-lang\task3-normal --target audio_fault_harness --parallel 4
C:\msys64\clang64\bin\ctest.exe --test-dir C:\pure-lang\task3-normal -R pure-audio-fault-bounds --output-on-failure
```

```text
audio fault test failed: failed start returns exact error without a usable stream
audio fault test failed: failed start closes its native stream
audio fault test failed: failed start rolls back all owned resources
audio fault test failed: zero tracked allocation delta
4 of 1387 audio fault checks failed
```

The same build/test commands produced these additional test-first RED results
before their corresponding corrections:

```text
Exact initialize-error propagation:
audio fault test failed: lifecycle failure returns exact error
1 of 1901 audio fault checks failed

Consuming close-error safety:
audio fault test failed: native pointer is never retried after a failed consuming close
1 of 2003 audio fault checks failed

Combined stop/abort/close/terminate failure recovery:
audio fault test failed: one restart recovers after successful termination without retrying consumed native pointer
1 of 2006 audio fault checks failed
```

The foreign-sentry guard was tested first in the ASan build:

```powershell
C:\msys64\clang64\bin\cmake.exe --build C:\pure-lang\task3-asan --target audio_fault_harness --parallel 4
C:\msys64\clang64\bin\ctest.exe --test-dir C:\pure-lang\task3-asan -R pure-audio-fault-bounds --output-on-failure
```

```text
audio fault test failed: foreign sentry with a matching pointer argument cannot close audio identity
1 of 2002 audio fault checks failed
```

Three temporary production mutations independently proved the larger fault
matrix catches its intended breaks. Each used the normal build/test commands
above, and each was restored before GREEN verification:

| Mutation | Exact failure summary |
| --- | --- |
| Omit callback count from the drain before native close | `10 of 1905 audio fault checks failed` |
| Return zero rather than error after a terminal queue wake | `50 of 1905 audio fault checks failed` |
| Destroy input condition before the later-acquired output condition | `4 of 1905 audio fault checks failed` |

These are mutation RED runs, not claims that the final expanded harness ran
unchanged against the base. The full allocation, alias, and concurrency matrix
was developed incrementally during the architecture change after the initial
start-failure RED.

## Coverage

- Initialize failure, device-count error, negative/out-of-range indices,
  default-device NULL info, open failure, start failure, NULL stream info,
  finished-callback registration failure, and device loss during start.
- Every stream allocation (descriptor and both queues), every initialized
  stream primitive (one mutex and two conditions), and all four numeric
  conversion temporary allocations can fail independently.
- Resource-stack assertions verify native close precedes reverse destruction
  of output condition, input condition, data mutex, output queue, input queue,
  and descriptor. Failed acquisitions are never destroyed.
- Stop, abort, close, terminate, negative-active-query, and inactive-query
  failures; combined teardown failure; retained-userdata recovery.
- Real Pure aliases with shared sentries, repeated explicit close and calls
  to the native finalizer entry, unrelated sentries, and identity reuse checks.
  All stream query and six raw/numeric I/O entry points reject stale IDs.
- Both blocked directions are confirmed separately by per-thread wait bits.
  Triggers cover stop, close, invalid callback, finished callback, active-query
  device loss, and close after partial input/output transfer.
- Callback admission is paused after obtaining its activity reference. Two
  closing threads race that callback; native close cannot run until callback
  release. Every wait has a two-second independent watchdog.

## GREEN evidence

Final normal build and full suite:

```powershell
C:\msys64\clang64\bin\cmake.exe --build C:\pure-lang\task3-normal --parallel 4
C:\msys64\clang64\bin\ctest.exe --test-dir C:\pure-lang\task3-normal --output-on-failure
```

```text
1/4 pure-audio-fault-bounds .......... Passed 5.89 sec
2/4 pure-audio-load .................. Passed 5.36 sec
3/4 pure-audio-processing ............ Passed 7.90 sec
4/4 pure-audio-public-bounds ......... Passed 8.04 sec
100% tests passed, 0 tests failed out of 4
Total Test time (real) = 27.20 sec
```

ASan configuration (same environment, with compiler runtime added to PATH):

```powershell
$env:PATH='C:\pure-lang\pure\build\windows-clang64-prefix\bin;C:\msys64\clang64\lib\clang\22\lib\windows;C:\msys64\clang64\bin;C:\Windows\System32;C:\Windows'
C:\msys64\clang64\bin\cmake.exe -S pure-audio -B C:\pure-lang\task3-asan -G 'MinGW Makefiles' '-DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/mingw32-make.exe' -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON '-DCMAKE_C_FLAGS=-fsanitize=address -fno-omit-frame-pointer' '-DCMAKE_EXE_LINKER_FLAGS=-fsanitize=address' '-DCMAKE_SHARED_LINKER_FLAGS=-fsanitize=address' '-DCMAKE_MODULE_LINKER_FLAGS=-fsanitize=address'
```

The 1,000-iteration runs preceded the final consuming-close and restart
corrections; final-source repetitions follow separately below.

```powershell
$env:PURE_AUDIO_STRESS_ITERATIONS='1000'
C:\pure-lang\task3-normal\audio_fault_harness.exe
C:\pure-lang\task3-asan\audio_fault_harness.exe
```

```text
Normal: LIFECYCLE_CONCURRENCY_OK iterations=1000 waiter_completions=12000 callback_drains=1000 descriptors=0 native_streams=0 owned_sync=0
Normal: AUDIO_FAULT_HARNESS_OK 53475 checks allocation_delta=0
ASan: LIFECYCLE_CONCURRENCY_OK iterations=1000 waiter_completions=12000 callback_drains=1000 descriptors=0 native_streams=0 owned_sync=0
ASan: AUDIO_FAULT_HARNESS_OK 53482 checks allocation_delta=0
ASAN_STRESS_EXIT=0 ELAPSED_SECONDS=282.2142684
```

Final-source stress commands:

```powershell
C:\msys64\clang64\bin\cmake.exe --build C:\pure-lang\task3-asan --parallel 4
$env:PURE_AUDIO_STRESS_ITERATIONS='200'
C:\pure-lang\task3-normal\audio_fault_harness.exe
C:\msys64\clang64\bin\ctest.exe --test-dir C:\pure-lang\task3-asan -R 'pure-audio-(fault-bounds|public-bounds)' -V
```

```text
Normal and ASan:
LIFECYCLE_CONCURRENCY_OK iterations=200 waiter_completions=2400 callback_drains=200 descriptors=0 native_streams=0 owned_sync=0
AUDIO_FAULT_HARNESS_OK 11886 checks allocation_delta=0

ASan CTest:
1/2 pure-audio-fault-bounds .......... Passed 75.77 sec
2/2 pure-audio-public-bounds ......... Passed 38.37 sec
100% tests passed, 0 tests failed out of 2
Total Test time (real) = 114.15 sec
```

Both final-source commands exited zero; no sanitizer diagnostic was emitted.
`git diff --check` passed after this verification. The normal default-iteration
suite and both stress configurations above use the final production changes.

## Self-review and residual boundaries

Review commands: `git diff --stat`, `git diff --check`, and full diffs of the
five changed code/registration files. The review checked registry/data lock
ordering, both drain boundaries, retained callback userdata, all public entry
paths, exact initialized-resource flags, and scope. The foreign-sentry,
consuming-close, and restart findings above were fixed through focused RED
tests. No temporary production mutation remains.

ThreadSanitizer availability was checked with:

```powershell
C:\msys64\clang64\bin\clang.exe -fsanitize=thread -x c -fsyntax-only NUL
```

```text
clang: error: unsupported option '-fsanitize=thread' for target 'x86_64-w64-windows-gnu'
```

There is no claim of TSan coverage. ASan, deterministic entry/wait barriers,
reverse-order resource tracking, atomic event counts, and zero descriptor,
native-stream, synchronization, and allocation deltas are the available
evidence. No physical audio devices were opened by the fake native harness.

The first ASan native CTest timed out at its former 30-second limit; a direct
unchanged run passed in 29.0097952 seconds. One ASan public-bounds run encountered
the existing LLVM/Pure JIT `IMAGE_REL_AMD64_ADDR32NB relocation requires an
ordered section layout` failure (`0xc0000409`); its unchanged retry passed in
40.85 seconds. Neither emitted an AddressSanitizer diagnostic. An intermediate
rebuild also required restoring `MSYSTEM_PREFIX` when CMake auto-regenerated;
the subsequent stale-binary test was not counted as verification of new code.

High-level `audio::*` entry points enforce the identity contract. Deliberate
external use of raw `Pa::*` pointers bypasses that layer. Broken hardware
drivers that never return from a native stop/close call cannot be bounded by
the fake-backend evidence; optional physical-hardware checks remain separate.
