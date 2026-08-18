# Task 1 report: immutable fcgi2 source contract

## Files changed

- `pure-fastcgi/CMakeLists.txt`
- `pure-fastcgi/cmake/Fcgi2Dependency.cmake`
- `pure-fastcgi/cmake/FetchFcgi2.cmake`
- `pure-fastcgi/tests/source-contract.cmake`
- `pure-fastcgi/tests/verify-one-archive.cmake`

## RED

Command (using this task worktree as `SOURCE_DIR`):

```powershell
& C:/msys64/clang64/bin/cmake.exe `
  '-DSOURCE_DIR=C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/pure-fastcgi' `
  '-DFCGI2_ARCHIVE=C:/pure-lang/tmp/fcgi2-2.4.7.tar.gz' `
  '-DTEST_ROOT=C:/pure-lang/tmp/pure-fastcgi source contract' `
  -P C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/pure-fastcgi/tests/source-contract.cmake
```

Result: exit code 1, as intended. CMake reported that it could not include `cmake/Fcgi2Dependency.cmake`; no production contract implementation existed.

## GREEN

The prescribed `C:/pure-lang/tmp/fcgi2-2.4.7.tar.gz` fixture was absent. I explicitly invoked the new opt-in fetch helper once to download the pinned archive into this worktree's untracked `tmp/fcgi2-2.4.7.tar.gz`; configuration never included or invoked that helper.

Focused source-contract command:

```powershell
& C:/msys64/clang64/bin/cmake.exe `
  '-DSOURCE_DIR=C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/pure-fastcgi' `
  '-DFCGI2_ARCHIVE=C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/tmp/fcgi2-2.4.7.tar.gz' `
  '-DTEST_ROOT=C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/tmp/pure-fastcgi source contract' `
  -P C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/pure-fastcgi/tests/source-contract.cmake
```

Result: exit code 0. It extracted the verified archive, checked the required upstream inputs, and confirmed the child CMake process rejected the test's mutated copy with a size or SHA-256 mismatch.

Additional registration check:

```powershell
& C:/msys64/clang64/bin/cmake.exe -G Ninja `
  -S C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/pure-fastcgi `
  -B C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/build/pure-fastcgi `
  '-DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe' `
  '-DPURE_FASTCGI_FCGI2_ARCHIVE=C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/tmp/fcgi2-2.4.7.tar.gz'
& C:/msys64/clang64/bin/ctest.exe --test-dir `
  C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/build/pure-fastcgi `
  -R pure-fastcgi-source-contract --output-on-failure
```

Result: configure exit code 0; CTest exit code 0, `1/1` test passed in 0.20 s with the `fastcgi`, `source`, and `contract` labels.

Direct reconfigure with `-DPURE_FASTCGI_FCGI2_ARCHIVE=` exited 1 at `CMakeLists.txt:12` with `PURE_FASTCGI_FCGI2_ARCHIVE must name an existing absolute file`, with no fetch performed.

## Self-review

- The fcgi2 version, commit, URL, archive size, and SHA-256 match the task brief exactly.
- `pure_fastcgi_prepare_fcgi2` accepts parsed `ARCHIVE` and `OUT_SOURCE_DIR` arguments, rejects non-absolute/missing files and size/hash mismatches before extraction, recreates the deterministic extraction directory, and returns its source directory via parent scope.
- `FetchFcgi2.cmake` is opt-in: no configure file includes it. It requires absolute `OUTPUT`, preserves a matching output, refuses a mismatching existing output, downloads to `.part` with the required expected hash, checks the expected size, and renames only after success.
- CMake registration requires Windows, CMake 3.25, C, and an existing absolute archive cache entry. The test name, labels, and 30-second timeout match the brief.
- `git diff --check` reported no whitespace errors. The fetched archive remains an untracked local input and is not staged.

## Concerns

- The shared `C:/pure-lang/tmp/fcgi2-2.4.7.tar.gz` fixture was not available, so verification used an identical explicitly fetched archive in the isolated worktree.
- Fresh CMake compiler ABI probes intermittently stalled in this environment before project validation. With explicit `-G Ninja` and the Clang compiler the configured CTest registration passed; the focused `cmake -P` contract test is the primary Task 1 verification.

## Fix round 1: same-size SHA-256 mutation

`source-contract.cmake` now copies the archive with `file(COPY_FILE)`, changes byte zero with a PowerShell byte-array XOR, asserts that the resulting file has the original size, and requires the child process to report `fcgi2 archive SHA-256 mismatch` specifically.

### RED

After adding the same-size assertion while retaining the previous HEX/text write, the focused test failed as expected:

```powershell
& C:/msys64/clang64/bin/cmake.exe `
  '-DSOURCE_DIR=C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/pure-fastcgi' `
  '-DFCGI2_ARCHIVE=C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/tmp/fcgi2-2.4.7.tar.gz' `
  '-DTEST_ROOT=C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/tmp/pure-fastcgi source contract' `
  -P C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/pure-fastcgi/tests/source-contract.cmake
```

Exact output (exit code 1):

```text
CMake Error at pure-fastcgi/tests/source-contract.cmake:26 (message):
  mutated fcgi2 archive changed size
```

### GREEN

The same direct source-contract command completed with exit code 0 and no output after the binary-safe copy and one-byte mutation were implemented. The passing result covers the retained-size assertion and the exact child-error assertion.

The child was also run directly against the generated mutation:

```powershell
& C:/msys64/clang64/bin/cmake.exe `
  '-DSOURCE_DIR=C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/pure-fastcgi' `
  '-DARCHIVE=C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/tmp/pure-fastcgi source contract/mutated.tar.gz' `
  -P C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/pure-fastcgi/tests/verify-one-archive.cmake
```

Exact output (exit code 1):

```text
CMake Error at pure-fastcgi/cmake/Fcgi2Dependency.cmake:22 (message):
  fcgi2 archive SHA-256 mismatch
Call Stack (most recent call first):
  pure-fastcgi/tests/verify-one-archive.cmake:3 (pure_fastcgi_prepare_fcgi2)
```

The registered CTest command was attempted after a fresh explicit Ninja/Clang configure:

```powershell
& C:/msys64/clang64/bin/cmake.exe -G Ninja `
  -S C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/pure-fastcgi `
  -B C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/build/pure-fastcgi `
  '-DCMAKE_C_COMPILER=C:/msys64/clang64/bin/clang.exe' `
  '-DPURE_FASTCGI_FCGI2_ARCHIVE=C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/tmp/fcgi2-2.4.7.tar.gz'
& C:/msys64/clang64/bin/ctest.exe --test-dir C:/pure-lang/.worktrees/todo-46-windows-pure-fastcgi/build/pure-fastcgi `
  -R pure-fastcgi-source-contract --output-on-failure
```

Exact configure output before it was terminated after two minutes (no CTest process started):

```text
-- The C compiler identification is Clang 22.1.8
-- Detecting C compiler ABI info
```

Self-review: `file(COPY_FILE)` is binary-safe, the XOR changes exactly byte zero, the size comparison is against the original archive, and the child assertion cannot pass on a size rejection. The external compiler-ABI stall remains the sole concern for the requested registered CTest rerun.
