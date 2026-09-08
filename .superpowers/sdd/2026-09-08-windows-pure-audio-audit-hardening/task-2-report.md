# Task 2 report — Frame-Aligned Callback Layouts

Status: DONE_WITH_CONCERNS

## Scope and changed files

- `pure-audio/audio.c`
- `pure-audio/audio.pure`
- `pure-audio/audio_test_api.h`
- `pure-audio/tests/audio_fault_harness.c`

The implementation replaces byte-counted ring state with a canonical
interleaved queue counted exclusively in complete frames. PortAudio
non-interleaved buffers are gathered/scattered one `(frame, channel)` sample at
a time at the callback boundary. The six supported base formats are Float32,
Int32, raw Int24, Int16, Int8, and UInt8, for one, two, and three channels in
both layouts.

The test-only `pure_audio_api` dispatch can replace the sample-size query only
in `PURE_AUDIO_TEST_SEAM` targets; production defaults to `Pa_GetSampleSize`.
Task 3 can extend this table with lifecycle operations. A mutex-protected
callback-consumed frame count is available as `audio::stream_consumed` and via
the native test seam. It counts frames removed from the local output queue,
not physical device playback.

## RED evidence

### Callback layouts, frame alignment, and encoded silence

After adding the real-callback tests and before changing `audio.c`:

```powershell
C:\msys64\clang64\bin\cmake.exe --build build\task1-make --target audio_fault_harness --parallel 4
C:\msys64\clang64\bin\ctest.exe --test-dir build\task1-make -R pure-audio-fault-bounds --output-on-failure
```

The harness built successfully and the test failed behaviorally:

```text
60 of 965 audio fault checks failed
0% tests passed, 1 tests failed out of 1
```

The 60 failures were:

- all 36 non-interleaved logical-ordering cases: input and output for six
  formats and one, two, and three channels;
- all 18 non-interleaved underflow-silence cases;
- all 3 UInt8 interleaved underflow-silence cases; and
- 3 frame-queue failures: 6144-byte data rounded into an 8192-byte byte queue,
  the resulting old-block/channel-shift behavior, and residual partial-frame
  data.

The same run retained intact per-channel guard bytes, showing that the failure
was incorrect pointer-array treatment and logical transfer rather than a test
fixture crash.

### Unsupported callback formats

After the frame queue was GREEN but before callback format validation:

```powershell
C:\msys64\clang64\bin\cmake.exe --build build\task1-make --target audio_fault_harness --parallel 4
C:\msys64\clang64\bin\ctest.exe --test-dir build\task1-make -R pure-audio-fault-bounds --output-on-failure
```

Exact failing summary:

```text
audio fault test failed: custom callback format fails closed
audio fault test failed: custom callback format does not enter the queue
audio fault test failed: multiple callback format bits fail closed
audio fault test failed: ambiguous callback format does not enter the queue
4 of 1267 audio fault checks failed
0% tests passed, 1 tests failed out of 1
```

## GREEN evidence

### Normal build and full hardware-free suite

```powershell
C:\msys64\clang64\bin\cmake.exe --build build\task1-make --parallel 4
C:\msys64\clang64\bin\ctest.exe --test-dir build\task1-make --output-on-failure
```

```text
1/4 pure-audio-fault-bounds .......... Passed 0.11 sec
2/4 pure-audio-load .................. Passed 4.52 sec
3/4 pure-audio-processing ............ Passed 6.60 sec
4/4 pure-audio-public-bounds ......... Passed 6.88 sec
100% tests passed, 0 tests failed out of 4
Total Test time (real) = 18.12 sec
```

The focused verbose run proved the callback assertions and tracked resource
balance reached their completion condition:

```text
AUDIO_FAULT_HARNESS_OK 1291 checks allocation_delta=0
100% tests passed, 0 tests failed out of 1
```

### Fresh ASan configure, build, and focused suite

