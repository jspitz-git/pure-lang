# Task 1 report — Correct ABI Widths, Matrix Bounds, and Size Arithmetic

Status: DONE_WITH_CONCERNS

Commits:

- `db8db537241a90e9e0e996d51f1a6b56c2d2a97b` (`Harden pure-audio ABI and buffer bounds`)
- `feca54ed72625c85ef306b3465c293af3dc7d5cf` (`Address pure-audio bounds review findings`)

## Changed files

The review-fix commit changes:

- `pure-audio/audio.c`
- `pure-audio/audio.pure`
- `pure-audio/samplerate/samplerate.pure`
- `pure-audio/samplerate/src.pure`
- `pure-audio/samplerate/srcprocess.c`
- `pure-audio/samplerate/srcprocess.h`
- `pure-audio/tests/audio_fault_harness.c`
- `pure-audio/tests/bounds.pure`
- `pure-audio/CMakeLists.txt`

The original Task 1 commit also changed `pure-audio/audio_test_api.h`,
`pure-audio/fftw/fftw.pure`, and `pure-audio/sndfile/sndfile.pure`.
`pure-audio/cmake/RunPureTest.cmake` is unchanged. No Task 2 callback
representation or Task 3 lifecycle architecture was changed.

## Review fixes

- Pure audio and samplerate capacity checks calculate `frames * channels` as
  a bigint and reject a frame count outside the platform C `long` range before
  entering FFI.
- Samplerate rejects NaN and infinite ratios, and invalid convenience-wrapper
  calls terminate with `-1` instead of falling through to an incompatible raw
  FFI signature. Small predicates avoid pathological Pure JIT compilation of
  one large conjunction.
- `src_process` obtains the real channel count with libsamplerate's
  `src_get_channels`; both `src_state` sentry pointers and raw public `src_new`
  states retain successful-path compatibility.
- Ring initialization now restricts power-of-two capacities to `LONG_MAX/2`.
  Consequently `bigMask`, doubled capacity, and every permitted index advance
  remain representable on LLP64. Tests exercise the actual initializer and
  read/write index operations at the boundary.
- The generated samplerate output and its appended source are synchronized:
  `SAMPLERATE_GENERATED_TAIL_MATCH=95`.
- CMake configuration reads the actual production `sndfile/sndfile.pure` and
  requires exactly the 19 installed-header-derived `int64` declarations.

## RED evidence

### Actual ring boundary

Command, after adding the boundary assertions and before tightening the
initializer/rounding limit:

```powershell
$env:PATH='C:\pure-lang\pure\build\windows-clang64-prefix\bin;C:\msys64\clang64\bin;C:\Windows\System32;C:\Windows'
cmake --build build/task1-make --target audio_fault_harness --parallel 4
.\build\task1-make\audio_fault_harness.exe
```

Output:

```text
audio fault test failed: ring power requiring unsafe signed indices rejected
audio fault test failed: unsafe ring capacity rejected by actual initializer
2 of 97 audio fault checks failed
HARNESS_EXIT=1
```

### Public Pure guard cases

After the dynamically bound fixture values were changed to `let`, the focused
fixture no longer returned a misleading zero without its completion marker.
Before the bigint/native-range and finite-ratio guards were complete, the
direct process exited nonzero before printing the marker. The exact historical
command line was not retained; this is the reproducible command form used for
the direct fixture:

```powershell
pure.exe --norc -I pure-audio -I pure-audio/fftw -I pure-audio/samplerate -I pure-audio/sndfile -I pure-audio/realtime -L build/task1-make/bounds-modules -x pure-audio/tests/bounds.pure
```

```text
PURE_EXIT=1
(no PURE_AUDIO_BOUNDS_OK marker)
```

This exit code and absent marker are the complete retained output evidence;
stderr and the individual failed assertion were not captured. The first newly
ordered assertion was the audio bigint product case, but assigning the exit to
that assertion is an inference from fixture order, not preserved output.

The first implementation expressed all checks as one large Pure conjunction;
the credible focused test then exposed a JIT compilation timeout:

```text
1/1 Test #4: pure-audio-public-bounds .........***Timeout  60.02 sec
0% tests passed, 1 tests failed out of 1
```

Splitting the same checks into `valid_frame_count`, `valid_capacity`, and
`valid_ratio` removed that compiler pathology without weakening the guards.

### Production declaration regression binding

After adding the CMake check, `sf_seek` was temporarily changed in the actual
`pure-audio/sndfile/sndfile.pure` from `int64` to `int`. This exact configure
command proved the regression is rejected:

```powershell
$env:MSYSTEM_PREFIX='C:\msys64\clang64'
$env:PKG_CONFIG_PATH='C:\pure-lang\pure\build\windows-clang64-prefix\lib\pkgconfig'
$env:PATH='C:\pure-lang\pure\build\windows-clang64-prefix\bin;C:\msys64\clang64\bin;C:\Windows\System32;C:\Windows'
cmake -S pure-audio -B build/task1-abi-red -G 'MinGW Makefiles' -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
```

```text
CMake Error at CMakeLists.txt:120 (message):
  sndfile.pure ABI regression: expected 'extern int64 sf_seek(SNDFILE*,
  int64, int);'
-- Configuring incomplete, errors occurred!
```

Restoring the production declaration produced:

```text
-- Configuring done (0.2s)
-- Generating done (0.5s)
-- Build files have been written to: C:/pure-lang/.worktrees/todo33-audit/build/task1-abi-red
```

### Original conversion RED

The exact historical compile/run command and the individual 14 failure lines
were not retained, so they are unavailable rather than reconstructed here.
The only preserved exact output line is:

