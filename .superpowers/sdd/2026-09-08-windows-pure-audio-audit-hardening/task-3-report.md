# Task 3 report — Deterministic Stream Lifecycle and Concurrent Close

Status: Fix round 1 implemented, self-reviewed, and verified. The original
Task 3 implementation is commit `6f1452b9`; the review corrections are described
below.

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
activity, and calls native close. On successful native close it then unlinks,
drains any callback admitted at that boundary, destroys initialized
conditions/mutex in reverse order, and releases buffers and descriptor. Numeric conversion buffers remain
inside the public activity reference. A terminal wake returns `-1`, including
when some frames were transferred before shutdown.

PortAudio 19.7 close errors require permanent quarantine. Its front end removes
the stream from its open list before abort/close success is known, while
termination visits only streams still on that list. A zero termination return
does not establish cessation of an unlinked producer. Version-pinned evidence:
[PortAudio 19.7 pa_front.c](https://github.com/PortAudio/portaudio/blob/v19.7.0/src/common/pa_front.c#L1268),
[19.7 termination](https://github.com/PortAudio/portaudio/blob/v19.7.0/src/common/pa_front.c#L357).
The corresponding WASAPI termination path releases host/device resources;
it is not an orphaned-stream join:
[19.7 WASAPI Terminate](https://github.com/PortAudio/portaudio/blob/v19.7.0/src/hostapi/wasapi/pa_win_wasapi.c#L2221).
The installed package inventory is
`mingw-w64-clang-x86_64-portaudio-1~19.7.0-5`.

The wrapper now forgets the native pointer, permanently retains the failed
descriptor and its synchronization/queues, rejects new streams, and prevents
backend terminate/reinitialize calls for the rest of the process. A late
callback can see only this stable FAILED descriptor and returns `paAbort`
without touching queues or caller output. Normal successful close still drains
and releases all resources. The earlier report's termination-based reclamation
and recovery claim was incorrect and is withdrawn.

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

Historical restart expectation, superseded by permanent quarantine in fix round 1:
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
  failures; combined teardown failure; permanent retained-userdata quarantine.
- Real Pure aliases with shared sentries, repeated explicit close and calls
  to the native finalizer entry, unrelated sentries, and identity reuse checks.
  All stream query and six raw/numeric I/O entry points reject stale IDs.
- Both blocked directions are confirmed separately by per-thread wait bits.
  Triggers cover stop, close, invalid callback, finished callback, active-query
  device loss, and close after partial input/output transfer.
- Callback admission is paused after obtaining its activity reference. Two
  closing threads race that callback; native close cannot run until callback
  release. Every wait has a two-second independent watchdog.

## Original commit GREEN evidence (historical)

Original commit normal build and full suite:

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

These historical 1,000-iteration runs preceded the original consuming-close
and restart corrections. Their direct commands had no independent outer
watchdog and are not the fix-round closure evidence.

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

Original commit stress commands (also superseded by outer-bounded commands):

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

Both original-commit commands exited zero; no sanitizer diagnostic was emitted.
These counts predate the review fixes and must not be read as proving safe
termination of a failed-close producer.

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
native-stream, synchronization, and allocation deltas on successful shutdown
are the available evidence. Quarantine is intentionally accounted separately.
No physical audio devices were opened by the fake native harness.

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

## Fix round 1 — review finding mapping

Only `audio.c`, `tests/audio_fault_harness.c`, and this report changed in this
round. Public interfaces and existing untracked `build/` remain untouched.

| Review finding | Correction and regression evidence |
| --- | --- |
| Critical: failed-close userdata reclaimed after terminate; address reuse | Permanent backend quarantine; retained descriptor address is never freed/reused; no wrapper terminate/restart is issued; late callback sees FAILED storage. The RED recycler forced the old address into a replacement and demonstrated incorrect callback consumption. |
| Important: cancellation strands shutdown locks | Disable cancellation across lifecycle open/start/stop/finalizer locks, waits, native calls, and cleanup. Tests cancel each of close/stop/start at the registry condition wait; callback, cancelled worker, and independent restart all complete within two seconds. |
| Important: fake backend masks native failure behavior | Fake close unlinks a still-live producer and retains callback, finished callback, and userdata separately. Successful fake terminate preserves that orphan. Worker threads schedule both late notifications after stop/restart attempts and after an external successful fake termination. |
| Important: shutdown watchdog and outer stress timeout | Stop/close triggers and cleanup run on monitored workers, so the main test thread can detect their deadlock within two seconds. Direct stress uses an independent 240-second parent process timeout with concurrent stdout/stderr readers. |
| Minor: mutable upstream citation and false guarantee | References above are pinned to PortAudio v19.7.0, matching installed package 1~19.7.0-5. The termination-based reclamation/recovery claim has been removed and explicitly withdrawn. |

Quarantine accounting is explicit rather than disguised as zero leaks: the
injected final failed close retains one descriptor, two queues, one mutex,
two conditions, and one modeled orphaned native stream until process exit.
The earlier normal lifecycle/stress cases still require exact zero resources
before entering this permanent-quarantine test. No production test-only reset
can undo quarantine.

### Fix-round RED

Both test-first regressions used the normal environment and commands already
given above:

```powershell
C:\msys64\clang64\bin\cmake.exe --build C:\pure-lang\task3-normal --target audio_fault_harness --parallel 4
C:\msys64\clang64\bin\ctest.exe --test-dir C:\pure-lang\task3-normal -R pure-audio-fault-bounds --output-on-failure
```

Before permanent quarantine:

```text
audio fault test failed: uncertain callback cessation permanently prevents backend termination and restart
audio fault test failed: failed-close callback userdata is never freed or rebound
audio fault test failed: quarantined backend rejects replacement before allocator can reuse descriptor address
audio fault test failed: scheduled late callback cannot consume or alter a replacement stream
audio fault test failed: quarantine accounts exactly one native orphan, three allocations, and three sync objects
5 of 2308 audio fault checks failed
reused_descriptors=1
```

Before cancellation guards, the monitored close left the registry locked:

```text
audio fault test failed: callback can leave after cancellation request
1/1 pure-audio-fault-bounds ... Failed 4.58 sec
```

The 4.58-second process duration includes interpreter startup; the independent
callback watchdog expired after two seconds. After the guards, winpthreads did
not necessarily deliver deferred cancellation merely on re-enable. The test
therefore uses an explicit `pthread_testcancel` after the operation returns,
and verifies `PTHREAD_CANCELED` plus released resources and independent restart.
It does not demand a non-portable immediate-delivery behavior.

### Fix-round GREEN

```text
Normal full suite:
1/4 pure-audio-fault-bounds .......... Passed 8.47 sec
2/4 pure-audio-load .................. Passed 5.05 sec
3/4 pure-audio-processing ............ Passed 7.66 sec
4/4 pure-audio-public-bounds ......... Passed 7.96 sec
100% tests passed, 0 tests failed out of 4; total 29.16 sec

ASan focused suite:
LIFECYCLE_CONCURRENCY_OK iterations=10 waiter_completions=120 callback_drains=10 descriptors=0 native_streams=0 owned_sync=0
QUARANTINE_OK orphaned_streams=1 retained_allocations=3 retained_sync=3 reused_descriptors=0
AUDIO_FAULT_HARNESS_OK 2391 checks quarantine_allocation_delta=3
1/2 pure-audio-fault-bounds .......... Passed 32.51 sec
2/2 pure-audio-public-bounds ......... Passed 34.11 sec
100% tests passed, 0 tests failed out of 2; total 66.63 sec
```

Final high-iteration stress uses the following parent process pattern for each
of `normal` and `asan`, with the exact runtime PATH shown here. Output readers
run concurrently, so the parent timeout does not depend on either pipe making
progress. Hidden process creation does not open an interactive window.

```powershell
$env:PATH='C:\pure-lang\pure\build\windows-clang64-prefix\bin;C:\msys64\clang64\lib\clang\22\lib\windows;C:\msys64\clang64\bin;C:\Windows\System32;C:\Windows'
$stressInfo = [Diagnostics.ProcessStartInfo]::new('C:\pure-lang\task3-asan\audio_fault_harness.exe') # also task3-normal
$stressInfo.WorkingDirectory = 'C:\pure-lang\.worktrees\todo33-audit'
$stressInfo.UseShellExecute = $false
$stressInfo.CreateNoWindow = $true
$stressInfo.Environment['PATH'] = $env:PATH
$stressInfo.Environment['PURE_AUDIO_STRESS_ITERATIONS'] = '200'
$stressInfo.RedirectStandardOutput = $true
$stressInfo.RedirectStandardError = $true
$stressProcess = [Diagnostics.Process]::Start($stressInfo)
$stressOutput = $stressProcess.StandardOutput.ReadToEndAsync()
$stressError = $stressProcess.StandardError.ReadToEndAsync()
if (!$stressProcess.WaitForExit(240000)) {
  $stressProcess.Kill()
  $stressProcess.WaitForExit()
  throw 'Independent 240-second stress watchdog expired'
}
$stressOutput.GetAwaiter().GetResult()
$stressError.GetAwaiter().GetResult()
exit $stressProcess.ExitCode
```

Both final stress processes exited zero, within their independent 240-second
outer deadlines. The ASan process emitted no sanitizer diagnostic:

```text
Normal and ASan (each):
LIFECYCLE_CONCURRENCY_OK iterations=200 waiter_completions=2400 callback_drains=200 descriptors=0 native_streams=0 owned_sync=0
QUARANTINE_OK orphaned_streams=1 retained_allocations=3 retained_sync=3 reused_descriptors=0
AUDIO_FAULT_HARNESS_OK 18731 checks quarantine_allocation_delta=3

NORMAL_STRESS_EXIT=0 ELAPSED_SECONDS=109.3953126
ASAN_STRESS_EXIT=0 ELAPSED_SECONDS=130.8565347
```

Final self-review read the complete fix-round production and harness diffs,
checked callback admission and both drain boundaries against the retained
tombstone, verified cancellation restoration follows lifecycle unlock, and
confirmed every shutdown trigger in the concurrency cases runs on a monitored
worker. `git diff --check` passed. No test-only quarantine reset or temporary
production mutation remains. Only the three fix-round files listed above are
modified; existing untracked `build/` is untouched.

The first bounded launcher attempt used Start-Process: the normal child exited
before test execution with missing-DLL status `0xc0000135`; the ASan child hit
the known LLVM/Pure section-layout failure `0xc0000409`. Neither was counted as
a successful stress run. The explicit ProcessStartInfo environment above uses
the complete CTest runtime PATH and an explicit working directory.