```powershell
C:\msys64\clang64\bin\cmake.exe -E env "MSYSTEM_PREFIX=C:\msys64\clang64" "PKG_CONFIG_PATH=C:\pure-lang\pure\build\windows-clang64-prefix\lib\pkgconfig;C:\msys64\clang64\lib\pkgconfig" "PATH=C:\pure-lang\pure\build\windows-clang64-prefix\bin;C:\msys64\clang64\bin;C:\Windows\System32;C:\Windows" C:\msys64\clang64\bin\cmake.exe -S pure-audio -B build\task2-asan -G "MinGW Makefiles" "-DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/mingw32-make.exe" -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON "-DCMAKE_C_FLAGS=-fsanitize=address -fno-omit-frame-pointer" "-DCMAKE_EXE_LINKER_FLAGS=-fsanitize=address" "-DCMAKE_SHARED_LINKER_FLAGS=-fsanitize=address" "-DCMAKE_MODULE_LINKER_FLAGS=-fsanitize=address"
C:\msys64\clang64\bin\cmake.exe --build build\task2-asan --parallel 4
C:\msys64\clang64\bin\ctest.exe --test-dir build\task2-asan -R "pure-audio-(fault-bounds|public-bounds)" --output-on-failure
```

```text
Clang 22.1.8; Pure 0.68; PortAudio 19
1/2 pure-audio-fault-bounds .......... Passed 0.09 sec
2/2 pure-audio-public-bounds ......... Passed 34.44 sec
100% tests passed, 0 tests failed out of 2
Total Test time (real) = 34.54 sec
```

No AddressSanitizer diagnostic was emitted.

The post-review verification repeated the full normal suite successfully in
17.62 seconds. Its first identical ASan invocation passed the native harness
but the public Pure fixture exited `0xc0000409` with:

```text
LLVM ERROR: IMAGE_REL_AMD64_ADDR32NB relocation requires an ordered section layout
```

An immediate retry of the exact same ASan command passed both tests (native
fault 0.06 seconds, public bounds 33.34 seconds; total 33.41 seconds). This is
the same intermittent Windows LLVM/Pure JIT section-layout failure recorded by
Task 1, not an AddressSanitizer diagnostic. The failing and passing outcomes
are both retained here rather than omitting the flake.

## Self-review from `1a24c6fa`

Review command set:

```powershell
git diff --stat 1a24c6fa
git diff 1a24c6fa -- pure-audio/audio.c pure-audio/audio.pure pure-audio/audio_test_api.h pure-audio/tests/audio_fault_harness.c
git diff --check 1a24c6fa
```

Findings fixed before commit:

- Important: the new non-volatile frame counters were initially read by
  `audio_stream_readable` and `audio_stream_writeable` without the queue mutex.
  Both queries now use the same input/output mutex as callback and blocking I/O.
- Important: signed Pure `int` format values could sign-extend the
  `Pa::NonInterleaved` flag on platforms where `PaSampleFormat` is wider than
  32 bits. Format inputs and base-format masking now normalize through
  `uint32_t`.
- Important: unsupported or ambiguous base-format bits were not rejected by
  the callback. The second RED cycle above now protects that fail-closed path.
- Minor: a stale byte-region comment was removed after the frame-queue rewrite.

No unresolved Critical, Important, or Minor code finding remains within Task 2
scope. `git diff --check 1a24c6fa` reports no whitespace error.

## Concerns and boundaries

- Hardware playback and capture were not run; Task 2 verification is
  deliberately deterministic and hardware-free.
- The existing intermittent Windows LLVM/Pure JIT section-layout failure was
  observed once during final ASan verification; the identical retry passed.
- The consumed-frame counter proves only that the PortAudio callback removed
  frames from the local queue. It intentionally does not claim DAC completion.
- Task 3 still owns lifecycle failures, start/stop/close rollback, blocked-I/O
  wakeup, alias invalidation, and callback/close concurrency. This task does not
  claim those semantics.
- `build/` remains untracked and was preserved.