```text
14 of 33 audio fault checks failed
```

It was recorded after the conversion assertions were added and before the
independent terminating `paInt16`, `paInt8`, and `paUInt8` branches.

### Original checked-arithmetic link RED

The exact historical command was not retained. The preserved linker output
identified these missing symbols:

```text
undefined symbol: pure_audio_test_allocation_delta
undefined symbol: pure_audio_checked_mul_size
undefined symbol: pure_audio_frame_bytes
```

### Original paInt24 rejection RED

The exact historical command was not retained. These are the complete
preserved output lines; their original stream ordering was not recorded:

```text
3 of 94 audio fault checks failed
audio fault test failed: paInt24 numeric write rejected before allocation
audio fault test failed: paInt24 numeric read leaves queue untouched
audio fault test failed: paInt24 numeric read rejected before allocation
```

## GREEN evidence

### Normal build and full hardware-free suite

```powershell
$env:PATH='C:\pure-lang\pure\build\windows-clang64-prefix\bin;C:\msys64\clang64\bin;C:\Windows\System32;C:\Windows'
$env:PKG_CONFIG_PATH='C:\pure-lang\pure\build\windows-clang64-prefix\lib\pkgconfig;C:\msys64\clang64\lib\pkgconfig'
$env:MSYSTEM_PREFIX='C:\msys64\clang64'
cmake -S pure-audio -B build/task1-make -G 'MinGW Makefiles' '-DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/mingw32-make.exe' -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build build/task1-make --parallel 4
C:\msys64\clang64\bin\ctest.exe --test-dir build/task1-make --output-on-failure
```

```text
1/4 pure-audio-fault-bounds .......... Passed 0.04 sec
2/4 pure-audio-load .................. Passed 4.19 sec
3/4 pure-audio-processing ............ Passed 6.16 sec
4/4 pure-audio-public-bounds ......... Passed 6.41 sec
100% tests passed, 0 tests failed out of 4
Total Test time (real) = 16.82 sec
```

Direct proof that both fixtures reached their completion conditions:

```text
AUDIO_FAULT_HARNESS_OK 97 checks allocation_delta=0
HARNESS_EXIT=0
PURE_AUDIO_BOUNDS_OK 24 checks
PURE_EXIT=0
```

### Focused ASan suite

Complete ASan configure, build, and focused-test commands:

```powershell
$env:MSYSTEM_PREFIX='C:\msys64\clang64'
$env:PKG_CONFIG_PATH='C:\pure-lang\pure\build\windows-clang64-prefix\lib\pkgconfig;C:\msys64\clang64\lib\pkgconfig'
$env:PATH='C:\pure-lang\pure\build\windows-clang64-prefix\bin;C:\msys64\clang64\bin;C:\Windows\System32;C:\Windows'
cmake -S pure-audio -B build/task1-asan -G 'MinGW Makefiles' '-DCMAKE_MAKE_PROGRAM=C:/msys64/clang64/bin/mingw32-make.exe' -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON '-DCMAKE_C_FLAGS=-fsanitize=address -fno-omit-frame-pointer' '-DCMAKE_EXE_LINKER_FLAGS=-fsanitize=address' '-DCMAKE_SHARED_LINKER_FLAGS=-fsanitize=address' '-DCMAKE_MODULE_LINKER_FLAGS=-fsanitize=address'
cmake --build build/task1-asan --parallel 4
C:\msys64\clang64\bin\ctest.exe --test-dir build/task1-asan -R 'pure-audio-(fault-bounds|public-bounds)' --output-on-failure
```

```text
1/2 pure-audio-fault-bounds .......... Passed 0.05 sec
2/2 pure-audio-public-bounds ......... Passed 32.76 sec
100% tests passed, 0 tests failed out of 2
Total Test time (real) = 32.82 sec
```

No AddressSanitizer diagnostic was emitted, and the native harness reported a
zero tracked allocation delta.

## Installed header and runtime ABI evidence

Installed header: `C:\msys64\clang64\include\sndfile.h`.

```text
368: typedef int64_t sf_count_t;
676: sf_count_t sf_seek(SNDFILE *sndfile, sf_count_t frames, int whence);
712-754: sf_read_raw/sf_write_raw and every frame/item read/write family use
         and return sf_count_t.
```

All 19 corresponding production Pure declarations use signed `int64`. The
Pure fixture proves `4294967297L` survives public Pure FFI conversion exactly;
the test-only seam then invokes the real installed libsndfile `sf_seek` with
that value and verifies both its `-1L` read-file result and a subsequent exact
seek back to frame zero.

Directly invoking every production `sndfile.pure` declaration is not reliable
in this isolated Windows test process because libsndfile symbols loaded only
transitively through `sfinfo.dll` do not consistently reduce. The unavoidable
runtime limit is covered in two independent ways: the C seam executes the real
installed ABI at a value above 32 bits, and configure-time regression coverage
binds to the exact actual production declarations rather than a copied shim
signature.

## Concerns and residual risks

- One intermediate ASan rerun failed before user code with LLVM's
  `IMAGE_REL_AMD64_ADDR32NB relocation requires an ordered section layout`
  (`0xc0000409`). The identical isolated test immediately passed in 32.80 s,
  followed by the complete focused ASan suite passing in 32.82 s. This is an
  intermittent Windows LLVM/Pure JIT layout failure, not an ASan diagnostic,
  but remains a test-infrastructure flake worth tracking.
- Hardware playback/capture was not run; Task 1 verification is hardware-free
  by contract.
